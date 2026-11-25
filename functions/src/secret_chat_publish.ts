import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";

import {requireUid} from "./access";
import {
  FORUM_DICTIONARY_VERSION,
  ForumModerationResult,
  isCrisisDisclosure,
  moderateForumText,
} from "./moderation/forum_moderation";

export const FORUM_LANGUAGE_WARNING =
  "MindMate is a safe and supportive community. Please revise your message using respectful language before publishing.";
const CRISIS_REDIRECT =
  "This sounds urgent. Please use MindAid or contact PACC/crisis support instead of posting publicly.";

const CATEGORIES = new Set([
  "Mental Health", "Anxiety", "Stress", "Gratitude", "Self-care", "School Pressure", "Support",
]);
const LABEL_PATTERN = /^[a-z_]{1,32}$/;
const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const RATE_WINDOW_MS = 10 * 60 * 1000;
const RATE_LIMITS = {post: 5, comment: 20} as const;

type ForumTextKind = "post" | "comment" | "alias";
export interface PublishDeps {
  moderate: (text: string) => ForumModerationResult;
  crisis: (text: string) => boolean;
}
const defaultDeps: PublishDeps = {moderate: moderateForumText, crisis: isCrisisDisclosure};

/**
 * Throws unless [text] may be published. Rejections record only who, what kind
 * and which categories; never the text. Any moderation failure rejects.
 */
export async function assertForumTextAllowed(
  text: string,
  context: {userId: string; kind: ForumTextKind; audit?: boolean},
  deps: Partial<PublishDeps> = {},
): Promise<void> {
  const {moderate, crisis} = {...defaultDeps, ...deps};
  let result: ForumModerationResult;
  let isCrisis: boolean;
  try {
    isCrisis = context.kind !== "alias" && crisis(text);
    result = moderate(text);
  } catch {
    throw new HttpsError(
      "unavailable",
      "We could not check your message right now. Your draft is kept; please try again.",
      {reason: "moderation_unavailable"},
    );
  }
  if (isCrisis) {
    throw new HttpsError("failed-precondition", CRISIS_REDIRECT, {reason: "crisis_support"});
  }
  if (result.allowed) return;
  if (context.audit !== false) {
    await getFirestore().collection("_secret_chat_moderation_events").add({
      userId: context.userId,
      kind: context.kind,
      categories: result.categories,
      severity: result.severity,
      dictionaryVersion: FORUM_DICTIONARY_VERSION,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  throw new HttpsError("invalid-argument", FORUM_LANGUAGE_WARNING, {reason: "inappropriate_language"});
}

function text(value: unknown, min: number, max: number): string {
  const trimmed = typeof value === "string" ? value.trim() : "";
  if (trimmed.length < min || trimmed.length > max) {
    throw new HttpsError("invalid-argument", `Write between ${min} and ${max} characters.`);
  }
  return trimmed;
}

function optionalId(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || !ID_PATTERN.test(value)) {
    throw new HttpsError("invalid-argument", "The ID is invalid.");
  }
  return value;
}

function labels(value: unknown): string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 6 ||
      !value.every((label) => typeof label === "string" && LABEL_PATTERN.test(label))) {
    throw new HttpsError("invalid-argument", "The safety labels are invalid.");
  }
  return [...new Set(value as string[])];
}

function categories(value: unknown): string[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 3 ||
      new Set(value).size !== value.length ||
      !value.every((item) => typeof item === "string" && CATEGORIES.has(item))) {
    throw new HttpsError("invalid-argument", "Choose between 1 and 3 categories.");
  }
  return value as string[];
}

async function consumeRate(
  transaction: FirebaseFirestore.Transaction,
  userId: string,
  kind: "post" | "comment",
): Promise<() => void> {
  const ref = getFirestore().collection("_secret_chat_rate_limits").doc(`${userId}_${kind}`);
  const snapshot = await transaction.get(ref);
  const now = Date.now();
  const start = snapshot.data()?.windowStart instanceof Timestamp ?
    (snapshot.data()!.windowStart as Timestamp).toMillis() : 0;
  const inWindow = now - start < RATE_WINDOW_MS;
  const count = inWindow ? Number(snapshot.data()?.count ?? 0) : 0;
  if (count >= RATE_LIMITS[kind]) {
    throw new HttpsError("resource-exhausted", "You are posting quickly. Please wait a few minutes.");
  }
  return () => transaction.set(ref, {
    windowStart: inWindow ? Timestamp.fromMillis(start) : Timestamp.fromMillis(now),
    count: count + 1,
  });
}

export async function createSecretChatPostHandler(
  request: CallableRequest,
  deps: Partial<PublishDeps> = {},
): Promise<{postId: string}> {
  const userId = requireUid(request);
  const data = request.data ?? {};
  const message = text(data.message, 8, 500);
  const chosen = categories(data.categories);
  const safetyLabels = labels(data.safetyLabels);
  const requestedId = optionalId(data.postId);
  await assertForumTextAllowed(message, {userId, kind: "post"}, deps);

  const db = getFirestore();
  const ref = requestedId ? db.collection("secret_chats").doc(requestedId) : db.collection("secret_chats").doc();
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) {
      // A retry of the same post by the same author is a success, once.
      if (existing.data()?.authorId === userId && existing.data()?.message === message) return;
      throw new HttpsError("already-exists", "That post ID is already used.");
    }
    const commitRate = await consumeRate(transaction, userId, "post");
    commitRate();
    transaction.set(ref, {
      authorId: userId,
      message,
      category: chosen[0],
      categories: chosen,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      likeCount: 0,
      commentCount: 0,
      readCount: 0,
      moderationStatus: "active",
      safetyLabels,
      isAnonymous: true,
    });
  });
  return {postId: ref.id};
}

export async function addSecretChatCommentHandler(
  request: CallableRequest,
  deps: Partial<PublishDeps> = {},
): Promise<{commentId: string}> {
  const userId = requireUid(request);
  const data = request.data ?? {};
  const postId = optionalId(data.postId);
  if (!postId) throw new HttpsError("invalid-argument", "The post ID is invalid.");
  const message = text(data.message, 3, 400);
  const safetyLabels = labels(data.safetyLabels);
  const requestedId = optionalId(data.commentId);
  await assertForumTextAllowed(message, {userId, kind: "comment"}, deps);

  const db = getFirestore();
  const postRef = db.collection("secret_chats").doc(postId);
  const ref = requestedId ?
    db.collection("secret_chat_comments").doc(requestedId) : db.collection("secret_chat_comments").doc();
  await db.runTransaction(async (transaction) => {
    const [post, existing] = await Promise.all([transaction.get(postRef), transaction.get(ref)]);
    if (existing.exists) {
      if (existing.data()?.authorId === userId && existing.data()?.message === message) return;
      throw new HttpsError("already-exists", "That comment ID is already used.");
    }
    if (!post.exists || post.data()?.moderationStatus !== "active") {
      throw new HttpsError("failed-precondition", "This thread is no longer available.",
        {reason: "thread_unavailable"});
    }
    const commitRate = await consumeRate(transaction, userId, "comment");
    commitRate();
    transaction.set(ref, {
      postId,
      authorId: userId,
      message,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      moderationStatus: "active",
      safetyLabels,
      isAnonymous: true,
    });
  });
  return {commentId: ref.id};
}

/** The only way to publish a Forum post: moderated, rate limited, server-written. */
export const createSecretChatPost = onCall((request) => createSecretChatPostHandler(request));

/** The only way to publish a Forum comment. */
export const addSecretChatComment = onCall((request) => addSecretChatCommentHandler(request));
