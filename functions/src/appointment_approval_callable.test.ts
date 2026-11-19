import assert from "node:assert/strict";
import {after, before, mock, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

import {
  changeAppointmentAgreement,
  getAppointmentForApproval,
  initializeAppointmentScheduleRevision,
  respondToAppointment,
  reviewAppointment,
  setStaffCollegeAssignments,
} from "./index";
import {
  authorizeAppointmentApprovalInTransaction,
  listAppointmentApprovals,
  listAppointmentApprovalsBatch,
} from "./appointment_approval_service";

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

test("counselor college reassignment and transactional TOCTOU verification revoke authority immediately", {skip: !emulated}, async () => {
  const tempCounselor = uid("temp-cA");
  await getAuth().createUser({uid: tempCounselor, email: `${tempCounselor}@example.invalid`, emailVerified: true});
  await db.doc(`users/${tempCounselor}`).set({
    accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active",
    name: "Temp CITE Counselor", assignedCollegeIds: [cite],
  });
  try {
    const {id, at} = await seed("cite");
    // Reassign tempCounselor from cite -> cas before acting: immediately refused.
    await db.doc(`users/${tempCounselor}`).update({assignedCollegeIds: [cas]});
    await rejects(
      (reviewAppointment as unknown as Callable).run({auth: {uid: tempCounselor}, data: confirm(id, at)}),
      "permission-denied",
    );
    assert.equal((await appointment(id)).status, "requested");

    // Re-assign back to cite, then verify transactional revocation inside a live Firestore transaction.
    await db.doc(`users/${tempCounselor}`).update({assignedCollegeIds: [cite]});
    await db.runTransaction(async (tx) => {
      const verified = await authorizeAppointmentApprovalInTransaction(tx, tempCounselor, uid("student-cite"));
      assert.equal(verified.approvalAuthority.mode, "college");
    });

    // If the counselor loses cite between initial read and tx commit, tx verification rejects.
    let txCalls = 0;
    await assert.rejects(
      db.runTransaction(async (tx) => {
        txCalls += 1;
        if (txCalls === 1) {
          // Simulate concurrent modification to counselor assignments outside tx on first attempt
          // (or directly test that once users/{tempCounselor} changes, tx re-read refuses).
          await db.doc(`users/${tempCounselor}`).update({assignedCollegeIds: [cas]});
        }
        await authorizeAppointmentApprovalInTransaction(tx, tempCounselor, uid("student-cite"));
        tx.update(db.doc(`appointments/${id}`), {status: "confirmed"});
      }),
      (e: unknown) => (e as {code?: string})?.code === "permission-denied",
    );
    assert.equal((await appointment(id)).status, "requested");
  } finally {
    await db.doc(`users/${tempCounselor}`).delete().catch(() => undefined);
    await getAuth().deleteUser(tempCounselor).catch(() => undefined);
  }
});

test("listAppointmentApprovals paginates deterministically past >500 active appointments without omissions or duplicates", {skip: !emulated}, async () => {
  const bulkIds: string[] = [];
  const slotStart = await freeSlot();
  try {
    // 520 non-pending confirmed appointments sorting before the pending items.
    for (let start = 0; start < 520; start += 400) {
      const batch = db.batch();
      for (let i = start; i < Math.min(520, start + 400); i += 1) {
        const id = `${p}-bulk-${String(i).padStart(4, "0")}`;
        bulkIds.push(id);
        batch.set(db.doc(`appointments/${id}`), {
          userId: uid("student-cite"),
          fullName: `Confirmed ${i}`,
          status: "confirmed",
          scheduleRevision: 0,
          proposalRevision: 0,
          scheduledAt: Timestamp.fromMillis(slotStart + i * 60_000),
          scheduledTime: "9:00 AM",
          concern: "Private confirmed concern",
          createdAt: Timestamp.now(),
        });
      }
      await batch.commit();
    }
    const pendingId = `${p}-bulk-0520`;
    const proposalId = `${p}-bulk-0521`;
    const exceptionId = `${p}-bulk-0522`;
    const deletedCursorId = `${p}-bulk-0521a`;
    bulkIds.push(pendingId, proposalId, deletedCursorId, exceptionId);
    const writeBatch = db.batch();
    writeBatch.set(db.doc(`appointments/${pendingId}`), {
      userId: uid("student-cite"), fullName: "Pending Cite", status: "requested",
      scheduleRevision: 0, proposalRevision: 0, scheduledAt: Timestamp.fromMillis(slotStart + 1000),
      scheduledTime: "9:00 AM", concern: "Private concern pending", createdAt: Timestamp.now(),
    });
    writeBatch.set(db.doc(`appointments/${proposalId}`), {
      userId: uid("student-cite"), fullName: "Proposal Cite", status: "confirmed",
      proposalStatus: "pending", proposedBy: "student", scheduleRevision: 0, proposalRevision: 1,
      scheduledAt: Timestamp.fromMillis(slotStart + 2000), scheduledTime: "10:00 AM",
      concern: "Private concern proposal", createdAt: Timestamp.now(),
    });
    writeBatch.set(db.doc(`appointments/${deletedCursorId}`), {
      userId: uid("student-cite"), fullName: "Deleted Mid Scan", status: "requested",
      scheduleRevision: 0, proposalRevision: 0, scheduledAt: Timestamp.fromMillis(slotStart + 3000),
      scheduledTime: "11:00 AM", concern: "Private concern deleted", createdAt: Timestamp.now(),
    });
    writeBatch.set(db.doc(`appointments/${exceptionId}`), {
      userId: uid("student-none"), fullName: "Exception Student", status: "requested",
      scheduleRevision: 0, proposalRevision: 0, scheduledAt: Timestamp.fromMillis(slotStart + 4000),
      scheduledTime: "1:00 PM", concern: "Private concern exception", createdAt: Timestamp.now(),
    });
    await writeBatch.commit();

    // Real callable with default limit scans past all 520 confirmed docs and finds both pending CITE approvals.
    const fullForA = await call(listAppointmentApprovals, "cA", {limit: 50});
    const fullIdsA = fullForA.items.map((i: {appointmentId: string}) => i.appointmentId);
    assert.ok(fullIdsA.includes(pendingId), "requested item past 500 active docs must be returned");
    assert.ok(fullIdsA.includes(proposalId), "pending student proposal past 500 confirmed docs must be returned");
    assert.ok(!fullIdsA.includes(exceptionId), "counselor must not see exception queue");
    assert.ok(!JSON.stringify(fullForA).includes("Private concern"), "clinical text never enters list responses");

    const fullForAdmin = await call(listAppointmentApprovals, "admin", {limit: 50});
    const adminIds = fullForAdmin.items.map((i: {appointmentId: string}) => i.appointmentId);
    assert.ok(adminIds.includes(exceptionId));
    assert.ok(!adminIds.includes(pendingId));

    // Invalid cursor rejected cleanly.
    await rejects(call(listAppointmentApprovals, "cA", {cursor: "bad/cursor"}), "invalid-argument");
    await rejects(call(listAppointmentApprovals, "ops", {}), "permission-denied");
    await rejects(call(listAppointmentApprovals, "otherAdmin", {}), "permission-denied");

    // Multi-page continuation where first page returns 0 eligible items (all confirmed) must NOT claim done/empty.
    let cursor: string | null = `${p}-bulk-`;
    const collected: string[] = [];
    let pages = 0;
    let sawEmptyPageWithMore = false;
    for (;;) {
      const page = await listAppointmentApprovalsBatch(uid("cA"), {limit: 1, cursor, pageSize: 200, maxPages: 2});
      pages += 1;
      assert.ok(page.scanned <= 400, "scan per call stays strictly bounded");
      if (page.items.length === 0 && page.hasMore) sawEmptyPageWithMore = true;
      for (const item of page.items) {
        const apptId = String(item.appointmentId);
        assert.ok(!collected.includes(apptId), `duplicate item ${apptId} across pages`);
        collected.push(apptId);
      }
      if (!page.hasMore) {
        assert.equal(page.done, true);
        assert.equal(page.nextCursor, null);
        break;
      }
      assert.ok(page.nextCursor);
      cursor = page.nextCursor;
      // Delete the cursor appointment right after its page is returned to ensure continuation survives deletion.
      if (cursor === proposalId) {
        await db.doc(`appointments/${proposalId}`).delete();
      }
      assert.ok(pages < 20, "pagination must terminate");
    }
    assert.equal(sawEmptyPageWithMore, true, "first page of only confirmed records must report hasMore=true");
    assert.ok(collected.includes(pendingId));
    assert.ok(collected.includes(proposalId));
    assert.ok(collected.includes(deletedCursorId));
  } finally {
    for (let start = 0; start < bulkIds.length; start += 400) {
      const batch = db.batch();
      for (const id of bulkIds.slice(start, start + 400)) batch.delete(db.doc(`appointments/${id}`));
      await batch.commit();
    }
  }
});

test("initializeAppointmentScheduleRevision enforces college scope and audits atomically without leaking override reasons", {skip: !emulated}, async () => {
  const mkLegacy = async (studentKey: string) => {
    const id = `${p}-legacy-${++n}`;
    const at = await freeSlot();
    const owner = uid(`student-${studentKey}`);
    await db.doc(`appointments/${id}`).set({
      userId: owner, fullName: `Legacy ${studentKey}`, status: "confirmed",
      scheduledAt: Timestamp.fromMillis(at), scheduledTime: "9:00 AM", concern: "Private concern", createdAt: Timestamp.now(),
    });
    await db.doc(`appointment_slots/pacc_${at}`).set({appointmentId: id, scheduledAt: Timestamp.fromMillis(at)});
    await db.doc(`appointment_user_locks/${owner}`).set({appointmentId: id});
    return {id, at};
  };

  // Wrong college, ops, non-super admin, suspended, unverified, disabled Auth, pending staff all denied with zero audit/mutation.
  const pendUid = uid("pending-init");
  const disAuthUid = uid("disabled-auth-init");
  await Promise.all([
    getAuth().createUser({uid: pendUid, email: `${pendUid}@example.invalid`, emailVerified: true}),
    db.doc(`users/${pendUid}`).set({accessRole: "counselor", staffAccountStatus: "pending", accountStatus: "active", assignedCollegeIds: [cite]}),
    getAuth().createUser({uid: disAuthUid, email: `${disAuthUid}@example.invalid`, emailVerified: true, disabled: true}),
    db.doc(`users/${disAuthUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: [cite]}),
  ]);
  try {
    const leg1 = await mkLegacy("cite");
    const initPayload = (id: string, at: number, extra: Record<string, unknown> = {}) => ({
      appointmentId: id, expectedScheduledAt: at, expectedStatus: "confirmed", ...extra,
    });
    for (const actor of ["cB", "sus", "unv", "ops", "otherAdmin"]) {
      await rejects(call(initializeAppointmentScheduleRevision, actor, initPayload(leg1.id, leg1.at)), "permission-denied");
    }
    for (const rawUid of [pendUid, disAuthUid]) {
      await rejects((initializeAppointmentScheduleRevision as unknown as Callable).run({auth: {uid: rawUid}, data: initPayload(leg1.id, leg1.at)}), "permission-denied");
    }
    assert.equal((await appointment(leg1.id)).scheduleRevision, undefined);
    assert.equal((await audits(leg1.id, "APPOINTMENT_SCHEDULE_REVISION_INITIALIZED")).length, 0);

    // Assigned college counselor initializes once + writes 1 audit log; retry creates no duplicate audit.
    await call(initializeAppointmentScheduleRevision, "cA", initPayload(leg1.id, leg1.at));
    assert.equal((await appointment(leg1.id)).scheduleRevision, 0);
    const [initAudit] = await audits(leg1.id, "APPOINTMENT_SCHEDULE_REVISION_INITIALIZED");
    assert.deepEqual([initAudit.actorId, initAudit.metadata.approval.mode, initAudit.metadata.approval.collegeId, initAudit.metadata.after.scheduleRevision], [uid("cA"), "college", cite, 0]);
    await rejects(call(initializeAppointmentScheduleRevision, "cA", initPayload(leg1.id, leg1.at)), "failed-precondition");
    assert.equal((await audits(leg1.id, "APPOINTMENT_SCHEDULE_REVISION_INITIALIZED")).length, 1);

    // Super-admin override requires valid reason and writes reason only to admin_audit_logs.
    const leg2 = await mkLegacy("cite");
    await rejects(call(initializeAppointmentScheduleRevision, "admin", initPayload(leg2.id, leg2.at)), "failed-precondition");
    assert.equal((await appointment(leg2.id)).scheduleRevision, undefined);
    assert.equal((await audits(leg2.id, "APPOINTMENT_SCHEDULE_REVISION_INITIALIZED")).length, 0);
    await call(initializeAppointmentScheduleRevision, "admin", initPayload(leg2.id, leg2.at, {exceptionReason: "Legacy backfill exception"}));
    assert.equal((await appointment(leg2.id)).scheduleRevision, 0);
    assert.equal((await history(leg2.id)).length, 0);
    const [overrideAudit] = await audits(leg2.id, "APPOINTMENT_SCHEDULE_REVISION_INITIALIZED");
    assert.deepEqual([overrideAudit.metadata.approval.mode, overrideAudit.metadata.approval.exceptionReason], ["admin_override", "Legacy backfill exception"]);

    // Super-admin triage succeeds cleanly on missing/unverified/no_eligible_counselor college.
    const leg3 = await mkLegacy("none");
    await rejects(call(initializeAppointmentScheduleRevision, "cA", initPayload(leg3.id, leg3.at)), "permission-denied");
    await call(initializeAppointmentScheduleRevision, "admin", initPayload(leg3.id, leg3.at));
    const [triageAudit] = await audits(leg3.id, "APPOINTMENT_SCHEDULE_REVISION_INITIALIZED");
    assert.deepEqual([triageAudit.metadata.approval.mode, triageAudit.metadata.approval.scopeReason], ["admin_triage", "missing_college"]);
  } finally {
    await Promise.all([
      db.doc(`users/${pendUid}`).delete().catch(() => undefined),
      db.doc(`users/${disAuthUid}`).delete().catch(() => undefined),
      getAuth().deleteUser(pendUid).catch(() => undefined),
      getAuth().deleteUser(disAuthUid).catch(() => undefined),
    ]);
  }
});

test("in-flight counselor reassignment, student college change, and suspension abort callable transactions without partial writes", {skip: !emulated}, async () => {
  const actorUid = uid("race-counselor");
  const studentUid = uid("race-student");
  await getAuth().createUser({uid: actorUid, email: `${actorUid}@example.invalid`, emailVerified: true});
  await db.doc(`users/${actorUid}`).set({
    accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active",
    name: "Race Counselor", assignedCollegeIds: [cite],
  });
  await db.doc(`users/${studentUid}`).set({accessRole: "appUser", verificationStatus: "verified", collegeId: cite});

  const seedRace = async (status = "requested") => {
    const id = `${p}-race-tx-${++n}`;
    const at = await freeSlot();
    await db.doc(`appointments/${id}`).set({
      userId: studentUid, fullName: "Race Student", status, scheduleRevision: 0, proposalRevision: 0,
      scheduledAt: Timestamp.fromMillis(at), scheduledTime: "9:00 AM", concern: "Private", createdAt: Timestamp.now(),
    });
    await db.doc(`appointment_slots/pacc_${at}`).set({appointmentId: id, scheduledAt: Timestamp.fromMillis(at)});
    await db.doc(`appointment_user_locks/${studentUid}`).set({appointmentId: id});
    return {id, at};
  };

  try {
    // 1. Counselor assignment removed between pre-tx read and transaction start.
    const r1 = await seedRace();
    const origRunTx1 = db.runTransaction.bind(db);
    let intercepted1 = false;
    const m1 = mock.method(db, "runTransaction", async (fn: (tx: FirebaseFirestore.Transaction) => Promise<unknown>) => {
      if (!intercepted1) {
        intercepted1 = true;
        await db.doc(`users/${actorUid}`).update({assignedCollegeIds: [cas]});
      }
      return origRunTx1(fn);
    });
    try {
      await rejects((reviewAppointment as unknown as Callable).run({auth: {uid: actorUid}, data: confirm(r1.id, r1.at)}), "permission-denied");
    } finally {
      m1.mock.restore();
    }
    assert.equal((await appointment(r1.id)).status, "requested");
    assert.equal((await history(r1.id)).length, 0);
    assert.equal((await audits(r1.id, "APPOINTMENT_CONFIRMED")).length, 0);

    // Restore counselor to cite; now change student's college mid-flight on changeAppointmentAgreement.
    await db.doc(`users/${actorUid}`).update({assignedCollegeIds: [cite]});
    const r2 = await seedRace("confirmed");
    const target2 = await freeSlot();
    const origRunTx2 = db.runTransaction.bind(db);
    let intercepted2 = false;
    const m2 = mock.method(db, "runTransaction", async (fn: (tx: FirebaseFirestore.Transaction) => Promise<unknown>) => {
      if (!intercepted2) {
        intercepted2 = true;
        await db.doc(`users/${studentUid}`).update({collegeId: cas});
      }
      return origRunTx2(fn);
    });
    try {
      await rejects(
        (changeAppointmentAgreement as unknown as Callable).run({
          auth: {uid: actorUid},
          data: {
            appointmentId: r2.id, action: "propose", requestId: `${p}_race_std_${r2.id}`,
            scheduledAt: target2, reason: "Shift", expectedScheduledAt: r2.at, expectedScheduleRevision: 0, expectedProposalRevision: 0,
          },
        }),
        "permission-denied",
      );
    } finally {
      m2.mock.restore();
    }
    assert.equal((await appointment(r2.id)).proposalStatus, undefined);
    assert.equal((await history(r2.id)).length, 0);

    // 3. Restore student college to cite; suspend staff right before transaction starts.
    await db.doc(`users/${studentUid}`).update({collegeId: cite});
    const r3 = await seedRace();
    const origRunTx3 = db.runTransaction.bind(db);
    let intercepted3 = false;
    const m3 = mock.method(db, "runTransaction", async (fn: (tx: FirebaseFirestore.Transaction) => Promise<unknown>) => {
      if (!intercepted3) {
        intercepted3 = true;
        await db.doc(`users/${actorUid}`).update({accountStatus: "suspended"});
      }
      return origRunTx3(fn);
    });
    try {
      await rejects((reviewAppointment as unknown as Callable).run({auth: {uid: actorUid}, data: confirm(r3.id, r3.at)}), "permission-denied");
    } finally {
      m3.mock.restore();
    }
    assert.equal((await appointment(r3.id)).status, "requested");
    assert.equal((await audits(r3.id, "APPOINTMENT_CONFIRMED")).length, 0);

    // 4. Real concurrent callable race: setStaffCollegeAssignments vs reviewAppointment produces consistent atomic outcome (no duplicate notifications or partial writes).
    await db.doc(`users/${actorUid}`).update({accountStatus: "active", assignedCollegeIds: [cite]});
    const r4 = await seedRace();
    await Promise.allSettled([
      (reviewAppointment as unknown as Callable).run({auth: {uid: actorUid}, data: confirm(r4.id, r4.at)}),
      (setStaffCollegeAssignments as unknown as Callable).run({auth: {uid: uid("admin")}, data: {userId: actorUid, collegeIds: [cas]}}),
    ]);
    const r4Data = await appointment(r4.id);
    const r4Notes = (await db.collection("notifications").where("appointmentId", "==", r4.id).get()).docs;
    const r4Audits = await audits(r4.id, "APPOINTMENT_CONFIRMED");
    if (r4Data.status === "confirmed") {
      assert.equal(r4Notes.length, 1);
      assert.equal(r4Audits.length, 1);
    } else {
      assert.equal(r4Data.status, "requested");
      assert.equal(r4Notes.length, 0);
      assert.equal(r4Audits.length, 0);
    }
  } finally {
    await Promise.all([
      db.doc(`users/${actorUid}`).delete().catch(() => undefined),
      db.doc(`users/${studentUid}`).delete().catch(() => undefined),
      getAuth().deleteUser(actorUid).catch(() => undefined),
    ]);
  }
});

test("getAppointmentForApproval enforces college/exception scope, lifecycle gates, and strict field projection", {skip: !emulated}, async () => {
  const unassignedUid = uid("unassigned-lookup");
  const pendUid = uid("pending-lookup");
  const disAuthUid = uid("disabled-auth-lookup");
  const tempStudentUid = uid("student-shift-lookup");
  const tempCounselorUid = uid("reassign-lookup");
  const tempApptId = `${p}-lookup-shift`;
  await Promise.all([
    getAuth().createUser({uid: unassignedUid, email: `${unassignedUid}@example.invalid`, emailVerified: true}),
    db.doc(`users/${unassignedUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: []}),
    getAuth().createUser({uid: pendUid, email: `${pendUid}@example.invalid`, emailVerified: true}),
    db.doc(`users/${pendUid}`).set({accessRole: "counselor", staffAccountStatus: "pending", accountStatus: "active", assignedCollegeIds: [cite]}),
    getAuth().createUser({uid: disAuthUid, email: `${disAuthUid}@example.invalid`, emailVerified: true, disabled: true}),
    db.doc(`users/${disAuthUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: [cite]}),
    getAuth().createUser({uid: tempCounselorUid, email: `${tempCounselorUid}@example.invalid`, emailVerified: true}),
    db.doc(`users/${tempCounselorUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: [cite]}),
    db.doc(`users/${tempStudentUid}`).set({accessRole: "appUser", verificationStatus: "verified", collegeId: cite}),
  ]);

  try {
    const at = await freeSlot();
    await db.doc(`appointments/${tempApptId}`).set({
      userId: tempStudentUid,
      fullName: "Lookup Student",
      email: "student@example.invalid",
      contactNumber: "09170000000",
      preferredContactMethod: "email",
      concern: "Approval detail concern",
      status: "requested",
      scheduledAt: Timestamp.fromMillis(at),
      scheduledTime: "9:00 AM",
      location: "PACC",
      scheduleRevision: 1,
      proposalRevision: 0,
      createdAt: Timestamp.now(),
      // Fields that must NEVER be projected back by getAppointmentForApproval:
      assignedStaffId: "secret-staff",
      approval: {mode: "college", exceptionReason: "internal-audit-only"},
      exceptionReason: "must-not-leak",
      scopeReason: "internal-scope",
      clinicalNotesSummary: "must-not-leak-notes",
    });
    const triage = await seed("none");
    const unverifiedAppt = await seed("unverified");

    // 1. Correct-college counselor retrieves eligible pending appointment with clean minimal fields.
    const citeRes = await call(getAppointmentForApproval, "cA", {appointmentId: tempApptId});
    assert.equal(citeRes.ok, true);
    assert.equal(citeRes.available, true);
    assert.equal(citeRes.appointment.id, tempApptId);
    assert.equal(citeRes.appointment.concern, "Approval detail concern");
    assert.equal(citeRes.appointment.scheduleRevision, 1);
    assert.equal(citeRes.appointment.assignedStaffId, undefined);
    assert.equal(citeRes.appointment.approval, undefined);
    assert.equal(citeRes.appointment.exceptionReason, undefined);
    assert.equal(citeRes.appointment.scopeReason, undefined);
    assert.equal(citeRes.appointment.clinicalNotesSummary, undefined);

    // 2. Super-admin retrieves authorized exception appointment, but CANNOT dump college-scoped appointments.
    const triageRes = await call(getAppointmentForApproval, "admin", {appointmentId: triage.id});
    assert.equal(triageRes.available, true);
    assert.equal(triageRes.appointment.id, triage.id);
    assert.equal((await call(getAppointmentForApproval, "admin", {appointmentId: unverifiedAppt.id})).available, true);
    await rejects(call(getAppointmentForApproval, "admin", {appointmentId: tempApptId}), "permission-denied");

    // 3. Negative authorization checks across all disallowed callers and invalid inputs.
    for (const actor of ["cB", "sus", "unv", "ops", "otherAdmin", "student-cite", "student-cas"]) {
      await rejects(call(getAppointmentForApproval, actor, {appointmentId: tempApptId}), "permission-denied");
    }
    for (const rawUid of [unassignedUid, pendUid, disAuthUid]) {
      await rejects((getAppointmentForApproval as unknown as Callable).run({auth: {uid: rawUid}, data: {appointmentId: tempApptId}}), "permission-denied");
    }
    await rejects(call(getAppointmentForApproval, "cA", {appointmentId: triage.id}), "permission-denied");
    await rejects((getAppointmentForApproval as unknown as Callable).run({auth: null as unknown as {uid: string}, data: {appointmentId: tempApptId}}), "unauthenticated");
    await rejects(call(getAppointmentForApproval, "cA", {appointmentId: "bad/id"}), "invalid-argument");
    await rejects(call(getAppointmentForApproval, "cA", {appointmentId: ""}), "invalid-argument");

    // 4. Student college shift immediately revokes old college counselor & grants new college counselor.
    await db.doc(`users/${tempStudentUid}`).update({collegeId: cas});
    await rejects(call(getAppointmentForApproval, "cA", {appointmentId: tempApptId}), "permission-denied");
    const casRes = await call(getAppointmentForApproval, "cB", {appointmentId: tempApptId});
    assert.equal(casRes.available, true);
    await db.doc(`users/${tempStudentUid}`).update({collegeId: cite});

    // 5. Reassigning counselor colleges immediately revokes & grants access.
    assert.equal((await (getAppointmentForApproval as unknown as Callable).run({auth: {uid: tempCounselorUid}, data: {appointmentId: tempApptId}})).available, true);
    await db.doc(`users/${tempCounselorUid}`).update({assignedCollegeIds: [cas]});
    await rejects((getAppointmentForApproval as unknown as Callable).run({auth: {uid: tempCounselorUid}, data: {appointmentId: tempApptId}}), "permission-denied");

    // 6. Becoming confirmed without pending student proposal, completed, cancelled, or archived -> available=false (while unauthorized callers still denied).
    await db.doc(`appointments/${tempApptId}`).update({status: "confirmed"});
    const confirmedNoProposal = await call(getAppointmentForApproval, "cA", {appointmentId: tempApptId});
    assert.deepEqual(confirmedNoProposal, {ok: true, available: false, reason: "not_pending_approval", appointment: null});
    await rejects(call(getAppointmentForApproval, "cB", {appointmentId: tempApptId}), "permission-denied");

    await db.doc(`appointments/${tempApptId}`).update({proposalStatus: "pending", proposedBy: "student", proposalRevision: 1});
    assert.equal((await call(getAppointmentForApproval, "cA", {appointmentId: tempApptId})).available, true);

    await db.doc(`appointments/${tempApptId}`).update({status: "completed"});
    assert.deepEqual(await call(getAppointmentForApproval, "cA", {appointmentId: tempApptId}), {ok: true, available: false, reason: "not_pending_approval", appointment: null});

    await db.doc(`appointments/${tempApptId}`).update({status: "cancelled"});
    assert.deepEqual(await call(getAppointmentForApproval, "cA", {appointmentId: tempApptId}), {ok: true, available: false, reason: "not_pending_approval", appointment: null});

    await db.doc(`appointments/${tempApptId}`).update({status: "requested", archivedAt: Timestamp.now()});
    assert.deepEqual(await call(getAppointmentForApproval, "cA", {appointmentId: tempApptId}), {ok: true, available: false, reason: "not_pending_approval", appointment: null});

    const missing = await call(getAppointmentForApproval, "cA", {appointmentId: `${p}-does-not-exist`});
    assert.deepEqual(missing, {ok: true, available: false, reason: "not_found", appointment: null});
  } finally {
    await Promise.all([
      db.doc(`appointments/${tempApptId}`).delete().catch(() => undefined),
      db.doc(`users/${unassignedUid}`).delete().catch(() => undefined),
      db.doc(`users/${pendUid}`).delete().catch(() => undefined),
      db.doc(`users/${disAuthUid}`).delete().catch(() => undefined),
      db.doc(`users/${tempCounselorUid}`).delete().catch(() => undefined),
      db.doc(`users/${tempStudentUid}`).delete().catch(() => undefined),
      getAuth().deleteUser(unassignedUid).catch(() => undefined),
      getAuth().deleteUser(pendUid).catch(() => undefined),
      getAuth().deleteUser(disAuthUid).catch(() => undefined),
      getAuth().deleteUser(tempCounselorUid).catch(() => undefined),
    ]);
  }
});
