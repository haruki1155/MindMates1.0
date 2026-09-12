import assert from "node:assert/strict";
import test from "node:test";
import {directPasswordResetLink, normalizeRecoveryEmail} from "./account_recovery";

test("normalizes a recovery email", () => {
  assert.equal(normalizeRecoveryEmail(" Staff@Example.edu "), "staff@example.edu");
});

test("rejects an invalid recovery email", () => {
  assert.throws(() => normalizeRecoveryEmail("not-an-email"));
});

test("moves a Firebase reset action onto the public admin host", () => {
  const result = new URL(directPasswordResetLink(
    "https://project.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=secret-code&apiKey=public-key&lang=en",
    "https://mindmate-admin-staging.vercel.app",
  ));
  assert.equal(result.origin, "https://mindmate-admin-staging.vercel.app");
  assert.equal(result.pathname, "/__/auth/action");
  assert.equal(result.searchParams.get("oobCode"), "secret-code");
  assert.equal(result.searchParams.get("apiKey"), "public-key");
  assert.equal(result.searchParams.get("mode"), "resetPassword");
});
