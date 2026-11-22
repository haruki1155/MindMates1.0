import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {INQUIRY_STATUSES_COLLECTION, acknowledgeInquiry, escalateInquiry, reassignInquiry, routeInquiry, setInquiryStatus} from "./inquiry_routing_service";
import {replyToInquiry, setInquirySla, takeOverInquiry} from "./inquiry_sla_service";

// Auth + Firestore emulators: real callables, real routing.
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const p = `sla-${Date.now()}`;
const uid = (name: string) => `${p}-${name}`;
const db = getFirestore();
const cite = `${p}-cite`;
const cas = `${p}-cas`;

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<any>};
const call = (fn: unknown, actor: string, data: Record<string, unknown>) => (fn as Callable).run({auth: {uid: uid(actor)}, data});
async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => e instanceof HttpsError && e.code === code);
}

const accounts: Record<string, {verified: boolean; disabled?: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  c1: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Counselor One", assignedCollegeIds: [cite]}},
  c1b: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Counselor One B", assignedCollegeIds: [cite]}},
  s1: {verified: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", name: "Staff One", assignedCollegeIds: [cite]}},
  c2: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Counselor Two", assignedCollegeIds: [cas]}},
  sus: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "disabled", accountStatus: "suspended", name: "Suspended Counselor", assignedCollegeIds: [cite]}},
  dis: {verified: true, disabled: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Disabled Counselor", assignedCollegeIds: [cite]}},
  unv: {verified: false, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Unverified Counselor", assignedCollegeIds: [cite]}},
  otherAdmin: {verified: true, profile: {accessRole: "admin", accountStatus: "active"}},
  student: {verified: true, profile: {accessRole: "appUser", populationRole: "student", verificationStatus: "verified", collegeId: cite}},
};

let n = 0;
async function routedInquiry(): Promise<string> {
  const id = `${p}-inq-${++n}`;
  await db.doc(`inquiries/${id}`).set({
    userId: uid("student"), subject: "Feedback", message: "Private student message", category: "Service Form",
    email: "s@x", name: "Student", role: "User", formType: "client_feedback", formData: {q: "private"}, status: "pending", createdAt: new Date(),
  });
  await routeInquiry(id);
  return id;
}
const inquiry = async (id: string) => (await db.doc(`inquiries/${id}`).get()).data()!;
const notes = async (id: string) => (await db.collection("notifications").where("inquiryId", "==", id).get()).docs.map((d) => ({id: d.id, ...d.data()}) as Record<string, any>);
const audit = async (target: string, action: string) =>
  (await db.collection("admin_audit_logs").where("targetId", "==", target).where("action", "==", action).get()).docs.map((d) => d.data());
const requestId = (label: string) => `${p}-req-${label}`;

let previous: string | undefined;
before(async () => {
  if (!emulated) return;
  previous = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = uid("admin");
  for (const [name, account] of Object.entries(accounts)) {
    await getAuth().createUser({uid: uid(name), email: `${uid(name)}@example.invalid`, emailVerified: account.verified, disabled: account.disabled ?? false});
    await db.doc(`users/${uid(name)}`).set(account.profile);
  }
  for (const id of [cite, cas]) await db.doc(`colleges/${id}`).set({name: id, code: id, active: true});
});

after(async () => {
  if (!emulated) return;
  if (previous == null) delete process.env.SUPER_ADMIN_UID; else process.env.SUPER_ADMIN_UID = previous;
  await Promise.all(Object.keys(accounts).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

test("only the super-administrator sets the response target, to a PACC option, with audit", {skip: !emulated}, async () => {
  for (const actor of ["c1", "s1", "otherAdmin", "student"]) await rejects(call(setInquirySla, actor, {hours: 48}), "permission-denied");
  await rejects(call(setInquirySla, "admin", {hours: 36}), "invalid-argument");
  await call(setInquirySla, "admin", {hours: 48});
  const config = (await db.doc("system_config/inquiry_sla").get()).data()!;
  assert.deepEqual([config.hours, config.updatedBy], [48, uid("admin")]);
  const rows = await audit("inquiry_sla", "INQUIRY_SLA_UPDATED");
  assert.ok(rows.some((row) => row.metadata.after === 48));
});

const projection = async (id: string) => (await db.doc(`${INQUIRY_STATUSES_COLLECTION}/${id}`).get()).data()!;

test("an assignee's reply reaches the student privately, updates projection atomically without leaking text, and is audited", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  // Assign s1 as operational monitor alongside routed counselors c1 & c1b.
  await call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c1"), uid("c1b")], monitoringStaffIds: [uid("s1")], expectedRevision: 1, reason: "Monitor setup"});
  const reply = "We received your feedback and will follow up on Monday.";
  const result = await call(replyToInquiry, "c1", {inquiryId: id, message: reply, expectedRevision: 2, requestId: requestId("a")});
  assert.deepEqual([result.duplicate, result.revision], [false, 3]);
  const stored = (await db.doc(`inquiries/${id}/replies/${requestId("a")}`).get()).data()!;
  assert.deepEqual([stored.message, stored.authorId, stored.authorRole], [reply, uid("c1"), "counselor"]);
  const data = await inquiry(id);
  assert.deepEqual([data.status, data.ownerId, data.responseCount, data.lastResponseByName, data.lastResponseRole, data.routingRevision],
    ["in_progress", uid("c1"), 1, "Counselor One", "counselor", 3]);
  assert.ok(data.firstResponseAt && data.lastResponseAt);

  // Operational projection updates atomically without leaking authored reply text or author PII.
  const proj = await projection(id);
  assert.deepEqual([proj.status, proj.responseCount, proj.routingRevision, proj.isTakenOver], ["in_progress", 1, 3, false]);
  assert.ok(proj.firstResponseAt && proj.lastResponseAt);
  const projJson = JSON.stringify(proj);
  for (const secret of [reply, "Private student message", "Counselor One", "s@x"]) {
    if (secret !== "Counselor One") assert.ok(!projJson.includes(secret), `projection leaked: ${secret}`);
  }
  assert.equal(proj.lastResponseByName, undefined);

  // Student notification exists without leaking clinical reply text in push-notification body.
  const all = await notes(id);
  const toStudent = all.filter((x) => x.userId === uid("student"));
  assert.equal(toStudent.length, 1);
  assert.ok(!JSON.stringify(toStudent[0]).includes("follow up"), "push/notification body must not leak authored reply text");
  const toStaff = all.filter((x) => x.userId === uid("c1b") && x.id.startsWith("portal_inquiry_reply_"));
  assert.equal(toStaff.length, 1, "the other counselor assignee is told a reply was posted");
  assert.ok(!JSON.stringify(toStaff[0]).includes("follow up"), "staff notifications carry no reply content");
  assert.equal(all.filter((x) => x.userId === uid("c1") && x.id.startsWith("portal_inquiry_reply_")).length, 0, "the author is not notified");
  const rows = await audit(id, "INQUIRY_RESPONDED");
  assert.equal(rows.length, 1);
  assert.ok(!JSON.stringify(rows[0]).includes("follow up"), "audit records the reply, not its content");
});

test("a retried reply returns the original reply and duplicates nothing", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  const first = await call(replyToInquiry, "c1", {inquiryId: id, message: "Hello", expectedRevision: 1, requestId: requestId("retry")});
  const again = await call(replyToInquiry, "c1", {inquiryId: id, message: "Hello", expectedRevision: 1, requestId: requestId("retry")});
  assert.deepEqual([first.duplicate, again.duplicate, again.replyId], [false, true, requestId("retry")]);
  assert.equal((await db.collection(`inquiries/${id}/replies`).get()).size, 1);
  assert.equal((await inquiry(id)).responseCount, 1);
  assert.equal((await notes(id)).filter((x) => x.userId === uid("student")).length, 1);
  assert.equal((await audit(id, "INQUIRY_RESPONDED")).length, 1);
});

test("replies are refused for portalStaff (even monitoring), wrong college, suspended, disabled, unverified, unassigned, stale views, resolved inquiries and bad input", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  await call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c1")], monitoringStaffIds: [uid("s1")], expectedRevision: 1, reason: "Monitor setup"});
  for (const actor of ["s1", "c2", "c1b", "otherAdmin", "student", "sus", "dis", "unv"]) {
    await rejects(call(replyToInquiry, actor, {inquiryId: id, message: "Hi", expectedRevision: 2, requestId: requestId(`deny-${actor}`)}), "permission-denied");
  }
  await rejects(call(replyToInquiry, "c1", {inquiryId: id, message: "", expectedRevision: 2, requestId: requestId("empty")}), "invalid-argument");
  await rejects(call(replyToInquiry, "c1", {inquiryId: id, message: "Hi", expectedRevision: 2, requestId: "bad/id"}), "invalid-argument");
  await rejects(call(replyToInquiry, "c1", {inquiryId: id, message: "Hi", expectedRevision: 1, requestId: requestId("stale")}), "failed-precondition");
  await call(acknowledgeInquiry, "c1", {inquiryId: id, expectedRevision: 2});
  await call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved", expectedRevision: 3});
  const resolved = await inquiry(id);
  await rejects(call(replyToInquiry, "c1", {inquiryId: id, message: "Late", expectedRevision: resolved.routingRevision, requestId: requestId("late")}), "failed-precondition");
  assert.equal((await db.collection(`inquiries/${id}/replies`).get()).size, 0);
});

test("concurrent staff and administrator replies, reply vs takeover, and reply vs resolve/reassignment serialize safely", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  const outcomes = await Promise.allSettled([
    call(replyToInquiry, "c1", {inquiryId: id, message: "Staff answer", expectedRevision: 1, requestId: requestId("race-staff")}),
    call(replyToInquiry, "admin", {inquiryId: id, message: "Admin answer", expectedRevision: 1, requestId: requestId("race-admin")}),
  ]);
  assert.equal(outcomes.filter((o) => o.status === "fulfilled").length, 1);
  const failed = outcomes.find((o) => o.status === "rejected") as PromiseRejectedResult;
  assert.ok(failed.reason instanceof HttpsError && failed.reason.code === "failed-precondition");
  assert.equal((await db.collection(`inquiries/${id}/replies`).get()).size, 1);

  // Reply vs takeover concurrency at revision 1.
  const idTakeoverRace = await routedInquiry();
  const takeoverRace = await Promise.allSettled([
    call(replyToInquiry, "c1", {inquiryId: idTakeoverRace, message: "Counselor race reply", expectedRevision: 1, requestId: requestId("race-r")}),
    call(takeOverInquiry, "admin", {inquiryId: idTakeoverRace, expectedRevision: 1, reason: "SLA takeover race"}),
  ]);
  assert.equal(takeoverRace.filter((o) => o.status === "fulfilled").length, 1);
  const loser1 = takeoverRace.find((o) => o.status === "rejected") as PromiseRejectedResult;
  assert.ok(loser1.reason instanceof HttpsError && ["failed-precondition", "permission-denied"].includes(loser1.reason.code));

  // Reply vs resolve concurrency at revision 2 (after acknowledgment).
  const idResolveRace = await routedInquiry();
  await call(acknowledgeInquiry, "c1", {inquiryId: idResolveRace, expectedRevision: 1});
  const resolveRace = await Promise.allSettled([
    call(replyToInquiry, "c1", {inquiryId: idResolveRace, message: "Reply during resolve", expectedRevision: 2, requestId: requestId("race-res")}),
    call(setInquiryStatus, "c1", {inquiryId: idResolveRace, status: "resolved", expectedRevision: 2}),
  ]);
  assert.equal(resolveRace.filter((o) => o.status === "fulfilled").length, 1);
  const loser2 = resolveRace.find((o) => o.status === "rejected") as PromiseRejectedResult;
  assert.ok(loser2.reason instanceof HttpsError && loser2.reason.code === "failed-precondition");

  // Reply vs reassignment concurrency at revision 1.
  const idReassignRace = await routedInquiry();
  const reassignRace = await Promise.allSettled([
    call(replyToInquiry, "c1", {inquiryId: idReassignRace, message: "Reply during reassign", expectedRevision: 1, requestId: requestId("race-rea")}),
    call(reassignInquiry, "admin", {inquiryId: idReassignRace, assigneeIds: [uid("c2")], expectedRevision: 1, reason: "Concurrent reassign"}),
  ]);
  assert.equal(reassignRace.filter((o) => o.status === "fulfilled").length, 1);
  const loser3 = reassignRace.find((o) => o.status === "rejected") as PromiseRejectedResult;
  assert.ok(loser3.reason instanceof HttpsError && ["failed-precondition", "permission-denied"].includes(loser3.reason.code));
});

test("takeover is super-admin only, updates projection safely, and revokes counselor & monitor mutation authority", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  await call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c1")], monitoringStaffIds: [uid("s1")], expectedRevision: 1, reason: "Add monitor"});
  await rejects(call(takeOverInquiry, "c1", {inquiryId: id, expectedRevision: 2, reason: "Overdue"}), "permission-denied");
  await rejects(call(takeOverInquiry, "admin", {inquiryId: id, expectedRevision: 1, reason: "Overdue"}), "failed-precondition");
  await rejects(call(takeOverInquiry, "admin", {inquiryId: id, expectedRevision: 2, reason: "no"}), "invalid-argument");
  const result = await call(takeOverInquiry, "admin", {inquiryId: id, expectedRevision: 2, reason: "Past the response target"});
  assert.equal(result.revision, 3);
  const data = await inquiry(id);
  assert.deepEqual([data.takeover.by, data.takeover.byName, data.takeover.reason, data.ownerId], [uid("admin"), "Super Admin", "Past the response target", uid("admin")]);
  const proj = await projection(id);
  assert.equal(proj.isTakenOver, true);
  assert.equal(proj.routingRevision, 3);
  assert.ok(!JSON.stringify(proj).includes("Past the response target"), "projection never leaks takeover reason");
  const told = (await notes(id)).filter((x) => x.id.startsWith("portal_inquiry_takeover_")).map((x) => x.userId).sort();
  assert.deepEqual(told, [uid("c1"), uid("s1")].sort());
  assert.equal((await audit(id, "INQUIRY_TAKEN_OVER")).length, 1);
  await rejects(call(takeOverInquiry, "admin", {inquiryId: id, expectedRevision: 3, reason: "Again please"}), "failed-precondition");
  // Assignees & monitors keep read access per role, but lose mutation authority until reassigned.
  await rejects(call(replyToInquiry, "c1", {inquiryId: id, message: "Late reply", expectedRevision: 3, requestId: requestId("late-staff")}), "permission-denied");
  await rejects(call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved"}), "permission-denied");
  await rejects(call(acknowledgeInquiry, "c1", {inquiryId: id, expectedRevision: 3}), "permission-denied");
  await rejects(call(escalateInquiry, "s1", {inquiryId: id, reason: "Monitor after takeover", expectedRevision: 3}), "permission-denied");
  const reply = await call(replyToInquiry, "admin", {inquiryId: id, message: "An administrator is handling this.", expectedRevision: 3, requestId: requestId("admin")});
  assert.equal(reply.revision, 4);
  const after = await inquiry(id);
  assert.deepEqual([after.lastResponseRole, after.status], ["admin", "in_progress"]);
});

test("status changes accept an expected revision and advance it", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  await call(acknowledgeInquiry, "c1", {inquiryId: id, expectedRevision: 1});
  await rejects(call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved", expectedRevision: 1}), "failed-precondition");
  await call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved", expectedRevision: 2});
  assert.equal((await inquiry(id)).routingRevision, 3);
});

test("reassignment after takeover hands the inquiry back to the new assignees", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  await call(takeOverInquiry, "admin", {inquiryId: id, expectedRevision: 1, reason: "Past the response target"});
  await call(reassignInquiry, "admin", {inquiryId: id, assigneeIds: [uid("c2")], expectedRevision: 2, reason: "Handing to CAS"});
  const data = await inquiry(id);
  assert.equal(data.takeover, null);
  assert.equal((await projection(id)).isTakenOver, false);
  const reply = await call(replyToInquiry, "c2", {inquiryId: id, message: "Taking this from here.", expectedRevision: data.routingRevision, requestId: requestId("handback")});
  assert.equal(reply.duplicate, false);
});

// ---- Revision consistency (PR #51 review) ---------------------------------

async function withStrictRevisions<T>(fn: () => Promise<T>): Promise<T> {
  const previousFlag = process.env.INQUIRY_REQUIRE_EXPECTED_REVISION;
  process.env.INQUIRY_REQUIRE_EXPECTED_REVISION = "true";
  try {
    return await fn();
  } finally {
    if (previousFlag == null) delete process.env.INQUIRY_REQUIRE_EXPECTED_REVISION;
    else process.env.INQUIRY_REQUIRE_EXPECTED_REVISION = previousFlag;
  }
}

test("acknowledgement advances the revision, does not set firstResponseAt, and rejects stale views", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  const fetched = (await inquiry(id)).routingRevision;
  assert.equal(fetched, 1);
  await call(acknowledgeInquiry, "c1", {inquiryId: id, expectedRevision: fetched});
  const afterAck = await inquiry(id);
  assert.equal(afterAck.routingRevision, 2);
  assert.equal(afterAck.firstResponseAt ?? null, null, "acknowledgement does not count as an authored reply");
  assert.equal(afterAck.responseCount ?? 0, 0);
  // The administrator and the second counselor still hold revision 1.
  await rejects(call(takeOverInquiry, "admin", {inquiryId: id, expectedRevision: fetched, reason: "Past the response target"}), "failed-precondition");
  await rejects(call(replyToInquiry, "c1b", {inquiryId: id, message: "Hello", expectedRevision: fetched, requestId: requestId("ack-stale")}), "failed-precondition");
  assert.equal((await inquiry(id)).takeover ?? null, null);
  assert.equal((await db.collection(`inquiries/${id}/replies`).get()).size, 0);
  const reply = await call(replyToInquiry, "c1b", {inquiryId: id, message: "Hello", expectedRevision: 2, requestId: requestId("ack-fresh")});
  assert.equal(reply.revision, 3);
});

test("a stale acknowledgement changes nothing: no status change, receipt or audit", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  await call(replyToInquiry, "c1", {inquiryId: id, message: "Answer first", expectedRevision: 1, requestId: requestId("before-ack")});
  const receiptsBefore = (await notes(id)).filter((x) => x.userId === uid("student") && x.title === "Form received").length;
  await rejects(call(acknowledgeInquiry, "c1b", {inquiryId: id, expectedRevision: 1}), "failed-precondition");
  const data = await inquiry(id);
  assert.equal(data.acknowledgedAt ?? null, null);
  assert.equal(data.routingRevision, 2);
  assert.equal((await notes(id)).filter((x) => x.userId === uid("student") && x.title === "Form received").length, receiptsBefore);
  assert.equal((await audit(id, "INQUIRY_ACKNOWLEDGED")).length, 0);
});

test("escalation advances the revision too", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  await call(escalateInquiry, "c1", {inquiryId: id, escalationType: "counselor_confirmation", expectedRevision: 1});
  const escalated = await inquiry(id);
  assert.equal(escalated.routingRevision, 2);
  assert.equal(escalated.escalation.type, "counselor_confirmation");
  assert.equal(escalated.escalation.reason, null);
  await rejects(call(takeOverInquiry, "admin", {inquiryId: id, expectedRevision: 1, reason: "Past the response target"}), "failed-precondition");
  await rejects(call(replyToInquiry, "c1b", {inquiryId: id, message: "Hi", expectedRevision: 1, requestId: requestId("esc-stale")}), "failed-precondition");
  // takeOverInquiry still enforces 3-500 char reason and preserves escalation.type when marking handled.
  await rejects(call(takeOverInquiry, "admin", {inquiryId: id, expectedRevision: 2, reason: "no"}), "invalid-argument");
  await call(takeOverInquiry, "admin", {inquiryId: id, expectedRevision: 2, reason: "Past the response target"});
  const taken = await inquiry(id);
  assert.equal(taken.escalation.status, "handled");
  assert.equal(taken.escalation.type, "counselor_confirmation");
});

test("legacy PR #4 clients that omit the revision are still served, and the audit says it was unchecked", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  await call(acknowledgeInquiry, "c1", {inquiryId: id});
  await call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved"});
  const data = await inquiry(id);
  assert.deepEqual([data.status, data.routingRevision], ["resolved", 3]);
  const [ack] = await audit(id, "INQUIRY_ACKNOWLEDGED");
  const [resolved] = await audit(id, "INQUIRY_RESOLVED");
  assert.equal(ack.metadata.revisionChecked, false);
  assert.equal(resolved.metadata.revisionChecked, false);
  assert.deepEqual([ack.metadata.revision, resolved.metadata.revision], [2, 3]);
});

test("a supplied revision is always enforced and recorded as checked", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  await rejects(call(setInquiryStatus, "c1", {inquiryId: id, status: "in_progress", expectedRevision: 7}), "failed-precondition");
  await call(setInquiryStatus, "c1", {inquiryId: id, status: "in_progress", expectedRevision: 1});
  const [changed] = await audit(id, "INQUIRY_STATUS_CHANGED");
  assert.equal(changed.metadata.revisionChecked, true);
  await rejects(call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved", expectedRevision: "2"}), "invalid-argument");
});

test("once strict revisions are switched on, omitted revisions are refused", {skip: !emulated}, async () => {
  const id = await routedInquiry();
  await withStrictRevisions(async () => {
    await rejects(call(acknowledgeInquiry, "c1", {inquiryId: id}), "invalid-argument");
    await rejects(call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved"}), "invalid-argument");
    await call(acknowledgeInquiry, "c1", {inquiryId: id, expectedRevision: 1});
    await call(setInquiryStatus, "c1", {inquiryId: id, status: "resolved", expectedRevision: 2});
  });
  assert.equal((await inquiry(id)).status, "resolved");
});
