import assert from "node:assert/strict";
import {test} from "node:test";

import {
  isAppointmentReminderEnabled,
  isReminderEligibleAppointmentStatus,
} from "./appointment_reminders";

test("appointment reminder preferences default on and disable only their matching stage", () => {
  assert.equal(isAppointmentReminderEnabled(undefined, "twentyFourHour"), true);
  assert.equal(isAppointmentReminderEnabled({}, "oneHour"), true);
  assert.equal(isAppointmentReminderEnabled({appointment24HourEnabled: false}, "twentyFourHour"), false);
  assert.equal(isAppointmentReminderEnabled({appointment24HourEnabled: false}, "oneHour"), true);
  assert.equal(isAppointmentReminderEnabled({appointment1HourEnabled: false}, "oneHour"), false);
  assert.equal(isAppointmentReminderEnabled({appointment1HourEnabled: false}, "twentyFourHour"), true);
});

test("reminders remain eligible for the original time while a reschedule proposal is unresolved", () => {
  assert.equal(isReminderEligibleAppointmentStatus("confirmed"), true);
  assert.equal(isReminderEligibleAppointmentStatus("reschedule_proposed"), true);
});

test("terminal appointments are never reminder eligible", () => {
  for (const status of ["cancelled", "completed", "no_show", "declined", "expired"]) {
    assert.equal(isReminderEligibleAppointmentStatus(status), false);
  }
});
