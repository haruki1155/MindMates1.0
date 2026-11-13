import assert from "node:assert/strict";
import test from "node:test";
import {auditLogOwnerField} from "./audit";

test("student information views are listed under the acting staff member", () => {
  assert.equal(auditLogOwnerField("STUDENT_PERSONAL_INFO_VIEWED"), "actorId");
});

test("existing audit actions keep the targetUserId lookup", () => {
  for (const action of ["", "STAFF_ROLE_CHANGED", "APPOINTMENT_CONFIRMED", "STAFF_SIGNED_IN"]) {
    assert.equal(auditLogOwnerField(action), "targetUserId");
  }
});
