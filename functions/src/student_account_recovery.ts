import {createHash, randomUUID} from "node:crypto";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {error as logError} from "firebase-functions/logger";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {accountEmailTransporter, canonicalLoginId, smtpAppPassword, smtpSender} from "./account_recovery";
import {AUDIT_CATEGORIES, writeAudit} from "./audit";
import {studentAuthAliasEmail} from "./student_auth_alias";
import {RECOVERY_CONTACTS, RECOVERY_VERIFICATIONS, maskEmail} from "./student_recovery_contacts";
import {
  generateActivationCode, hashActivationCode, normalizeActivationCode, verifyActivationCode,
} from "./student_roster_domain";

if (!getApps().length) initializeApp();

/**
 * Recovery for Student ID accounts. The student's Firebase Auth email is an internal alias, so Firebase cannot
 * mail them. Two things therefore run on our own SMTP transport:
 *
 *  1. Verifying the recovery address: an emailed one-time code the signed-in student types into the app. The code
 *     is bound to the student's uid and to the exact address it was sent to, is stored only as a scrypt hash,
 *     expires, has an attempt cap and is single use. A link would let anyone who receives a mistyped address
 *     verify it, which is why this is a code.
 *  2. Password reset by Student ID: a Firebase Admin reset link for the alias, mailed only to a verified recovery
 *     address. Every outcome returns the same response so a Student ID cannot be probed.
 */
const db = () => getFirestore();

const LIMITS = "_student_recovery_limits";
const WINDOW_MS = 15 * 60 * 1000;
const CODE_TTL_MS = 15 * 60 * 1000;
const MAX_ATTEMPTS = 5;
const RESEND_COOLDOWN_MS = 30 * 1000;
const CODE_REQUEST_LIMIT = 5;
const RESET_ID_LIMIT = 3;
const IP_LIMIT = 12;
const RESET_MIN_RESPONSE_MS = 2500;
const PRODUCTION_PROJECT_ID = "mind-mates-cd2cf";

export type RecoveryMail = {to: string; subject: string; text: string; html: string};
export type RecoveryDeps = {
  sendMail: (mail: RecoveryMail) => Promise<void>;
  now: () => number;
  newCode: () => string;
  resetLink: (aliasEmail: string) => Promise<string>;
  minResetResponseMs: number;
};
type Req = {auth?: {uid: string} | null; data?: unknown; rawRequest?: {ip?: string; socket?: {remoteAddress?: string}}};

export const defaultRecoveryDeps: RecoveryDeps = {
  sendMail: async (mail) => {
    await accountEmailTransporter().sendMail({from: `MindMate <${smtpSender.value().trim()}>`, ...mail});
  },
  now: () => Date.now(),
  newCode: generateActivationCode,
  resetLink: (aliasEmail) => getAuth().generatePasswordResetLink(aliasEmail),
  minResetResponseMs: RESET_MIN_RESPONSE_MS,
};

/** Dev endpoints skip App Check (Staging has no provider) but must never answer in the production project. */
export function assertDevEndpointAllowed(projectId = process.env.GCLOUD_PROJECT): void {
  if (projectId === PRODUCTION_PROJECT_ID) {
    throw new HttpsError("failed-precondition", "This endpoint is not available.");
  }
}

function digest(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function callerIp(request: Req): string {
  return request.rawRequest?.ip || request.rawRequest?.socket?.remoteAddress || "unknown";
}

function requireUid(request: Req): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  return uid;
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>'"]/g, (c) => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", "\"": "&quot;"})[c] ?? c);
}

/** Fixed-window limiter. Counts every request, so real and unknown identifiers are limited identically. */
async function consumeWindow(scope: string, subject: string, limit: number, now: number): Promise<void> {
  const ref = db().collection(LIMITS).doc(`${scope}_${digest(subject)}`);
  await db().runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const started = snap.data()?.startedAt instanceof Timestamp ? (snap.data()!.startedAt as Timestamp).toMillis() : 0;
    const inWindow = now - started < WINDOW_MS;
    const count = inWindow ? Number(snap.data()?.count ?? 0) : 0;
    if (count >= limit) {
      throw new HttpsError("resource-exhausted", "Too many requests. Please wait 15 minutes and try again.");
    }
    const startedAt = inWindow ? started : now;
    transaction.set(ref, {
      startedAt: Timestamp.fromMillis(startedAt), count: count + 1,
      expiresAt: Timestamp.fromMillis(startedAt + WINDOW_MS * 2),
    });
  });
}

/** A verified recovery contact whose Auth account has not been flagged yet is repaired here (safe to repeat). */
async function ensureAuthVerified(uid: string): Promise<void> {
  const user = await getAuth().getUser(uid);
  if (!user.emailVerified) await getAuth().updateUser(uid, {emailVerified: true});
}

// ------------------------------------------------------------------ verification code

export async function requestRecoveryEmailCode(request: Req, deps: RecoveryDeps = defaultRecoveryDeps) {
  const uid = requireUid(request);
  const contactRef = db().collection(RECOVERY_CONTACTS).doc(uid);
  const contact = await contactRef.get();
  if (!contact.exists) {
    throw new HttpsError("failed-precondition", "Recovery email verification is not available for this account.");
  }
  const contactData = contact.data() ?? {};
  if (contactData.verifiedAt) {
    await ensureAuthVerified(uid);
    return {accepted: true, alreadyVerified: true};
  }
  const email = String(contactData.email ?? "");
  const emailHash = String(contactData.emailHash ?? "");
  if (!email || !emailHash) {
    throw new HttpsError("failed-precondition", "Recovery email verification is not available for this account.");
  }

  const now = deps.now();
  const verificationRef = db().collection(RECOVERY_VERIFICATIONS).doc(uid);
  const previous = (await verificationRef.get()).data();
  if (previous && Number(previous.sentAtMs ?? 0) + RESEND_COOLDOWN_MS > now) {
    throw new HttpsError("resource-exhausted", "A code was just sent. Please wait a moment before requesting another.");
  }
  await consumeWindow("code_uid", uid, CODE_REQUEST_LIMIT, now);
  await consumeWindow("code_ip", callerIp(request), IP_LIMIT + 8, now);

  const code = deps.newCode();
  const stored = await hashActivationCode(code, new Date(now));
  await verificationRef.set({
    emailHash, hash: stored.hash, salt: stored.salt, attempts: 0, sentAtMs: now,
    issuedAt: Timestamp.fromMillis(now), expiresAt: Timestamp.fromMillis(now + CODE_TTL_MS),
  });
  try {
    await deps.sendMail({
      to: email,
      subject: "Your MindMate verification code",
      text: [
        "MindMate - verify your recovery email",
        "",
        `Your verification code is: ${code}`,
        "",
        "Enter it in the MindMate app within 15 minutes. If you did not create a MindMate account, ignore this email.",
        "We will never ask you for this code by phone, chat or email.",
      ].join("\n"),
      html: `<div style="font-family:Arial,Helvetica,sans-serif;color:#242424"><h2>Verify your recovery email</h2>`
        + `<p>Your verification code is:</p><p style="font-size:26px;letter-spacing:3px;font-weight:700">${escapeHtml(code)}</p>`
        + `<p>Enter it in the MindMate app within 15 minutes. If you did not create a MindMate account, ignore this email.</p>`
        + `<p style="color:#77736d;font-size:12px">We will never ask you for this code by phone, chat or email.</p></div>`,
    });
  } catch (error) {
    await verificationRef.delete().catch(() => undefined);
    const correlationId = randomUUID();
    logError("Student recovery code delivery failed", {correlationId, error: error instanceof Error ? error.message : String(error)});
    throw new HttpsError("unavailable", "The verification email could not be delivered. Please try again shortly.", {correlationId});
  }
  return {accepted: true, maskedEmail: maskEmail(email), expiresInSeconds: CODE_TTL_MS / 1000};
}

const EXPIRED = () => new HttpsError("failed-precondition", "That code has expired. Request a new one.", {reason: "expired"});

export async function confirmRecoveryEmailCode(request: Req, deps: RecoveryDeps = defaultRecoveryDeps) {
  const uid = requireUid(request);
  const raw = (request.data && typeof request.data === "object" ? (request.data as {code?: unknown}).code : undefined);
  const code = normalizeActivationCode(raw);
  if (!code) throw new HttpsError("invalid-argument", "Enter the 10-character code from your email.");

  const contactRef = db().collection(RECOVERY_CONTACTS).doc(uid);
  const verificationRef = db().collection(RECOVERY_VERIFICATIONS).doc(uid);
  const contact = await contactRef.get();
  if (!contact.exists) {
    throw new HttpsError("failed-precondition", "Recovery email verification is not available for this account.");
  }
  // Already verified: report success and make sure the Auth flag agrees (a safe retry after a partial failure).
  if (contact.data()?.verifiedAt) {
    await ensureAuthVerified(uid);
    return {verified: true};
  }

  // Reserve the attempt before checking anything, so concurrent guesses cannot exceed the cap.
  const reserved = await db().runTransaction(async (transaction) => {
    const [verification, current] = await Promise.all([transaction.get(verificationRef), transaction.get(contactRef)]);
    const data = verification.data();
    const expired = !data || !(data.expiresAt instanceof Timestamp) || (data.expiresAt as Timestamp).toMillis() <= deps.now();
    if (!data || expired || data.emailHash !== current.data()?.emailHash) {
      if (verification.exists) transaction.delete(verificationRef);
      return null;
    }
    if (Number(data.attempts ?? 0) >= MAX_ATTEMPTS) return null;
    transaction.update(verificationRef, {attempts: FieldValue.increment(1)});
    return {hash: String(data.hash), salt: String(data.salt), attempts: Number(data.attempts ?? 0) + 1};
  });
  if (!reserved) throw EXPIRED();

  const matches = await verifyActivationCode(code, {
    hash: reserved.hash, salt: reserved.salt, issuedAt: new Date(deps.now()), expiresAt: new Date(deps.now()),
  });
  if (!matches) {
    throw new HttpsError("failed-precondition", "That code is not correct. Check it or request a new one.",
      {reason: "invalid-code", attemptsRemaining: Math.max(0, MAX_ATTEMPTS - reserved.attempts)});
  }

  const profile = (await db().collection("users").doc(uid).get()).data() ?? {};
  const actorName = [profile.firstName, profile.lastName].map((v) => String(v ?? "")).filter(Boolean).join(" ") || "Student";
  await db().runTransaction(async (transaction) => {
    const [verification, current] = await Promise.all([transaction.get(verificationRef), transaction.get(contactRef)]);
    // Single use: a concurrent or repeated redemption finds the code already consumed.
    if (!verification.exists || verification.data()?.hash !== reserved.hash ||
      verification.data()?.emailHash !== current.data()?.emailHash) {
      throw EXPIRED();
    }
    transaction.delete(verificationRef);
    transaction.update(contactRef, {verifiedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    writeAudit(transaction, db(), {
      actorId: uid, actorNameSnapshot: actorName, actorRoleSnapshot: "student",
      action: "STUDENT_RECOVERY_EMAIL_VERIFIED", category: AUDIT_CATEGORIES.authentication,
      targetType: "student", targetId: String(current.data()?.studentKey ?? ""), metadata: {userId: uid},
    });
  });
  await ensureAuthVerified(uid);
  return {verified: true};
}

// ------------------------------------------------------------------ password reset

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

export async function resetPasswordForStudentId(request: Req, deps: RecoveryDeps = defaultRecoveryDeps) {
  const started = Date.now();
  const raw = request.data && typeof request.data === "object" ? (request.data as {studentId?: unknown}).studentId : undefined;
  const key = canonicalLoginId(raw);
  const now = deps.now();
  await consumeWindow("reset_id", key, RESET_ID_LIMIT, now);
  await consumeWindow("reset_ip", callerIp(request), IP_LIMIT, now);

  try {
    await sendResetIfEligible(key, deps);
  } catch (error) {
    // Failures must not be distinguishable from "no such account", so they are logged, never returned.
    logError("Student password reset could not be completed", {
      correlationId: randomUUID(), error: error instanceof Error ? error.message : String(error),
    });
  }
  const wait = deps.minResetResponseMs - (Date.now() - started);
  if (wait > 0) await sleep(wait);
  return {accepted: true};
}

async function sendResetIfEligible(key: string, deps: RecoveryDeps): Promise<void> {
  const alias = studentAuthAliasEmail(key);
  const reservation = (await db().collection("student_id_reservations").doc(key).get()).data();
  const uid = typeof reservation?.userId === "string" ? reservation.userId : "";
  if (!uid) return;
  const contact = (await db().collection(RECOVERY_CONTACTS).doc(uid).get()).data();
  // Only a recovery address that the student proved they control, for this exact Student ID, is ever used.
  if (!contact || !contact.verifiedAt || contact.studentKey !== key || typeof contact.email !== "string") return;
  const user = await getAuth().getUser(uid).catch(() => null);
  if (!user || user.disabled || user.email !== alias || !user.emailVerified) return;

  const link = await deps.resetLink(alias);
  await deps.sendMail({
    to: contact.email,
    subject: "Reset your MindMate password",
    text: [
      "A password reset was requested for your MindMate account.",
      "",
      `Choose a new password: ${link}`,
      "",
      "This secure link expires automatically. If you did not request it, you can ignore this email.",
    ].join("\n"),
    html: `<div style="font-family:Arial,Helvetica,sans-serif;color:#242424"><h2>Reset your MindMate password</h2>`
      + `<p>A password reset was requested for your MindMate account.</p>`
      + `<p><a href="${escapeHtml(link)}" style="display:inline-block;background:#242424;color:#fff;text-decoration:none;padding:12px 20px;border-radius:8px">Choose a new password</a></p>`
      + `<p style="color:#77736d;font-size:12px">This secure link expires automatically. If you did not request it, you can ignore this email.</p></div>`,
  });
}

// ------------------------------------------------------------------ callables

const options = {secrets: [smtpAppPassword]};

export const requestStudentRecoveryEmailCode = onCall(
  {enforceAppCheck: true, ...options}, (request) => requestRecoveryEmailCode(request));
export const requestStudentRecoveryEmailCodeDev = onCall(
  {enforceAppCheck: false, ...options}, (request) => {
    assertDevEndpointAllowed();
    return requestRecoveryEmailCode(request);
  });
export const confirmStudentRecoveryEmailCode = onCall(
  {enforceAppCheck: true}, (request) => confirmRecoveryEmailCode(request));
export const confirmStudentRecoveryEmailCodeDev = onCall(
  {enforceAppCheck: false}, (request) => {
    assertDevEndpointAllowed();
    return confirmRecoveryEmailCode(request);
  });
export const requestStudentPasswordReset = onCall(
  {enforceAppCheck: true, ...options}, (request) => resetPasswordForStudentId(request));
export const requestStudentPasswordResetDev = onCall(
  {enforceAppCheck: false, ...options}, (request) => {
    assertDevEndpointAllowed();
    return resetPasswordForStudentId(request);
  });
