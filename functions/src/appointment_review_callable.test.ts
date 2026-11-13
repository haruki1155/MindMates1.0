import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

import {respondToAppointment, reviewAppointment} from "./index";

type Callable = {run: (request: {auth?: {uid: string}; data?: Record<string, unknown>}) => Promise<unknown>};
const db = getFirestore();
const prefix = `appointment-review-${Date.now()}`;
const studentId = `${prefix}-student`;
const adminId = `${prefix}-admin`;
const counselorId = `${prefix}-counselor`;
const otherCounselorId = `${prefix}-other-counselor`;
const portalStaffId = `${prefix}-portal-staff`;
const rawReview = reviewAppointment as unknown as Callable;
// Applied-schedule assertions include the now-required other-side acceptance.
const review: Callable = {run: async request => {
  const result = await rawReview.run(request);
  if (request.data?.action === "rescheduled") {
    const id = String(request.data.appointmentId);
    const data = (await db.doc(`appointments/${id}`).get()).data()!;
    await (respondToAppointment as unknown as Callable).run({auth: {uid: data.userId}, data: {appointmentId: id, action: "accept_reschedule", requestId: `accept_${id}`, expectedScheduledAt: data.scheduledAt.toMillis(), expectedScheduleRevision: data.scheduleRevision, expectedProposalRevision: data.proposalRevision}});
  }
  return result;
}};
const respond = respondToAppointment as unknown as Callable;
const availability = db.collection("pacc_availability").doc("current");

async function futureWeekdaySlot(excluded = new Set<number>()): Promise<number> {
  for (let offset = 1; offset <= 21; offset += 1) {
    const candidate = new Date(Date.now() + offset * 86_400_000);
    if (candidate.getUTCDay() < 1 || candidate.getUTCDay() > 5) continue;
    const slot = Date.UTC(candidate.getUTCFullYear(), candidate.getUTCMonth(), candidate.getUTCDate(), 1);
    if (excluded.has(slot)) continue;
    const claimed = await db.collection("appointment_slots").doc(`pacc_${slot}`).get();
    if (!claimed.exists) return slot;
  }
  throw new Error("No future weekday slot found.");
}
const presented = new Map<string, {expectedScheduledAt: number; expectedStatus: string; expectedScheduleRevision: number}>();
function payload(appointmentId: string, proposedAt: number, reason = "Office schedule adjustment") {
  return {appointmentId, ...presented.get(appointmentId), action: "rescheduled", reply: "PACC has updated your appointment schedule.", proposedScheduledAt: proposedAt, rescheduleReason: reason};
}
async function expectCallableFailure(promise: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(promise, (error: {code?: unknown}) => error?.code === code);
}
async function seedAppointment(id: string, options: {assignedStaffId?: string; status?: string; scheduledAt?: number; claimSlot?: boolean} = {}) {
  const scheduledAt = options.scheduledAt ?? await futureWeekdaySlot();
  const appointment = db.collection("appointments").doc(`${prefix}-${id}`);
  const status = options.status ?? "confirmed";
  presented.set(appointment.id, {expectedScheduledAt: scheduledAt, expectedStatus: status, expectedScheduleRevision: 0});
  await appointment.set({userId: studentId, status, scheduleRevision: 0, assignedStaffId: options.assignedStaffId ?? counselorId, scheduledAt: Timestamp.fromMillis(scheduledAt), scheduledTime: "9:00 AM", concern: "Academic pressure"});
  await db.collection("appointment_user_locks").doc(studentId).set({appointmentId: appointment.id});
  if (options.claimSlot !== false) await db.collection("appointment_slots").doc(`pacc_${scheduledAt}`).set({appointmentId: appointment.id, scheduledAt: Timestamp.fromMillis(scheduledAt)});
  return appointment;
}
async function setOpenSchedule(): Promise<void> {
  await availability.set({openDays: [1, 2, 3, 4, 5], opensAt: "09:00", closesAt: "17:00", presence: "in_office", acceptsWalkIns: false, notice: "", blackoutDates: []});
}

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("FIRESTORE_EMULATOR_HOST is required for appointment callable tests.");
  await Promise.all([
    db.collection("users").doc(studentId).set({accessRole: "appUser"}), db.collection("users").doc(adminId).set({accessRole: "admin", name: "Test Admin"}),
    db.collection("users").doc(counselorId).set({accessRole: "counselor", name: "Assigned Counselor"}), db.collection("users").doc(otherCounselorId).set({accessRole: "counselor", name: "Other Counselor"}),
    db.collection("users").doc(portalStaffId).set({accessRole: "portalStaff", name: "Portal Staff"}), setOpenSchedule(),
  ]);
});
after(async () => {
  const appointments = await db.collection("appointments").where("userId", "==", studentId).get();
  const appointmentIds = new Set(appointments.docs.map((item) => item.id));
  for (const appointment of appointments.docs) {
    const [history, notes] = await Promise.all([appointment.ref.collection("history").get(), appointment.ref.collection("clinical_notes").get()]);
    await Promise.all([...history.docs.map((item) => item.ref.delete()), ...notes.docs.map((item) => item.ref.delete()), appointment.ref.delete()]);
  }
  const [slots, notifications, audits] = await Promise.all([db.collection("appointment_slots").get(), db.collection("notifications").where("userId", "==", studentId).get(), db.collection("admin_audit_logs").get()]);
  await Promise.all([...slots.docs.filter((item) => appointmentIds.has(String(item.data().appointmentId ?? ""))).map((item) => item.ref.delete()), ...notifications.docs.map((item) => item.ref.delete()), ...audits.docs.filter((item) => appointmentIds.has(String(item.data().targetId ?? ""))).map((item) => item.ref.delete()), db.collection("appointment_user_locks").doc(studentId).delete(), availability.delete(), ...[studentId, adminId, counselorId, otherCounselorId, portalStaffId].map((id) => db.collection("users").doc(id).delete())]);
});

test("staff proposal is applied atomically only after student acceptance and audited", async () => {
  const oldAt = await futureWeekdaySlot(); const appointment = await seedAppointment("atomic", {scheduledAt: oldAt}); const newAt = await futureWeekdaySlot(new Set([oldAt]));
  await assert.doesNotReject(review.run({auth: {uid: counselorId}, data: payload(appointment.id, newAt)}));
  const [updated, oldSlot, newSlot, lock, history, notices, audit] = await Promise.all([appointment.get(), db.collection("appointment_slots").doc(`pacc_${oldAt}`).get(), db.collection("appointment_slots").doc(`pacc_${newAt}`).get(), db.collection("appointment_user_locks").doc(studentId).get(), appointment.collection("history").get(), db.collection("notifications").where("appointmentId", "==", appointment.id).get(), db.collection("admin_audit_logs").where("targetId", "==", appointment.id).get()]);
  assert.equal(updated.data()?.status, "confirmed"); assert.equal(updated.data()?.scheduledAt.toMillis(), newAt); assert.equal(updated.data()?.proposalStatus, "accepted"); assert.deepEqual(updated.data()?.reminders, {});
  assert.equal(oldSlot.exists, false); assert.equal(newSlot.data()?.appointmentId, appointment.id); assert.equal(lock.data()?.appointmentId, appointment.id);
  const historyEntry = history.docs.find((item) => item.data().type === "appointment_schedule_agreed")?.data();
  assert.equal(history.docs.find(item => item.data().type === "appointment_schedule_proposed")?.data().reason, payload(appointment.id, newAt).rescheduleReason);
  assert.equal(historyEntry?.previousScheduledAt.toMillis(), oldAt); assert.equal(historyEntry?.scheduledAt.toMillis(), newAt);
  assert.equal(notices.docs.some(n => n.data().type === "appointment" && n.data().agreementEvent === "appointment_schedule_agreed" && n.data().audience === "portal"), true);
  assert.equal(audit.docs.some((item) => item.data().action === "APPOINTMENT_SCHEDULE_PROPOSED" && item.data().actorId === counselorId), true);
  await expectCallableFailure(respond.run({auth: {uid: studentId}, data: {appointmentId: appointment.id, action: "accept_reschedule", requestId: "stale_completed_accept", expectedScheduledAt: oldAt, expectedScheduleRevision: 0, expectedProposalRevision: 1}}), "aborted");
});

test("occupied target is rejected without appointment or slot mutation", async () => {
  const oldAt = await futureWeekdaySlot(); const newAt = await futureWeekdaySlot(new Set([oldAt])); const appointment = await seedAppointment("occupied", {scheduledAt: oldAt});
  await db.collection("appointment_slots").doc(`pacc_${newAt}`).set({appointmentId: "other", scheduledAt: Timestamp.fromMillis(newAt)});
  await expectCallableFailure(review.run({auth: {uid: counselorId}, data: payload(appointment.id, newAt)}), "already-exists");
  assert.equal((await appointment.get()).data()?.scheduledAt.toMillis(), oldAt); assert.equal((await db.collection("appointment_slots").doc(`pacc_${oldAt}`).get()).data()?.appointmentId, appointment.id);
});

test("closed, overridden, unavailable, and disabled schedules reject without mutation", async () => {
  const oldAt = await futureWeekdaySlot(); const newAt = await futureWeekdaySlot(new Set([oldAt])); const appointment = await seedAppointment("availability", {scheduledAt: oldAt});
  const date = new Date(newAt).toISOString().slice(0, 10);
  const closed = {enabled: false, opensAt: "09:00", closesAt: "17:00", presence: "out_of_office", appointmentsEnabled: false, acceptsWalkIns: false};
  const open = {enabled: true, opensAt: "09:00", closesAt: "17:00", presence: "in_office", appointmentsEnabled: true, acceptsWalkIns: false};
  for (const config of [
    {weekdays: Object.fromEntries(Array.from({length: 7}, (_, i) => [String(i + 1), closed])), overrides: []},
    {weekdays: Object.fromEntries(Array.from({length: 7}, (_, i) => [String(i + 1), open])), overrides: [{date, closedAllDay: true, reason: "Special closure"}]},
    {weekdays: Object.fromEntries(Array.from({length: 7}, (_, i) => [String(i + 1), {...open, presence: "on_leave"}])), overrides: []},
    {weekdays: Object.fromEntries(Array.from({length: 7}, (_, i) => [String(i + 1), {...open, appointmentsEnabled: false}])), overrides: []},
  ]) { await availability.set({schemaVersion: 2, timezone: "Asia/Manila", ...config, notice: ""}); await expectCallableFailure(review.run({auth: {uid: counselorId}, data: payload(appointment.id, newAt)}), "failed-precondition"); assert.equal((await appointment.get()).data()?.scheduledAt.toMillis(), oldAt); }
  await setOpenSchedule();
});

test("terminal, unauthorized, and forged staff actions are denied", async () => {
  const slot = await futureWeekdaySlot(); const terminal = await seedAppointment("terminal", {scheduledAt: slot, status: "completed"});
  await expectCallableFailure(review.run({auth: {uid: counselorId}, data: payload(terminal.id, await futureWeekdaySlot(new Set([slot])))}), "failed-precondition");
  const appointment = await seedAppointment("authority"); const target = await futureWeekdaySlot();
  await expectCallableFailure(review.run({auth: {uid: studentId}, data: payload(appointment.id, target)}), "permission-denied"); await expectCallableFailure(review.run({auth: {uid: portalStaffId}, data: payload(appointment.id, target)}), "permission-denied");
  await assert.doesNotReject(review.run({auth: {uid: otherCounselorId}, data: payload(appointment.id, target)}));
  const updated = (await appointment.get()).data()!;
  assert.equal(updated.assignedStaffId, counselorId);
  const actions = await appointment.collection("history").get();
  assert.equal(actions.docs.some(d => d.data().performedBy === otherCounselorId), true);
});

test("legacy proposal is explicitly counterproposed by staff and accepted by student", async () => {
  const oldAt = await futureWeekdaySlot(); const newAt = await futureWeekdaySlot(new Set([oldAt])); const appointment = await seedAppointment("legacy", {scheduledAt: oldAt, status: "reschedule_proposed"});
  await appointment.update({proposedScheduledAt: Timestamp.fromMillis(newAt), proposedScheduledTime: "9:00 AM", proposedBy: "counselor", proposalStatus: "pending", rescheduleReason: "Legacy"});
  await assert.doesNotReject(review.run({auth: {uid: counselorId}, data: payload(appointment.id, newAt)}));
  const data = (await appointment.get()).data()!; assert.equal(data.status, "confirmed"); assert.equal(data.scheduledAt.toMillis(), newAt);
  assert.equal(data.proposalStatus, "accepted");
});

test("concurrent re-schedules to one slot allow exactly one claimant", async () => {
  const firstAt = await futureWeekdaySlot(); const secondAt = await futureWeekdaySlot(new Set([firstAt])); const target = await futureWeekdaySlot(new Set([firstAt, secondAt]));
  const first = await seedAppointment("race-first", {scheduledAt: firstAt}); const second = await seedAppointment("race-second", {scheduledAt: secondAt});
  await first.update({userId: `${studentId}-race`});
  await db.doc(`appointment_user_locks/${studentId}-race`).set({appointmentId: first.id});
  const outcomes = await Promise.allSettled([review.run({auth: {uid: counselorId}, data: payload(first.id, target)}), review.run({auth: {uid: adminId}, data: payload(second.id, target)})]);
  assert.equal(outcomes.filter((result) => result.status === "fulfilled").length, 1); assert.equal(outcomes.filter((result) => result.status === "rejected").length, 1); assert.equal((await db.collection("appointment_slots").doc(`pacc_${target}`).get()).exists, true);
});
