import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";

import {ensureVerifiedAuthUser} from "./test_support_auth";
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
const baseUids = [student, counselor, admin, staff];
const request = (uid: string, data: Record<string, unknown>): Request => ({auth: {uid}, data});
const callable = (value: Request) => value as unknown as Parameters<typeof acknowledgeMindAidEmergencyAlertHandler>[0];

async function expects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (error: {code?: unknown}) => error?.code === code);
}

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error("FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST are required for emergency callable tests.");
  }
  const staleCounselors = await db.collection("users").where("accessRole", "==", "counselor").get();
  await Promise.all(staleCounselors.docs.map((doc) => doc.ref.delete()));
  await Promise.all([
    ensureVerifiedAuthUser(student),
    ensureVerifiedAuthUser(staff),
    ensureVerifiedAuthUser(counselor),
    ensureVerifiedAuthUser(admin),
    db.collection("users").doc(student).set({accessRole: "appUser"}),
    db.collection("users").doc(staff).set({accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"}),
    db.collection("users").doc(counselor).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Test Counselor"}),
    db.collection("users").doc(admin).set({accessRole: "admin", accountStatus: "active", name: "Test Admin"}),
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
    ...baseUids.map((id) => db.collection("users").doc(id).delete().catch(() => undefined)),
    ...baseUids.map((id) => getAuth().deleteUser(id).catch(() => undefined)),
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

async function seedTempAlert(targetStudent: string, status: "open" | "acknowledged"): Promise<string> {
  const ref = db.collection("mind_aid_emergency_alerts").doc();
  await ref.set({
    alertId: ref.id,
    userId: targetStudent,
    publicUserId: "USR-REG-TEST",
    conversationId: "conv-reg",
    triggerMessageId: "msg-reg",
    safetyLevel: "crisisOrImmediateRisk",
    source: "mind_aid_deterministic_safety_classifier",
    status,
    triggerCount: 1,
    acknowledgedAt: status === "acknowledged" ? new Date() : null,
    acknowledgedBy: status === "acknowledged" ? counselor : null,
    resolvedAt: null,
    resolvedBy: null,
    resolutionDisposition: null,
  });
  return ref.id;
}

async function assertNoUnauthorizedMutation(actorUid: string) {
  const openId = await seedTempAlert(`${student}-open`, "open");
  const ackId = await seedTempAlert(`${student}-ack`, "acknowledged");
  try {
    await expects(acknowledgeMindAidEmergencyAlertHandler(callable(request(actorUid, {alertId: openId}))), "permission-denied");
    const openData = (await db.collection("mind_aid_emergency_alerts").doc(openId).get()).data()!;
    assert.equal(openData.status, "open");
    assert.equal(openData.acknowledgedBy, null);
    assert.equal(openData.acknowledgedAt, null);

    await expects(resolveMindAidEmergencyAlertHandler(callable(request(actorUid, {alertId: ackId, resolutionDisposition: "contacted_user"}))), "permission-denied");
    const ackData = (await db.collection("mind_aid_emergency_alerts").doc(ackId).get()).data()!;
    assert.equal(ackData.status, "acknowledged");
    assert.equal(ackData.acknowledgedBy, counselor);
    assert.equal(ackData.resolvedBy, null);
    assert.equal(ackData.resolvedAt, null);
    assert.equal(ackData.resolutionDisposition, null);
  } finally {
    await Promise.all([
      db.collection("mind_aid_emergency_alerts").doc(openId).delete().catch(() => undefined),
      db.collection("mind_aid_emergency_alerts").doc(ackId).delete().catch(() => undefined),
    ]);
  }
}

test("Scenario A: disabled Firebase Auth counselor is denied both emergency alert operations", async () => {
  const uid = `${prefix}-disabled-auth-counselor`;
  await getAuth().createUser({uid, email: `${uid}@example.invalid`, emailVerified: true, disabled: true});
  await db.collection("users").doc(uid).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Disabled Counselor"});
  try {
    await assertNoUnauthorizedMutation(uid);
  } finally {
    await Promise.all([db.collection("users").doc(uid).delete().catch(() => undefined), getAuth().deleteUser(uid).catch(() => undefined)]);
  }
});

test("Scenario B: unverified-email counselor is denied both emergency alert operations", async () => {
  const uid = `${prefix}-unverified-counselor`;
  await getAuth().createUser({uid, email: `${uid}@example.invalid`, emailVerified: false, disabled: false});
  await db.collection("users").doc(uid).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Unverified Counselor"});
  try {
    await assertNoUnauthorizedMutation(uid);
  } finally {
    await Promise.all([db.collection("users").doc(uid).delete().catch(() => undefined), getAuth().deleteUser(uid).catch(() => undefined)]);
  }
});

test("Scenario C: suspended legacy clinical account (missing staffAccountStatus) is denied and not notified", async () => {
  const uid = `${prefix}-suspended-legacy-counselor`;
  const tempStudent = `${prefix}-temp-student`;
  await ensureVerifiedAuthUser(uid);
  await db.collection("users").doc(uid).set({accessRole: "counselor", accountStatus: "suspended", name: "Suspended Legacy"});
  await db.collection("users").doc(tempStudent).set({accessRole: "appUser"});
  let createdAlertId = "";
  try {
    await assertNoUnauthorizedMutation(uid);
    const created = await createOrUpdateMindAidEmergencyAlert({userId: tempStudent, conversationId: "conv-leg", triggerMessageId: "msg-leg"});
    createdAlertId = created.alertId;
    const notice = await db.collection("notifications").doc(`mind_aid_emergency_${createdAlertId}_${uid}`).get();
    assert.equal(notice.exists, false, "suspended legacy counselor must not receive emergency notifications");
  } finally {
    await Promise.all([
      db.collection("users").doc(uid).delete().catch(() => undefined),
      db.collection("users").doc(tempStudent).delete().catch(() => undefined),
      getAuth().deleteUser(uid).catch(() => undefined),
      createdAlertId ? db.collection("mind_aid_emergency_alerts").doc(createdAlertId).delete().catch(() => undefined) : Promise.resolve(),
      db.collection("_mind_aid_active_emergency_alerts").doc(tempStudent).delete().catch(() => undefined),
      createdAlertId ? db.collection("notifications").doc(`mind_aid_emergency_${createdAlertId}_${counselor}`).delete().catch(() => undefined) : Promise.resolve(),
      createdAlertId ? db.collection("notifications").doc(`mind_aid_emergency_${createdAlertId}_${uid}`).delete().catch(() => undefined) : Promise.resolve(),
    ]);
  }
});

test("Scenario D/E & fail-closed missing Auth / unapproved / unauthenticated checks", async () => {
  const missingAuthUid = `${prefix}-missing-auth-counselor`;
  const pendingUid = `${prefix}-pending-counselor`;
  const suspendedLegacyAdminUid = `${prefix}-suspended-legacy-admin`;
  await Promise.all([ensureVerifiedAuthUser(pendingUid), ensureVerifiedAuthUser(suspendedLegacyAdminUid)]);
  await Promise.all([
    db.collection("users").doc(missingAuthUid).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"}),
    db.collection("users").doc(pendingUid).set({accessRole: "counselor", staffAccountStatus: "pending", accountStatus: "active"}),
    db.collection("users").doc(suspendedLegacyAdminUid).set({accessRole: "admin", accountStatus: "suspended"}),
  ]);
  const unauthAlertId = await seedTempAlert(`${student}-unauth`, "open");
  try {
    await expects(acknowledgeMindAidEmergencyAlertHandler(callable({data: {alertId: unauthAlertId}})), "unauthenticated");
    await expects(resolveMindAidEmergencyAlertHandler(callable({data: {alertId: unauthAlertId, resolutionDisposition: "other"}})), "unauthenticated");
    await assertNoUnauthorizedMutation(staff);
    await assertNoUnauthorizedMutation(student);
    await assertNoUnauthorizedMutation(missingAuthUid);
    await assertNoUnauthorizedMutation(pendingUid);
    await assertNoUnauthorizedMutation(suspendedLegacyAdminUid);
  } finally {
    await Promise.all([
      db.collection("users").doc(missingAuthUid).delete().catch(() => undefined),
      db.collection("users").doc(pendingUid).delete().catch(() => undefined),
      db.collection("users").doc(suspendedLegacyAdminUid).delete().catch(() => undefined),
      getAuth().deleteUser(pendingUid).catch(() => undefined),
      getAuth().deleteUser(suspendedLegacyAdminUid).catch(() => undefined),
      db.collection("mind_aid_emergency_alerts").doc(unauthAlertId).delete().catch(() => undefined),
    ]);
  }
});

test("Scenario F/G: eligible counselor (including active legacy) and super-admin preserve emergency alert access", async () => {
  const legacyActiveUid = `${prefix}-legacy-active-counselor`;
  const superAdminUid = `${prefix}-super-admin`;
  await Promise.all([ensureVerifiedAuthUser(legacyActiveUid), ensureVerifiedAuthUser(superAdminUid)]);
  await Promise.all([
    db.collection("users").doc(legacyActiveUid).set({accessRole: "counselor", name: "Legacy Active Counselor"}),
    db.collection("users").doc(superAdminUid).set({accessRole: "admin", accountStatus: "active", name: "Super Admin"}),
  ]);
  const prevSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = superAdminUid;
  const alertByLegacyId = await seedTempAlert(`${student}-f1`, "open");
  const alertBySuperId = await seedTempAlert(`${student}-g1`, "open");
  const activeRef1 = db.collection("_mind_aid_active_emergency_alerts").doc(`${student}-f1`);
  const activeRef2 = db.collection("_mind_aid_active_emergency_alerts").doc(`${student}-g1`);
  try {
    await acknowledgeMindAidEmergencyAlertHandler(callable(request(legacyActiveUid, {alertId: alertByLegacyId})));
    await resolveMindAidEmergencyAlertHandler(callable(request(counselor, {alertId: alertByLegacyId, resolutionDisposition: "contacted_user"})));
    const legData = (await db.collection("mind_aid_emergency_alerts").doc(alertByLegacyId).get()).data()!;
    assert.equal(legData.status, "resolved");
    assert.equal(legData.acknowledgedBy, legacyActiveUid);
    assert.equal(legData.resolvedBy, counselor);

    await acknowledgeMindAidEmergencyAlertHandler(callable(request(superAdminUid, {alertId: alertBySuperId})));
    await resolveMindAidEmergencyAlertHandler(callable(request(superAdminUid, {alertId: alertBySuperId, resolutionDisposition: "referred_immediate_support"})));
    const supData = (await db.collection("mind_aid_emergency_alerts").doc(alertBySuperId).get()).data()!;
    assert.equal(supData.status, "resolved");
    assert.equal(supData.acknowledgedBy, superAdminUid);
    assert.equal(supData.resolvedBy, superAdminUid);
  } finally {
    if (prevSuperAdmin == null) delete process.env.SUPER_ADMIN_UID;
    else process.env.SUPER_ADMIN_UID = prevSuperAdmin;
    await Promise.all([
      db.collection("users").doc(legacyActiveUid).delete().catch(() => undefined),
      db.collection("users").doc(superAdminUid).delete().catch(() => undefined),
      getAuth().deleteUser(legacyActiveUid).catch(() => undefined),
      getAuth().deleteUser(superAdminUid).catch(() => undefined),
      db.collection("mind_aid_emergency_alerts").doc(alertByLegacyId).delete().catch(() => undefined),
      db.collection("mind_aid_emergency_alerts").doc(alertBySuperId).delete().catch(() => undefined),
      activeRef1.delete().catch(() => undefined),
      activeRef2.delete().catch(() => undefined),
    ]);
  }
});

test("notificationRecipients excludes disabled-Auth, unverified-email, missing-Auth, and suspended legacy accounts", async () => {
  const disabledUid = `${prefix}-notify-disabled-auth`;
  const unverifiedUid = `${prefix}-notify-unverified`;
  const suspendedLegacyUid = `${prefix}-notify-suspended-legacy`;
  const missingAuthUid = `${prefix}-notify-missing-auth`;
  const pendingUid = `${prefix}-notify-pending`;
  const targetStudent = `${prefix}-notify-student`;
  await Promise.all([
    getAuth().createUser({uid: disabledUid, email: `${disabledUid}@example.invalid`, emailVerified: true, disabled: true}),
    getAuth().createUser({uid: unverifiedUid, email: `${unverifiedUid}@example.invalid`, emailVerified: false, disabled: false}),
    ensureVerifiedAuthUser(suspendedLegacyUid),
    ensureVerifiedAuthUser(pendingUid),
    ensureVerifiedAuthUser(targetStudent),
    db.collection("users").doc(disabledUid).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Disabled Counselor"}),
    db.collection("users").doc(unverifiedUid).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Unverified Counselor"}),
    db.collection("users").doc(suspendedLegacyUid).set({accessRole: "counselor", accountStatus: "suspended", name: "Suspended Legacy Counselor"}),
    db.collection("users").doc(missingAuthUid).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Missing Auth Counselor"}),
    db.collection("users").doc(pendingUid).set({accessRole: "counselor", staffAccountStatus: "pending", accountStatus: "active", name: "Pending Counselor"}),
    db.collection("users").doc(targetStudent).set({accessRole: "appUser"}),
  ]);
  let alertId = "";
  try {
    const created = await createOrUpdateMindAidEmergencyAlert({
      userId: targetStudent,
      conversationId: "conv-notify",
      triggerMessageId: "msg-notify",
    });
    alertId = created.alertId;
    assert.equal(created.notified, true);
    const notices = await db.collection("notifications").where("emergencyAlertId", "==", alertId).get();
    const notifiedUids = notices.docs.map((doc) => String(doc.data().userId)).sort();
    assert.deepEqual(notifiedUids, [counselor]);
    assert.equal((await db.collection("notifications").doc(`mind_aid_emergency_${alertId}_${disabledUid}`).get()).exists, false);
    assert.equal((await db.collection("notifications").doc(`mind_aid_emergency_${alertId}_${unverifiedUid}`).get()).exists, false);
    assert.equal((await db.collection("notifications").doc(`mind_aid_emergency_${alertId}_${suspendedLegacyUid}`).get()).exists, false);
    assert.equal((await db.collection("notifications").doc(`mind_aid_emergency_${alertId}_${missingAuthUid}`).get()).exists, false);
    assert.equal((await db.collection("notifications").doc(`mind_aid_emergency_${alertId}_${pendingUid}`).get()).exists, false);
    assert.equal((await db.collection("notifications").doc(`mind_aid_emergency_${alertId}_${staff}`).get()).exists, false);
    assert.equal((await db.collection("notifications").doc(`mind_aid_emergency_${alertId}_${admin}`).get()).exists, false);
  } finally {
    const noticeDocs = alertId ? await db.collection("notifications").where("emergencyAlertId", "==", alertId).get() : null;
    await Promise.all([
      ...[disabledUid, unverifiedUid, suspendedLegacyUid, missingAuthUid, pendingUid, targetStudent]
        .map((id) => db.collection("users").doc(id).delete().catch(() => undefined)),
      ...[disabledUid, unverifiedUid, suspendedLegacyUid, pendingUid, targetStudent]
        .map((id) => getAuth().deleteUser(id).catch(() => undefined)),
      alertId ? db.collection("mind_aid_emergency_alerts").doc(alertId).delete().catch(() => undefined) : Promise.resolve(),
      db.collection("_mind_aid_active_emergency_alerts").doc(targetStudent).delete().catch(() => undefined),
      ...(noticeDocs?.docs.map((doc) => doc.ref.delete().catch(() => undefined)) ?? []),
    ]);
  }
});
