import assert from "node:assert/strict";
import test from "node:test";
import {
  isNormalNotificationType,
  notificationArchiveAtMillis,
  notificationDeleteAtMillis,
  portalNotificationPayload,
} from "./index";

test("portal submission notifications contain routing metadata but no care details", () => {
  const appointment = portalNotificationPayload("appointment", "staff-1", "appointment-1");
  const inquiry = portalNotificationPayload("inquiry", "staff-1", "inquiry-1");

  assert.equal(appointment.audience, "portal");
  assert.equal(appointment.appointmentId, "appointment-1");
  assert.equal(inquiry.inquiryId, "inquiry-1");
  assert.equal(appointment.archivedAt, null);
  assert.equal(appointment.expiresAt, null);
  assert.deepEqual(
    Object.keys(appointment).filter((key) => ["concern", "message", "name", "email"].includes(key)),
    [],
  );
  assert.deepEqual(
    Object.keys(inquiry).filter((key) => ["formData", "message", "name", "email"].includes(key)),
    [],
  );
});

test("normal notification retention uses 30-day archive and 90-day deletion windows", () => {
  const day = 24 * 60 * 60 * 1000;
  const readAt = Date.UTC(2026, 8, 10);
  const archiveAt = notificationArchiveAtMillis(readAt);

  assert.equal(archiveAt, readAt + 30 * day);
  assert.equal(notificationDeleteAtMillis(archiveAt), archiveAt + 90 * day);
  assert.equal(isNormalNotificationType("appointment"), true);
  assert.equal(isNormalNotificationType("inquiry"), true);
  assert.equal(isNormalNotificationType("security"), false);
  assert.equal(isNormalNotificationType("audit"), false);
});
