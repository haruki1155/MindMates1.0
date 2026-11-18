import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {
  acknowledgeInquiry,
  escalateInquiry,
  INQUIRY_STATUSES_COLLECTION,
  reassignInquiry,
  ensureActiveNotification,
  routeExistingInquiries,
  routeExistingInquiriesBatch,
  routeInquiry,
  setInquiryStatus,
  syncInquiryStatusProjection,
} from "./inquiry_routing_service";

// Auth + Firestore emulators. Real callables and the real routing handler.
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const p = `inq-${Date.now()}`;
const uid = (name: string) => `${p}-${name}`;
const college = (name: string) => `${p}-${name}`;
const db = getFirestore();

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<any>};
const call = (fn: unknown, actor: string, data: Record<string, unknown>) =>
  (fn as Callable).run({auth: {uid: uid(actor)}, data});

const staff: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  c1: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Counselor One", assignedCollegeIds: [college("cite")]}},
  s1: {verified: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", name: "Staff One", assignedCollegeIds: [college("cite")]}},
  c2: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Counselor Two", assignedCollegeIds: [college("cas")]}},
  sus: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "disabled", accountStatus: "suspended", name: "Suspended", assignedCollegeIds: [college("cite")]}},
  unv: {verified: false, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Unverified", assignedCollegeIds: [college("cite")]}},
  otherAdmin: {verified: true, profile: {accessRole: "admin", accountStatus: "active"}},
};
const students: Record<string, Record<string, unknown>> = {
  cite: {accessRole: "appUser", populationRole: "student", verificationStatus: "verified", collegeId: college("cite")},
  unverified: {accessRole: "appUser", populationRole: "student", verificationStatus: "needsReview", collegeId: college("cite")},
  none: {accessRole: "appUser", populationRole: "student", verificationStatus: "verified"},
  ghost: {accessRole: "appUser", populationRole: "student", verificationStatus: "verified", collegeId: college("ghost")},
  empty: {accessRole: "appUser", populationRole: "student", verificationStatus: "verified", collegeId: college("cba")},
};

let counter = 0;
async function newInquiry(student: string, extra: Record<string, unknown> = {}): Promise<string> {
  const id = `${p}-inquiry-${++counter}`;
  await db.doc(`inquiries/${id}`).set({
    userId: uid(`student-${student}`), subject: "Sensitive subject text", message: "Sensitive message text",
    category: "Service Form", email: "s@example.invalid", name: "Student", role: "User",
    formType: "client_feedback", formData: {q1: "private answer"}, status: "pending", createdAt: new Date(), ...extra,
  });
  return id;
}
async function notificationsFor(inquiryId: string): Promise<FirebaseFirestore.DocumentData[]> {
  return (await db.collection("notifications").where("inquiryId", "==", inquiryId).get()).docs.map((d) => ({id: d.id, ...d.data()}));
}
async function audit(inquiryId: string, action: string): Promise<FirebaseFirestore.DocumentData[]> {
  return (await db.collection("admin_audit_logs").where("targetId", "==", inquiryId).where("action", "==", action).get()).docs.map((d) => d.data());
}
async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => e instanceof HttpsError && e.code === code);
}

let previousSuperAdmin: string | undefined;
before(async () => {
  if (!emulated) return;
  previousSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = uid("admin");
  for (const [name, account] of Object.entries(staff)) {
    await getAuth().createUser({uid: uid(name), email: `${uid(name)}@example.invalid`, emailVerified: account.verified});
    await db.doc(`users/${uid(name)}`).set(account.profile);
  }
  for (const [name, profile] of Object.entries(students)) {
    await getAuth().createUser({uid: uid(`student-${name}`), email: `${uid(`student-${name}`)}@example.invalid`, emailVerified: true});
    await db.doc(`users/${uid(`student-${name}`)}`).set(profile);
  }
  for (const name of ["cite", "cas", "cba"]) await db.doc(`colleges/${college(name)}`).set({name: name.toUpperCase(), code: name.toUpperCase(), active: true});
});

after(async () => {
  if (!emulated) return;
  if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID; else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  const all = [...Object.keys(staff), ...Object.keys(students).map((s) => `student-${s}`)];
  await Promise.all(all.map((n) => getAuth().deleteUser(uid(n)).catch(() => undefined)));
});

test("routes to eligible counselors only, ignores legacy portalStaff college assignments, and projects sanitized status", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  const result = await routeInquiry(id);
  assert.deepEqual(result.assigneeIds, [uid("c1")]);
  const inquiry = (await db.doc(`inquiries/${id}`).get()).data()!;
  assert.equal(inquiry.routingStatus, "routed");
  assert.equal(inquiry.routingReason, null);
  assert.equal(inquiry.collegeId, college("cite"));
  assert.equal(inquiry.routingMode, "automatic");
  assert.equal(inquiry.routingRevision, 1);
  assert.equal(inquiry.ownerId, null);
  assert.deepEqual(inquiry.assigneeLabels, {[uid("c1")]: "Counselor One"});
  assert.deepEqual(inquiry.monitoringStaffIds, []);

  // Sanitized projection mirrors operational state without any student PII or body.
  const projection = (await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).get()).data()!;
  assert.equal(projection.inquiryId, id);
  assert.equal(projection.operationalLabel, "Client Feedback Form");
  assert.deepEqual(projection.assigneeIds, [uid("c1")]);
  assert.deepEqual(projection.monitoringStaffIds, []);
  const json = JSON.stringify(projection);
  for (const forbidden of ["Sensitive subject text", "Sensitive message text", "s@example.invalid", "private answer", uid("student-cite")]) {
    assert.ok(!json.includes(forbidden), `projection leaked: ${forbidden}`);
  }

  const notes = await notificationsFor(id);
  assert.deepEqual(notes.map((n) => n.userId), [uid("c1")]);
  for (const n of notes) {
    assert.equal(n.audience, "portal");
    assert.ok(!JSON.stringify(n).includes("Sensitive"), "notification must not carry inquiry content");
  }
  const routed = await audit(id, "INQUIRY_ROUTED");
  assert.equal(routed.length, 1);
  assert.deepEqual(routed[0].metadata.assigneeIds, [uid("c1")]);
  assert.equal(routed[0].category, "INQUIRIES");
});

test("routing is idempotent and a retry repairs a missing notification without duplicating anything", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  await db.doc(`notifications/portal_inquiry_${id}_${uid("c1")}`).delete();
  await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).delete();
  const again = await routeInquiry(id);
  assert.equal(again.alreadyRouted, true);
  assert.equal((await notificationsFor(id)).length, 1);
  assert.ok((await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).get()).exists, "retry repairs missing status projection");
  await routeInquiry(id);
  assert.equal((await notificationsFor(id)).length, 1);
  assert.equal((await audit(id, "INQUIRY_ROUTED")).length, 1);
  assert.equal((await db.doc(`inquiries/${id}`).get()).data()!.routingRevision, 1);
});

test("unverified, missing, unknown and unstaffed colleges go to super-admin triage only", {skip: !emulated}, async () => {
  const cases: Array<[string, string, string]> = [
    ["unverified", "unverified_profile", ""],
    ["none", "missing_college", ""],
    ["ghost", "unknown_college", ""],
    ["empty", "no_eligible_staff", college("cba")],
  ];
  for (const [student, reason, collegeId] of cases) {
    const id = await newInquiry(student);
    await routeInquiry(id);
    const inquiry = (await db.doc(`inquiries/${id}`).get()).data()!;
    assert.deepEqual([inquiry.routingStatus, inquiry.routingReason, inquiry.collegeId, inquiry.assigneeIds], ["needs_triage", reason, collegeId, []], student);
    const notes = await notificationsFor(id);
    assert.deepEqual(notes.map((n) => [n.id, n.userId]), [[`portal_inquiry_triage_${id}`, uid("admin")]], student);
  }
  // The student's home college is never changed by routing.
  assert.equal((await db.doc(`users/${uid("student-cite")}`).get()).data()!.collegeId, college("cite"));
});

test("only clinical counselors/super-admin or explicit monitoring staff acknowledge; monitors never claim counselor ownerId", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  // Before explicit monitoring assignment, s1 cannot acknowledge or act.
  await rejects(call(acknowledgeInquiry, "s1", {inquiryId: id}), "permission-denied");
  await call(reassignInquiry, "admin", {
    inquiryId: id,
    assigneeIds: [uid("c1")],
    monitoringStaffIds: [uid("s1")],
    expectedRevision: 1,
    reason: "Assign operational monitor",
  });
  for (const actor of ["c2", "otherAdmin", "student-cite", "sus", "unv"]) {
    await rejects(call(acknowledgeInquiry, actor, {inquiryId: id}), "permission-denied");
  }
  await call(acknowledgeInquiry, "s1", {inquiryId: id});
  const inquiry = (await db.doc(`inquiries/${id}`).get()).data()!;
  assert.deepEqual([inquiry.status, inquiry.ownerId, inquiry.acknowledgedBy], ["in_progress", null, uid("s1")]);
  const projection = (await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).get()).data()!;
  assert.equal(projection.status, "in_progress");
  assert.ok(projection.acknowledgedAt != null);
  assert.equal(projection.ownerId, null);
  assert.equal((await audit(id, "INQUIRY_ACKNOWLEDGED")).length, 1);
  const receiptSnap = await db.collection("notifications").where("inquiryId", "==", id).where("userId", "==", uid("student-cite")).get();
  assert.equal(receiptSnap.size, 1);
  const receiptNote = receiptSnap.docs[0].data();
  assert.equal(receiptNote.body, "PACC received your inquiry. Open MindMate to view its status.");
  assert.equal(receiptNote.inquiryId, id);
  assert.ok(!JSON.stringify(receiptNote).includes("Sensitive"), "acknowledgment notification must not echo user subject");
  await rejects(call(acknowledgeInquiry, "c1", {inquiryId: id}), "failed-precondition");
  const triage = await newInquiry("none");
  await routeInquiry(triage);
  await call(acknowledgeInquiry, "admin", {inquiryId: triage});
  assert.equal((await db.doc(`inquiries/${triage}`).get()).data()!.ownerId, uid("admin"));
});

test("resolved inquiries cannot be reopened by acknowledgement, including under concurrent updates", {skip: !emulated}, async () => {
  const resolvedId = await newInquiry("cite");
  await routeInquiry(resolvedId);
  await call(reassignInquiry, "admin", {inquiryId: resolvedId, assigneeIds: [uid("c1")], monitoringStaffIds: [uid("s1")], expectedRevision: 1, reason: "Add monitor"});
  await call(setInquiryStatus, "c1", {inquiryId: resolvedId, status: "resolved"});
  await rejects(call(acknowledgeInquiry, "s1", {inquiryId: resolvedId}), "failed-precondition");
  const resolvedDoc = (await db.doc(`inquiries/${resolvedId}`).get()).data()!;
  assert.equal(resolvedDoc.status, "resolved");
  assert.equal(resolvedDoc.acknowledgedAt ?? null, null);
  assert.equal((await audit(resolvedId, "INQUIRY_ACKNOWLEDGED")).length, 0);
  const resolvedStudentNotes = await db.collection("notifications")
    .where("inquiryId", "==", resolvedId)
    .where("userId", "==", uid("student-cite"))
    .get();
  assert.equal(resolvedStudentNotes.size, 0);

  // Concurrent resolve vs acknowledge race never reopens status to in_progress.
  const raceId = await newInquiry("cite");
  await routeInquiry(raceId);
  await call(reassignInquiry, "admin", {inquiryId: raceId, assigneeIds: [uid("c1")], monitoringStaffIds: [uid("s1")], expectedRevision: 1, reason: "Add monitor"});
  const outcomes = await Promise.allSettled([
    call(setInquiryStatus, "c1", {inquiryId: raceId, status: "resolved"}),
    call(acknowledgeInquiry, "s1", {inquiryId: raceId}),
  ]);
  assert.equal(outcomes[0].status, "fulfilled");
  const raceDoc = (await db.doc(`inquiries/${raceId}`).get()).data()!;
  assert.equal(raceDoc.status, "resolved");
  if (outcomes[1].status === "rejected") {
    assert.ok(outcomes[1].reason instanceof HttpsError && outcomes[1].reason.code === "failed-precondition");
    assert.equal((await audit(raceId, "INQUIRY_ACKNOWLEDGED")).length, 0);
    const raceNotes = await db.collection("notifications")
      .where("inquiryId", "==", raceId)
      .where("userId", "==", uid("student-cite"))
      .get();
    assert.equal(raceNotes.size, 0);
  }
});

test("status changes are server-side, counselor/super-admin scoped and audited; portalStaff cannot alter clinical resolution", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  await call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c1")], monitoringStaffIds: [uid("s1")], expectedRevision: 1, reason: "Add monitor"});
  await rejects(call(setInquiryStatus, "s1", {inquiryId: id, status: "resolved"}), "permission-denied");
  await rejects(call(setInquiryStatus, "c2", {inquiryId: id, status: "resolved"}), "permission-denied");
  await rejects(call(setInquiryStatus, "student-cite", {inquiryId: id, status: "resolved"}), "permission-denied");
  await rejects(call(setInquiryStatus, "c1", {inquiryId: id, status: "deleted"}), "invalid-argument");
  await call(setInquiryStatus, "c1", {inquiryId: id, status: "in_progress"});
  await call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved"});
  const inquiry = (await db.doc(`inquiries/${id}`).get()).data()!;
  assert.deepEqual([inquiry.status, inquiry.resolvedBy], ["resolved", uid("c1")]);
  const projection = (await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).get()).data()!;
  assert.equal(projection.status, "resolved");
  assert.ok(projection.resolvedAt != null);
  const changed = await audit(id, "INQUIRY_STATUS_CHANGED");
  const resolved = await audit(id, "INQUIRY_RESOLVED");
  assert.equal(changed.length, 1);
  assert.equal(resolved.length, 1);
  assert.deepEqual([resolved[0].metadata.before, resolved[0].metadata.after], ["in_progress", "resolved"]);
  await call(setInquiryStatus, "admin", {inquiryId: id, status: "resolved"});
  assert.equal((await audit(id, "INQUIRY_RESOLVED")).length, 1, "an unchanged status writes nothing");
});

test("assigned counselors or monitoring staff escalate once to the super-administrator without leaking reason into projection", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  await call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c1")], monitoringStaffIds: [uid("s1")], expectedRevision: 1, reason: "Add monitor"});
  await rejects(call(escalateInquiry, "c2", {inquiryId: id, reason: "Needs supervisor review"}), "permission-denied");
  await rejects(call(escalateInquiry, "c1", {inquiryId: id, reason: "no"}), "invalid-argument");
  await call(escalateInquiry, "c1", {inquiryId: id, reason: "Private clinical escalation reason"});
  const inquiry = (await db.doc(`inquiries/${id}`).get()).data()!;
  assert.deepEqual([inquiry.escalation.status, inquiry.escalation.requestedBy, inquiry.escalation.reason], ["requested", uid("c1"), "Private clinical escalation reason"]);
  const projection = (await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).get()).data()!;
  assert.equal(projection.escalationStatus, "requested");
  assert.ok(!JSON.stringify(projection).includes("Private clinical escalation reason"));
  assert.equal(projection.escalationReason, undefined);
  const note = await db.doc(`notifications/portal_inquiry_escalation_${id}_2`).get();
  assert.equal(note.data()?.userId, uid("admin"));
  assert.ok(!JSON.stringify(note.data()).includes("Sensitive"));
  assert.equal((await audit(id, "INQUIRY_ESCALATED")).length, 1);
  await rejects(call(escalateInquiry, "s1", {inquiryId: id, reason: "Again please"}), "failed-precondition");
});

test("the super-administrator reassigns with revision checks; removed assignees and monitors lose projection access immediately", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  await call(reassignInquiry, "admin", {
    inquiryId: id,
    assigneeIds: [uid("c1")],
    monitoringStaffIds: [uid("s1")],
    expectedRevision: 1,
    reason: "Add operational monitor",
  });
  await call(escalateInquiry, "c1", {inquiryId: id, reason: "Needs another college"});
  // escalation incremented routingRevision from 2 to 3.
  await rejects(call(reassignInquiry, "c1", {inquiryId: id, assigneeIds: [uid("c2")], expectedRevision: 3, reason: "Coverage change"}), "permission-denied");
  await rejects(call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("s1")], expectedRevision: 3, reason: "Invalid clinical role"}), "failed-precondition");
  await rejects(call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [], monitoringStaffIds: [uid("s1")], expectedRevision: 3, reason: "Monitors only must fail"}), "invalid-argument");
  await rejects(call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c1")], monitoringStaffIds: [uid("c2")], expectedRevision: 3, reason: "Invalid monitor role"}), "failed-precondition");
  await rejects(call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("sus")], expectedRevision: 3, reason: "Coverage change"}), "failed-precondition");
  await rejects(call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("unv")], expectedRevision: 3, reason: "Coverage change"}), "failed-precondition");
  await rejects(call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c2")], expectedRevision: 1, reason: "Coverage change"}), "failed-precondition");
  const result = await call(reassignInquiry, "admin", {
    inquiryId: id,
    assigneeIds: [uid("c2")],
    monitoringStaffIds: [],
    expectedRevision: 3,
    reason: "Coverage change",
  });
  assert.equal(result.revision, 4, "escalation advanced the revision before reassignment");
  const inquiry = (await db.doc(`inquiries/${id}`).get()).data()!;
  assert.deepEqual([inquiry.assigneeIds, inquiry.monitoringStaffIds, inquiry.routingMode, inquiry.routingRevision, inquiry.escalation.status, inquiry.escalation.handledBy],
    [[uid("c2")], [], "manual", 4, "handled", uid("admin")]);
  const projection = (await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).get()).data()!;
  assert.deepEqual(projection.assigneeIds, [uid("c2")]);
  assert.deepEqual(projection.monitoringStaffIds, []);
  assert.equal(projection.routingRevision, 4);
  assert.equal(projection.escalationStatus, "handled");
  const reassignments = await audit(id, "INQUIRY_REASSIGNED");
  const row = reassignments.find((r) => r.metadata.reason === "Coverage change")!;
  assert.deepEqual([row.metadata.added, row.metadata.removed, row.metadata.outOfCollege, row.metadata.reason],
    [[uid("c2")], [uid("c1"), uid("s1")].sort(), [uid("c2")], "Coverage change"]);
  assert.ok((await db.doc(`notifications/portal_inquiry_${id}_${uid("c2")}`).get()).exists);
  assert.ok((await db.doc(`notifications/portal_inquiry_${id}_${uid("c1")}`).get()).data()!.archivedAt);
  assert.ok((await db.doc(`notifications/portal_inquiry_${id}_${uid("s1")}`).get()).data()!.archivedAt);
  // Previous clinical assignee and monitoring staff can no longer act on it.
  await rejects(call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved"}), "permission-denied");
  await rejects(call(acknowledgeInquiry, "s1", {inquiryId: id}), "permission-denied");

  // Delayed sync with stale state cannot regress the newer revision.
  await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).update({routingRevision: 5, monitoringStaffIds: ["newer-monitor"]});
  assert.equal(await syncInquiryStatusProjection(id), false);
  const preserved = (await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).get()).data()!;
  assert.equal(preserved.routingRevision, 5);
  assert.deepEqual(preserved.monitoringStaffIds, ["newer-monitor"]);
});

test("concurrent reassignments with the same revision: exactly one wins", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  const attempts = await Promise.allSettled([
    call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c2")], expectedRevision: 1, reason: "Race one"}),
    call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c1")], expectedRevision: 1, reason: "Race two"}),
  ]);
  assert.equal(attempts.filter((a) => a.status === "fulfilled").length, 1);
  const failure = attempts.find((a) => a.status === "rejected") as PromiseRejectedResult;
  assert.ok(failure.reason instanceof HttpsError && failure.reason.code === "failed-precondition");
  assert.equal((await audit(id, "INQUIRY_REASSIGNED")).length, 1);
});

test("an assignee or monitoring staff suspended after routing can no longer act", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  await call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c1")], monitoringStaffIds: [uid("s1")], expectedRevision: 1, reason: "Add monitor"});
  await db.doc(`users/${uid("s1")}`).update({accountStatus: "suspended"});
  try {
    await rejects(call(acknowledgeInquiry, "s1", {inquiryId: id}), "permission-denied");
    await rejects(call(escalateInquiry, "s1", {inquiryId: id, reason: "Blocked monitor"}), "permission-denied");
  } finally {
    await db.doc(`users/${uid("s1")}`).update({accountStatus: "active"});
  }
});

test("legacy unrouted and pre-projection routed inquiries are backfilled cleanly; resolved ones are not re-notified", {skip: !emulated}, async () => {
  const open = await newInquiry("cite");
  const resolved = await newInquiry("cite", {status: "resolved"});
  const legacyRoutedWithoutProjection = await newInquiry("cite", {routingStatus: "routed", collegeId: college("cite"), assigneeIds: [uid("c1")], routingRevision: 1});
  await rejects(call(routeExistingInquiries, "c1", {limit: 50}), "permission-denied");
  await call(routeExistingInquiries, "admin", {limit: 100});
  for (const id of [open, resolved, legacyRoutedWithoutProjection]) {
    assert.equal((await db.doc(`inquiries/${id}`).get()).data()!.routingStatus, "routed");
    assert.ok((await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).get()).exists, id);
  }
  assert.equal((await notificationsFor(open)).length, 1);
  assert.equal((await notificationsFor(resolved)).length, 0);
  assert.equal((await audit(open, "INQUIRY_ROUTED")).length, 1);

  // Deleting the projection after initial trigger/backfill lets us verify missing-projection repair deterministically.
  await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${legacyRoutedWithoutProjection}`).delete();
  const repaired = await call(routeExistingInquiries, "admin", {limit: 100});
  assert.ok(repaired.projectionsSynced >= 1);
  assert.ok((await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${legacyRoutedWithoutProjection}`).get()).exists);

  const again = await call(routeExistingInquiries, "admin", {limit: 100});
  assert.equal((await audit(open, "INQUIRY_ROUTED")).length, 1);
  assert.equal(again.routed, 0);
  assert.equal(again.projectionsSynced, 0);
});

test("reassigning A -> B -> A reactivates A's original notification without duplicating it", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  const noteId = `portal_inquiry_${id}_${uid("c1")}`;
  await db.doc(`notifications/${noteId}`).update({readAt: new Date()});
  await call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c2")], expectedRevision: 1, reason: "Move to CAS"});
  assert.ok((await db.doc(`notifications/${noteId}`).get()).data()!.archivedAt, "removed assignee's notification is archived");

  await call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c1")], expectedRevision: 2, reason: "Back to CITE"});
  const note = (await db.doc(`notifications/${noteId}`).get()).data()!;
  assert.equal(note.archivedAt, null, "re-added assignee's notification is active again");
  assert.equal(note.resolvedAt, null);
  assert.equal(note.readAt, null, "and unread, so the badge shows it");
  assert.equal(note.expiresAt, null);
  assert.equal(note.userId, uid("c1"));
  assert.ok(!JSON.stringify(note).includes("Sensitive"));
  const forC1 = (await notificationsFor(id)).filter((n) => n.userId === uid("c1"));
  assert.equal(forC1.length, 1, "one notification document per assignee, never a duplicate");
  // B lost the inquiry, so B's notification is archived.
  assert.ok((await db.doc(`notifications/portal_inquiry_${id}_${uid("c2")}`).get()).data()!.archivedAt);
});

test("ensureActiveNotification is idempotent across retries", {skip: !emulated}, async () => {
  const id = `${p}-notify-retry`;
  const payload = {userId: uid("c1"), type: "inquiry", audience: "portal", title: "T", body: "B", inquiryId: id};
  await ensureActiveNotification(id, payload);
  await db.doc(`notifications/${id}`).update({archivedAt: new Date(), resolvedAt: new Date(), readAt: new Date()});
  await ensureActiveNotification(id, payload);
  const reactivated = (await db.doc(`notifications/${id}`).get()).data()!;
  assert.equal(reactivated.archivedAt, null);
  await db.doc(`notifications/${id}`).update({readAt: new Date()});
  await ensureActiveNotification(id, payload);
  assert.ok((await db.doc(`notifications/${id}`).get()).data()!.readAt, "an active notification is left untouched on retry");
  assert.equal((await db.collection("notifications").where("inquiryId", "==", id).get()).size, 1);
});

async function seedInquiries(prefix: string, count: number, routedBelow: number): Promise<string[]> {
  const ids = Array.from({length: count}, (_, i) => `${prefix}-${String(i).padStart(4, "0")}`);
  for (let start = 0; start < ids.length; start += 400) {
    const batch = db.batch();
    for (const [offset, id] of ids.slice(start, start + 400).entries()) {
      const routed = start + offset < routedBelow;
      batch.set(db.doc(`inquiries/${id}`), {
        userId: uid("student-cite"), subject: "S", message: "M", category: "Service Form", email: "s@x",
        status: "resolved", createdAt: new Date(),
        ...(routed ? {routingStatus: "routed", assigneeIds: [], routingRevision: 1} : {}),
      });
    }
    await batch.commit();
  }
  return ids;
}

test("backfill pages past already-routed inquiries and resumes from a cursor", {skip: !emulated}, async () => {
  const ids = await seedInquiries(`${p}-page`, 6, 4);
  const admin = {uid: uid("admin"), name: "Super Admin", role: "admin"};
  // One page of two documents per call: the first pages hold only routed
  // inquiries, so the old in-memory filter would report nothing to do.
  let cursor: string | null = `${p}-page`;
  let routed = 0;
  let calls = 0;
  for (;;) {
    const result: {routed: number; nextCursor: string | null; done: boolean; scanned: number} =
      await routeExistingInquiriesBatch(admin, {limit: 100, cursor, pageSize: 2, maxPages: 1});
    calls += 1;
    routed += result.routed;
    assert.ok(result.scanned <= 2, "work per call is bounded");
    if (result.done) {
      assert.equal(result.nextCursor, null);
      break;
    }
    assert.ok(result.nextCursor, "an unfinished pass returns a cursor");
    cursor = result.nextCursor;
    assert.ok(calls < 50, "pagination must terminate");
  }
  assert.ok(calls >= 3, "routing reached past the first, fully routed page");
  for (const id of ids.slice(4)) {
    assert.equal((await db.doc(`inquiries/${id}`).get()).data()!.routingStatus, "routed");
    assert.ok((await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).get()).exists);
  }
  assert.ok(routed >= 0);
});

test("the callable routes unrouted inquiries that sit behind more than 1,000 routed ones", {skip: !emulated}, async () => {
  const ids = await seedInquiries(`${p}-bulk`, 1005, 1000);
  let response = await call(routeExistingInquiries, "admin", {limit: 100});
  let guard = 0;
  while (!response.done && guard++ < 20) {
    response = await call(routeExistingInquiries, "admin", {limit: 100, cursor: response.nextCursor});
  }
  assert.equal(response.done, true);
  for (const id of ids.slice(1000)) {
    assert.equal((await db.doc(`inquiries/${id}`).get()).data()!.routingStatus, "routed", id);
  }
  await rejects(call(routeExistingInquiries, "admin", {limit: 100, cursor: "bad/cursor"}), "invalid-argument");
});

test("backfill bounds already-routed missing-projection sync work per invocation, preserves revisions, and finishes cleanly", {skip: !emulated}, async () => {
  // Explicitly confirm triage inquiry cannot become monitor-only routed while super-admin still resolves it.
  const triageId = await newInquiry("empty");
  await routeInquiry(triageId);
  await rejects(
    call(reassignInquiry, "admin", {inquiryId: triageId, assigneeIds: [], monitoringStaffIds: [uid("s1")], expectedRevision: 1, reason: "Monitor only triage"}),
    "invalid-argument",
  );
  assert.equal((await db.doc(`inquiries/${triageId}`).get()).data()!.routingStatus, "needs_triage");
  await call(setInquiryStatus, "admin", {inquiryId: triageId, status: "resolved"});

  const legacyPrefix = `${p}-legacy-proj`;
  const ids = await seedInquiries(legacyPrefix, 155, 150);
  // Seed revision 4 on one inquiry whose projection is missing to test live revision preservation.
  await db.doc(`inquiries/${ids[45]}`).update({routingRevision: 4, assigneeIds: [uid("c1")]});
  const admin = {uid: uid("admin"), name: "Super Admin", role: "admin"};

  let cursor: string | null = legacyPrefix;
  let calls = 0;
  let totalSynced = 0;
  let totalRouted = 0;
  for (;;) {
    const result = await routeExistingInquiriesBatch(admin, {limit: 40, cursor, pageSize: 60, maxPages: 2});
    calls += 1;
    assert.ok(
      result.routed + result.projectionsSynced <= 40,
      `per-invocation mutation work exceeded limit 40: routed=${result.routed}, projectionsSynced=${result.projectionsSynced}`,
    );
    totalSynced += result.projectionsSynced;
    totalRouted += result.routed;
    if (result.done) {
      assert.equal(result.nextCursor, null);
      break;
    }
    assert.ok(result.nextCursor);
    cursor = result.nextCursor;
    assert.ok(calls < 20, "bounded backfill must terminate");
  }
  assert.ok(calls >= 2);
  assert.ok(totalSynced + totalRouted >= 0);

  for (const id of ids) {
    assert.equal((await db.doc(`inquiries/${id}`).get()).data()!.routingStatus, "routed");
    assert.ok((await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).get()).exists, `projection synced for ${id}`);
  }
  assert.equal((await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${ids[45]}`).get()).data()!.routingRevision, 4);
  for (const id of ids.slice(0, 150)) {
    assert.equal((await notificationsFor(id)).length, 0, `no duplicate notifications for already-routed ${id}`);
  }

  // Subsequent pass does zero duplicate work.
  const rerun = await routeExistingInquiriesBatch(admin, {limit: 40, cursor: legacyPrefix, pageSize: 60, maxPages: 2});
  assert.equal(rerun.routed, 0);
  assert.equal(rerun.projectionsSynced, 0);
});

test("routeExistingInquiriesBatch enforces exact per-call work bounds, cursor continuity, and mixed routed/projection totals deterministically", async () => {
  // Synthetic trigger-free store: 8 unrouted (3 triage, 5 routed), 65 routed missing projection, 10 already projected.
  const records = Array.from({length: 83}, (_, i) => {
    const id = `det-${String(i).padStart(4, "0")}`;
    if (i < 65) return {id, routingStatus: "routed" as string | null, hasProjection: false, triage: false};
    if (i < 73) return {id, routingStatus: null, hasProjection: false, triage: i >= 70};
    return {id, routingStatus: "routed" as string | null, hasProjection: true, triage: false};
  });
  const byId = new Map(records.map((r) => [r.id, r]));
  const admin = {uid: "admin-det", name: "Super Admin", role: "admin"};

  let cursor: string | null = null;
  let calls = 0;
  let totalRouted = 0;
  let totalTriage = 0;
  let totalSynced = 0;
  for (;;) {
    const res = await routeExistingInquiriesBatch(
      admin,
      {limit: 20, cursor, pageSize: 25, maxPages: 1},
      {
        readPage: async (afterCursor, pageSize) => {
          const start = afterCursor ? records.findIndex((r) => r.id > afterCursor) : 0;
          if (start < 0) return [];
          return records.slice(start, start + pageSize).map((r) => ({
            id: r.id,
            routingStatus: r.routingStatus,
            hasProjection: r.hasProjection,
          }));
        },
        routeDoc: async (inquiryId) => {
          const rec = byId.get(inquiryId)!;
          if (rec.routingStatus != null) {
            return {routingStatus: String(rec.routingStatus), assigneeIds: [], alreadyRouted: true};
          }
          rec.routingStatus = rec.triage ? "needs_triage" : "routed";
          rec.hasProjection = true;
          return {routingStatus: rec.routingStatus, assigneeIds: rec.triage ? [] : ["c1"], alreadyRouted: false};
        },
        syncProjection: async (inquiryId) => {
          const rec = byId.get(inquiryId)!;
          if (rec.hasProjection) return false;
          rec.hasProjection = true;
          return true;
        },
      },
    );
    calls += 1;
    assert.ok(res.routed + res.projectionsSynced <= 20);
    totalRouted += res.routed;
    totalTriage += res.needsTriage;
    totalSynced += res.projectionsSynced;
    if (res.done) {
      assert.equal(res.nextCursor, null);
      break;
    }
    assert.ok(res.nextCursor);
    cursor = res.nextCursor;
    assert.ok(calls < 20);
  }
  assert.deepEqual([totalRouted, totalTriage, totalSynced], [8, 3, 65]);
  assert.ok(calls >= 4);
  for (const r of records) {
    assert.ok(r.routingStatus != null);
    assert.equal(r.hasProjection, true);
  }
});
