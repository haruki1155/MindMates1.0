import assert from "node:assert/strict";
import {test} from "node:test";

import {appointmentActionsFor, canTransitionAppointment} from "./appointment_lifecycle";

test("lifecycle matrix permits every supported PACC transition", () => {
  const allowed: Array<[string, "student" | "staff", string]> = [
    ["requested", "staff", "confirmed"], ["requested", "staff", "reschedule_proposed"],
    ["requested", "staff", "declined"], ["requested", "staff", "cancelled"],
    ["requested", "student", "cancelled"], ["confirmed", "student", "reschedule_proposed"],
    ["confirmed", "student", "cancelled"], ["confirmed", "staff", "completed"],
    ["confirmed", "staff", "no_show"], ["confirmed", "staff", "reschedule_proposed"],
    ["confirmed", "staff", "cancelled"], ["reschedule_proposed", "student", "confirmed"],
    ["reschedule_proposed", "staff", "reschedule_proposed"], ["reschedule_proposed", "staff", "cancelled"],
  ];
  for (const [status, actor, next] of allowed) {
    assert.equal(canTransitionAppointment(status, actor, next), true, `${status} -> ${next}`);
  }
});

test("lifecycle matrix rejects terminal and unauthorized transitions", () => {
  for (const terminal of ["completed", "no_show", "cancelled", "declined"]) {
    assert.equal(appointmentActionsFor(terminal, "student").length, 0);
    assert.equal(appointmentActionsFor(terminal, "staff").length, 0);
  }
  assert.equal(canTransitionAppointment("requested", "student", "confirmed"), false);
  assert.equal(canTransitionAppointment("requested", "student", "completed"), false);
  assert.equal(canTransitionAppointment("confirmed", "student", "no_show"), false);
  assert.equal(canTransitionAppointment("pending", "staff", "confirmed"), true);
});
