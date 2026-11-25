import assert from "node:assert/strict";
import {beforeEach, test} from "node:test";

import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import type {CallableRequest} from "firebase-functions/v2/https";

import {
  addSecretChatCommentHandler,
  assertForumTextAllowed,
  createSecretChatPostHandler,
  FORUM_LANGUAGE_WARNING,
} from "./secret_chat_publish";

const projectId = process.env.GCLOUD_PROJECT ?? "demo-mindmate-mood-v2";
if (!getApps().length) initializeApp({projectId});
const db = getFirestore();
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
let seq = 0;

function request(uid: string, data: Record<string, unknown>, token: Record<string, unknown> = {}) {
  return {auth: {uid, token}, data} as unknown as CallableRequest;
}

const uid = () => `forum-user-${Date.now()}-${++seq}`;
const post = (extra: Record<string, unknown> = {}) => ({
  message: "Exams are stressful but kaya natin to.",
  categories: ["Stress", "School Pressure"],
  safetyLabels: ["stress"],
  ...extra,
});

async function rejectsWith(promise: Promise<unknown>, code: string, reason?: string) {
  await assert.rejects(promise, (error: {code?: string; details?: {reason?: string}}) => {
    assert.equal(error.code, code);
    if (reason) assert.equal(error.details?.reason, reason);
    return true;
  });
}

beforeEach(() => {
  if (!emulated) throw new Error("secret_chat_publish.test.ts needs the Firestore emulator.");
});

test("an allowed post is published by the server with the usual fields", {skip: !emulated}, async () => {
  const author = uid();
  const {postId} = await createSecretChatPostHandler(request(author, post()));
  const stored = (await db.doc(`secret_chats/${postId}`).get()).data()!;
  assert.equal(stored.authorId, author);
  assert.equal(stored.message, "Exams are stressful but kaya natin to.");
  assert.deepEqual(stored.categories, ["Stress", "School Pressure"]);
  assert.equal(stored.category, "Stress");
  assert.equal(stored.moderationStatus, "active");
  assert.equal(stored.isAnonymous, true);
  assert.equal(stored.likeCount, 0);
  assert.ok(stored.createdAt instanceof Timestamp);
});

test("profanity is refused, nothing is written, and the audit row holds no text", {skip: !emulated}, async () => {
  const author = uid();
  const postId = `p-${Date.now()}-${++seq}`;
  const message = "Putangina ng thesis na to, stress na stress ako.";
  await rejectsWith(
    createSecretChatPostHandler(request(author, post({postId, message}))),
    "invalid-argument",
    "inappropriate_language",
  );
  assert.equal((await db.doc(`secret_chats/${postId}`).get()).exists, false);
  const audit = await db.collection("_secret_chat_moderation_events").where("userId", "==", author).get();
  assert.equal(audit.size, 1);
  const row = audit.docs[0].data();
  assert.equal(row.kind, "post");
  assert.ok(Array.isArray(row.categories) && row.categories.length > 0);
  assert.equal(JSON.stringify(row).toLowerCase().includes("putangina"), false);
  assert.equal(JSON.stringify(row).includes("thesis"), false);
});

test("the refusal message is the community warning", async () => {
  assert.equal(
    FORUM_LANGUAGE_WARNING,
    "MindMate is a safe and supportive community. Please revise your message using respectful language before publishing.",
  );
  await assert.rejects(
    assertForumTextAllowed("g@go ka", {userId: "u", kind: "alias", audit: false}),
    (error: {message?: string}) => error.message === FORUM_LANGUAGE_WARNING,
  );
});

test("crisis language gets the support redirect, not a profanity refusal", {skip: !emulated}, async () => {
  await rejectsWith(
    createSecretChatPostHandler(request(uid(), post({message: "I want to kill myself, I am so tired."}))),
    "failed-precondition",
    "crisis_support",
  );
});

test("a failing moderator rejects the post and writes nothing", {skip: !emulated}, async () => {
  const postId = `p-${Date.now()}-${++seq}`;
  await rejectsWith(
    createSecretChatPostHandler(request(uid(), post({postId})), {
      moderate: () => {
        throw new Error("dictionary unavailable");
      },
    }),
    "unavailable",
  );
  assert.equal((await db.doc(`secret_chats/${postId}`).get()).exists, false);
});

test("a retry with the same ID succeeds once; another user cannot take the ID", {skip: !emulated}, async () => {
  const author = uid();
  const postId = `p-${Date.now()}-${++seq}`;
  await createSecretChatPostHandler(request(author, post({postId})));
  assert.deepEqual(await createSecretChatPostHandler(request(author, post({postId}))), {postId});
  await rejectsWith(createSecretChatPostHandler(request(uid(), post({postId}))), "already-exists");
});

test("posting is rate limited per user", {skip: !emulated}, async () => {
  const author = uid();
  for (let i = 0; i < 5; i++) await createSecretChatPostHandler(request(author, post()));
  await rejectsWith(createSecretChatPostHandler(request(author, post())), "resource-exhausted");
});

test("shape, length, categories and first-login are enforced", {skip: !emulated}, async () => {
  await rejectsWith(createSecretChatPostHandler(request(uid(), post({message: "short"}))), "invalid-argument");
  await rejectsWith(createSecretChatPostHandler(request(uid(), post({message: "x".repeat(501)}))), "invalid-argument");
  await rejectsWith(createSecretChatPostHandler(request(uid(), post({categories: ["Politics"]}))), "invalid-argument");
  await rejectsWith(createSecretChatPostHandler(request(uid(), post({safetyLabels: ["<b>"]}))), "invalid-argument");
  await rejectsWith(
    createSecretChatPostHandler(request(uid(), post(), {firstLoginPending: true})),
    "permission-denied",
  );
});

test("comments are moderated and only reach active posts", {skip: !emulated}, async () => {
  const author = uid();
  const {postId} = await createSecretChatPostHandler(request(author, post()));
  const commenter = uid();
  const {commentId} = await addSecretChatCommentHandler(
    request(commenter, {postId, message: "Kaya mo yan, proud of you!", safetyLabels: ["support"]}),
  );
  const stored = (await db.doc(`secret_chat_comments/${commentId}`).get()).data()!;
  assert.equal(stored.postId, postId);
  assert.equal(stored.authorId, commenter);
  assert.equal(stored.moderationStatus, "active");

  await rejectsWith(
    addSecretChatCommentHandler(request(commenter, {postId, message: "ang b0b0 mo", safetyLabels: []})),
    "invalid-argument",
    "inappropriate_language",
  );
  await db.doc(`secret_chats/${postId}`).update({moderationStatus: "hidden"});
  await rejectsWith(
    addSecretChatCommentHandler(request(commenter, {postId, message: "Kaya mo yan!", safetyLabels: []})),
    "failed-precondition",
    "thread_unavailable",
  );
});

test("repeated refusals are rate limited and stop writing audit rows", {skip: !emulated}, async () => {
  const author = uid();
  const bad = post({message: "Putangina ng thesis na to, stress na stress ako."});
  for (let i = 0; i < 20; i++) {
    await rejectsWith(createSecretChatPostHandler(request(author, bad)), "invalid-argument");
  }
  await rejectsWith(createSecretChatPostHandler(request(author, bad)), "resource-exhausted");
  await rejectsWith(createSecretChatPostHandler(request(author, post())), "resource-exhausted");
  const audit = await db.collection("_secret_chat_moderation_events").where("userId", "==", author).get();
  assert.equal(audit.size, 20);
});

test("a comment retry only succeeds on the same post", {skip: !emulated}, async () => {
  const author = uid();
  const first = await createSecretChatPostHandler(request(author, post()));
  const second = await createSecretChatPostHandler(request(author, post()));
  const commentId = `c-${Date.now()}-${++seq}`;
  const comment = {message: "Kaya mo yan, proud of you!", safetyLabels: [], commentId};
  await addSecretChatCommentHandler(request(author, {...comment, postId: first.postId}));
  assert.deepEqual(
    await addSecretChatCommentHandler(request(author, {...comment, postId: first.postId})),
    {commentId},
  );
  await rejectsWith(
    addSecretChatCommentHandler(request(author, {...comment, postId: second.postId})),
    "already-exists",
  );
});

test("a post ID that still has comments cannot be reused", {skip: !emulated}, async () => {
  const postId = `p-${Date.now()}-${++seq}`;
  await db.doc(`secret_chat_comments/leftover-${postId}`).set({postId, authorId: "someone", message: "old"});
  await rejectsWith(createSecretChatPostHandler(request(uid(), post({postId}))), "already-exists");
});
