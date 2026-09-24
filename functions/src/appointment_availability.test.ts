import assert from "node:assert/strict";
import test from "node:test";

import {
  AppointmentAvailabilityValidationError,
  canManagePaccAvailability,
  validatePaccAppointmentAvailability,
  validatePaccAvailabilityPayload,
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

test("accepts only clinical staff as availability managers", () => {
  assert.equal(canManagePaccAvailability("admin"), true);
  assert.equal(canManagePaccAvailability("counselor"), true);
  assert.equal(canManagePaccAvailability("portalStaff"), false);
  assert.equal(canManagePaccAvailability("appUser"), false);
});

test("validates availability payload shape, time ordering, and bounded notice text", () => {
  assert.deepEqual(validatePaccAvailabilityPayload({...availability, notice: " Office hours "}), {
    ...availability,
    notice: "Office hours",
  });
  for (const invalid of [
    {...availability, opensAt: "9 AM"},
    {...availability, opensAt: "17:00", closesAt: "17:00"},
    {...availability, openDays: [1, 1]},
    {...availability, presence: "unknown"},
    {...availability, acceptsWalkIns: "yes"},
    {...availability, unsupported: true},
  ]) {
    assert.throws(
      () => validatePaccAvailabilityPayload(invalid),
      AppointmentAvailabilityValidationError,
    );
  }
});
