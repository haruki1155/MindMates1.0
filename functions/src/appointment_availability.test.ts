import assert from "node:assert/strict";
import test from "node:test";

import {
  AppointmentAvailabilityValidationError,
  canManagePaccAvailability,
  normalizePaccAvailabilityForRead,
  previewPaccScheduleConflicts,
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
    {...v2Availability, weekdays: {...v2Availability.weekdays, 6: {...v2Availability.weekdays[6], enabled: true, presence: "in_office", appointmentsEnabled: true}}},
  ]) {
    assert.throws(() => validatePaccAvailabilityPayload(invalid), AppointmentAvailabilityValidationError);
  }
});

test("weekends are closed when reading V1 schedules and never resolve as bookable", () => {
  const normalized = normalizePaccAvailabilityForRead({...availability, openDays: [1, 6, 7]});
  assert.equal(normalized.weekdays[6].enabled, false);
  assert.equal(normalized.weekdays[7].enabled, false);
  const saturdayNine = Date.UTC(2026, 8, 26, 1, 0, 0);
  assert.equal(resolvePaccSchedule(saturdayNine, normalized).canBookAppointments, false);
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

test("schedule conflict preview finds every active appointment timestamp and ignores terminal or historical records", () => {
  const candidate = validatePaccAvailabilityPayload({...v2Availability, overrides: [{date: "2027-01-04", closedAllDay: true, reason: "University event"}]});
  const mondayNine = Date.UTC(2027, 0, 4, 1, 0, 0);
  const conflicts = previewPaccScheduleConflicts(candidate, [
    {id: "requested", status: "requested", scheduledAt: mondayNine},
    {id: "confirmed", status: "confirmed", scheduledAt: mondayNine},
    {id: "proposal-current", status: "reschedule_proposed", scheduledAt: mondayNine},
    {id: "proposal-new", status: "reschedule_proposed", scheduledAt: Date.UTC(2027, 0, 4, 2, 0, 0), proposedScheduledAt: mondayNine},
    {id: "pending", status: "pending", scheduledAt: mondayNine},
    {id: "upcoming", status: "upcoming", scheduledAt: mondayNine},
    {id: "required", status: "reschedule_required", scheduledAt: mondayNine},
    {id: "terminal", status: "completed", scheduledAt: mondayNine},
    {id: "past", status: "confirmed", scheduledAt: Date.UTC(2020, 0, 1, 1, 0, 0)},
  ]);
  assert.deepEqual(conflicts.map((conflict) => conflict.appointmentId), ["confirmed", "pending", "proposal-current", "proposal-new", "proposal-new", "requested", "required", "upcoming"]);
  assert.equal(conflicts.find((conflict) => conflict.appointmentId === "proposal-new")?.timestamp, mondayNine);
});

test("schedule conflict preview reports closed overrides, outside hours, appointments-disabled, and unavailable counselors without false positives", () => {
  const mondayNine = Date.UTC(2027, 0, 4, 1, 0, 0);
  const candidate = validatePaccAvailabilityPayload({
    ...v2Availability,
    weekdays: {...v2Availability.weekdays, 1: {...v2Availability.weekdays[1], opensAt: "10:00", appointmentsEnabled: false}},
    overrides: [{date: "2027-01-05", closedAllDay: true, reason: "Closed"}],
  });
  const conflicts = previewPaccScheduleConflicts(candidate, [
    {id: "outside-hours", status: "requested", scheduledAt: mondayNine},
    {id: "closed-override", status: "requested", scheduledAt: Date.UTC(2027, 0, 5, 1, 0, 0)},
    {id: "valid", status: "requested", scheduledAt: Date.UTC(2027, 0, 7, 3, 0, 0)},
  ]);
  assert.deepEqual(conflicts.map((conflict) => conflict.appointmentId), ["closed-override", "outside-hours"]);
  const unavailable = validatePaccAvailabilityPayload({...candidate, weekdays: {...candidate.weekdays, 1: {...candidate.weekdays[1], opensAt: "08:00", appointmentsEnabled: true, presence: "on_leave"}}});
  assert.equal(previewPaccScheduleConflicts(unavailable, [{id: "counselor-unavailable", status: "confirmed", scheduledAt: mondayNine}])[0].reason, "Counselor is unavailable.");
  const disabled = validatePaccAvailabilityPayload({...candidate, weekdays: {...candidate.weekdays, 1: {...candidate.weekdays[1], opensAt: "08:00", presence: "in_office", appointmentsEnabled: false}}});
  assert.equal(previewPaccScheduleConflicts(disabled, [{id: "appointments-disabled", status: "confirmed", scheduledAt: mondayNine}])[0].reason, "Appointments are unavailable.");
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
