import {HttpsError} from "firebase-functions/v2/https";

import {canonicalLoginId} from "./account_recovery";
import {normalizeRecoveryContactEmail} from "./student_recovery_contacts";
import {normalizeName, parseDateKey} from "./student_roster_domain";

/**
 * Identity matching for no-code student account setup. A student is found in the imported roster by Student
 * Number + full name + date of birth. These are knowledge-based attributes, not secrets, so matching only selects
 * the candidate record; the account is claimed after the student proves control of a personal email.
 */
export type StudentClaimInput = {
  studentNo: string;
  studentKey: string;
  firstName: string;
  middleName: string;
  lastName: string;
  dateOfBirthKey: string;
};

export type NormalizedIdentity = {firstName: string; middleName: string; lastName: string; dateOfBirthKey: string};

function normalizedName(value: unknown): string {
  return typeof value === "string" ? normalizeName(value) : "";
}

export function readStudentClaimInput(raw: unknown): StudentClaimInput {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "Enter valid student identity details.");
  }
  const fields = raw as Record<string, unknown>;
  const studentNo = typeof fields.studentNo === "string" ? fields.studentNo.trim() : "";
  const studentKey = canonicalLoginId(studentNo);
  const firstName = normalizedName(fields.firstName);
  const lastName = normalizedName(fields.lastName);
  const middleName = normalizedName(fields.middleName);
  const dateOfBirthKey = parseDateKey(fields.dateOfBirth);
  const middleOk = fields.middleName === undefined ||
    (typeof fields.middleName === "string" && (!fields.middleName.trim() || middleName.length > 0));
  if (!firstName || !lastName || !dateOfBirthKey || !middleOk) {
    throw new HttpsError("invalid-argument", "Enter valid student identity details.");
  }
  return {studentNo, studentKey, firstName, middleName, lastName, dateOfBirthKey};
}

/** The roster row's identity, normalized the same way, for storing with a pending claim and re-checking later. */
export function rosterIdentity(row: Record<string, unknown>): NormalizedIdentity {
  return {
    firstName: normalizedName(row.firstName), middleName: normalizedName(row.middleName),
    lastName: normalizedName(row.surname), dateOfBirthKey: String(row.dateOfBirthKey ?? ""),
  };
}

export function claimIdentityMatches(input: StudentClaimInput, row: Record<string, unknown>): boolean {
  const identity = rosterIdentity(row);
  return input.studentKey === row.studentKey &&
    input.firstName === identity.firstName &&
    input.lastName === identity.lastName &&
    (!input.middleName || input.middleName === identity.middleName) &&
    input.dateOfBirthKey === identity.dateOfBirthKey;
}

/** Whether the identity captured when setup started still matches the roster row (re-checked when claiming). */
export function storedIdentityMatches(stored: Partial<NormalizedIdentity> | undefined, row: Record<string, unknown>): boolean {
  if (!stored) return false;
  const identity = rosterIdentity(row);
  return stored.firstName === identity.firstName && stored.lastName === identity.lastName &&
    (!stored.middleName || stored.middleName === identity.middleName) && stored.dateOfBirthKey === identity.dateOfBirthKey;
}

const RESERVED_EMAIL_DOMAINS = ["ucu.edu.ph", "mindmate.local"];

/**
 * Students use a personal email. The institution's staff-only domain and MindMate's reserved synthetic domains
 * (including the Student ID login alias) can never be a recovery address.
 */
export function isAllowedPersonalEmail(value: unknown): boolean {
  const email = normalizeRecoveryContactEmail(value);
  if (!email) return false;
  const domain = email.slice(email.lastIndexOf("@") + 1);
  return !RESERVED_EMAIL_DOMAINS.some((reserved) => domain === reserved || domain.endsWith(`.${reserved}`));
}

export function readSetupPassword(value: unknown): string {
  if (typeof value !== "string" || value.length < 8 || value.length > 4096) {
    throw new HttpsError("invalid-argument", "Password must be at least 8 characters.");
  }
  return value;
}
