import {randomUUID} from "node:crypto";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";

import {defaultActivityFields} from "./account_integrity";
import {canonicalLoginId} from "./account_recovery";
import {AUDIT_CATEGORIES, writeAudit} from "./audit";
import {
  StoredActivationCode, hashActivationCode, normalizeActivationCode, parseDateKey, verifyActivationCode,
} from "./student_roster_domain";
import {studentAuthAliasEmail} from "./student_auth_alias";
import {
  RECOVERY_CONTACTS, RECOVERY_EMAILS, normalizeRecoveryContactEmail, recoveryEmailHash, releaseStudentAlias,
} from "./student_recovery_contacts";

if (!getApps().length) initializeApp();

const MAX_FAILURES = 5;
const LOCK_MS = 30 * 60 * 1000;
/**
 * TTL on an attempts doc: the full lockout window plus a 24-hour margin. `student_activation_attempts`
 * is written from an unauthenticated endpoint keyed by any canonical-shaped string, so without a TTL the
 * collection grows without bound. The margin is deliberately larger than Firestore's own "deleted within
 * 24 hours of expiry" guarantee is tight, so a live lockout can never be swept away early; a doc older
 * than that protects nothing, because the lock has long since lapsed and a lapsed lock starts a fresh window.
 */
const ATTEMPT_TTL_MS = LOCK_MS + 24 * 60 * 60 * 1000;

type Reason = "mismatch" | "expired" | "already-activated" | "email-in-use" | "invalid-input";

const COPY: Record<Exclude<Reason, "invalid-input">, {code: "not-found" | "deadline-exceeded" | "already-exists"; message: string}> = {
  "mismatch": {code: "not-found", message: "Those details don't match our records."},
  "expired": {code: "deadline-exceeded", message: "This activation code has expired. Ask the PACC office for a new one."},
  "already-activated": {code: "already-exists", message: "This account is already activated. Sign in or use Forgot password."},
  "email-in-use": {code: "already-exists", message: "This email address is already registered."},
};

function activationError(reason: Exclude<Reason, "invalid-input">): HttpsError {
  return new HttpsError(COPY[reason].code, COPY[reason].message, {reason});
}

function invalidInput(message: string): HttpsError {
  return new HttpsError("invalid-argument", message, {reason: "invalid-input"});
}

function database(): FirebaseFirestore.Firestore {
  return getFirestore();
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

function lockedUntilMillis(data: FirebaseFirestore.DocumentData | undefined): number {
  const value = data?.lockedUntil;
  return value instanceof Timestamp ? value.toMillis() : 0;
}

/**
 * Lockout check and attempt reservation in one transaction, before any identity check. Reserving the attempt up
 * front means concurrent guesses cannot slip past the limit. Returns false when the Student No. is locked.
 */
async function reserveAttempt(key: string): Promise<boolean> {
  const db = database();
  const ref = db.collection("student_activation_attempts").doc(key);
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const now = Date.now();
    const lockedUntil = lockedUntilMillis(snap.data());
    if (lockedUntil > now) return false;
    // A lapsed lock starts a fresh window.
    const previous = lockedUntil > 0 ? 0 : Number(snap.data()?.failedCount ?? 0);
    const failedCount = previous + 1;
    transaction.set(ref, {
      studentKey: key, failedCount,
      lockedUntil: failedCount >= MAX_FAILURES ? Timestamp.fromMillis(now + LOCK_MS) : null,
      expiresAt: Timestamp.fromMillis(now + ATTEMPT_TTL_MS),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

async function clearAttempts(key: string): Promise<void> {
  await database().collection("student_activation_attempts").doc(key).delete();
}

/** True when any Firebase Auth account (employee, legacy or pre-alias student) already uses this address. */
async function authEmailTaken(address: string): Promise<boolean> {
  try {
    await getAuth().getUserByEmail(address);
    return true;
  } catch (error) {
    if ((error as {code?: string})?.code === "auth/user-not-found") return false;
    throw error;
  }
}

/**
 * Creates the student's alias account. If the alias is still held by a disabled account that an administrator
 * revoked for this same roster row, that account is moved off the alias first (it stays disabled) and the
 * creation is retried once, so a revoke followed by a new code always works. Anything else holding the alias
 * is left alone and surfaces as auth/email-already-exists.
 */
async function createAliasUser(
  authEmail: string, password: string, row: FirebaseFirestore.DocumentData, key: string,
): Promise<string> {
  const create = () => getAuth().createUser({email: authEmail, password, emailVerified: false, disabled: false});
  try {
    return (await create()).uid;
  } catch (error) {
    if ((error as {code?: string})?.code !== "auth/email-already-exists") throw error;
    const occupant = await getAuth().getUserByEmail(authEmail).catch(() => null);
    if (!occupant) throw error;
    const revoked = Array.isArray(row.revokedUserIds) ? row.revokedUserIds : [];
    if (occupant.disabled && revoked.includes(occupant.uid)) {
      await releaseStudentAlias(occupant.uid);
    } else if (await isAbandonedAlias(occupant, key)) {
      // Anyone can create a Firebase Auth user with a guessable alias; such an account has no profile, contact or
      // reservation and must not be able to block the real student. Removing it frees the alias.
      await getAuth().deleteUser(occupant.uid);
    } else {
      throw error;
    }
    return (await create()).uid;
  }
}

/**
 * An alias holder that nothing in the system refers to and that is old enough not to be a concurrent activation
 * still in flight (which creates the Auth user a moment before its profile).
 */
async function isAbandonedAlias(occupant: {uid: string; metadata: {creationTime: string}}, key: string): Promise<boolean> {
  const minAgeMs = Number(process.env.STUDENT_ALIAS_ORPHAN_MIN_AGE_MS ?? 2 * 60 * 1000);
  const created = Date.parse(occupant.metadata.creationTime);
  if (!Number.isFinite(created) || Date.now() - created < minAgeMs) return false;
  const db = database();
  const [profile, contact, reservation] = await Promise.all([
    db.collection("users").doc(occupant.uid).get(),
    db.collection(RECOVERY_CONTACTS).doc(occupant.uid).get(),
    db.collection("student_id_reservations").doc(key).get(),
  ]);
  return !profile.exists && !contact.exists && reservation.data()?.userId !== occupant.uid;
}

async function deleteAuthUser(uid: string, correlationId: string): Promise<void> {
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    console.error("student_activation_auth_cleanup_failed", {correlationId, code: (error as {code?: string})?.code ?? "unknown"});
  }
}

async function activateStudentAccountHandler(request: CallableRequest) {
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
    uid = await createAliasUser(authEmail, input.password, row, key);
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
      transaction.create(profileRef, {
        id: uid, email: input.email, emailVerified: false, studentIdLogin: true, schoolId: studentNo,
        firstName: String(live.firstName ?? ""), middleName: String(live.middleName ?? ""), lastName: String(live.surname ?? ""),
        name: [live.firstName, live.middleName, live.surname].map((v) => String(v ?? "")).filter(Boolean).join(" "),
        populationRole: "student", declaredRole: "student", role: "student",
        collegeId: String(live.collegeId ?? ""), college: String(live.college ?? ""),
        courseId: String(live.courseId ?? ""), course: String(live.course ?? ""),
        departmentId: String(live.departmentId ?? ""), department: String(live.department ?? ""),
        yearLevel: String(live.yearLevel ?? ""),
        dateOfBirth: live.dateOfBirth ?? Timestamp.fromDate(new Date(`${live.dateOfBirthKey}T00:00:00Z`)),
        dateOfBirthKey: String(live.dateOfBirthKey ?? ""),
        gender: "", sector: "", position: "", employeeId: "",
        accessRole: "appUser", verificationStatus: "verified", profileVersion: 3,
        verifiedAt: FieldValue.serverTimestamp(), verifiedBy: "roster-activation",
        personalInfoRequired: true, rosterLinked: true,
        ...defaultActivityFields(),
      });
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

export const activateStudentAccount = onCall({enforceAppCheck: true}, activateStudentAccountHandler);
export const activateStudentAccountDev = onCall({enforceAppCheck: false}, activateStudentAccountHandler);
