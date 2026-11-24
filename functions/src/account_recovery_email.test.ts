import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import {
  directEmailActionLink,
  directPasswordResetLink,
  normalizeRecoveryEmail,
  resolveStaffVerificationWebUrl,
} from "./account_recovery";

test("normalizes a recovery email", () => {
  assert.equal(normalizeRecoveryEmail(" Staff@Example.edu "), "staff@example.edu");
});

test("rejects an invalid recovery email", () => {
  assert.throws(() => normalizeRecoveryEmail("not-an-email"));
});

test("moves a Firebase reset action onto an app route of the public admin host", () => {
  const result = new URL(directPasswordResetLink(
    "https://project.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=secret-code&apiKey=public-key&lang=en",
    "https://mindmate-staging.web.app",
  ));
  assert.equal(result.origin, "https://mindmate-staging.web.app");
  // Firebase Hosting reserves /__/*, so /__/auth/action would bypass the admin app's action screen.
  assert.equal(result.pathname, "/reset-password");
  assert.equal(result.searchParams.get("oobCode"), "secret-code");
  assert.equal(result.searchParams.get("apiKey"), "public-key");
  assert.equal(result.searchParams.get("mode"), "resetPassword");
});

test("moves a Firebase verification action onto /verify-email on the public admin host", () => {
  const result = new URL(directEmailActionLink(
    "https://mindmate-staging.firebaseapp.com/__/auth/action?mode=verifyEmail&oobCode=synthetic-code&apiKey=public-key&lang=en",
    "https://paaccmindmate.com",
  ));
  assert.equal(result.origin, "https://paaccmindmate.com");
  assert.equal(result.pathname, "/verify-email");
  assert.equal(result.searchParams.get("mode"), "verifyEmail");
  assert.equal(result.searchParams.get("oobCode"), "synthetic-code");
  assert.equal(result.searchParams.get("apiKey"), "public-key");
  assert.equal(result.searchParams.get("lang"), "en");
});

test("resolveStaffVerificationWebUrl falls back to the staging Firebase Hosting URL", () => {
  for (const configured of [
    "",
    "https://mindmate-admin-staging.vercel.app",
    "https://mind-mates-cd2cf.web.app",
    "https://mindmate-dev-4e91c.web.app",
    "http://paaccmindmate.com",
    "https://evil.example.com",
    "not a url",
  ]) {
    assert.equal(
      resolveStaffVerificationWebUrl(configured, "mindmate-staging"),
      "https://mindmate-staging.web.app",
      configured,
    );
  }
});

test("resolveStaffVerificationWebUrl uses the staging custom domain only when configured", () => {
  assert.equal(
    resolveStaffVerificationWebUrl("https://paaccmindmate.com/some/path", "mindmate-staging"),
    "https://paaccmindmate.com",
  );
  assert.equal(
    resolveStaffVerificationWebUrl("https://mindmate-staging.web.app/", "mindmate-staging"),
    "https://mindmate-staging.web.app",
  );
});

test("resolveStaffVerificationWebUrl keeps production on the production host", () => {
  for (const configured of [
    "",
    "https://mindmate-admin-staging.vercel.app",
    "https://paaccmindmate.com",
    "https://mindmate-staging.web.app",
    "https://mindmate-dev-4e91c.web.app",
    "http://mind-mates-cd2cf.web.app",
    "https://evil.example.com",
    "not a url",
  ]) {
    assert.equal(
      resolveStaffVerificationWebUrl(configured, "mind-mates-cd2cf"),
      "https://mind-mates-cd2cf.web.app",
      configured,
    );
  }
  assert.equal(
    resolveStaffVerificationWebUrl("https://mind-mates-cd2cf.firebaseapp.com/", "mind-mates-cd2cf"),
    "https://mind-mates-cd2cf.firebaseapp.com",
  );
});

test("resolveStaffVerificationWebUrl preserves development config", () => {
  assert.equal(
    resolveStaffVerificationWebUrl("http://localhost:5000/", "mindmate-dev-4e91c"),
    "http://localhost:5000",
  );
});

test("Vercel SPA rewrites route /verify-email and /__/auth/action without cleanUrls /index.html 404", () => {
  const repoRoot = path.resolve(__dirname, "..", "..");
  const rootVercel = JSON.parse(
    fs.readFileSync(path.join(repoRoot, "vercel.json"), "utf8"),
  ) as {cleanUrls?: boolean; rewrites?: Array<{source?: string; destination?: string}>};
  assert.equal(rootVercel.cleanUrls, true);
  assert.ok(
    rootVercel.rewrites?.some(
      (rule) => rule.source === "/(.*)" && rule.destination === "/",
    ),
  );
  assert.ok(
    !rootVercel.rewrites?.some(
      (rule) => rule.destination === "/index.html",
    ),
  );

  const webVercel = JSON.parse(
    fs.readFileSync(path.join(repoRoot, "web", "vercel.json"), "utf8"),
  ) as {rewrites?: Array<{source?: string; destination?: string}>};
  assert.ok(
    webVercel.rewrites?.some(
      (rule) => rule.source === "/verify-email" && rule.destination === "/index.html",
    ),
  );
  assert.ok(
    webVercel.rewrites?.some(
      (rule) => rule.source === "/__/auth/action" && rule.destination === "/index.html",
    ),
  );
});
