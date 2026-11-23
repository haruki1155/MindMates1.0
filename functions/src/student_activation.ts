import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {releaseStudentAlias} from "./student_recovery_contacts";

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

export function activationError(reason: Exclude<Reason, "invalid-input">): HttpsError {
  return new HttpsError(COPY[reason].code, COPY[reason].message, {reason});
}

export function database(): FirebaseFirestore.Firestore {
  return getFirestore();
}

function lockedUntilMillis(data: FirebaseFirestore.DocumentData | undefined): number {
  const value = data?.lockedUntil;
  return value instanceof Timestamp ? value.toMillis() : 0;
}

/**
 * Lockout check and attempt reservation in one transaction, before any identity check. Reserving the attempt up
 * front means concurrent guesses cannot slip past the limit. Returns false when the Student No. is locked.
 */
export async function reserveAttempt(key: string): Promise<boolean> {
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

export async function clearAttempts(key: string): Promise<void> {
  await database().collection("student_activation_attempts").doc(key).delete();
}

/** True when any Firebase Auth account (employee, legacy or pre-alias student) already uses this address. */
export async function authEmailTaken(address: string): Promise<boolean> {
  try {
    await getAuth().getUserByEmail(address);
    return true;
  } catch (error) {
    if ((error as {code?: string})?.code === "auth/user-not-found") return false;
    throw error;
  }
}

/**
 * Creates the student's alias account. If the alias is held by a disabled account that an administrator revoked
 * for this same roster row (its uid is recorded in the row's revokedUserIds), that account is moved off the alias
 * (it stays disabled) and the creation is retried once, so a revoke followed by a new code always works.
 *
 * Any other holder is an unrelated account: it is never modified or deleted, whatever its age or records, and the
 * activation fails closed (auth/email-already-exists).
 */
export async function createAliasUser(authEmail: string, password: string, row: FirebaseFirestore.DocumentData): Promise<string> {
  const create = () => getAuth().createUser({email: authEmail, password, emailVerified: false, disabled: false});
  try {
    return (await create()).uid;
  } catch (error) {
    if ((error as {code?: string})?.code !== "auth/email-already-exists") throw error;
    const occupant = await getAuth().getUserByEmail(authEmail).catch(() => null);
    const revoked = Array.isArray(row.revokedUserIds) ? row.revokedUserIds : [];
    if (!occupant || !occupant.disabled || !revoked.includes(occupant.uid)) throw error;
    await releaseStudentAlias(occupant.uid);
    return (await create()).uid;
  }
}

/**
 * The activation-code workflow is retired: a code plus a date of birth must never create or link a student identity,
 * because that path bypasses PACC approval (see student_account_setup.ts). Both endpoints stay exported only so older
 * installed apps get a clear refusal instead of a missing-function error. They read nothing from the request and
 * touch no Auth user, roster record, reservation or recovery contact. There is deliberately no switch to re-enable them.
 */
function activationRetired(): never {
  throw new HttpsError(
    "failed-precondition",
    "Activation codes are no longer used. Set up your account with your Student No., name and date of birth.",
    {reason: "activation-retired"},
  );
}

export const activateStudentAccount = onCall({enforceAppCheck: true}, activationRetired);
export const activateStudentAccountDev = onCall({enforceAppCheck: false}, activationRetired);
