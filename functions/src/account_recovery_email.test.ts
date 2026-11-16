import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import {
  directEmailActionLink,
  directPasswordResetLink,
  normalizeRecoveryEmail,
  resolveAdminWebUrl,
} from "./account_recovery";

test("normalizes a recovery email", () => {
  assert.equal(normalizeRecoveryEmail(" Staff@Example.edu "), "staff@example.edu");
});

test("rejects an invalid recovery email", () => {
  assert.throws(() => normalizeRecoveryEmail("not-an-email"));
});

test("moves a Firebase reset action onto the public admin host", () => {
  const result = new URL(directPasswordResetLink(
    "https://project.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=secret-code&apiKey=public-key&lang=en",
    "https://paaccmindmate.com",
  ));
  assert.equal(result.origin, "https://paaccmindmate.com");
  assert.equal(result.pathname, "/__/auth/action");
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

test("resolveAdminWebUrl defaults staging to paaccmindmate.com and rejects obsolete Vercel domain", () => {
  assert.equal(
    resolveAdminWebUrl("", "mindmate-staging"),
    "https://paaccmindmate.com",
  );
  assert.equal(
    resolveAdminWebUrl("https://mindmate-admin-staging.vercel.app", "mindmate-staging"),
    "https://paaccmindmate.com",
  );
  assert.equal(
    resolveAdminWebUrl("https://paaccmindmate.com/some/path", "mindmate-staging"),
    "https://paaccmindmate.com",
  );
});

test("resolveAdminWebUrl blocks cross-environment hosts between staging and production", () => {
  assert.equal(
    resolveAdminWebUrl("https://mind-mates-cd2cf.web.app", "mindmate-staging"),
    "https://paaccmindmate.com",
  );
  assert.equal(
    resolveAdminWebUrl("https://paaccmindmate.com", "mind-mates-cd2cf"),
    "https://mind-mates-cd2cf.web.app",
  );
  assert.equal(
    resolveAdminWebUrl("https://mindmate-admin-staging.vercel.app", "mind-mates-cd2cf"),
    "https://mind-mates-cd2cf.web.app",
  );
  assert.equal(
    resolveAdminWebUrl("https://mind-mates-cd2cf.web.app", "mind-mates-cd2cf"),
    "https://mind-mates-cd2cf.web.app",
  );
});

test("Vercel SPA rewrites route /verify-email and /__/auth/action to index.html", () => {
  const repoRoot = path.resolve(__dirname, "..", "..");
  const rootVercel = JSON.parse(
    fs.readFileSync(path.join(repoRoot, "vercel.json"), "utf8"),
  ) as {rewrites?: Array<{source?: string; destination?: string}>};
  assert.ok(
    rootVercel.rewrites?.some(
      (rule) => rule.source === "/(.*)" && rule.destination === "/index.html",
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
