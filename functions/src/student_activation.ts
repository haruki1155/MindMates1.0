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

if (!getApps().length) initializeApp();

const MAX_FAILURES = 5;
const LOCK_MS = 30 * 60 * 1000;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

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
  const email = typeof raw.email === "string" ? raw.email.trim().toLowerCase() : "";
  if (!EMAIL_PATTERN.test(email) || email.length > 254) throw invalidInput("Enter a valid email address.");
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
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

async function clearAttempts(key: string): Promise<void> {
  await database().collection("student_activation_attempts").doc(key).delete();
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
  const stored = row?.status === "active" ? usableStoredCode(row.activationCode) : null;
  const codeOk = await codeMatches(input.activationCode, stored);
  const dobOk = row?.dateOfBirthKey === input.dateOfBirthKey;
  if (!row || !stored || !codeOk || !dobOk) {
    console.info("student_activation_rejected", {correlationId, reason: "mismatch"});
    throw activationError("mismatch");
  }

  // Full identity match: the attempt counter no longer protects anything.
  await clearAttempts(key);
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

  // 4. Create the Auth user.
  const name = [row.firstName, row.middleName, row.surname].map((v) => String(v ?? "")).filter(Boolean).join(" ");
  let uid: string;
  try {
    uid = (await getAuth().createUser({email: input.email, password: input.password, emailVerified: false,
      disabled: false})).uid;
  } catch (error) {
    const code = (error as {code?: string})?.code ?? "";
    if (code === "auth/email-already-exists") throw activationError("email-in-use");
    if (code === "auth/invalid-email") throw invalidInput("Enter a valid email address.");
    if (code === "auth/invalid-password") throw invalidInput("Password must be at least 8 characters.");
    console.error("student_activation_auth_create_failed", {correlationId, code});
    throw new HttpsError("internal", "Account activation could not be completed.", {correlationId});
  }

  // 5. Atomic profile + reservation + roster link + audit.
  const verifiedHash = String((stored as StoredActivationCode).hash);
  const profileRef = db.collection("users").doc(uid);
  const reservationRef = db.collection("student_id_reservations").doc(key);
  try {
    await db.runTransaction(async (transaction) => {
      const [current, reservation] = await Promise.all([transaction.get(rosterRef), transaction.get(reservationRef)]);
      const live = current.data();
      if (!live || live.status !== "active" || live.activationCode?.hash !== verifiedHash) {
        throw activationError("mismatch");
      }
      if (live.activated === true) throw activationError("already-activated");
      if (reservation.exists && reservation.data()?.userId !== uid) throw activationError("already-activated");

      const studentNo = String(live.studentNo ?? key);
      transaction.create(profileRef, {
        id: uid, email: input.email, emailVerified: false, schoolId: studentNo,
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
      transaction.update(rosterRef, {
        activated: true, userId: uid, activationCode: null,
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
  return {ok: true, email: input.email};
}

export const activateStudentAccount = onCall({enforceAppCheck: true}, activateStudentAccountHandler);
export const activateStudentAccountDev = onCall({enforceAppCheck: false}, activateStudentAccountHandler);
