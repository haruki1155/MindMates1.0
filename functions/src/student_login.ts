import {randomUUID} from "node:crypto";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {error as logError} from "firebase-functions/logger";
import {onCall} from "firebase-functions/v2/https";

import {canonicalLoginId, smtpAppPassword} from "./account_recovery";
import {AUDIT_CATEGORIES, writeAudit} from "./audit";
import {
  RecoveryDeps, assertDevEndpointAllowed, callerIp, consumeWindow, currentProjectId, defaultRecoveryDeps,
} from "./student_account_recovery";
import {authEmailTaken} from "./student_activation";
import {studentAuthAliasEmail} from "./student_auth_alias";
import {isAllowedPersonalEmail} from "./student_claim_domain";
import {
  FIRST_LOGIN_CLAIM, MAX_ISSUES_PER_DAY, TEMP_PASSWORD_TTL_MS, generateTemporaryPassword, hashPassword, mayReissue,
} from "./student_login_domain";
import {rosterStudentProfile} from "./student_profile";
import {RECOVERY_CONTACTS, RECOVERY_EMAILS, normalizeRecoveryContactEmail, recoveryEmailHash} from "./student_recovery_contacts";

if (!getApps().length) initializeApp();

/**
 * Student login by roster email. A student asks for a login by Student ID; if the ID is on the roster with a usable
 * email, the system creates the Student ID account (once) and emails the Student ID and a temporary password to that
 * roster address and nowhere else. PACC chose that mailbox, so no code or approval step is needed. The session that
 * signs in with the temporary password carries the `firstLoginPending` claim until the permanent password is set.
 * The response is the same for every outcome.
 */
const db = () => getFirestore();
export const ISSUANCE = "student_login_issuance";
export const CLAIM_METHOD = "roster-email-login";
const IP_LIMIT = 10;
const ID_LIMIT = 3;
const DAY_MS = 24 * 60 * 60 * 1000;
const LOCK_MS = 2 * 60 * 1000;

export type LoginDeps = {now: () => number; sendMail: RecoveryDeps["sendMail"]; minResponseMs: number};
export const defaultLoginDeps: LoginDeps = {now: () => Date.now(), sendMail: defaultRecoveryDeps.sendMail, minResponseMs: 700};
type Req = {data?: unknown; rawRequest?: {ip?: string; socket?: {remoteAddress?: string}}};

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const escapeHtml = (v: string) => v.replace(/[&<>'"]/g, (c) => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", "\"": "&quot;"})[c] ?? c);

/** The school's registered email for the record, or null when the row has none (or an unusable one). */
export function rosterEmail(row: FirebaseFirestore.DocumentData | undefined): string | null {
  const email = normalizeRecoveryContactEmail(row?.contactEmail);
  return email && isAllowedPersonalEmail(email) ? email : null;
}

export async function requestLogin(request: Req, deps: LoginDeps = defaultLoginDeps) {
  const started = Date.now();
  const now = deps.now();
  // The per-caller limit may answer "too many requests"; the per-Student-ID limit never does, so nobody can use it
  // to probe an ID or to lock one out. Real and unknown IDs are counted identically.
  await consumeWindow("login_ip", callerIp(request), IP_LIMIT, now);
  let key: string | null = null;
  try {
    const raw = request.data && typeof request.data === "object" ? (request.data as {studentId?: unknown}).studentId : undefined;
    key = canonicalLoginId(raw);
  } catch {
    key = null;
  }
  try {
    if (key && await consumeWindow("login_id", key, ID_LIMIT, now, true)) await issueIfEligible(key, deps);
  } catch (error) {
    // A failure must not be distinguishable from "no such student", so it is logged, never returned.
    logError("Student login could not be issued", {
      correlationId: randomUUID(), error: error instanceof Error ? error.message : String(error),
    });
  }
  const wait = deps.minResponseMs - (Date.now() - started);
  if (wait > 0) await sleep(wait);
  return {accepted: true as const};
}

type Plan = {kind: "none"} | {kind: "create"; uid: string} | {kind: "reissue"; uid: string};

async function issueIfEligible(key: string, deps: LoginDeps): Promise<void> {
  const rosterRef = db().collection("student_roster").doc(key);
  const row = (await rosterRef.get()).data();
  const email = rosterEmail(row);
  // A row this flow already linked may be reissued while its first-login issuance is open; any other activated row
  // (old flow, administrator approval) is a finished account and is never touched.
  const ours = row?.activated === true && row.claimMethod === CLAIM_METHOD;
  if (!row || row.status !== "active" || (row.activated === true && !ours) || !email) return;
  // An address already used by some other account can never identify this student.
  if (await authEmailTaken(email)) return;

  const issuanceRef = db().collection(ISSUANCE).doc(key);
  const now = deps.now();
  // One transaction decides who may act, so concurrent requests cannot create two identities or send two emails.
  const plan = await db().runTransaction(async (transaction): Promise<Plan> => {
    const snap = await transaction.get(issuanceRef);
    const d = snap.data();
    if (!d) {
      const uid = randomUUID();
      transaction.create(issuanceRef, {
        studentKey: key, uid, state: "creating", lockUntilMs: now + LOCK_MS, issuedInWindow: 0, windowStartMs: now,
        lastSentAtMs: 0, expiresAtMs: 0, createdAt: FieldValue.serverTimestamp(),
      });
      return {kind: "create", uid};
    }
    const uid = String(d.uid);
    if (d.state === "creating") {
      if (Number(d.lockUntilMs ?? 0) > now) return {kind: "none"};
      transaction.update(issuanceRef, {lockUntilMs: now + LOCK_MS});
      return {kind: "create", uid};
    }
    if (d.state !== "issued" && d.state !== "send-failed") return {kind: "none"};
    const timing = {
      expiresAtMs: Number(d.expiresAtMs ?? 0), lastSentAtMs: Number(d.lastSentAtMs ?? 0), issuedInWindow: Number(d.issuedInWindow ?? 0),
    };
    if (d.state !== "send-failed" && !mayReissue(timing, now)) return {kind: "none"};
    const freshWindow = now - Number(d.windowStartMs ?? 0) >= DAY_MS;
    transaction.update(issuanceRef, {
      lastSentAtMs: now, windowStartMs: freshWindow ? now : d.windowStartMs,
      issuedInWindow: freshWindow ? 1 : Math.min(timing.issuedInWindow + 1, MAX_ISSUES_PER_DAY),
    });
    return {kind: "reissue", uid};
  });
  if (plan.kind === "none") return;

  const password = generateTemporaryPassword();
  const stored = hashPassword(password);
  const alias = studentAuthAliasEmail(key);
  try {
    if (plan.kind === "create") await createIdentity(key, plan.uid, alias, email, password, stored, now);
    else await rotatePassword(issuanceRef, plan.uid, alias, password, stored, now);
  } catch (error) {
    if (plan.kind === "create") {
      await getAuth().deleteUser(plan.uid).catch(() => undefined);
      await issuanceRef.delete().catch(() => undefined);
    } else {
      await issuanceRef.update({state: "send-failed"}).catch(() => undefined);
    }
    throw error;
  }
  try {
    await sendLoginMail(deps, email, String(row.studentNo ?? key), password);
  } catch (error) {
    await issuanceRef.update({state: "send-failed"}).catch(() => undefined);
    throw error;
  }
}

async function createIdentity(
  key: string, uid: string, alias: string, email: string, password: string, stored: {hash: string; salt: string}, now: number,
): Promise<void> {
  try {
    await getAuth().createUser({uid, email: alias, password, emailVerified: true, disabled: false});
  } catch (error) {
    // Resuming an interrupted creation of this same issuance: the account exists, so only set the password again.
    if ((error as {code?: string})?.code !== "auth/uid-already-exists") throw error;
    await getAuth().updateUser(uid, {password});
  }
  // Confined before anything is delivered: the password reaches nobody until the email is sent below.
  await getAuth().setCustomUserClaims(uid, {[FIRST_LOGIN_CLAIM]: true});
  const emailHash = recoveryEmailHash(email);
  const rosterRef = db().collection("student_roster").doc(key);
  const reservationRef = db().collection("student_id_reservations").doc(key);
  const emailRef = db().collection(RECOVERY_EMAILS).doc(emailHash);
  await db().runTransaction(async (transaction) => {
    const [roster, reservation, emailReservation] = await Promise.all([
      transaction.get(rosterRef), transaction.get(reservationRef), transaction.get(emailRef),
    ]);
    const live = roster.data();
    if (!live || live.status !== "active" || live.activated === true || rosterEmail(live) !== email) throw new Error("roster-changed");
    if (reservation.exists && reservation.data()?.userId !== uid) throw new Error("student-id-reserved");
    if (emailReservation.exists && emailReservation.data()?.uid !== uid) throw new Error("email-reserved");
    const studentNo = String(live.studentNo ?? key);
    transaction.set(db().collection("users").doc(uid), {
      ...rosterStudentProfile(live, {uid, email, studentNo, emailVerified: true, claimMethod: CLAIM_METHOD}),
      mustChangePassword: true,
    });
    transaction.set(reservationRef, {userId: uid, studentId: studentNo, createdAt: FieldValue.serverTimestamp()});
    transaction.set(emailRef, {uid, studentKey: key, createdAt: FieldValue.serverTimestamp()});
    transaction.set(db().collection(RECOVERY_CONTACTS).doc(uid), {
      uid, studentKey: key, email, emailHash, verifiedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(rosterRef, {
      activated: true, userId: uid, activationCode: null, claimMethod: CLAIM_METHOD,
      activatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(db().collection(ISSUANCE).doc(key), {
      state: "issued", ...stored, expiresAtMs: now + TEMP_PASSWORD_TTL_MS, lastSentAtMs: now, issuedInWindow: 1, windowStartMs: now,
    });
    writeAudit(transaction, db(), {
      actorId: "system", actorNameSnapshot: "Student login by roster email", actorRoleSnapshot: "system",
      action: "STUDENT_LOGIN_ISSUED", category: AUDIT_CATEGORIES.userManagement, targetType: "student", targetId: key,
      metadata: {studentNo, userId: uid, claimMethod: CLAIM_METHOD},
    });
  });
}

async function rotatePassword(
  issuanceRef: FirebaseFirestore.DocumentReference, uid: string, alias: string, password: string,
  stored: {hash: string; salt: string}, now: number,
): Promise<void> {
  const user = await getAuth().getUser(uid);
  if (user.email !== alias || user.disabled) throw new Error("identity-mismatch");
  await getAuth().updateUser(uid, {password});
  await getAuth().setCustomUserClaims(uid, {[FIRST_LOGIN_CLAIM]: true});
  await issuanceRef.update({state: "issued", ...stored, expiresAtMs: now + TEMP_PASSWORD_TTL_MS});
}

async function sendLoginMail(deps: LoginDeps, to: string, studentNo: string, password: string): Promise<void> {
  const lines = [
    "Your MindMate login", "",
    `Student ID: ${studentNo}`, `Temporary password: ${password}`, "",
    "Sign in with these, then choose your own password. The temporary password works for 24 hours.",
    "If you did not ask for this, you can ignore this email.",
  ];
  await deps.sendMail({
    to, subject: "Your MindMate login", text: lines.join("\n"),
    html: `<div style="font-family:Arial,Helvetica,sans-serif;color:#242424"><h2>Your MindMate login</h2>`
      + `<p>Student ID: <strong>${escapeHtml(studentNo)}</strong><br>Temporary password: <strong style="font-family:monospace">${escapeHtml(password)}</strong></p>`
      + `<p>Sign in with these, then choose your own password. The temporary password works for 24 hours.</p>`
      + `<p style="color:#77736d;font-size:12px">If you did not ask for this, you can ignore this email.</p></div>`,
  });
}

// ------------------------------------------------------------------ callables

export const requestStudentLogin = onCall(
  {enforceAppCheck: true, secrets: [smtpAppPassword]}, (request) => requestLogin(request));
export const requestStudentLoginDev = onCall(
  {enforceAppCheck: false, secrets: [smtpAppPassword]}, (request) => {
    assertDevEndpointAllowed(currentProjectId());
    return requestLogin(request);
  });
