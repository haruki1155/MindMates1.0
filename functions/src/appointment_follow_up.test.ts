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

test("only a completed counseling session can parent a follow-up", () => {
  assert.equal(isEligibleFollowUpParentStatus("completed"), true);
  assert.equal(isEligibleFollowUpParentStatus("no_show"), false);
  assert.equal(isEligibleFollowUpParentStatus("noshow"), false);
  assert.equal(isEligibleFollowUpParentStatus("expired"), false);
  assert.equal(isEligibleFollowUpParentStatus("cancelled"), false);
  assert.equal(isEligibleFollowUpParentStatus("declined"), false);
  assert.equal(isEligibleFollowUpParentStatus("confirmed"), false);
});

test("a parent can create only one linked follow-up", () => {
  const offeredParent = {
    status: "completed",
    followUpRecommended: true,
    followUpStatus: "offered",
  };
  assert.equal(canBookFollowUpFromParent(offeredParent), true);
  assert.equal(canBookFollowUpFromParent({status: "completed"}), false);
  assert.equal(canBookFollowUpFromParent({...offeredParent, followUpStatus: "booked"}), false);
  assert.equal(canBookFollowUpFromParent({...offeredParent, followUpAppointmentId: "child-1"}), false);
});

test("completion requires an internal summary and a client message only for follow-up", () => {
  assert.throws(() => validateCompletionInput({summary: "no", offerFollowUp: false}), /Session summary must contain at least 3 characters/);
  assert.throws(() => validateCompletionInput({summary: "Private summary", offerFollowUp: true}), /Client message is required/);
  assert.deepEqual(
    validateCompletionInput({summary: "Private summary", offerFollowUp: true, followUpMessage: "Please book when ready."}),
    {summary: "Private summary", offerFollowUp: true, followUpMessage: "Please book when ready."},
  );
});
