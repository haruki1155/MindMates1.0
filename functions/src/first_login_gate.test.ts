import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {test} from "node:test";

import {assertNotFirstLogin, requireUid} from "./access";

const pending = {auth: {uid: "u1", token: {firstLoginPending: true}}};
const normal = {auth: {uid: "u1", token: {}}};
const codeOf = (fn: () => unknown) => {
  try { fn(); } catch (error) { return (error as {code?: string; details?: {reason?: string}}); }
  return undefined;
};

test("requireUid and assertNotFirstLogin refuse a first-login session and accept a normal one", () => {
  assert.equal(codeOf(() => requireUid(pending))?.code, "permission-denied");
  assert.equal(codeOf(() => assertNotFirstLogin(pending))?.details?.reason, "first-login-pending");
  assert.equal(requireUid(normal), "u1");
  assert.equal(codeOf(() => assertNotFirstLogin(normal)), undefined);
  assert.equal(codeOf(() => assertNotFirstLogin({auth: null})), undefined);
});

// Files that must read the raw auth: the unauthenticated or setup/recovery endpoints, and the gate itself.
const ALLOWED = new Set(["access.ts", "student_login.ts", "student_account_setup.ts", "student_account_recovery.ts", "account_recovery.ts"]);

function sources(dir: string): string[] {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return sources(full);
    return /\.ts$/.test(entry.name) && !/\.(test|rules)\.ts$/.test(entry.name) ? [full] : [];
  });
}

test("every callable that reads request.auth guards first-login sessions", () => {
  const root = path.resolve(__dirname, "..", "src");
  const offenders: string[] = [];
  for (const file of sources(root)) {
    if (ALLOWED.has(path.basename(file))) continue;
    const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
    lines.forEach((line, i) => {
      if (!/request\.auth\b/.test(line)) return;
      const nearby = lines.slice(Math.max(0, i - 4), i + 1).join("\n");
      if (!/assertNotFirstLogin\(/.test(nearby)) offenders.push(`${path.relative(root, file)}:${i + 1}`);
    });
  }
  assert.deepEqual(offenders, []);
});
