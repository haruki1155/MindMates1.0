import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getFirestore} from "firebase-admin/firestore";

import {
  acknowledgeMindAidEmergencyAlertHandler,
  createOrUpdateMindAidEmergencyAlert,
  resolveMindAidEmergencyAlertHandler,
} from "./mind_aid_emergency";

type Request = {auth?: {uid: string}; data?: Record<string, unknown>};
const db = getFirestore();
const prefix = `mind-aid-emergency-${Date.now()}`;
const student = `${prefix}-student`;
const counselor = `${prefix}-counselor`;
const admin = `${prefix}-admin`;
const staff = `${prefix}-staff`;
const request = (uid: string, data: Record<string, unknown>): Request => ({auth: {uid}, data});
const callable = (value: Request) => value as unknown as Parameters<typeof acknowledgeMindAidEmergencyAlertHandler>[0];

async function expects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (error: {code?: unknown}) => error?.code === code);
}

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("FIRESTORE_EMULATOR_HOST is required for emergency callable tests.");
  await Promise.all([
    db.collection("users").doc(student).set({accessRole: "appUser"}),
    db.collection("users").doc(staff).set({accessRole: "portalStaff"}),
    db.collection("users").doc(counselor).set({accessRole: "counselor", name: "Test Counselor"}),
    db.collection("users").doc(admin).set({accessRole: "admin", name: "Test Admin"}),
  ]);
});

after(async () => {
  const [alerts, notices] = await Promise.all([
    db.collection("mind_aid_emergency_alerts").where("userId", "==", student).get(),
    db.collection("notifications").where("type", "==", "mind_aid_emergency").get(),
  ]);
  await Promise.all([
    ...alerts.docs.flatMap((item) => [item.ref.delete(), db.collection("_mind_aid_active_emergency_alerts").doc(student).delete()]),
    ...notices.docs.filter((item) => String(item.id).includes("mind_aid_emergency_")).map((item) => item.ref.delete()),
    ...[student, counselor, admin, staff].map((id) => db.collection("users").doc(id).delete()),
  ]);
});

test("active emergency incident is idempotent and notifies counselors, not admins", async () => {
  const first = await createOrUpdateMindAidEmergencyAlert({userId: student, conversationId: "conversation-1", triggerMessageId: "turn-1"});
  const second = await createOrUpdateMindAidEmergencyAlert({userId: student, conversationId: "conversation-1", triggerMessageId: "turn-2"});
  assert.equal(first.alertId, second.alertId);
  assert.equal(first.notified, true);
  const alert = (await db.collection("mind_aid_emergency_alerts").doc(first.alertId).get()).data()!;
  assert.equal(alert.status, "open");
  assert.equal(alert.triggerCount, 2);
  assert.equal(alert.triggerMessageId, "turn-1");
  const notices = await db.collection("notifications").where("emergencyAlertId", "==", first.alertId).get();
  assert.equal(notices.size, 1);
  assert.equal(notices.docs[0].data().userId, counselor);
  assert.doesNotMatch(String(notices.docs[0].data().body), /kill|suicide|turn-1/i);
});

test("only clinical roles can execute the server-authored lifecycle", async () => {
  const active = (await db.collection("_mind_aid_active_emergency_alerts").doc(student).get()).data()!;
  const alertId = String(active.alertId);
  await expects(acknowledgeMindAidEmergencyAlertHandler(callable(request(student, {alertId}))), "permission-denied");
  await expects(acknowledgeMindAidEmergencyAlertHandler(callable(request(staff, {alertId}))), "permission-denied");
  await expects(resolveMindAidEmergencyAlertHandler(callable(request(counselor, {alertId, resolutionDisposition: "contacted_user"}))), "failed-precondition");
  await acknowledgeMindAidEmergencyAlertHandler(callable(request(counselor, {alertId, acknowledgedBy: "forged"})));
  let data = (await db.collection("mind_aid_emergency_alerts").doc(alertId).get()).data()!;
  assert.equal(data.status, "acknowledged");
  assert.equal(data.acknowledgedBy, counselor);
  assert.ok(data.acknowledgedAt);
  await expects(acknowledgeMindAidEmergencyAlertHandler(callable(request(admin, {alertId}))), "failed-precondition");
  await resolveMindAidEmergencyAlertHandler(callable(request(admin, {alertId, resolutionDisposition: "false_positive", resolvedBy: "forged"})));
  data = (await db.collection("mind_aid_emergency_alerts").doc(alertId).get()).data()!;
  assert.equal(data.status, "resolved");
  assert.equal(data.resolvedBy, admin);
  assert.equal(data.resolutionDisposition, "false_positive");
  assert.ok(data.resolvedAt);
  await expects(resolveMindAidEmergencyAlertHandler(callable(request(admin, {alertId, resolutionDisposition: "false_positive"}))), "failed-precondition");
  await expects(acknowledgeMindAidEmergencyAlertHandler(callable(request(admin, {alertId: "missing-alert"}))), "not-found");
});
