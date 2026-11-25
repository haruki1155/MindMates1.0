import assert from "node:assert/strict";
import {test} from "node:test";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import * as functions from "./index";
import {ensureAuthUser} from "./test_auth_helper";

test("queue delayed and duplicate events project authoritative confirmation", async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  const db = getFirestore();
  const ref = db.doc("appointments/gate2-queue");
  await db.doc("users/gate2-queue-student").set({accessRole: "appUser", collegeId: "college-verified"});
  await ref.set({userId: "gate2-queue-student", fullName: "Student", collegeId: "untrusted-client-value", status: "requested", scheduleRevision: 1, scheduledAt: Timestamp.fromMillis(2000000000000)});
  const old = await ref.get();
  await ref.update({status: "confirmed", scheduleRevision: 2});
  const trigger = functions.syncPortalAppointmentQueue as unknown as {run: (event: unknown) => Promise<void>};
  await Promise.all([1, 2].map(() => trigger.run({params: {appointmentId: ref.id}, data: {after: old}})));
  const queue = (await db.doc(`appointment_queue/${ref.id}`).get()).data()!;
  assert.equal(queue.status, "confirmed");
  assert.equal(queue.scheduleRevision, 2);
  assert.equal(queue.collegeId, "college-verified");
  assert.equal(queue.userId, undefined);
  assert.equal(queue.concern, undefined);
  await ref.update({status: "requested", scheduleRevision: 3});
  const olderPending = await ref.get();
  await ref.update({status: "confirmed"}); // confirmation keeps the revision
  await trigger.run({params: {appointmentId: ref.id}, data: {after: olderPending}});
  await ensureAuthUser("gate2-refresh-staff", true);
  await db.doc("users/gate2-refresh-staff").set({accessRole: "portalStaff"});
  await db.doc(`appointment_queue/${ref.id}`).delete();
  const refresh = functions.refreshPortalAppointmentQueue as unknown as {run: (request: unknown) => Promise<unknown>};
  await refresh.run({auth: {uid: "gate2-refresh-staff"}});
  const refreshed = (await db.doc(`appointment_queue/${ref.id}`).get()).data()!;
  assert.equal(refreshed.status, "confirmed");
  assert.equal(refreshed.scheduleRevision, 3);
  assert.equal(refreshed.collegeId, "college-verified");
  assert.equal(refreshed.userId, undefined);
  assert.equal(refreshed.scheduledAt.toMillis(), 2000000000000);
});

test("reschedule notifications reject delayed pending events after confirmation", async () => {
  const db = getFirestore();
  const ref = db.doc("appointments/gate2-notification");
  await ensureAuthUser("gate2-staff", true);
  await db.doc("users/gate2-staff").set({accessRole: "portalStaff"});
  await ref.set({userId: "gate2-student", status: "confirmed", scheduleRevision: 0, scheduledAt: Timestamp.fromMillis(2000000000000), concern: "PRIVATE"});
  const before = await ref.get();
  await ref.update({status: "requested", scheduleRevision: 1, studentScheduleRequestId: "gate2_request_1"});
  const pending = await ref.get();
  await ref.update({status: "confirmed"});
  const trigger = functions.notifyPortalOfStudentAppointmentAction as unknown as {run: (event: unknown) => Promise<void>};
  await trigger.run({params: {appointmentId: ref.id}, data: {before, after: pending}});
  assert.equal((await db.collection("notifications").where("appointmentId", "==", ref.id).get()).empty, true);
});

test("reminder A to B to A uses revision identities and legacy remains compatible", async () => {
  const db = getFirestore();
  const ref = db.doc("appointments/gate2-reminder");
  const time = Timestamp.fromMillis(Date.now() + 55 * 60000);
  await ref.set({userId: "gate2-student", status: "confirmed", scheduledAt: time});
  const run = functions.sendAppointmentReminders as unknown as {run: (event: unknown) => Promise<void>};
  await run.run({});
  assert.equal((await db.doc(`notifications/appointment_reminder_oneHour_${ref.id}`).get()).exists, true);
  await ref.update({status: "confirmed", scheduleRevision: 1, reminders: {}, scheduledAt: Timestamp.fromMillis(time.toMillis() + 60000), studentScheduleRequestId: "g2-edit-1"});
  await run.run({});
  await ref.update({scheduleRevision: 2, reminders: {}, scheduledAt: time, studentScheduleRequestId: "g2-edit-2"});
  await Promise.all([run.run({}), run.run({})]);
  const reminders = await db.collection("notifications")
    .where("appointmentId", "==", ref.id)
    .where("type", "==", "appointment_reminder")
    .get();
  assert.equal(reminders.size, 3);
  assert.deepEqual(
    reminders.docs.map((doc) => doc.id).sort(),
    [
      `appointment_reminder_oneHour_${ref.id}`,
      `appointment_reminder_oneHour_${ref.id}_revision_1`,
      `appointment_reminder_oneHour_${ref.id}_revision_2`,
    ].sort(),
  );
  for (const doc of reminders.docs) {
    assert.equal(doc.data().type, "appointment_reminder");
    assert.equal(doc.data().reminderStage, "oneHour");
  }
  assert.equal(reminders.docs.filter((n) => (n.data().scheduleRevision ?? null) === null).length, 1);
  assert.equal(reminders.docs.filter((n) => n.data().scheduleRevision === 1).length, 1);
  assert.equal(reminders.docs.filter((n) => n.data().scheduleRevision === 2).length, 1);
});

test("push dispatcher rejects an obsolete reminder immediately before delivery", async () => {
  const db = getFirestore();
  const ref = db.doc("appointments/gate2-dispatch");
  const time = Timestamp.fromMillis(Date.now() + 55 * 60000);
  await ref.set({userId: "gate2-dispatch-user", status: "confirmed", scheduleRevision: 2, scheduledAt: time});
  const note = db.doc("notifications/gate2-obsolete");
  await note.set({userId: "gate2-dispatch-user", type: "appointment_reminder", appointmentId: ref.id, scheduleRevision: 0, scheduledAt: time, reminderStage: "oneHour"});
  await db.doc("user_devices/gate2-dispatch-user/tokens/test-token").set({token: "test-token"});
  const messaging = (await import("firebase-admin/messaging")).getMessaging();
  const {mock} = await import("node:test");
  const send = mock.method(messaging, "sendEachForMulticast", async () => ({responses: [{success: true}], successCount: 1, failureCount: 0}));
  try {
    const trigger = functions.sendAppointmentNotification as unknown as {run: (event: unknown) => Promise<void>};
    await trigger.run({params: {notificationId: note.id}, data: await note.get()});
    assert.equal(send.mock.callCount(), 0);
  } finally { send.mock.restore(); }
});

test("push retries retain transient tokens and completed delivery is deduplicated", async () => {
  const db = getFirestore();
  const appointment = db.doc("appointments/gate2-retry");
  const time = Timestamp.fromMillis(Date.now() + 55 * 60000);
  await appointment.set({userId: "gate2-retry-user", status: "confirmed", scheduleRevision: 1, scheduledAt: time});
  const note = db.doc("notifications/gate2-retry");
  await note.set({userId: "gate2-retry-user", type: "appointment_reminder", appointmentId: appointment.id, scheduleRevision: 1, scheduledAt: time, reminderStage: "oneHour"});
  const token = db.doc("user_devices/gate2-retry-user/tokens/retry-token");
  await token.set({token: "retry-token"});
  const {getMessaging} = await import("firebase-admin/messaging");
  const {mock} = await import("node:test");
  let fail = true;
  const send = mock.method(getMessaging(), "sendEachForMulticast", async () => fail
    ? {responses: [{success: false, error: {code: "messaging/internal-error"}}], successCount: 0, failureCount: 1}
    : {responses: [{success: true}], successCount: 1, failureCount: 0});
  const trigger = functions.sendAppointmentNotification as unknown as {run: (event: unknown) => Promise<void>};
  const event = {params: {notificationId: note.id}, data: await note.get()};
  try {
    await assert.rejects(trigger.run(event));
    assert.equal((await token.get()).exists, true);
    fail = false;
    await trigger.run(event);
    await trigger.run(event);
    assert.equal(send.mock.callCount(), 2);
    assert.ok((await note.get()).data()?.pushDeliveredAt);
  } finally { send.mock.restore(); }
});

test("integrated reschedule, notification retries, queue, confirmation, and revised reminders", async () => {
  const db = getFirestore();
  const {mock} = await import("node:test");
  const day = new Date(Date.now() + 42 * 86400000);
  while ([0, 6].includes(day.getUTCDay())) day.setUTCDate(day.getUTCDate() + 1);
  const a = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 3);
  const b = a - 3600000;
  const id = "gate2-integrated";
  const uid = "gate2-integrated-student";
  const staff = "gate2-integrated-staff";
  const college = "gate2-integrated-college";
  const previousSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = staff;
  try {
  const ref = db.doc(`appointments/${id}`);
  await ensureAuthUser(staff, true);
  await db.doc(`colleges/${college}`).set({name: "Gate2 College", code: "G2C", active: true});
  await db.doc(`users/${uid}`).set({accessRole: "appUser", verificationStatus: "verified", collegeId: college});
  await db.doc(`users/${staff}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: [college]});
  await db.doc("pacc_availability/current").set({openDays: [1, 2, 3, 4, 5], opensAt: "09:00", closesAt: "17:00", presence: "in_office", acceptsWalkIns: false, blackoutDates: []});
  await ref.set({userId: uid, fullName: "Private name", concern: "PRIVATE CONCERN", status: "confirmed", scheduleRevision: 0, scheduledAt: Timestamp.fromMillis(a), scheduledTime: "11:00 AM"});
  await db.doc(`appointment_slots/pacc_${a}`).set({appointmentId: id});
  await db.doc(`appointment_user_locks/${uid}`).set({appointmentId: id});
  const edit = functions.rescheduleStudentAppointment as unknown as {run: (r: unknown) => Promise<unknown>};
  const review = functions.reviewAppointment as unknown as {run: (r: unknown) => Promise<unknown>};
  const notify = functions.notifyPortalOfStudentAppointmentAction as unknown as {run: (r: unknown) => Promise<unknown>};
  const sync = functions.syncPortalAppointmentQueue as unknown as {run: (r: unknown) => Promise<unknown>};
  const remind = functions.sendAppointmentReminders as unknown as {run: (r: unknown) => Promise<unknown>};
  const original = await ref.get();
  const request = {auth: {uid}, data: {appointmentId: id, expectedScheduledAt: a, expectedScheduleRevision: 0, scheduledAt: b, requestId: "gate2-integrated-edit"}};
  await edit.run({...request, data: {...request.data, scheduledAt: a, requestId: "gate2_noop_original"}});
  assert.deepEqual((await ref.get()).data(), original.data());
  // Fail the transactional proposal once, then retry the same identity.
  const failure = mock.method(db, "runTransaction", async () => { throw new Error("injected processing failure"); });
  await assert.rejects(edit.run(request), /injected/);
  failure.mock.restore();
  await edit.run(request);
  await edit.run(request);
  const pending = await ref.get();
  assert.equal(pending.data()?.scheduledAt.toMillis(), a);
  assert.equal(pending.data()?.proposalStatus, "pending");
  const event = {params: {appointmentId: id}, data: {before: original, after: pending}};
  await sync.run(event);
  const noteRef = db.doc(`notifications/agreement_${id}_gate2-integrated-edit_${staff}`);
  const note = (await noteRef.get()).data()!;
  assert.equal(note.scheduleRevision, 0);
  assert.equal(note.proposalRevision, 1);
  assert.equal(note.scheduledAt.toMillis(), a);
  assert.equal(JSON.stringify(note).includes("PRIVATE"), false);
  assert.equal(note.fullName, undefined);
  assert.equal((await db.doc(`appointment_queue/${id}`).get()).data()?.status, "confirmed");
  const agree = functions.changeAppointmentAgreement as unknown as {run: (r: unknown) => Promise<unknown>};
  await agree.run({auth: {uid: staff}, data: {appointmentId: id, action: "accept", requestId: "gate2_staff_accept", expectedScheduledAt: a, expectedScheduleRevision: 0, expectedProposalRevision: 1}});
  await sync.run(event);
  assert.equal((await db.doc(`appointment_queue/${id}`).get()).data()?.scheduledAt.toMillis(), b);
  assert.ok((await noteRef.get()).data()?.archivedAt);
  const clock = mock.method(Timestamp, "now", () => Timestamp.fromMillis(b - 55 * 60000));
  try { await Promise.all([remind.run({}), remind.run({})]); } finally { clock.mock.restore(); }
  const reminder = db.doc(`notifications/appointment_reminder_oneHour_${id}_revision_1`);
  assert.equal((await reminder.get()).exists, true);
  const beforeReturn = await ref.get();
  await edit.run({auth: {uid}, data: {appointmentId: id, expectedScheduledAt: b, expectedScheduleRevision: 1, expectedProposalRevision: 2, scheduledAt: a, requestId: "gate2-integrated-return"}});
  assert.equal((await ref.get()).data()?.scheduledAt.toMillis(), b);
  await agree.run({auth: {uid: staff}, data: {appointmentId: id, action: "accept", requestId: "gate2_accept_return", expectedScheduledAt: b, expectedScheduleRevision: 1, expectedProposalRevision: 3}});
  await sync.run(event);
  assert.ok((await reminder.get()).data()?.archivedAt);
  await notify.run(event); // revision 1 cannot recreate a current pending alert
  assert.ok((await noteRef.get()).data()?.archivedAt);
  const revised = await ref.get();
  await notify.run({params: {appointmentId: id}, data: {before: beforeReturn, after: revised}});
  await edit.run(request); // old successful replay does not restore B
  assert.equal((await ref.get()).data()?.scheduleRevision, 2);
  assert.equal((await ref.get()).data()?.scheduledAt.toMillis(), a);
  assert.equal((await db.doc(`appointment_slots/pacc_${a}`).get()).data()?.appointmentId, id);
  assert.equal((await db.doc(`appointment_slots/pacc_${b}`).get()).exists, false);
  assert.equal((await db.doc(`appointment_user_locks/${uid}`).get()).data()?.appointmentId, id);
  } finally {
    if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID;
    else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  }
});

test("partial push retry does not resend to a successful device", async () => {
  const db = getFirestore();
  const time = Timestamp.fromMillis(Date.now() + 55 * 60000);
  const appointment = db.doc("appointments/gate2-partial");
  await appointment.set({status: "confirmed", scheduleRevision: 1, scheduledAt: time});
  const note = db.doc("notifications/gate2-partial");
  await note.set({userId: "gate2-partial", type: "appointment_reminder", appointmentId: appointment.id, scheduleRevision: 1, scheduledAt: time, reminderStage: "oneHour"});
  for (const token of ["device-a", "device-b"]) await db.doc(`user_devices/gate2-partial/tokens/${token}`).set({token});
  const {getMessaging} = await import("firebase-admin/messaging");
  const {mock} = await import("node:test");
  const recipients: string[][] = [];
  const send = mock.method(getMessaging(), "sendEachForMulticast", async (message: {tokens: string[]}) => {
    recipients.push(message.tokens);
    return {responses: message.tokens.map((token) => recipients.length === 1 && token === "device-b"
      ? {success: false, error: {code: "messaging/internal-error"}} : {success: true}), successCount: 1, failureCount: recipients.length === 1 ? 1 : 0};
  });
  const trigger = functions.sendAppointmentNotification as unknown as {run: (event: unknown) => Promise<void>};
  const event = {params: {notificationId: note.id}, data: await note.get()};
  try {
    await assert.rejects(trigger.run(event));
    await trigger.run(event);
    assert.deepEqual(recipients, [["device-a", "device-b"], ["device-b"]]);
    assert.ok((await note.get()).data()?.pushDeliveredAt);
  } finally { send.mock.restore(); }
});

test("delayed current-revision reminder is rejected after its delivery window", async () => {
  const db = getFirestore();
  const time = Timestamp.fromMillis(Date.now() - 60000);
  await db.doc("appointments/gate2-expired").set({status: "confirmed", scheduleRevision: 1, scheduledAt: time});
  const note = db.doc("notifications/gate2-expired");
  await note.set({userId: "gate2-expired", type: "appointment_reminder", appointmentId: "gate2-expired", scheduleRevision: 1, scheduledAt: time, reminderStage: "oneHour"});
  await db.doc("user_devices/gate2-expired/tokens/device").set({token: "expired-device"});
  const {getMessaging} = await import("firebase-admin/messaging");
  const {mock} = await import("node:test");
  const delivered: string[] = [];
  const send = mock.method(getMessaging(), "sendEachForMulticast", async (message: {tokens: string[]}) => {
    delivered.push(...message.tokens);
    return {responses: [{success: true}], successCount: 1, failureCount: 0};
  });
  try {
    const trigger = functions.sendAppointmentNotification as unknown as {run: (event: unknown) => Promise<void>};
    await trigger.run({params: {notificationId: note.id}, data: await note.get()});
    assert.deepEqual(delivered, []);
    assert.ok((await note.get()).data()?.archivedAt);
  } finally { send.mock.restore(); }
});

test("current cancellation alert survives automatic appointment archiving", async () => {
  const db = getFirestore();
  const time = Timestamp.fromMillis(Date.now() + 86400000);
  const appointment = db.doc("appointments/gate2-cancelled");
  await appointment.set({status: "cancelled", scheduleRevision: 1, scheduledAt: time, archivedAt: Timestamp.now()});
  const note = db.doc("notifications/gate2-cancelled");
  await note.set({userId: "gate2-cancelled-staff", type: "appointment", appointmentId: appointment.id, scheduleRevision: 1, scheduledAt: time, expectedStatus: "cancelled", studentScheduleRequestId: null});
  await db.doc("user_devices/gate2-cancelled-staff/tokens/device").set({token: "cancel-device"});
  const sync = functions.syncPortalAppointmentQueue as unknown as {run: (event: unknown) => Promise<void>};
  await sync.run({params: {appointmentId: appointment.id}});
  assert.equal((await note.get()).data()?.archivedAt, undefined);
  const {getMessaging} = await import("firebase-admin/messaging");
  const {mock} = await import("node:test");
  const delivered: string[] = [];
  const send = mock.method(getMessaging(), "sendEachForMulticast", async (message: {tokens: string[]}) => {
    delivered.push(...message.tokens);
    return {responses: [{success: true}], successCount: 1, failureCount: 0};
  });
  try {
    const trigger = functions.sendAppointmentNotification as unknown as {run: (event: unknown) => Promise<void>};
    await trigger.run({params: {notificationId: note.id}, data: await note.get()});
    assert.deepEqual(delivered, ["cancel-device"]);
  } finally { send.mock.restore(); }
});

test("concurrent reminder delivery uses one lease and rejects ineligible statuses", async () => {
  const db = getFirestore();
  const time = Timestamp.fromMillis(Date.now() + 55 * 60000);
  const appointment = db.doc("appointments/gate2-concurrent-push");
  await appointment.set({status: "confirmed", scheduleRevision: 1, scheduledAt: time});
  const note = db.doc("notifications/gate2-concurrent-push");
  await note.set({userId: "gate2-concurrent-push", type: "appointment_reminder", appointmentId: appointment.id, scheduleRevision: 1, scheduledAt: time, reminderStage: "oneHour"});
  await db.doc("user_devices/gate2-concurrent-push/tokens/device").set({token: "concurrent-device"});
  const {getMessaging} = await import("firebase-admin/messaging");
  const {mock} = await import("node:test");
  const delivered: string[] = [];
  const send = mock.method(getMessaging(), "sendEachForMulticast", async (message: {tokens: string[]}) => {
    delivered.push(...message.tokens);
    return {responses: [{success: true}], successCount: 1, failureCount: 0};
  });
  const trigger = functions.sendAppointmentNotification as unknown as {run: (event: unknown) => Promise<void>};
  try {
    const event = {params: {notificationId: note.id}, data: await note.get()};
    await Promise.allSettled([trigger.run(event), trigger.run(event)]);
    await trigger.run(event);
    assert.deepEqual(delivered, ["concurrent-device"]);
    assert.ok((await note.get()).data()?.pushDeliveredAt);
    for (const status of ["requested", "cancelled", "completed", "declined", "no_show", "expired"]) {
      await appointment.update({status});
      const blocked = db.doc(`notifications/gate2-ineligible-${status}`);
      await blocked.set({userId: "gate2-concurrent-push", type: "appointment_reminder", appointmentId: appointment.id, scheduleRevision: 1, scheduledAt: time, reminderStage: "oneHour"});
      await trigger.run({params: {notificationId: blocked.id}, data: await blocked.get()});
      assert.ok((await blocked.get()).data()?.archivedAt);
    }
    assert.deepEqual(delivered, ["concurrent-device"]);
  } finally { send.mock.restore(); }
});

test("clinical appointment actions reject wrong-college, suspended, disabled, unverified, pending, portalStaff, and non-super-admin accounts", async () => {
  const db = getFirestore();
  const {getAuth} = await import("firebase-admin/auth");
  const prefix = `gate2-neg-${Date.now()}`;
  const cite = `${prefix}-cite`;
  const cas = `${prefix}-cas`;
  const studentUid = `${prefix}-student`;
  const assignedUid = `${prefix}-assigned`;
  const superAdminUid = `${prefix}-super-admin`;
  const wrongCollegeUid = `${prefix}-wrong-college`;
  const suspendedUid = `${prefix}-suspended`;
  const disabledAuthUid = `${prefix}-disabled-auth`;
  const unverifiedUid = `${prefix}-unverified`;
  const pendingStaffUid = `${prefix}-pending`;
  const portalStaffUid = `${prefix}-portal-staff`;
  const nonSuperAdminUid = `${prefix}-non-super-admin`;
  const previousSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = superAdminUid;
  try {
    await Promise.all([
      db.doc(`colleges/${cite}`).set({name: "CITE", code: "CITE", active: true}),
      db.doc(`colleges/${cas}`).set({name: "CAS", code: "CAS", active: true}),
      db.doc(`users/${studentUid}`).set({accessRole: "appUser", verificationStatus: "verified", collegeId: cite}),
      ensureAuthUser(assignedUid, true),
      db.doc(`users/${assignedUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: [cite]}),
      ensureAuthUser(superAdminUid, true),
      db.doc(`users/${superAdminUid}`).set({accessRole: "admin", accountStatus: "active"}),
      ensureAuthUser(wrongCollegeUid, true),
      db.doc(`users/${wrongCollegeUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: [cas]}),
      ensureAuthUser(suspendedUid, true),
      db.doc(`users/${suspendedUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "suspended", assignedCollegeIds: [cite]}),
      ensureAuthUser(disabledAuthUid, true),
      db.doc(`users/${disabledAuthUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: [cite]}),
      ensureAuthUser(unverifiedUid, false),
      db.doc(`users/${unverifiedUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: [cite]}),
      ensureAuthUser(pendingStaffUid, true),
      db.doc(`users/${pendingStaffUid}`).set({accessRole: "counselor", staffAccountStatus: "pending", accountStatus: "active", assignedCollegeIds: [cite]}),
      ensureAuthUser(portalStaffUid, true),
      db.doc(`users/${portalStaffUid}`).set({accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: [cite]}),
      ensureAuthUser(nonSuperAdminUid, true),
      db.doc(`users/${nonSuperAdminUid}`).set({accessRole: "admin", accountStatus: "active"}),
    ]);
    await getAuth().updateUser(disabledAuthUid, {disabled: true, emailVerified: true});
    const day = new Date(Date.now() + 49 * 86400000);
    while ([0, 6].includes(day.getUTCDay())) day.setUTCDate(day.getUTCDate() + 1);
    const slotAt = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 2);
    const apptId = `${prefix}-appt`;
    await db.doc(`appointments/${apptId}`).set({
      userId: studentUid, status: "requested", scheduleRevision: 0, proposalRevision: 0,
      scheduledAt: Timestamp.fromMillis(slotAt), scheduledTime: "10:00 AM", concern: "PRIVATE",
    });
    await db.doc(`appointment_slots/pacc_${slotAt}`).set({appointmentId: apptId});
    await db.doc(`appointment_user_locks/${studentUid}`).set({appointmentId: apptId});
    const review = functions.reviewAppointment as unknown as {run: (r: unknown) => Promise<unknown>};
    for (const actorUid of [wrongCollegeUid, suspendedUid, disabledAuthUid, unverifiedUid, pendingStaffUid, portalStaffUid, nonSuperAdminUid]) {
      await assert.rejects(
        review.run({
          auth: {uid: actorUid},
          data: {
            appointmentId: apptId, action: "confirmed", reply: "Approved.",
            expectedScheduledAt: slotAt, expectedScheduleRevision: 0, expectedProposalRevision: 0, expectedStatus: "requested",
          },
        }),
        (e: {code?: string}) => e.code === "permission-denied",
        `expected permission-denied for ${actorUid}`,
      );
    }
    assert.equal((await db.doc(`appointments/${apptId}`).get()).data()?.status, "requested");
    await review.run({
      auth: {uid: assignedUid},
      data: {
        appointmentId: apptId, action: "confirmed", reply: "Approved by college counselor.",
        expectedScheduledAt: slotAt, expectedScheduleRevision: 0, expectedProposalRevision: 0, expectedStatus: "requested",
      },
    });
    assert.equal((await db.doc(`appointments/${apptId}`).get()).data()?.status, "confirmed");
  } finally {
    if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID;
    else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  }
});
