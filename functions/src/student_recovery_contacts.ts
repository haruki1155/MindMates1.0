import {createHash} from "node:crypto";
import {getAuth} from "firebase-admin/auth";
import {Transaction, getFirestore} from "firebase-admin/firestore";

/**
 * Server-only records behind Student ID sign-in. A roster-activated student's Firebase Auth email is the
 * deterministic alias (student_auth_alias.ts); the student's real email lives here as a recovery contact
 * that is only trusted for password recovery once the student has proved they control it.
 * None of these collections has a Firestore rule, so clients cannot read or write them.
 *
 *  - student_recovery_contacts/{uid}       the recovery address and when it was verified
 *  - student_recovery_emails/{sha256}      one-to-one reservation: a recovery address belongs to one student
 *  - student_recovery_verifications/{uid}  the pending emailed code (hashed, short-lived, single use)
 */
export const RECOVERY_CONTACTS = "student_recovery_contacts";
export const RECOVERY_EMAILS = "student_recovery_emails";
export const RECOVERY_VERIFICATIONS = "student_recovery_verifications";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function normalizeRecoveryContactEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const email = value.trim().toLowerCase();
  return email.length <= 254 && EMAIL_PATTERN.test(email) ? email : null;
}

export function recoveryEmailHash(emailLower: string): string {
  return createHash("sha256").update(emailLower).digest("hex");
}

export function maskEmail(email: string): string {
  const at = email.lastIndexOf("@");
  if (at < 1) return "***";
  return `${email[0]}***${email.slice(at)}`;
}

/** Deletes a student's recovery records inside a transaction. Reads must already have happened. */
export function releaseRecoveryRecords(transaction: Transaction, uid: string, emailHash: string | null): void {
  const db = getFirestore();
  transaction.delete(db.collection(RECOVERY_CONTACTS).doc(uid));
  transaction.delete(db.collection(RECOVERY_VERIFICATIONS).doc(uid));
  if (emailHash) transaction.delete(db.collection(RECOVERY_EMAILS).doc(emailHash));
}

/**
 * Frees a revoked student's Auth alias so the Student ID can be activated again. The (disabled) account
 * keeps its password and uid but moves to an address no one can derive or sign in with.
 */
export async function releaseStudentAlias(uid: string): Promise<void> {
  const tombstone = `revoked-${createHash("sha256").update(uid).digest("hex").slice(0, 32)}@revoked.mindmate.local`;
  try {
    await getAuth().updateUser(uid, {email: tombstone});
  } catch (error) {
    if ((error as {code?: string})?.code !== "auth/user-not-found") throw error;
  }
}
