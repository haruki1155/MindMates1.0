import assert from "node:assert/strict";
import {test} from "node:test";

import {InquirySlaError, parseSlaHours, replyMessage, requestIdFrom, SLA_HOUR_OPTIONS} from "./inquiry_sla";

const code = (expected: string) => (e: unknown) => e instanceof InquirySlaError && e.code === expected;

test("the response target is one of the PACC options and nothing else", () => {
  assert.deepEqual([...SLA_HOUR_OPTIONS], [24, 48, 72]);
  for (const hours of [24, 48, 72]) assert.equal(parseSlaHours(hours), hours);
  for (const bad of [0, 12, 36, 96, "48", null, undefined, 48.5, -24]) {
    assert.throws(() => parseSlaHours(bad), code("invalid-sla"), String(bad));
  }
});

test("reply messages are trimmed text of 1-2000 characters", () => {
  assert.equal(replyMessage("  Thank you, we will call you.  "), "Thank you, we will call you.");
  assert.equal(replyMessage("x".repeat(2000)).length, 2000);
  for (const bad of ["", "   ", "x".repeat(2001), 42, null]) {
    assert.throws(() => replyMessage(bad), code("invalid-message"));
  }
});

test("request ids are client-generated, path-safe idempotency keys", () => {
  assert.equal(requestIdFrom("8f14e45f-ceea-467a-9575-3d8f2a1b2c3d"), "8f14e45f-ceea-467a-9575-3d8f2a1b2c3d");
  for (const bad of ["", "short", "has/slash", "x".repeat(129), 7, null]) {
    assert.throws(() => requestIdFrom(bad), code("invalid-request"));
  }
});
