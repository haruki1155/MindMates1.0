import assert from "node:assert/strict";
import {test} from "node:test";

import {canBookFollowUpFromParent, isEligibleFollowUpParentStatus, validateCompletionInput, validateRescheduleReason} from "./appointment_follow_up";

test("reschedule reason requires meaningful client-safe text", () => {
  assert.throws(
    () => validateRescheduleReason("  "),
    /Reschedule reason is required/,
  );
  assert.throws(
    () => validateRescheduleReason("ok"),
    /at least 3 characters/,
  );
  assert.equal(
    validateRescheduleReason("Counselor schedule conflict"),
    "Counselor schedule conflict",
  );
});

test("only valid terminal outcomes can parent a follow-up", () => {
  for (const finalStatus of ["completed", "no_show", "noshow", "expired"]) {
    assert.equal(isEligibleFollowUpParentStatus(finalStatus), true);
  }
  assert.equal(isEligibleFollowUpParentStatus("cancelled"), false);
  assert.equal(isEligibleFollowUpParentStatus("declined"), false);
  assert.equal(isEligibleFollowUpParentStatus("confirmed"), false);
});

test("a parent can create only one linked follow-up", () => {
  assert.equal(canBookFollowUpFromParent({status: "completed"}), true);
  assert.equal(canBookFollowUpFromParent({status: "completed", followUpStatus: "booked"}), false);
  assert.equal(canBookFollowUpFromParent({status: "completed", followUpAppointmentId: "child-1"}), false);
});

test("completion requires an internal summary and a client message only for follow-up", () => {
  assert.throws(() => validateCompletionInput({summary: "no", offerFollowUp: false}), /Session summary must contain at least 3 characters/);
  assert.throws(() => validateCompletionInput({summary: "Private summary", offerFollowUp: true}), /Client message is required/);
  assert.deepEqual(
    validateCompletionInput({summary: "Private summary", offerFollowUp: true, followUpMessage: "Please book when ready."}),
    {summary: "Private summary", offerFollowUp: true, followUpMessage: "Please book when ready."},
  );
});
