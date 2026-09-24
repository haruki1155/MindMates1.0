import assert from "node:assert/strict";
import {test} from "node:test";

import {isReminderEligibleAppointmentStatus} from "./appointment_reminders";

test("reminders remain eligible for the original time while a reschedule proposal is unresolved", () => {
  assert.equal(isReminderEligibleAppointmentStatus("confirmed"), true);
  assert.equal(isReminderEligibleAppointmentStatus("reschedule_proposed"), true);
});

test("terminal appointments are never reminder eligible", () => {
  for (const status of ["cancelled", "completed", "no_show", "declined", "expired"]) {
    assert.equal(isReminderEligibleAppointmentStatus(status), false);
  }
});
