import assert from "node:assert/strict";
import {test} from "node:test";

import {portalAppointmentQueueProjection} from "./index";

test("portal queue projection excludes clinical and personal appointment fields", () => {
  const projection = portalAppointmentQueueProjection("appointment-1", {
    fullName: "Student Name",
    scheduledAt: "2026-10-01T09:00:00.000Z",
    scheduledTime: "5:00 PM",
    status: "requested",
    scheduleRevision: 7,
    counselorName: "Counselor Name",
    concern: "Sensitive concern",
    email: "student@example.com",
    contactNumber: "09123456789",
    address: "Private address",
    therapyBefore: "Private history",
    userId: "student",
  });

  assert.deepEqual(Object.keys(projection).sort(), [
    "appointmentId",
    "assignedCounselor",
    "collegeId",
    "isArchived",
    "projectedAt",
    "proposalRevision",
    "proposalStatus",
    "proposedBy",
    "proposedScheduledAt",
    "proposedScheduledTime",
    "scheduleRevision",
    "scheduledAt",
    "scheduledTime",
    "sourceUpdatedAt",
    "status",
    "studentDisplayName",
  ]);
  assert.equal(projection.studentDisplayName, "Student Name");
  assert.equal(projection.appointmentId, "appointment-1");
  assert.equal(projection.collegeId, "");
  assert.equal(projection.scheduleRevision, 7);
  assert.equal(projection.concern, undefined);
  assert.equal(projection.email, undefined);
  assert.equal(projection.userId, undefined);
});

test("staff queue retains only the verified college key used for filtering", () => {
  const projected = portalAppointmentQueueProjection("appointment-2", {
    fullName: "Staff-safe label",
    userId: "private-student-uid",
    collegeId: "forged-client-college",
    concern: "Sensitive notes",
    scheduledAt: "2026-11-16T09:00:00.000Z",
  }, "college-verified");
  assert.equal(projected.collegeId, "college-verified");
  assert.equal(projected.userId, undefined);
  assert.equal(projected.concern, undefined);
});
