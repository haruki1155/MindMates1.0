import {test} from "node:test";
import {strict as assert} from "node:assert";
import {allowedAppointmentActions, appointmentDateHasArrived} from "./appointment_workflow";

test("confirmation cannot complete a request directly", () => {
  assert.deepEqual(allowedAppointmentActions("requested"), ["confirmed", "declined", "reschedule_proposed"]);
});

test("confirmed appointments allow outcomes but no cancellation", () => {
  assert.deepEqual(allowedAppointmentActions("confirmed"), ["completed", "not_attended"]);
});

test("outcomes become available on the local appointment date", () => {
  const scheduled = new Date("2026-09-22T01:00:00.000Z");
  assert.equal(appointmentDateHasArrived(scheduled, new Date("2026-09-21T15:59:59.000Z")), false);
  assert.equal(appointmentDateHasArrived(scheduled, new Date("2026-09-21T16:00:00.000Z")), true);
});
