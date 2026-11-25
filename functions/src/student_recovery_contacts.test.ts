import assert from "node:assert/strict";
import test from "node:test";

import {maskEmail, normalizeRecoveryContactEmail, recoveryEmailHash} from "./student_recovery_contacts";

test("recovery emails normalize case and whitespace and reject malformed values", () => {
  assert.equal(normalizeRecoveryContactEmail("  Student@Example.COM "), "student@example.com");
  for (const bad of ["", "not-an-email", "a@b", "a b@c.com", `${"a".repeat(250)}@x.com`, null, undefined, 7, {}]) {
    assert.equal(normalizeRecoveryContactEmail(bad), null, String(bad));
  }
});

test("the uniqueness key is a stable, case-insensitive hash that never contains the address", () => {
  const a = recoveryEmailHash("student@example.com");
  assert.match(a, /^[0-9a-f]{64}$/);
  assert.equal(a, recoveryEmailHash(normalizeRecoveryContactEmail("STUDENT@Example.com")!));
  assert.notEqual(a, recoveryEmailHash("other@example.com"));
  assert.ok(!a.includes("student"));
});

test("masked addresses never reveal the whole local part", () => {
  assert.equal(maskEmail("juan.delacruz@example.com"), "j***@example.com");
  assert.equal(maskEmail("a@example.com"), "a***@example.com");
  assert.equal(maskEmail("not-an-email"), "***");
});
