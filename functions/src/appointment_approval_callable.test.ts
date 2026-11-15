import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

import {changeAppointmentAgreement, respondToAppointment, reviewAppointment} from "./index";
import {listAppointmentApprovals} from "./appointment_approval_service";

// Auth + Firestore emulators. Real callables, real slot locks and history.
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const p = `approval-${Date.now()}`;
const uid = (name: string) => `${p}-${name}`;
const db = getFirestore();
const cite = `${p}-cite`;
const cas = `${p}-cas`;
const cba = `${p}-cba`;

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<any>};
const call = (fn: unknown, actor: string, data: Record<string, unknown>) => (fn as Callable).run({auth: {uid: uid(actor)}, data});
async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => (e as {code?: string})?.code === code, `expected ${code}`);
}

const staff: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  otherAdmin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Other Admin"}},
  cA: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Counselor CITE", assignedCollegeIds: [cite]}},
  cB: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Counselor CAS", assignedCollegeIds: [cas]}},
  sus: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "disabled", accountStatus: "suspended", name: "Suspended", assignedCollegeIds: [cite]}},
  unv: {verified: false, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Unverified", assignedCollegeIds: [cite]}},
  ops: {verified: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", name: "Operations", assignedCollegeIds: [cite]}},
};
const students: Record<string, Record<string, unknown>> = {
  cite: {accessRole: "appUser", verificationStatus: "verified", collegeId: cite},
  cas: {accessRole: "appUser", verificationStatus: "verified", collegeId: cas},
  none: {accessRole: "appUser", verificationStatus: "verified"},
  unverified: {accessRole: "appUser", verificationStatus: "needsReview", collegeId: cite},
  cba: {accessRole: "appUser", verificationStatus: "verified", collegeId: cba},
};

let slotCursor = 0;
async function freeSlot(): Promise<number> {
  for (let offset = 2 + slotCursor; offset < 400; offset += 1) {
    const day = new Date(Date.now() + offset * 86_400_000);
    if (day.getUTCDay() < 1 || day.getUTCDay() > 5) continue;
    const millis = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 1 + (offset % 7));
    if (!(await db.doc(`appointment_slots/pacc_${millis}`).get()).exists) {
      slotCursor = offset - 1;
      return millis;
    }
  }
  throw new Error("no free slot");
}

let n = 0;
async function seed(student: string, status = "requested"): Promise<{id: string; at: number}> {
  const id = `${p}-appt-${++n}`;
  const at = await freeSlot();
  const owner = uid(`student-${student}`);
  await db.doc(`appointments/${id}`).set({
    userId: owner, fullName: `Student ${student}`, status, scheduleRevision: 0, proposalRevision: 0,
    scheduledAt: Timestamp.fromMillis(at), scheduledTime: "9:00 AM", concern: "Private concern text", createdAt: Timestamp.now(),
  });
  await db.doc(`appointment_slots/pacc_${at}`).set({appointmentId: id, scheduledAt: Timestamp.fromMillis(at)});
  await db.doc(`appointment_user_locks/${owner}`).set({appointmentId: id});
  return {id, at};
}
const confirm = (id: string, at: number, extra: Record<string, unknown> = {}) => ({
  appointmentId: id, action: "confirmed", reply: "Your appointment is confirmed.",
  expectedScheduledAt: at, expectedScheduleRevision: 0, expectedProposalRevision: 0, expectedStatus: "requested", ...extra,
});
const appointment = async (id: string) => (await db.doc(`appointments/${id}`).get()).data()!;
const history = async (id: string) => (await db.collection(`appointments/${id}/history`).get()).docs.map((d) => d.data());
const audits = async (id: string, action: string) =>
  (await db.collection("admin_audit_logs").where("targetId", "==", id).where("action", "==", action).get()).docs.map((d) => d.data());

/** History is student-readable: only the approval mode may appear there. */
function assertNoInternalApprovalDetail(entry: Record<string, unknown>): void {
  for (const field of ["approvalCollegeId", "approvalScopeReason", "approvalExceptionReason"]) {
    assert.equal(entry[field], undefined, `${field} must stay in the admin-only audit log`);
  }
}

let previous: string | undefined;
before(async () => {
  if (!emulated) return;
  previous = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = uid("admin");
  for (const [name, account] of Object.entries(staff)) {
    await getAuth().createUser({uid: uid(name), email: `${uid(name)}@example.invalid`, emailVerified: account.verified});
    await db.doc(`users/${uid(name)}`).set(account.profile);
  }
  for (const [name, profile] of Object.entries(students)) await db.doc(`users/${uid(`student-${name}`)}`).set(profile);
  for (const id of [cite, cas, cba]) await db.doc(`colleges/${id}`).set({name: id, code: id, active: true});
  await db.doc("pacc_availability/current").set({openDays: [1, 2, 3, 4, 5], opensAt: "08:00", closesAt: "17:00", presence: "in_office", acceptsWalkIns: false, notice: "", blackoutDates: []});
});

after(async () => {
  if (!emulated) return;
  if (previous == null) delete process.env.SUPER_ADMIN_UID; else process.env.SUPER_ADMIN_UID = previous;
  await Promise.all(Object.keys(staff).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

test("the counselor assigned to the student's college confirms; history, audit and notification record it", {skip: !emulated}, async () => {
  const {id, at} = await seed("cite");
  await call(reviewAppointment, "cA", confirm(id, at));
  const data = await appointment(id);
  assert.equal(data.status, "confirmed");
  const entries = await history(id);
  assert.equal(entries.length, 1);
  assert.deepEqual([entries[0].status, entries[0].staffId, entries[0].approvalMode], ["confirmed", uid("cA"), "college"]);
  const [row] = await audits(id, "APPOINTMENT_CONFIRMED");
  assert.deepEqual([row.metadata.approval.mode, row.metadata.approval.collegeId], ["college", cite]);
  const toStudent = (await db.collection("notifications").where("appointmentId", "==", id).where("userId", "==", uid("student-cite")).get()).docs.map((d) => d.data());
  assert.equal(toStudent.length, 1);
  assert.equal(toStudent[0].type, "appointment_confirmed");
  // The slot and the student's lock are untouched by a confirmation.
  assert.equal((await db.doc(`appointment_slots/pacc_${at}`).get()).data()?.appointmentId, id);
});

test("wrong-college, suspended, unverified counselors, operational staff and students are refused without writes", {skip: !emulated}, async () => {
  const {id, at} = await seed("cite");
  for (const actor of ["cB", "sus", "unv", "ops", "otherAdmin"]) {
    await rejects(call(reviewAppointment, actor, confirm(id, at)), "permission-denied");
  }
  await rejects((reviewAppointment as unknown as Callable).run({auth: {uid: uid("student-cite")}, data: confirm(id, at)}), "permission-denied");
  assert.equal((await appointment(id)).status, "requested");
  assert.equal((await history(id)).length, 0);
  assert.equal((await audits(id, "APPOINTMENT_CONFIRMED")).length, 0);
});

test("missing, unverified, unknown or unstaffed colleges go to super-admin triage; counselors cannot act on them", {skip: !emulated}, async () => {
  for (const [student, reason] of [["none", "missing_college"], ["unverified", "unverified_profile"], ["cba", "no_eligible_counselor"]] as const) {
    const {id, at} = await seed(student);
    await rejects(call(reviewAppointment, "cA", confirm(id, at)), "permission-denied");
    await call(reviewAppointment, "admin", confirm(id, at));
    const [entry] = await history(id);
    assert.equal(entry.approvalMode, "admin_triage", student);
    assertNoInternalApprovalDetail(entry);
    const [row] = await audits(id, "APPOINTMENT_CONFIRMED");
    assert.deepEqual([row.metadata.approval.mode, row.metadata.approval.scopeReason], ["admin_triage", reason]);
  }
});

test("the super-admin overrides a college-scoped appointment only with a written reason", {skip: !emulated}, async () => {
  const {id, at} = await seed("cite");
  await rejects(call(reviewAppointment, "admin", confirm(id, at)), "failed-precondition");
  await rejects(call(reviewAppointment, "admin", confirm(id, at, {exceptionReason: "no"})), "failed-precondition");
  assert.equal((await appointment(id)).status, "requested");
  await call(reviewAppointment, "admin", confirm(id, at, {exceptionReason: "Counselor on approved leave"}));
  const [entry] = await history(id);
  assert.equal(entry.approvalMode, "admin_override");
  assertNoInternalApprovalDetail(entry);
  assert.ok(!JSON.stringify(entry).includes("approved leave"), "the student-readable history must not carry the override reason");
  const [row] = await audits(id, "APPOINTMENT_CONFIRMED");
  assert.deepEqual([row.metadata.approval.mode, row.metadata.approval.exceptionReason], ["admin_override", "Counselor on approved leave"]);
});

test("the two-way agreement still works for the assigned counselor and refuses others", {skip: !emulated}, async () => {
  const {id, at} = await seed("cite", "confirmed");
  const target = await freeSlot();
  const propose = (requestId: string) => ({appointmentId: id, action: "propose", requestId, scheduledAt: target, reason: "Counselor schedule change",
    expectedScheduledAt: at, expectedScheduleRevision: 0, expectedProposalRevision: 0});
  await rejects(call(changeAppointmentAgreement, "cB", propose(`${p}-propose-cB`)), "permission-denied");
  await rejects(call(changeAppointmentAgreement, "ops", propose(`${p}-propose-ops`)), "permission-denied");
  await call(changeAppointmentAgreement, "cA", propose(`${p}-propose-cA`));
  let data = await appointment(id);
  assert.deepEqual([data.proposalStatus, data.proposedBy, data.scheduledAt.toMillis()], ["pending", "counselor", at], "the current reservation is kept until the student accepts");
  await (respondToAppointment as unknown as Callable).run({auth: {uid: uid("student-cite")}, data: {appointmentId: id, action: "accept_reschedule", requestId: `${p}-accept-${id}`,
    expectedScheduledAt: at, expectedScheduleRevision: 0, expectedProposalRevision: data.proposalRevision}});
  data = await appointment(id);
  assert.equal(data.scheduledAt.toMillis(), target);
  assert.equal((await db.doc(`appointment_slots/pacc_${target}`).get()).data()?.appointmentId, id);
  assert.equal((await db.doc(`appointment_slots/pacc_${at}`).get()).exists, false, "the old slot is released");
  const proposed = (await history(id)).find((h) => h.type === "APPOINTMENT_SCHEDULE_PROPOSED" || h.proposedBy === "counselor");
  assert.equal(proposed?.approvalMode, "college");
  assertNoInternalApprovalDetail(proposed!);
});

test("a student's counterproposal can be accepted only by the assigned counselor", {skip: !emulated}, async () => {
  const {id, at} = await seed("cite", "confirmed");
  const target = await freeSlot();
  await (changeAppointmentAgreement as unknown as Callable).run({auth: {uid: uid("student-cite")}, data: {appointmentId: id, action: "propose", requestId: `${p}-student-${id}`, scheduledAt: target,
    reason: "Class conflict", expectedScheduledAt: at, expectedScheduleRevision: 0, expectedProposalRevision: 0}});
  const proposalRevision = (await appointment(id)).proposalRevision;
  const accept = (actor: string) => call(changeAppointmentAgreement, actor, {appointmentId: id, action: "accept", requestId: `${p}-accept-${actor}-${id}`,
    expectedScheduledAt: at, expectedScheduleRevision: 0, expectedProposalRevision: proposalRevision});
  await rejects(accept("cB"), "permission-denied");
  await accept("cA");
  assert.equal((await appointment(id)).scheduledAt.toMillis(), target);
});

test("two approvers racing on one appointment produce exactly one confirmation", {skip: !emulated}, async () => {
  const {id, at} = await seed("cite");
  const outcomes = await Promise.allSettled([
    call(reviewAppointment, "cA", confirm(id, at)),
    call(reviewAppointment, "admin", confirm(id, at, {exceptionReason: "Covering the queue today"})),
  ]);
  assert.equal(outcomes.filter((o) => o.status === "fulfilled").length, 1);
  assert.equal((await history(id)).filter((h) => h.status === "confirmed").length, 1);
  assert.equal((await audits(id, "APPOINTMENT_CONFIRMED")).length, 1);
});

test("two counselors rescheduling different appointments into one slot cannot double-book it", {skip: !emulated}, async () => {
  const first = await seed("cite", "confirmed");
  const second = await seed("cas", "confirmed");
  const target = await freeSlot();
  const propose = (actor: string, appt: {id: string; at: number}) => call(changeAppointmentAgreement, actor, {appointmentId: appt.id, action: "propose", requestId: `${p}-race-${appt.id}`,
    scheduledAt: target, reason: "Consolidating sessions", expectedScheduledAt: appt.at, expectedScheduleRevision: 0, expectedProposalRevision: 0});
  await Promise.all([propose("cA", first), propose("cB", second)]);
  const acceptBy = async (student: string, appt: {id: string; at: number}) => (respondToAppointment as unknown as Callable).run({auth: {uid: uid(`student-${student}`)}, data: {
    appointmentId: appt.id, action: "accept_reschedule", requestId: `${p}-race-accept-${appt.id}`,
    expectedScheduledAt: appt.at, expectedScheduleRevision: 0, expectedProposalRevision: (await appointment(appt.id)).proposalRevision}});
  const outcomes = await Promise.allSettled([acceptBy("cite", first), acceptBy("cas", second)]);
  assert.equal(outcomes.filter((o) => o.status === "fulfilled").length, 1);
  const owner = (await db.doc(`appointment_slots/pacc_${target}`).get()).data()?.appointmentId;
  assert.ok(owner === first.id || owner === second.id);
  const moved = [await appointment(first.id), await appointment(second.id)].filter((a) => a.scheduledAt.toMillis() === target);
  assert.equal(moved.length, 1);
});

test("My College's Approvals lists only the counselor's colleges; the super-admin sees exceptions; no clinical text", {skip: !emulated}, async () => {
  const mine = await seed("cite");
  const theirs = await seed("cas");
  const triage = await seed("none");
  const forA = await call(listAppointmentApprovals, "cA", {});
  const idsA = forA.items.map((i: {appointmentId: string}) => i.appointmentId);
  assert.ok(idsA.includes(mine.id));
  assert.ok(!idsA.includes(theirs.id) && !idsA.includes(triage.id));
  const forB = await call(listAppointmentApprovals, "cB", {});
  assert.ok(forB.items.some((i: {appointmentId: string}) => i.appointmentId === theirs.id));
  const forAdmin = await call(listAppointmentApprovals, "admin", {});
  const exception = forAdmin.items.find((i: {appointmentId: string}) => i.appointmentId === triage.id);
  assert.deepEqual([exception?.scope, exception?.reason], ["exception", "missing_college"]);
  assert.ok(!forAdmin.items.some((i: {appointmentId: string}) => i.appointmentId === mine.id), "college-scoped items belong to counselors");
  assert.ok(!JSON.stringify([forA, forB, forAdmin]).includes("Private concern"), "no clinical text in the list");
  for (const actor of ["ops", "otherAdmin", "sus"]) await rejects(call(listAppointmentApprovals, actor, {}), "permission-denied");
});

test("internal approval detail is only in the admin-only audit log, never in student-readable history", {skip: !emulated}, async () => {
  const {id, at} = await seed("cba");
  await call(reviewAppointment, "admin", confirm(id, at));
  const [entry] = await history(id);
  assertNoInternalApprovalDetail(entry);
  const [row] = await audits(id, "APPOINTMENT_CONFIRMED");
  assert.deepEqual([row.metadata.approval.mode, row.metadata.approval.scopeReason, row.metadata.approval.collegeId], ["admin_triage", "no_eligible_counselor", cba]);
});
