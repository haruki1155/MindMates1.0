import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {getCaseRemarks, saveCaseRemarks} from "./case_remarks_callable";
import {getStudentCaseHistory} from "./student_case_history_callable";

// Auth + Firestore emulators. Exercises the real callables and the shared
// staff gate (functions/src/access.ts) with real verified Auth users.
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `remarks-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const id = (name: string) => `${prefix}-${name}`;
const cite = `${prefix}-cite`;
const cas = `${prefix}-cas`;
const db = getFirestore();

type View = {
  appointmentId: string;
  text: string;
  revision: number;
  updatedAt: string | null;
  authorName: string;
  versions: Array<{revision: number; text: string; authorName: string; savedAt: string | null}>;
};
type Callable<T> = {run: (r: {auth?: {uid: string}; data?: unknown}) => Promise<T>};
const getRemarks = getCaseRemarks as unknown as Callable<View>;
const saveRemarks = saveCaseRemarks as unknown as Callable<View>;
const history = getStudentCaseHistory as unknown as Callable<unknown>;

const counselorProfile = {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"};
const accounts: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  "other-admin": {verified: true, profile: {accessRole: "admin", accountStatus: "active"}},
  "cite-counselor": {verified: true, profile: {...counselorProfile, name: "Coach Cite", assignedCollegeIds: [cite]}},
  "cite-counselor-2": {verified: true, profile: {...counselorProfile, name: "Coach Two", assignedCollegeIds: [cite]}},
  "cas-counselor": {verified: true, profile: {...counselorProfile, assignedCollegeIds: [cas]}},
  "case-counselor": {verified: true, profile: {...counselorProfile, name: "Coach Case", assignedCollegeIds: []}},
  "suspended-counselor": {verified: true, profile: {...counselorProfile, accountStatus: "suspended", assignedCollegeIds: [cite]}},
  "unverified-counselor": {verified: false, profile: {...counselorProfile, assignedCollegeIds: [cite]}},
  staff: {verified: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: [cite]}},
  ana: {verified: true, profile: {accessRole: "appUser", role: "student", firstName: "Ana", lastName: "Cruz", collegeId: cite, verificationStatus: "verified"}},
  bea: {verified: true, profile: {accessRole: "appUser", role: "student", firstName: "Bea", lastName: "Reyes", collegeId: cas, verificationStatus: "verified"}},
};

const at = (iso: string) => Timestamp.fromDate(new Date(iso));
const appointments: Record<string, Record<string, unknown>> = {
  "ana-done": {userId: uid("ana"), status: "completed", scheduledAt: at("2026-03-02T01:00:00Z"), concern: "Sleep", assignedStaffId: uid("case-counselor")},
  "ana-open": {userId: uid("ana"), status: "confirmed", scheduledAt: at("2026-10-02T01:00:00Z"), concern: "Exams"},
  "ana-blank": {userId: uid("ana"), status: "requested", scheduledAt: at("2026-11-02T01:00:00Z"), concern: "Stress"},
  "ana-history": {userId: uid("ana"), status: "completed", scheduledAt: at("2026-01-02T01:00:00Z"), concern: "Grief"},
  "bea-open": {userId: uid("bea"), status: "confirmed", scheduledAt: at("2026-10-05T01:00:00Z"), concern: "Family"},
};

async function as<T>(callable: Callable<T>, actor: string, data: Record<string, unknown>) {
  return callable.run({auth: {uid: uid(actor)}, data});
}
async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => e instanceof HttpsError && e.code === code);
}
async function remarkAudits(appointment: string, action: string): Promise<FirebaseFirestore.DocumentData[]> {
  const rows = await db.collection("admin_audit_logs").where("action", "==", action).where("targetId", "==", id(appointment)).get();
  return rows.docs.map((d) => d.data());
}
const current = (appointment: string) => db.doc(`appointments/${id(appointment)}/case_remarks/current`);

let previousSuperAdmin: string | undefined;
before(async () => {
  if (!emulated) return;
  previousSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = uid("admin");
  for (const [name, account] of Object.entries(accounts)) {
    await getAuth().createUser({uid: uid(name), email: `${uid(name)}@example.invalid`, emailVerified: account.verified});
    await db.doc(`users/${uid(name)}`).set(account.profile);
  }
  for (const [name, data] of Object.entries(appointments)) await db.doc(`appointments/${id(name)}`).set(data);
});

after(async () => {
  if (!emulated) return;
  if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID; else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  await Promise.all(Object.keys(accounts).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

test("remarks are optional: a case with none reads as blank, and saving blank is valid and writes nothing", {skip: !emulated}, async () => {
  const empty = await as(getRemarks, "cite-counselor", {appointmentId: id("ana-blank")});
  assert.deepEqual(empty, {appointmentId: id("ana-blank"), text: "", revision: 0, updatedAt: null, authorName: "", versions: []});
  const saved = await as(saveRemarks, "cite-counselor", {appointmentId: id("ana-blank"), expectedRevision: 0});
  assert.equal(saved.revision, 0);
  const blank = await as(saveRemarks, "cite-counselor", {appointmentId: id("ana-blank"), text: "   ", expectedRevision: 0});
  assert.equal(blank.revision, 0);
  assert.equal((await current("ana-blank").get()).exists, false);
  assert.equal((await remarkAudits("ana-blank", "CASE_REMARKS_UPDATED")).length, 0);
});

test("an authorized counselor saves remarks; reload shows them with author, revision and versions newest first", {skip: !emulated}, async () => {
  const first = await as(saveRemarks, "cite-counselor", {appointmentId: id("ana-open"), text: "  First note\r\nline two ", expectedRevision: 0});
  assert.deepEqual([first.text, first.revision, first.authorName], ["First note\nline two", 1, "Coach Cite"]);
  assert.ok(first.updatedAt);

  const second = await as(saveRemarks, "cite-counselor-2", {appointmentId: id("ana-open"), text: "Second note", expectedRevision: 1});
  assert.equal(second.revision, 2);

  const reloaded = await as(getRemarks, "cite-counselor", {appointmentId: id("ana-open")});
  assert.deepEqual([reloaded.text, reloaded.revision, reloaded.authorName], ["Second note", 2, "Coach Two"]);
  assert.deepEqual(reloaded.versions.map((v) => [v.revision, v.text, v.authorName]), [[2, "Second note", "Coach Two"], [1, "First note\nline two", "Coach Cite"]]);

  const stored = (await current("ana-open").get()).data()!;
  assert.deepEqual([stored.studentId, stored.authorId, stored.authorRoleSnapshot, stored.appointmentId], [uid("ana"), uid("cite-counselor-2"), "counselor", id("ana-open")]);
  const version1 = (await current("ana-open").collection("versions").doc("1").get()).data()!;
  assert.deepEqual([version1.text, version1.authorId], ["First note\nline two", uid("cite-counselor")]);

  // Clearing is a real, versioned edit, and omitting text never silently deletes saved remarks.
  await rejects(as(saveRemarks, "cite-counselor", {appointmentId: id("ana-open"), expectedRevision: 2}), "invalid-argument");
  const cleared = await as(saveRemarks, "cite-counselor", {appointmentId: id("ana-open"), text: "", expectedRevision: 2});
  assert.deepEqual([cleared.text, cleared.revision], ["", 3]);
});

test("updates and views are audited under the counselor, never with the note text", {skip: !emulated}, async () => {
  await as(saveRemarks, "cite-counselor", {appointmentId: id("ana-done"), text: "SECRET REMARK TEXT", expectedRevision: 0});
  await as(getRemarks, "cite-counselor", {appointmentId: id("ana-done")});
  const updates = await remarkAudits("ana-done", "CASE_REMARKS_UPDATED");
  const views = await remarkAudits("ana-done", "CASE_REMARKS_VIEWED");
  assert.equal(updates.length, 1);
  assert.equal(views.length, 1);
  assert.deepEqual([updates[0].actorId, updates[0].targetType, updates[0].metadata.studentId, updates[0].metadata.revision, updates[0].metadata.basis],
    [uid("cite-counselor"), "appointment", uid("ana"), 1, "college"]);
  assert.ok(!JSON.stringify([...updates, ...views]).includes("SECRET REMARK TEXT"));
});

test("a stale update conflicts and changes nothing", {skip: !emulated}, async () => {
  await as(saveRemarks, "cite-counselor", {appointmentId: id("ana-history"), text: "Counselor A", expectedRevision: 0});
  await as(saveRemarks, "cite-counselor-2", {appointmentId: id("ana-history"), text: "Counselor B", expectedRevision: 1});
  const auditsBefore = (await remarkAudits("ana-history", "CASE_REMARKS_UPDATED")).length;
  await rejects(as(saveRemarks, "cite-counselor", {appointmentId: id("ana-history"), text: "Counselor A again", expectedRevision: 1}), "aborted");
  const stored = (await current("ana-history").get()).data()!;
  assert.deepEqual([stored.text, stored.revision], ["Counselor B", 2]);
  assert.equal((await current("ana-history").collection("versions").get()).size, 2);
  assert.equal((await remarkAudits("ana-history", "CASE_REMARKS_UPDATED")).length, auditsBefore);
});

test("a counselor assigned to one of the student's cases may use remarks on that student's cases only", {skip: !emulated}, async () => {
  const view = await as(getRemarks, "case-counselor", {appointmentId: id("ana-done")});
  assert.equal(view.text, "SECRET REMARK TEXT");
  await rejects(as(getRemarks, "case-counselor", {appointmentId: id("bea-open")}), "permission-denied");
});

test("wrong-college, unassigned, admin, staff, student, suspended and unverified accounts can neither read nor write", {skip: !emulated}, async () => {
  const viewsBefore = (await remarkAudits("ana-done", "CASE_REMARKS_VIEWED")).length;
  for (const actor of ["cas-counselor", "admin", "other-admin", "staff", "suspended-counselor", "unverified-counselor", "ana", "bea"]) {
    await rejects(as(getRemarks, actor, {appointmentId: id("ana-done")}), "permission-denied");
    await rejects(as(saveRemarks, actor, {appointmentId: id("ana-done"), text: `Forged by ${actor}`, expectedRevision: 1}), "permission-denied");
  }
  await rejects(as(getRemarks, "cite-counselor", {appointmentId: id("bea-open")}), "permission-denied");
  await rejects(as(saveRemarks, "cite-counselor", {appointmentId: id("bea-open"), text: "x", expectedRevision: 0}), "permission-denied");
  await rejects(getRemarks.run({data: {appointmentId: id("ana-done")}}), "unauthenticated");

  const stored = (await current("ana-done").get()).data()!;
  assert.deepEqual([stored.text, stored.revision], ["SECRET REMARK TEXT", 1]);
  assert.equal((await current("bea-open").get()).exists, false);
  assert.equal((await remarkAudits("ana-done", "CASE_REMARKS_VIEWED")).length, viewsBefore);
});

test("unknown appointments look like out-of-scope ones; bad input is rejected", {skip: !emulated}, async () => {
  await rejects(as(getRemarks, "cite-counselor", {appointmentId: id("nope")}), "permission-denied");
  await rejects(as(getRemarks, "cite-counselor", {appointmentId: "../users"}), "invalid-argument");
  await rejects(as(getRemarks, "cite-counselor", {}), "invalid-argument");
  await rejects(as(saveRemarks, "cite-counselor", {appointmentId: id("ana-blank"), text: "x".repeat(10001), expectedRevision: 0}), "invalid-argument");
  await rejects(as(saveRemarks, "cite-counselor", {appointmentId: id("ana-blank"), text: "x"}), "invalid-argument");
  await rejects(as(saveRemarks, "cite-counselor", {appointmentId: id("ana-blank"), text: 5, expectedRevision: 0}), "invalid-argument");
});

test("remarks never appear in the student case history", {skip: !emulated}, async () => {
  const text = JSON.stringify(await as(history, "cite-counselor", {studentId: uid("ana"), pageSize: 50}));
  for (const secret of ["SECRET REMARK TEXT", "Counselor B", "case_remarks"]) assert.ok(!text.includes(secret), `${secret} leaked`);
});

test("a counselor whose college or case assignment is revoked loses access immediately", {skip: !emulated}, async () => {
  await db.doc(`users/${uid("cite-counselor-2")}`).update({assignedCollegeIds: []});
  await rejects(as(getRemarks, "cite-counselor-2", {appointmentId: id("ana-done")}), "permission-denied");
  await rejects(as(saveRemarks, "cite-counselor-2", {appointmentId: id("ana-done"), text: "After revoke", expectedRevision: 1}), "permission-denied");

  await db.doc(`appointments/${id("ana-done")}`).update({assignedStaffId: uid("cite-counselor")});
  await rejects(as(getRemarks, "case-counselor", {appointmentId: id("ana-done")}), "permission-denied");
  await rejects(as(saveRemarks, "case-counselor", {appointmentId: id("ana-done"), text: "After reassign", expectedRevision: 1}), "permission-denied");
});
