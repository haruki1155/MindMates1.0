import assert from "node:assert/strict";
import {createHash, randomUUID} from "node:crypto";
import {performance} from "node:perf_hooks";
import {before, test} from "node:test";
import {getFirestore} from "firebase-admin/firestore";
import {CallableRequest} from "firebase-functions/v2/https";
import {
  MIN_PASSWORD_RESET_RESPONSE_MS, PasswordResetDelivery, PasswordResetMessage, processAdminPasswordReset,
  requestAdminPasswordResetDev,
} from "./account_recovery";

// Task 11A.5F / D3b: the pre-login admin password reset must answer every
// accepted request identically and never log addresses or reset links.
// Delivery is stubbed: these tests never generate real links or send mail.

const db = getFirestore();
// Timers count whole milliseconds, so a padded wait can measure just under its floor.
const TIMER_TOLERANCE_MS = 50;
const SLOW_DELIVERY_MS = 1000;
const firebaseLink = (oobCode: string) =>
  `https://mindmate-staging.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=${oobCode}` +
  "&apiKey=synthetic-api-key&lang=en&continueUrl=https%3A%2F%2Fpaaccmindmate.com%2F";

before(() => {
  for (const host of [process.env.FIRESTORE_EMULATOR_HOST, process.env.FIREBASE_AUTH_EMULATOR_HOST]) {
    assert.match(host ?? "", /^(localhost|127\.0\.0\.1):\d+$/);
  }
});

function request(email: unknown, ip = `198.51.100.${Math.floor(Math.random() * 250) + 1}`) {
  return {data: {email}, rawRequest: {ip, headers: {}}} as unknown as CallableRequest;
}

function withProject<T>(project: string, fn: () => Promise<T>): Promise<T> {
  const previous = [process.env.GCLOUD_PROJECT, process.env.GOOGLE_CLOUD_PROJECT];
  process.env.GCLOUD_PROJECT = project;
  process.env.GOOGLE_CLOUD_PROJECT = project;
  return fn().finally(() => {
    for (const [key, value] of [["GCLOUD_PROJECT", previous[0]], ["GOOGLE_CLOUD_PROJECT", previous[1]]] as const) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });
}

/** Captures everything the logger writes while `fn` runs. */
async function captureLogs<T>(fn: () => Promise<T>): Promise<{result: T; output: string}> {
  const chunks: string[] = [];
  const originals = {out: process.stdout.write, err: process.stderr.write, log: console.log, error: console.error,
    warn: console.warn, info: console.info, debug: console.debug};
  const record = (...args: unknown[]) => { chunks.push(args.map(String).join(" ")); return true; };
  process.stdout.write = record as typeof process.stdout.write;
  process.stderr.write = record as typeof process.stderr.write;
  console.log = console.error = console.warn = console.info = console.debug = record;
  try {
    return {result: await fn(), output: chunks.join("\n")};
  } finally {
    process.stdout.write = originals.out;
    process.stderr.write = originals.err;
    Object.assign(console, {log: originals.log, error: originals.error, warn: originals.warn,
      info: originals.info, debug: originals.debug});
  }
}

function stubDelivery(known: Set<string>, sendError?: Error, sendDelayMs = 0) {
  const sent: PasswordResetMessage[] = [];
  const continueUrls: string[] = [];
  const delivery: PasswordResetDelivery = {
    async generateLink(email, continueUrl) {
      continueUrls.push(continueUrl);
      if (!known.has(email)) throw Object.assign(new Error("There is no user record."), {code: "auth/user-not-found"});
      return firebaseLink(`oob-${createHash("sha256").update(email).digest("hex").slice(0, 12)}`);
    },
    async send(message) {
      if (sendDelayMs) await new Promise(resolve => setTimeout(resolve, sendDelayMs));
      if (sendError) throw sendError;
      sent.push(message);
    },
  };
  return {delivery, sent, continueUrls};
}

async function timed<T>(fn: () => Promise<T>): Promise<{value: T; ms: number}> {
  const started = performance.now();
  const value = await fn();
  return {value, ms: performance.now() - started};
}

test("known, unknown and failed deliveries are all padded to the production floor", async () => {
  await withProject("mindmate-staging", async () => {
    assert.equal(MIN_PASSWORD_RESET_RESPONSE_MS, 3000);
    const known = `admin-${randomUUID()}@example.org`;
    const unknown = `nobody-${randomUUID()}@example.org`;
    const undeliverable = `bounced-${randomUUID()}@example.org`;
    const stub = stubDelivery(new Set([known]), undefined, SLOW_DELIVERY_MS);
    const failing = stubDelivery(new Set([undeliverable]), new Error("synthetic delivery failure"));
    // The first Firestore call connects lazily and can outlast the floor, hiding the padding.
    await processAdminPasswordReset(request(`warmup-${randomUUID()}@example.org`), stubDelivery(new Set()).delivery, 0);
    // No floor override: this exercises the default the deployed callable uses.
    const [a, b, c] = await Promise.all([
      timed(() => processAdminPasswordReset(request(known), stub.delivery)),
      timed(() => processAdminPasswordReset(request(unknown), stub.delivery)),
      timed(() => processAdminPasswordReset(request(undeliverable), failing.delivery)),
    ]);
    for (const [label, {value, ms}] of Object.entries({known: a, unknown: b, undeliverable: c})) {
      assert.deepEqual(value, {accepted: true}, label);
      assert.ok(ms >= MIN_PASSWORD_RESET_RESPONSE_MS - TIMER_TOLERANCE_MS, `${label} padded to the floor (${ms}ms)`);
    }
    // The floor must absorb delivery time; a fixed delay added afterwards would expose it.
    assert.ok(Math.abs(a.ms - b.ms) < SLOW_DELIVERY_MS / 2, `delivery time is hidden (${a.ms}ms, ${b.ms}ms)`);
    assert.equal(stub.sent.length, 1, "mail goes only to the existing account");
    assert.equal(stub.sent[0].to, known);
  });
});

test("Staging reset links use the supported admin host's action handler", async () => {
  await withProject("mindmate-staging", async () => {
    const known = `admin-${randomUUID()}@example.org`;
    const stub = stubDelivery(new Set([known]));
    await processAdminPasswordReset(request(known), stub.delivery, 0);
    assert.deepEqual(stub.continueUrls, ["https://paaccmindmate.com/"]);
    const link = stub.sent[0].text.match(/https:\/\/\S+/)?.[0] ?? "";
    const url = new URL(link);
    assert.equal(url.origin, "https://paaccmindmate.com");
    assert.equal(url.pathname, "/__/auth/action");
    assert.equal(url.searchParams.get("mode"), "resetPassword");
    assert.match(url.searchParams.get("oobCode") ?? "", /^oob-[0-9a-f]{12}$/);
    assert.ok(!link.includes("vercel.app"), "the obsolete Vercel host is never used");
    const htmlLinks = [...stub.sent[0].html.matchAll(/href="([^"]+)"/g)].map(match => match[1].replace(/&amp;/g, "&"));
    assert.ok(htmlLinks.includes(link), "the HTML button carries the same corrected link");
  });
});

test("SMTP failure answers like success and logs no address, link or provider message", async () => {
  await withProject("mindmate-staging", async () => {
    const known = `admin-${randomUUID()}@example.org`;
    const providerError = Object.assign(new Error(`550 mailbox ${known} rejected for https://paaccmindmate.com/x`),
      {code: "EENVELOPE"});
    const stub = stubDelivery(new Set([known]), providerError);
    const {result, output} = await captureLogs(() => processAdminPasswordReset(request(known), stub.delivery, 0));
    assert.deepEqual(result, {accepted: true});
    assert.match(output, /Admin password reset delivery failed/);
    assert.match(output, /EENVELOPE/);
    for (const secret of [known, "oob-", "paaccmindmate.com/x", "550 mailbox"]) {
      assert.ok(!output.includes(secret), `log must not contain ${secret}`);
    }
  });
});

test("unknown accounts are not logged at all", async () => {
  await withProject("mindmate-staging", async () => {
    const unknown = `nobody-${randomUUID()}@example.org`;
    const {output} = await captureLogs(() => processAdminPasswordReset(request(unknown), stubDelivery(new Set()).delivery, 0));
    assert.ok(!output.includes(unknown));
    assert.ok(!/delivery failed/.test(output));
  });
});

test("format and rate-limit outcomes do not depend on account existence", async () => {
  await withProject("mindmate-staging", async () => {
    const stub = stubDelivery(new Set());
    for (const malformed of ["", "not-an-email", 42, null]) {
      // Rejected before any account lookup, without waiting for the floor.
      const started = Date.now();
      await assert.rejects(processAdminPasswordReset(request(malformed), stub.delivery, 5000), {code: "invalid-argument"});
      assert.ok(Date.now() - started < 1000);
    }
    // Per-email limit: three per window for an address, whether or not it exists.
    for (const [label, known] of [["unknown", false], ["known", true]] as const) {
      const email = `${label}-${randomUUID()}@example.org`;
      const delivery = stubDelivery(new Set(known ? [email] : [])).delivery;
      for (let i = 0; i < 3; i++) {
        assert.deepEqual(await processAdminPasswordReset(request(email), delivery, 0), {accepted: true});
      }
      await assert.rejects(processAdminPasswordReset(request(email), delivery, 0), {code: "resource-exhausted"}, label);
    }
    // Per-source limit across different addresses (fresh source per run).
    const ip = `2001:db8::${randomUUID().slice(0, 4)}`;
    for (let i = 0; i < 12; i++) {
      await processAdminPasswordReset(request(`burst-${i}-${randomUUID()}@example.org`, ip), stub.delivery, 0);
    }
    await assert.rejects(processAdminPasswordReset(request(`burst-x-${randomUUID()}@example.org`, ip), stub.delivery, 0),
      {code: "resource-exhausted"});
  });
});

test("the Dev reset alias refuses hosted Staging before any rate-limit write", async () => {
  await withProject("mindmate-staging", async () => {
    const email = `dev-alias-${randomUUID()}@example.org`;
    await assert.rejects((requestAdminPasswordResetDev as unknown as {run(r: unknown): Promise<unknown>})
      .run(request(email)), {code: "permission-denied"});
    const digest = createHash("sha256").update(email).digest("hex");
    assert.equal((await db.collection("_password_reset_limits").doc(`email_${digest}`).get()).exists, false);
  });
});

test("the protected reset callable rejects missing and invalid App Check tokens before its handler", async () => {
  assert.notEqual(process.env.FIREBASE_DEBUG_MODE, "true", "token verification must be real");
  const {requestAdminPasswordReset} = await import("./account_recovery");
  const {default: express} = await import("express");
  const app = express();
  app.use(express.json());
  const handler = requestAdminPasswordReset as unknown as (req: unknown, res: unknown) => unknown;
  app.post("/reset", (req, res) => handler(req, res));
  const server = await new Promise<import("node:http").Server>(resolve => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const port = (server.address() as import("node:net").AddressInfo).port;
    await withProject("mindmate-staging", async () => {
      const email = `appcheck-${randomUUID()}@example.org`;
      for (const headers of [{}, {"X-Firebase-AppCheck": "not-a-valid-app-check-token"}] as Array<Record<string, string>>) {
        const response = await fetch(`http://127.0.0.1:${port}/reset`, {method: "POST",
          headers: {"Content-Type": "application/json", ...headers}, body: JSON.stringify({data: {email}})});
        assert.equal(response.status, 401);
        assert.match(await response.text(), /UNAUTHENTICATED/);
      }
      const digest = createHash("sha256").update(email).digest("hex");
      assert.equal((await db.collection("_password_reset_limits").doc(`email_${digest}`).get()).exists, false,
        "the handler (and its rate-limit write) never ran");
    });
  } finally {
    await new Promise<void>(resolve => server.close(() => resolve()));
  }
});
