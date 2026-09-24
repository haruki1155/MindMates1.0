import assert from "node:assert/strict";
import {test} from "node:test";

import {portalAppointmentQueueProjection} from "./index";

test("portal queue projection excludes clinical and personal appointment fields", () => {
  const projection = portalAppointmentQueueProjection("appointment-1", {
    fullName: "Student Name",
    scheduledAt: "2026-10-01T09:00:00.000Z",
    scheduledTime: "5:00 PM",
    status: "requested",
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
    "isArchived",
    "projectedAt",
    "scheduledAt",
    "scheduledTime",
    "sourceUpdatedAt",
    "status",
    "studentDisplayName",
  ]);
  assert.equal(projection.studentDisplayName, "Student Name");
  assert.equal(projection.appointmentId, "appointment-1");
  assert.equal(projection.concern, undefined);
  assert.equal(projection.email, undefined);
  assert.equal(projection.userId, undefined);
});
