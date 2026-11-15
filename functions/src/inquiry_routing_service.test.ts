import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {
  acknowledgeInquiry,
  escalateInquiry,
  reassignInquiry,
  routeExistingInquiries,
  routeInquiry,
  setInquiryStatus,
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

test("routes to every eligible assignee of the student's verified college and notifies only them", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  const result = await routeInquiry(id);
  assert.deepEqual(result.assigneeIds, [uid("c1"), uid("s1")].sort());
  const inquiry = (await db.doc(`inquiries/${id}`).get()).data()!;
  assert.equal(inquiry.routingStatus, "routed");
  assert.equal(inquiry.routingReason, null);
  assert.equal(inquiry.collegeId, college("cite"));
  assert.equal(inquiry.routingMode, "automatic");
  assert.equal(inquiry.routingRevision, 1);
  assert.equal(inquiry.ownerId, null);
  assert.deepEqual(inquiry.assigneeLabels, {[uid("c1")]: "Counselor One", [uid("s1")]: "Staff One"});
  const notes = await notificationsFor(id);
  assert.deepEqual(notes.map((n) => n.userId).sort(), [uid("c1"), uid("s1")].sort());
  for (const n of notes) {
    assert.equal(n.audience, "portal");
    assert.ok(!JSON.stringify(n).includes("Sensitive"), "notification must not carry inquiry content");
  }
  const routed = await audit(id, "INQUIRY_ROUTED");
  assert.equal(routed.length, 1);
  assert.deepEqual(routed[0].metadata.assigneeIds, [uid("c1"), uid("s1")].sort());
  assert.equal(routed[0].category, "INQUIRIES");
});

test("routing is idempotent and a retry repairs a missing notification without duplicating anything", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  await db.doc(`notifications/portal_inquiry_${id}_${uid("c1")}`).delete();
  const again = await routeInquiry(id);
  assert.equal(again.alreadyRouted, true);
  assert.equal((await notificationsFor(id)).length, 2);
  await routeInquiry(id);
  assert.equal((await notificationsFor(id)).length, 2);
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

test("only assignees or the super-administrator acknowledge; acknowledgement claims ownership", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  for (const actor of ["c2", "otherAdmin", "student-cite", "sus", "unv"]) {
    await rejects(call(acknowledgeInquiry, actor, {inquiryId: id}), "permission-denied");
  }
  await call(acknowledgeInquiry, "s1", {inquiryId: id});
  const inquiry = (await db.doc(`inquiries/${id}`).get()).data()!;
  assert.deepEqual([inquiry.status, inquiry.ownerId, inquiry.acknowledgedBy], ["in_progress", uid("s1"), uid("s1")]);
  assert.equal((await audit(id, "INQUIRY_ACKNOWLEDGED")).length, 1);
  const receipt = (await db.collection("notifications").where("inquiryId", "==", id).where("userId", "==", uid("student-cite")).get()).size;
  assert.equal(receipt, 1);
  await rejects(call(acknowledgeInquiry, "c1", {inquiryId: id}), "failed-precondition");
  const triage = await newInquiry("none");
  await routeInquiry(triage);
  await call(acknowledgeInquiry, "admin", {inquiryId: triage});
  assert.equal((await db.doc(`inquiries/${triage}`).get()).data()!.ownerId, uid("admin"));
});

test("status changes are server-side, assignee-scoped and audited", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  await rejects(call(setInquiryStatus, "c2", {inquiryId: id, status: "resolved"}), "permission-denied");
  await rejects(call(setInquiryStatus, "student-cite", {inquiryId: id, status: "resolved"}), "permission-denied");
  await rejects(call(setInquiryStatus, "c1", {inquiryId: id, status: "deleted"}), "invalid-argument");
  await call(setInquiryStatus, "c1", {inquiryId: id, status: "in_progress"});
  await call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved"});
  const inquiry = (await db.doc(`inquiries/${id}`).get()).data()!;
  assert.deepEqual([inquiry.status, inquiry.resolvedBy], ["resolved", uid("c1")]);
  const changed = await audit(id, "INQUIRY_STATUS_CHANGED");
  const resolved = await audit(id, "INQUIRY_RESOLVED");
  assert.equal(changed.length, 1);
  assert.equal(resolved.length, 1);
  assert.deepEqual([resolved[0].metadata.before, resolved[0].metadata.after], ["in_progress", "resolved"]);
  await call(setInquiryStatus, "admin", {inquiryId: id, status: "resolved"});
  assert.equal((await audit(id, "INQUIRY_RESOLVED")).length, 1, "an unchanged status writes nothing");
});

test("an assignee escalates once to the super-administrator; others cannot", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  await rejects(call(escalateInquiry, "c2", {inquiryId: id, reason: "Needs supervisor review"}), "permission-denied");
  await rejects(call(escalateInquiry, "c1", {inquiryId: id, reason: "no"}), "invalid-argument");
  await call(escalateInquiry, "c1", {inquiryId: id, reason: "Needs supervisor review"});
  const inquiry = (await db.doc(`inquiries/${id}`).get()).data()!;
  assert.deepEqual([inquiry.escalation.status, inquiry.escalation.requestedBy, inquiry.escalation.reason], ["requested", uid("c1"), "Needs supervisor review"]);
  const note = await db.doc(`notifications/portal_inquiry_escalation_${id}_1`).get();
  assert.equal(note.data()?.userId, uid("admin"));
  assert.ok(!JSON.stringify(note.data()).includes("Sensitive"));
  assert.equal((await audit(id, "INQUIRY_ESCALATED")).length, 1);
  await rejects(call(escalateInquiry, "s1", {inquiryId: id, reason: "Again please"}), "failed-precondition");
});

test("the super-administrator reassigns with revision checks; removed assignees lose their notification", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  await call(escalateInquiry, "c1", {inquiryId: id, reason: "Needs another college"});
  await rejects(call(reassignInquiry, "c1", {inquiryId: id, assigneeIds: [uid("c2")], expectedRevision: 1, reason: "Coverage change"}), "permission-denied");
  await rejects(call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("sus")], expectedRevision: 1, reason: "Coverage change"}), "failed-precondition");
  await rejects(call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("unv")], expectedRevision: 1, reason: "Coverage change"}), "failed-precondition");
  await rejects(call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c2")], expectedRevision: 0, reason: "Coverage change"}), "failed-precondition");
  const result = await call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c2")], expectedRevision: 1, reason: "Coverage change"});
  assert.equal(result.revision, 2);
  const inquiry = (await db.doc(`inquiries/${id}`).get()).data()!;
  assert.deepEqual([inquiry.assigneeIds, inquiry.routingMode, inquiry.routingRevision, inquiry.escalation.status, inquiry.escalation.handledBy],
    [[uid("c2")], "manual", 2, "handled", uid("admin")]);
  const [row] = await audit(id, "INQUIRY_REASSIGNED");
  assert.deepEqual([row.metadata.added, row.metadata.removed, row.metadata.outOfCollege, row.metadata.reason],
    [[uid("c2")], [uid("c1"), uid("s1")].sort(), [uid("c2")], "Coverage change"]);
  assert.ok((await db.doc(`notifications/portal_inquiry_${id}_${uid("c2")}`).get()).exists);
  assert.ok((await db.doc(`notifications/portal_inquiry_${id}_${uid("c1")}`).get()).data()!.archivedAt);
  // The previous assignee can no longer act on it.
  await rejects(call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved"}), "permission-denied");
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

test("an assignee suspended after routing can no longer act", {skip: !emulated}, async () => {
  const id = await newInquiry("cite");
  await routeInquiry(id);
  await db.doc(`users/${uid("s1")}`).update({accountStatus: "suspended"});
  try {
    await rejects(call(setInquiryStatus, "s1", {inquiryId: id, status: "resolved"}), "permission-denied");
    await rejects(call(acknowledgeInquiry, "s1", {inquiryId: id}), "permission-denied");
  } finally {
    await db.doc(`users/${uid("s1")}`).update({accountStatus: "active"});
  }
});

test("legacy inquiries are routed by the super-admin backfill; resolved ones are not re-notified", {skip: !emulated}, async () => {
  const open = await newInquiry("cite");
  const resolved = await newInquiry("cite", {status: "resolved"});
  await rejects(call(routeExistingInquiries, "c1", {limit: 50}), "permission-denied");
  const result = await call(routeExistingInquiries, "admin", {limit: 100});
  assert.ok(result.routed >= 2);
  for (const id of [open, resolved]) assert.equal((await db.doc(`inquiries/${id}`).get()).data()!.routingStatus, "routed");
  assert.equal((await notificationsFor(open)).length, 2);
  assert.equal((await notificationsFor(resolved)).length, 0);
  const again = await call(routeExistingInquiries, "admin", {limit: 100});
  assert.equal((await audit(open, "INQUIRY_ROUTED")).length, 1);
  assert.equal(again.routed, 0);
});
