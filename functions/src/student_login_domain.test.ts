import assert from "node:assert/strict";
import {test} from "node:test";

import {
  MAX_ISSUES_PER_DAY, REISSUE_COOLDOWN_MS, TEMP_PASSWORD_TTL_MS, generateTemporaryPassword, hashPassword, mayReissue,
  passwordMatches, validatePermanentPassword,
} from "./student_login_domain";

const ALPHABET = /^[ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789]{12}$/;
const MIN = 60 * 1000;
const thrown = (fn: () => void) => {
  try { fn(); } catch (error) { return error as {code?: string}; }
  return undefined;
};

test("generated temporary passwords are 12 unambiguous characters and unique", () => {
  const seen = new Set<string>();
  for (let i = 0; i < 1000; i++) {
    const pw = generateTemporaryPassword();
    assert.match(pw, ALPHABET);
    seen.add(pw);
  }
  assert.equal(seen.size, 1000);
});

test("hashPassword round-trips and never stores the password", () => {
  const stored = hashPassword("Abc123xyz789");
  assert.ok(passwordMatches("Abc123xyz789", stored));
  assert.ok(!passwordMatches("Abc123xyz788", stored));
  assert.ok(!JSON.stringify(stored).includes("Abc123xyz789"));
});

test("permanent password policy", () => {
  const temporary = hashPassword("Temp2Pass9xy");
  const ctx = {studentKey: "QA20260002", temporary};
  for (const bad of ["Sh0rt", "alllowercase123", "ALLUPPERCASE123", "NoDigitsHereAbc", "Temp2Pass9xy", "QA20260002"]) {
    assert.equal(thrown(() => validatePermanentPassword(bad, ctx))?.code, "invalid-argument", bad);
  }
  assert.equal(thrown(() => validatePermanentPassword("Str0ngPerm!9", ctx)), undefined);
});

test("reissue policy: expiry, cooldown and a daily cap", () => {
  const now = 100 * 60 * MIN;
  const base = {expiresAtMs: now + TEMP_PASSWORD_TTL_MS, lastSentAtMs: now, issuedInWindow: 1};
  assert.ok(mayReissue({...base, expiresAtMs: now - 1}, now));
  assert.ok(!mayReissue(base, now + 30 * MIN));
  assert.ok(mayReissue({...base, issuedInWindow: 2}, now + REISSUE_COOLDOWN_MS + MIN));
  assert.ok(!mayReissue({...base, issuedInWindow: MAX_ISSUES_PER_DAY}, now + REISSUE_COOLDOWN_MS + MIN));
});
