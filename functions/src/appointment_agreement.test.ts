import assert from "node:assert/strict";
import {test} from "node:test";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import * as functions from "./index";

type Input = Record<string, unknown>;
const db = getFirestore();
const staff = "agreement-clinician";
const student = "agreement-student";
function call(uid: string, data: Input): Promise<unknown> {
  const callable = (functions as unknown as Record<string, {run: (r: unknown) => Promise<unknown>}>).changeAppointmentAgreement;
  assert.ok(callable, "two-way agreement callable must exist");
  return callable.run({auth: {uid}, data});
}
async function seed(id: string, status = "confirmed") {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "demo emulator required");
  const day = new Date(Date.now() + 45 * 86400000);
  while ([0, 6].includes(day.getUTCDay())) day.setUTCDate(day.getUTCDate() + 1);
  const a = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 1);
  const b = a + 3600000;
  const c = a + 7200000;
  await db.doc(`users/${staff}`).set({accessRole: "admin"});
  await db.doc("pacc_availability/current").set({openDays: [1,2,3,4,5], opensAt: "09:00", closesAt: "17:00", presence: "in_office", acceptsWalkIns: false, blackoutDates: []});
  await db.doc(`appointments/${id}`).set({userId: student, status, scheduledAt: Timestamp.fromMillis(a), scheduledTime: "09:00 AM", scheduleRevision: 0, concern: "PRIVATE CONCERN"});
  await db.doc(`appointment_slots/pacc_${a}`).set({appointmentId: id});
  await db.doc(`appointment_slots/pacc_${b}`).delete();
  await db.doc(`appointment_slots/pacc_${c}`).delete();
  await db.doc(`appointment_user_locks/${student}`).set({appointmentId: id});
  const input = {appointmentId: id, expectedScheduledAt: a, expectedScheduleRevision: 0, expectedProposalRevision: 0};
  return {a,b,c,input, ref: db.doc(`appointments/${id}`)};
}

test("proposal keeps approved current reservation until other-side acceptance", async () => {
  const {a,b,input,ref} = await seed("agreement-accept");
  const propose = {...input, action: "propose", scheduledAt: b, requestId: "agreement_propose_1"};
  await call(student, propose);
  await call(student, propose);
  let data = (await ref.get()).data()!;
  assert.equal(data.scheduledAt.toMillis(), a);
  assert.equal(data.status, "confirmed");
  assert.equal(data.proposedScheduledAt.toMillis(), b);
  assert.equal(data.proposalRevision, 1);
  assert.equal((await db.doc(`appointment_slots/pacc_${a}`).get()).data()?.appointmentId, ref.id);
  assert.equal((await db.doc(`appointment_slots/pacc_${b}`).get()).exists, false);
  await assert.rejects(call(student, {...input, expectedProposalRevision: 1, action: "accept", requestId: "agreement_self_accept"}), {code: "permission-denied"});
  await call(staff, {...input, expectedProposalRevision: 1, action: "accept", requestId: "agreement_accept_1"});
  data = (await ref.get()).data()!;
  assert.equal(data.status, "confirmed");
  assert.equal(data.scheduledAt.toMillis(), b);
  assert.equal(data.scheduleRevision, 1);
  assert.equal(data.proposalStatus, "accepted");
  assert.equal((await db.doc(`appointment_slots/pacc_${a}`).get()).exists, false);
  assert.equal((await db.doc(`appointment_slots/pacc_${b}`).get()).data()?.appointmentId, ref.id);
  assert.equal((await ref.collection("history").get()).size, 2);
  const audit = await db.collection("admin_audit_logs").where("targetId", "==", ref.id).get();
  assert.equal(audit.docs.some(d => d.data().action === "APPOINTMENT_SCHEDULE_AGREED"), true);
});

test("staff suggestion requires student acceptance; superseded proposals cannot be accepted", async () => {
  const {a,b,c,input,ref} = await seed("agreement-counter", "requested");
  await call(staff, {...input, action: "propose", scheduledAt: b, requestId: "agreement_staff_propose"});
  await call(student, {...input, expectedProposalRevision: 1, action: "propose", scheduledAt: c, requestId: "agreement_counter_propose"});
  await assert.rejects(call(student, {...input, expectedProposalRevision: 1, action: "accept", requestId: "agreement_stale_accept"}), {code: "aborted"});
  assert.equal((await ref.get()).data()?.scheduledAt.toMillis(), a);
  await call(staff, {...input, expectedProposalRevision: 2, action: "accept", requestId: "agreement_counter_accept"});
  assert.equal((await ref.get()).data()?.scheduledAt.toMillis(), c);
  assert.equal((await ref.get()).data()?.status, "confirmed");
});

for (const status of ["requested", "confirmed"]) test(`student cancellation is immediate with optional reason: ${status}`, async () => {
  const {a,b,input,ref} = await seed(`agreement-cancel-${status}`, status);
  await call(staff, {...input, action: "propose", scheduledAt: b, requestId: `agreement_before_${status}`});
  const cancel = {...input, expectedProposalRevision: 1, action: "cancel", requestId: `agreement_cancel_${status}`, reason: status === "requested" ? "" : "PRIVATE REASON"};
  await call(student, cancel);
  await call(student, cancel);
  const data = (await ref.get()).data()!;
  assert.equal(data.status, "cancelled");
  assert.equal(data.proposalStatus, "cancelled");
  assert.equal((await db.doc(`appointment_slots/pacc_${a}`).get()).exists, false);
  assert.equal((await db.doc(`appointment_user_locks/${student}`).get()).exists, false);
  assert.equal((await ref.collection("history").get()).size, 2);
  const notes = await db.collection("notifications").where("appointmentId", "==", ref.id).get();
  assert.equal(JSON.stringify(notes.docs.map(d => d.data())).includes("PRIVATE"), false);
  await assert.rejects(call(student, {...input, expectedProposalRevision: 1, action: "accept", requestId: "agreement_cancelled_accept"}));
});

test("occupied replacement and unauthorized caller leave current reservation intact", async () => {
  const {a,b,input,ref} = await seed("agreement-conflict");
  await assert.rejects(call("unrelated-student", {...input, action: "cancel", requestId: "agreement_other_cancel"}), {code: "permission-denied"});
  await call(staff, {...input, action: "propose", scheduledAt: b, requestId: "agreement_conflict_propose"});
  await db.doc(`appointment_slots/pacc_${b}`).set({appointmentId: "another-appointment"});
  await assert.rejects(call(student, {...input, expectedProposalRevision: 1, action: "accept", requestId: "agreement_conflict_accept"}), {code: "already-exists"});
  assert.equal((await ref.get()).data()?.scheduledAt.toMillis(), a);
  assert.equal((await db.doc(`appointment_slots/pacc_${a}`).get()).data()?.appointmentId, ref.id);
});


test("accept/cancel race has one winner and no leaked reservation", async () => {
  const {a,b,input,ref} = await seed("agreement-race");
  await call(staff, {...input, action: "propose", scheduledAt: b, requestId: "agreement_race_propose"});
  const outcomes = await Promise.allSettled(["accept", "cancel"].map(action => call(student, {...input, expectedProposalRevision: 1, action, requestId: `agreement_race_${action}`})));
  assert.equal(outcomes.filter(r => r.status === "fulfilled").length, 1);
  const data = (await ref.get()).data()!;
  assert.equal((await db.doc(`appointment_slots/pacc_${a}`).get()).exists, false);
  if (data.status === "cancelled") {
    assert.equal((await db.doc(`appointment_slots/pacc_${b}`).get()).exists, false);
    assert.equal((await db.doc(`appointment_user_locks/${student}`).get()).exists, false);
  } else {
    assert.equal(data.scheduledAt.toMillis(), b);
    assert.equal((await db.doc(`appointment_slots/pacc_${b}`).get()).data()?.appointmentId, ref.id);
    assert.equal((await db.doc(`appointment_user_locks/${student}`).get()).data()?.appointmentId, ref.id);
  }
});

test("past, archived, terminal and foreign reservation fail closed", async () => {
  for (const state of ["past", "archived", "completed", "foreign"]) {
    const {a,input,ref} = await seed(`agreement_ineligible_${state}`);
    if (state === "past") await ref.update({scheduledAt: Timestamp.fromMillis(Date.now() - 1000)});
    if (state === "archived") await ref.update({archivedAt: Timestamp.now()});
    if (state === "completed") await ref.update({status: "completed"});
    if (state === "foreign") await db.doc(`appointment_slots/pacc_${a}`).set({appointmentId: "foreign-owner"});
    const data = (await ref.get()).data()!;
    await assert.rejects(call(student, {...input, expectedScheduledAt: data.scheduledAt.toMillis(), action: "cancel", requestId: `agreement_bad_${state}`}));
    assert.deepEqual((await ref.get()).data(), data);
  }
});

test("pending proposal cannot be bypassed by confirming old time; current reminders stay valid", async () => {
  const {a,b,input,ref} = await seed("agreement-reminders");
  await call(student, {...input, action: "propose", scheduledAt: b, requestId: "agreement_reminder_propose"});
  const data = (await ref.get()).data()!;
  assert.equal(functions.appointmentNotificationIsCurrent({type: "appointment_reminder", scheduleRevision: 0, scheduledAt: Timestamp.fromMillis(a)}, data), true);
  const review = functions.reviewAppointment as unknown as {run: (r: unknown) => Promise<unknown>};
  await assert.rejects(review.run({auth: {uid: staff}, data: {appointmentId: ref.id, action: "confirmed", reply: "Confirm old time", expectedScheduledAt: a, expectedScheduleRevision: 0, expectedStatus: "confirmed"}}), {code: "failed-precondition"});
  await call(staff, {...input, action: "accept", expectedProposalRevision: 1, requestId: "agreement_reminder_accept"});
  assert.equal(functions.appointmentNotificationIsCurrent({type: "appointment_reminder", scheduleRevision: 0, scheduledAt: Timestamp.fromMillis(a)}, (await ref.get()).data()), false);
});


test("agreement notices reach portal recipients and remain current on previously edited records", async () => {
  const {b,input,ref} = await seed("agreement-notification-compatibility");
  await ref.update({studentScheduleRequestId: "previous-v2-edit"});
  await call(student, {...input, action: "propose", scheduledAt: b, requestId: "agreement_compat_propose"});
  const pending = (await ref.get()).data()!;
  const note = (await db.doc(`notifications/agreement_${ref.id}_agreement_compat_propose_${staff}`).get()).data()!;
  assert.deepEqual([note.audience, note.type, functions.appointmentNotificationIsCurrent(note, pending)], ["portal", "appointment", true]);
});

test("cancellation update trigger does not duplicate durable agreement intents", async () => {
  const {input,ref} = await seed("agreement-cancel-notices");
  const before = await ref.get();
  await call(student, {...input, action: "cancel", requestId: "agreement_single_cancel"});
  const after = await ref.get();
  const trigger = functions.notifyPortalOfStudentAppointmentAction as unknown as {run: (event: unknown) => Promise<void>};
  const event = {params: {appointmentId: ref.id}, data: {before, after}};
  await trigger.run(event); await trigger.run(event);
  const notes = await db.collection("notifications").where("appointmentId", "==", ref.id).get();
  assert.equal(notes.docs.filter(d => d.data().userId === staff).length, 1);
});

test("counterproposal history preserves each target and staff context privately", async () => {
  const {b,c,input,ref} = await seed("agreement-history");
  await call(staff, {...input, action: "propose", scheduledAt: b, reason: "PRIVATE staff context", requestId: "agreement_history_staff"});
  await call(student, {...input, expectedProposalRevision: 1, action: "propose", scheduledAt: c, requestId: "agreement_history_counter"});
  await call(student, {...input, expectedProposalRevision: 2, action: "cancel", requestId: "agreement_history_cancel"});
  const history = (await ref.collection("history").get()).docs.map(d => d.data());
  assert.equal(history.some(h => h.proposedScheduledAt?.toMillis() === b && h.reason === "PRIVATE staff context" && h.performedBy === staff), true);
  assert.equal(history.some(h => h.proposedScheduledAt?.toMillis() === c && h.performedBy === student), true);
  const notes = await db.collection("notifications").where("appointmentId", "==", ref.id).get();
  assert.equal(JSON.stringify(notes.docs.map(d => d.data())).includes("PRIVATE"), false);
});
