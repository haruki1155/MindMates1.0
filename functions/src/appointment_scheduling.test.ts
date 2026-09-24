import assert from "node:assert/strict";
import test from "node:test";

import {
  AppointmentSchedulingValidationError,
  validateAppointmentTimestamp,
} from "./appointment_scheduling";

const now = Date.UTC(2026, 8, 24, 0, 0, 0);
const valid = Date.UTC(2026, 8, 24, 1, 0, 0);

test("allows a future hourly appointment timestamp and derives Manila display time", () => {
  assert.deepEqual(validateAppointmentTimestamp(valid, now), {
    millis: valid,
    scheduledTime: "09:00 AM",
  });
});

test("rejects past, current, invalid, and non-hourly appointment timestamps", () => {
  for (const value of [now - 60 * 60 * 1000, now, "invalid", Date.UTC(2026, 8, 24, 1, 30, 0)]) {
    assert.throws(
      () => validateAppointmentTimestamp(value, now),
      AppointmentSchedulingValidationError,
    );
  }
});

test("accepts Firestore-compatible timestamp values", () => {
  assert.deepEqual(validateAppointmentTimestamp({_seconds: valid / 1000}, now), {
    millis: valid,
    scheduledTime: "09:00 AM",
  });
});

test("client display strings cannot override the canonical appointment time", () => {
  const schedule = validateAppointmentTimestamp(valid, now);
  assert.notEqual(schedule.scheduledTime, "03:00 PM");
  assert.equal(schedule.scheduledTime, "09:00 AM");
});
