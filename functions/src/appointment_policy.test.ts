import assert from "node:assert/strict";
import {test} from "node:test";
import {appointmentBookingPolicy, bookingPolicyViolation} from "./appointment_policy";

test("booking policy defaults preserve current unrestricted behavior", () => {
  const policy = appointmentBookingPolicy(null);
  assert.equal(bookingPolicyViolation(policy, Date.now() + 365 * 86_400_000), null);
});

test("enabled booking policy rejects lead-time and horizon violations", () => {
  const now = Date.UTC(2026, 0, 1, 0, 0);
  const policy = appointmentBookingPolicy({minimumLeadTimeMinutes: 60, maximumBookingDaysAhead: 7});
  assert.match(bookingPolicyViolation(policy, now + 30 * 60_000, now) ?? "", /lead time/);
  assert.match(bookingPolicyViolation(policy, now + 8 * 86_400_000, now) ?? "", /booking window/);
  assert.equal(bookingPolicyViolation(policy, now + 2 * 86_400_000, now), null);
});

test("stale request expiry remains disabled unless a positive policy is published", () => {
  assert.equal(appointmentBookingPolicy({}).staleRequestExpiryHours, null);
  assert.equal(appointmentBookingPolicy({staleRequestExpiryHours: 24}).staleRequestExpiryHours, 24);
});
