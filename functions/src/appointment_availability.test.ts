import assert from "node:assert/strict";
import test from "node:test";

import {
  AppointmentAvailabilityValidationError,
  validatePaccAppointmentAvailability,
} from "./appointment_availability";

const availability = {
  openDays: [1, 2, 3, 4, 5],
  opensAt: "09:00",
  closesAt: "17:00",
  presence: "in_office",
  acceptsWalkIns: false,
};

// Thursday, September 24, 2026, 9:00 AM Asia/Manila.
const openSlot = Date.UTC(2026, 8, 24, 1, 0, 0);

test("allows a published open-day appointment during office hours", () => {
  assert.doesNotThrow(() => validatePaccAppointmentAvailability(openSlot, availability));
});

test("rejects a closed day and times outside published office hours", () => {
  assert.throws(
    () => validatePaccAppointmentAvailability(Date.UTC(2026, 8, 26, 1, 0, 0), availability),
    AppointmentAvailabilityValidationError,
  );
  assert.throws(
    () => validatePaccAppointmentAvailability(Date.UTC(2026, 8, 24, 0, 0, 0), availability),
    AppointmentAvailabilityValidationError,
  );
  assert.throws(
    () => validatePaccAppointmentAvailability(Date.UTC(2026, 8, 24, 9, 0, 0), availability),
    AppointmentAvailabilityValidationError,
  );
});

test("rejects unavailable counselors, missing schedules, and malformed published configuration", () => {
  assert.throws(
    () => validatePaccAppointmentAvailability(openSlot, {...availability, presence: "on_leave"}),
    AppointmentAvailabilityValidationError,
  );
  assert.throws(
    () => validatePaccAppointmentAvailability(openSlot, null),
    AppointmentAvailabilityValidationError,
  );
  assert.throws(
    () => validatePaccAppointmentAvailability(openSlot, {...availability, opensAt: "17:00", closesAt: "09:00"}),
    AppointmentAvailabilityValidationError,
  );
});
