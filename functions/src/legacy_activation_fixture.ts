/**
 * TEST FIXTURE ONLY. Reproduces the retired activation-code operation so tests can build the legacy account states
 * (activated by code, unverified, cancellable, revocable) that already exist on Staging. This module is not imported
 * by index.ts or any production module and must never be exported as a callable.
 */
import {randomUUID} from "node:crypto";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {canonicalLoginId} from "./account_recovery";
import {AUDIT_CATEGORIES, writeAudit} from "./audit";
import {
  StoredActivationCode, hashActivationCode, normalizeActivationCode, parseDateKey, verifyActivationCode,
} from "./student_roster_domain";
import {rosterStudentProfile} from "./student_profile";
import {studentAuthAliasEmail} from "./student_auth_alias";
import {RECOVERY_CONTACTS, RECOVERY_EMAILS, normalizeRecoveryContactEmail, recoveryEmailHash} from "./student_recovery_contacts";
import {
  activationError, authEmailTaken, clearAttempts, createAliasUser, database, reserveAttempt,
} from "./student_activation";

function invalidInput(message: string): HttpsError {
  return new HttpsError("invalid-argument", message, {reason: "invalid-input"});
}


// A fixed dummy hash so every mismatch path costs exactly one scrypt derivation, whether or not the
// Student No. exists or has a code. Computed lazily to keep scrypt off the cold-start path of other functions.
const DUMMY_INPUT = "AAAAAAAAAA";
let dummyStored: Promise<StoredActivationCode> | null = null;
function dummyCode(): Promise<StoredActivationCode> {
  dummyStored ??= hashActivationCode(DUMMY_INPUT);
  return dummyStored;
}

function usableStoredCode(value: unknown): StoredActivationCode | null {
  const stored = value as {hash?: unknown; salt?: unknown; expiresAt?: unknown} | null | undefined;
  if (!stored || typeof stored.hash !== "string" || typeof stored.salt !== "string") return null;
  if (Buffer.from(stored.hash, "base64").length !== 32) return null;
  return stored as unknown as StoredActivationCode;
}

/** Exactly one scrypt derivation on every path. */
async function codeMatches(input: string | null, stored: StoredActivationCode | null): Promise<boolean> {
  if (input && stored) return verifyActivationCode(input, stored);
  await verifyActivationCode(DUMMY_INPUT, await dummyCode());
  return false;
}

type Input = {studentNo: unknown; activationCode: string | null; dateOfBirthKey: string; email: string; password: string};

function readInput(data: unknown): Input {
  if (!data || typeof data !== "object" || Array.isArray(data)) throw invalidInput("Enter your activation details.");
  const raw = data as Record<string, unknown>;
  const email = normalizeRecoveryContactEmail(raw.email);
  if (!email) throw invalidInput("Enter a valid email address.");
  const password = typeof raw.password === "string" ? raw.password : "";
  if (password.length < 8 || password.length > 4096) throw invalidInput("Password must be at least 8 characters.");
  const dateOfBirthKey = parseDateKey(raw.dateOfBirth);
  if (!dateOfBirthKey) throw invalidInput("Enter a valid date of birth.");
  return {studentNo: raw.studentNo, activationCode: normalizeActivationCode(raw.activationCode), dateOfBirthKey, email, password};
}

function canonicalOrNull(value: unknown): string | null {
  try {
    return canonicalLoginId(value);
  } catch {
    return null;
  }
}


async function deleteAuthUser(uid: string, correlationId: string): Promise<void> {
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    console.error("student_activation_auth_cleanup_failed", {correlationId, code: (error as {code?: string})?.code ?? "unknown"});
  }
}


async function legacyActivateHandler(request: CallableRequest) {
  const correlationId = randomUUID();
  const input = readInput(request.data);
  const db = database();

  // Unparseable Student No.: generic mismatch, no attempts doc, same scrypt cost.
  const key = canonicalOrNull(input.studentNo);
  if (!key) {
    await codeMatches(null, null);
    console.info("student_activation_rejected", {correlationId, reason: "mismatch"});
    throw activationError("mismatch");
  }

  // 1. Lockout (a locked Student No. is indistinguishable from a mismatch).
  if (!(await reserveAttempt(key))) {
    await codeMatches(null, null);
    console.info("student_activation_rejected", {correlationId, reason: "mismatch"});
    throw activationError("mismatch");
  }

  // 2. Identity: active row + matching code + exact date of birth.
  const rosterRef = db.collection("student_roster").doc(key);
  const row = (await rosterRef.get()).data();
  // An unredeemed code is checked first; otherwise the redeemed (consumed) one, so a student re-entering their
  // slip after activating learns it is already activated. Still exactly one scrypt on every path.
  const active = row?.status === "active";
  const pending = active ? usableStoredCode(row?.activationCode) : null;
  const consumed = active && !pending ? usableStoredCode(row?.consumedActivationCode) : null;
  const stored = pending ?? consumed;
  const codeOk = await codeMatches(input.activationCode, stored);
  const dobOk = row?.dateOfBirthKey === input.dateOfBirthKey;
  if (!row || !stored || !codeOk || !dobOk) {
    console.info("student_activation_rejected", {correlationId, reason: "mismatch"});
    throw activationError("mismatch");
  }

  // Full identity match: the attempt counter no longer protects anything.
  await clearAttempts(key);
  if (!pending) {
    console.info("student_activation_rejected", {correlationId, reason: "already-activated"});
    throw activationError("already-activated");
  }
  const expiresAt = (row.activationCode as {expiresAt?: unknown}).expiresAt;
  if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= Date.now()) {
    console.info("student_activation_rejected", {correlationId, reason: "expired"});
    throw activationError("expired");
  }
  // 3. Already activated.
  if (row.activated === true) {
    console.info("student_activation_rejected", {correlationId, reason: "already-activated"});
    throw activationError("already-activated");
  }

  // 4. Create the Auth user. The student signs in with the Student ID, so the Auth account uses the
  // deterministic alias derived from it; the real email is only a recovery contact (never an Auth email).
  // A real address that already belongs to any Auth account stays rejected, as before.
  const name = [row.firstName, row.middleName, row.surname].map((v) => String(v ?? "")).filter(Boolean).join(" ");
  const authEmail = studentAuthAliasEmail(key);
  const recoveryHash = recoveryEmailHash(input.email);
  if (await authEmailTaken(input.email)) throw activationError("email-in-use");
  let uid: string;
  try {
    uid = await createAliasUser(authEmail, input.password, row);
  } catch (error) {
    const code = (error as {code?: string})?.code ?? "";
    // The alias is derived from the roster key, so a clash means this Student ID is already taken.
    if (code === "auth/email-already-exists") throw activationError("already-activated");
    if (code === "auth/invalid-email") throw invalidInput("Enter a valid email address.");
    if (code === "auth/invalid-password") throw invalidInput("Password must be at least 8 characters.");
    console.error("student_activation_auth_create_failed", {correlationId, code});
    throw new HttpsError("internal", "Account activation could not be completed.", {correlationId});
  }

  // 5. Atomic profile + reservation + roster link + audit.
  const verifiedHash = String((stored as StoredActivationCode).hash);
  const profileRef = db.collection("users").doc(uid);
  const reservationRef = db.collection("student_id_reservations").doc(key);
  const contactRef = db.collection(RECOVERY_CONTACTS).doc(uid);
  const recoveryEmailRef = db.collection(RECOVERY_EMAILS).doc(recoveryHash);
  try {
    await db.runTransaction(async (transaction) => {
      const [current, reservation, recoveryEmail] = await Promise.all([
        transaction.get(rosterRef), transaction.get(reservationRef), transaction.get(recoveryEmailRef),
      ]);
      const live = current.data();
      if (live?.activated === true) throw activationError("already-activated");
      if (!live || live.status !== "active" || live.activationCode?.hash !== verifiedHash) {
        throw activationError("mismatch");
      }
      if (reservation.exists && reservation.data()?.userId !== uid) throw activationError("already-activated");
      // One recovery address backs exactly one student (compared case-insensitively).
      if (recoveryEmail.exists && recoveryEmail.data()?.uid !== uid) throw activationError("email-in-use");

      const studentNo = String(live.studentNo ?? key);
      transaction.create(profileRef, rosterStudentProfile(live, {uid, email: input.email, studentNo, emailVerified: false}));
      if (!reservation.exists) {
        transaction.create(reservationRef, {userId: uid, studentId: studentNo, createdAt: FieldValue.serverTimestamp()});
      }
      transaction.create(contactRef, {
        uid, studentKey: key, email: input.email, emailHash: recoveryHash, verifiedAt: null,
        createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(recoveryEmailRef, {uid, studentKey: key, createdAt: FieldValue.serverTimestamp()});
      transaction.update(rosterRef, {
        activated: true, userId: uid, activationCode: null,
        // Kept (hash only, never the plain code) so a cancelled unverified activation can restore the slip.
        consumedActivationCode: {
          hash: live.activationCode.hash, salt: live.activationCode.salt,
          issuedAt: live.activationCode.issuedAt ?? null, expiresAt: live.activationCode.expiresAt ?? null,
          consumedAt: FieldValue.serverTimestamp(), userId: uid,
        },
        activatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      });
      writeAudit(transaction, db, {
        actorId: uid, actorNameSnapshot: name, actorRoleSnapshot: "student",
        action: "STUDENT_ACCOUNT_ACTIVATED", category: AUDIT_CATEGORIES.userManagement,
        targetType: "student", targetId: key, metadata: {studentNo, userId: uid, correlationId},
      });
    });
  } catch (error) {
    // 6. Never leave an orphaned Auth user behind.
    await deleteAuthUser(uid, correlationId);
    const reason = error instanceof HttpsError ? (error.details as {reason?: string} | undefined)?.reason ?? error.code : "internal";
    console.info("student_activation_rejected", {correlationId, reason});
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "Account activation could not be completed.", {correlationId});
  }

  console.info("student_activation_succeeded", {correlationId});
  return {ok: true, email: input.email, authEmail};
}


/** Same call shape as the old callable (`.run({data})`). */
export const legacyActivate = {run: (request: unknown) => legacyActivateHandler(request as CallableRequest)};
