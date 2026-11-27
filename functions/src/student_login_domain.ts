import {randomBytes, randomInt, scryptSync, timingSafeEqual} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";

/** Auth custom claim that confines a session to the forced password change. */
export const FIRST_LOGIN_CLAIM = "firstLoginPending";
export const TEMP_PASSWORD_TTL_MS = 24 * 60 * 60 * 1000;
export const REISSUE_COOLDOWN_MS = 60 * 60 * 1000;
export const MAX_ISSUES_PER_DAY = 3;

// No 0/O, 1/l/I: the password is read from an email and typed by hand.
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
const TEMP_LENGTH = 12;

export type StoredPassword = {hash: string; salt: string};

export function generateTemporaryPassword(): string {
  let out = "";
  for (let i = 0; i < TEMP_LENGTH; i++) out += ALPHABET[randomInt(ALPHABET.length)];
  return out;
}

const scrypt = (pw: string, salt: Buffer) => scryptSync(pw, salt, 32);

export function hashPassword(pw: string): StoredPassword {
  const salt = randomBytes(16);
  return {hash: scrypt(pw, salt).toString("hex"), salt: salt.toString("hex")};
}

export function passwordMatches(pw: string, stored: StoredPassword): boolean {
  return timingSafeEqual(scrypt(pw, Buffer.from(stored.salt, "hex")), Buffer.from(stored.hash, "hex"));
}

const policy = (message: string) => new HttpsError("invalid-argument", message, {reason: "weak-password"});

export function validatePermanentPassword(pw: unknown, ctx: {studentKey: string; temporary?: StoredPassword}): void {
  if (typeof pw !== "string" || pw.length < 10 || pw.length > 128) throw policy("Use at least 10 characters.");
  if (!/[a-z]/.test(pw) || !/[A-Z]/.test(pw) || !/[0-9]/.test(pw)) {
    throw policy("Use upper-case and lower-case letters and a number.");
  }
  if (pw.toUpperCase().replace(/[^A-Z0-9]/g, "") === ctx.studentKey) throw policy("Do not use your Student ID.");
  if (ctx.temporary && passwordMatches(pw, ctx.temporary)) throw policy("Choose a different password from the temporary one.");
}

export type IssuanceTiming = {expiresAtMs: number; lastSentAtMs: number; issuedInWindow: number};

/** A new temporary password may replace the current one only when it is expired, or after a cooldown and under the daily cap. */
export function mayReissue(issuance: IssuanceTiming, now: number): boolean {
  if (issuance.expiresAtMs <= now) return true;
  return now - issuance.lastSentAtMs >= REISSUE_COOLDOWN_MS && issuance.issuedInWindow < MAX_ISSUES_PER_DAY;
}

/**
 * True when a roster Student ID already belongs to an activated, finalized
 * MindMate account (either via an earlier activation flow or after finishing
 * permanent password setup) and must not be re-issued a temporary login.
 */
export function isAlreadyActivatedRosterLogin(
  input: {
    status?: unknown;
    activated?: unknown;
    claimMethod?: unknown;
    issuanceState?: unknown;
  },
  claimMethod: string,
): boolean {
  if (input.status !== "active" || input.activated !== true) return false;
  if (input.claimMethod !== claimMethod) return true;
  const state = typeof input.issuanceState === "string" ? input.issuanceState.trim() : "";
  return state === "" || state === "completed" || state === "completing";
}
