import {canonicalLoginId} from "./account_recovery";

/**
 * Roster-activated students sign in with their Student ID. Firebase Auth needs an email-shaped
 * identifier, so each student's Auth account uses a deterministic alias derived from the canonical
 * Student ID. The student's real email is only a verified recovery contact (see
 * student_account_recovery.ts) and is never the Auth email.
 *
 * The alias lives on its own subdomain so it can never collide with the legacy School-ID alias
 * (`authEmailForSchoolId`, `@mindmate.local`), which stays unchanged for legacy accounts. The client
 * mirrors this derivation in AuthRepository.studentAuthAliasEmail; keep the shared test vectors in sync.
 */
export const STUDENT_AUTH_ALIAS_DOMAIN = "students.mindmate.local";

export function studentAuthAliasEmail(studentId: unknown): string {
  return `${canonicalLoginId(studentId).toLowerCase()}@${STUDENT_AUTH_ALIAS_DOMAIN}`;
}

export function isStudentAuthAlias(email: string | null | undefined): boolean {
  return typeof email === "string" && email.trim().toLowerCase().endsWith(`@${STUDENT_AUTH_ALIAS_DOMAIN}`);
}
