import assert from "node:assert/strict";
import test from "node:test";

import {
  AppointmentAvailabilityValidationError,
  canManagePaccAvailability,
  normalizePaccAvailabilityForRead,
  resolvePaccSchedule,
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

const v2Availability = {
  schemaVersion: 2,
  timezone: "Asia/Manila",
  weekdays: {
    1: {enabled: true, opensAt: "08:00", closesAt: "17:00", presence: "in_office", appointmentsEnabled: true, acceptsWalkIns: true},
    2: {enabled: false, opensAt: "08:00", closesAt: "17:00", presence: "out_of_office", appointmentsEnabled: false, acceptsWalkIns: false},
    3: {enabled: true, opensAt: "08:00", closesAt: "17:00", presence: "in_office", appointmentsEnabled: false, acceptsWalkIns: true},
    4: {enabled: true, opensAt: "08:00", closesAt: "17:00", presence: "in_office", appointmentsEnabled: true, acceptsWalkIns: true},
    5: {enabled: true, opensAt: "08:00", closesAt: "17:00", presence: "in_office", appointmentsEnabled: true, acceptsWalkIns: true},
    6: {enabled: false, opensAt: "08:00", closesAt: "17:00", presence: "out_of_office", appointmentsEnabled: false, acceptsWalkIns: false},
    7: {enabled: false, opensAt: "08:00", closesAt: "17:00", presence: "out_of_office", appointmentsEnabled: false, acceptsWalkIns: false},
  },
  overrides: [
    {date: "2026-09-24", closedAllDay: false, schedule: {enabled: true, opensAt: "10:00", closesAt: "12:00", presence: "in_office", appointmentsEnabled: true, acceptsWalkIns: false}, reason: "Reduced hours"},
  ],
  notice: " Office hours ",
};

test("V2 payload round-trips seven weekdays and rejects unsupported or contradictory values", () => {
  assert.deepEqual(validatePaccAvailabilityPayload(v2Availability), {
    ...v2Availability,
    notice: "Office hours",
  });
  for (const invalid of [
    {...v2Availability, weekdays: {...v2Availability.weekdays, 7: undefined}},
    {...v2Availability, timezone: "UTC"},
    {...v2Availability, unexpected: true},
    {...v2Availability, weekdays: {...v2Availability.weekdays, 2: {...v2Availability.weekdays[2], appointmentsEnabled: true}}},
    {...v2Availability, overrides: [{date: "2026-09-24", closedAllDay: true, schedule: v2Availability.weekdays[1], reason: "Contradiction"}]},
  ]) {
    assert.throws(() => validatePaccAvailabilityPayload(invalid), AppointmentAvailabilityValidationError);
  }
});

test("V1 documents normalize with server metadata and blackout dates as closed overrides", () => {
  const normalized = normalizePaccAvailabilityForRead({...availability, blackoutDates: ["2026-09-24"], updatedAt: {seconds: 1}, revision: 3});
  assert.equal(normalized.schemaVersion, 2);
  assert.equal(normalized.weekdays[1].appointmentsEnabled, true);
  assert.deepEqual(normalized.overrides, [{date: "2026-09-24", closedAllDay: true, reason: ""}]);
});

test("V2 override resolution follows Manila date rather than UTC date and normalizes closed days", () => {
  const v2 = validatePaccAvailabilityPayload(v2Availability);
  const override = resolvePaccSchedule(Date.UTC(2026, 8, 24, 3, 0, 0), v2);
  assert.equal(override.source, "override");
  assert.equal(override.opensAt, "10:00");
  assert.equal(override.acceptsWalkIns, false);

  const ManilaMondayButUtcSunday = resolvePaccSchedule(Date.UTC(2026, 8, 20, 16, 30, 0), v2);
  assert.equal(ManilaMondayButUtcSunday.weekday, 1);

  const closedTuesday = resolvePaccSchedule(Date.UTC(2026, 8, 22, 1, 0, 0), v2);
  assert.equal(closedTuesday.isOfficeOpen, false);
  assert.equal(closedTuesday.canBookAppointments, false);
  assert.equal(closedTuesday.closureReason, "Office is closed.");
});

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

test("rejects a configured PACC blackout date", () => {
  assert.throws(
    () => validatePaccAppointmentAvailability(openSlot, {...availability, blackoutDates: ["2026-09-24"]}),
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
  assert.deepEqual(validatePaccAvailabilityPayload({...v2Availability, notice: " Office hours "}), {
    ...v2Availability,
    notice: "Office hours",
  });
  for (const invalid of [
    availability,
    {...v2Availability, weekdays: {...v2Availability.weekdays, 1: {...v2Availability.weekdays[1], opensAt: "9 AM"}}},
    {...v2Availability, weekdays: {...v2Availability.weekdays, 1: {...v2Availability.weekdays[1], opensAt: "17:00", closesAt: "17:00"}}},
    {...v2Availability, weekdays: {...v2Availability.weekdays, 1: {...v2Availability.weekdays[1], presence: "unknown"}}},
    {...v2Availability, unsupported: true},
  ]) {
    assert.throws(
      () => validatePaccAvailabilityPayload(invalid),
      AppointmentAvailabilityValidationError,
    );
  }
});
