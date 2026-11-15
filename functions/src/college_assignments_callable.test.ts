import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {setStaffCollegeAssignments} from "./college_assignments_callable";

// Auth + Firestore emulators. Exercises the real callable, including the
// super-admin gate inherited from functions/src/access.ts.
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `assign-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const db = getFirestore();
const callable = setStaffCollegeAssignments as unknown as {run: (r: {auth?: {uid: string}; data?: unknown}) => Promise<{ok: boolean; revision: number; collegeIds: string[]}>};

const accounts: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  "other-admin": {verified: true, profile: {accessRole: "admin", accountStatus: "active"}},
  counselor: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"}},
  staff: {verified: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"}},
  "suspended-counselor": {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "disabled", accountStatus: "suspended", assignedCollegeIds: [`${prefix}-cite`, `${prefix}-cas`], collegeAssignmentRevision: 1}},
  student: {verified: true, profile: {accessRole: "appUser", role: "student", collegeId: `${prefix}-cite`}},
};
const cite = `${prefix}-cite`;
const cas = `${prefix}-cas`;
const old = `${prefix}-old`;

async function run(actor: string, data: Record<string, unknown>) {
  return callable.run({auth: {uid: uid(actor)}, data: {reason: "Assigning for this semester", ...data}});
}
async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => e instanceof HttpsError && e.code === code);
}
async function auditRows(target: string): Promise<FirebaseFirestore.DocumentData[]> {
  const rows = await db.collection("admin_audit_logs").where("action", "==", "STAFF_COLLEGE_ASSIGNMENTS_UPDATED").where("targetId", "==", uid(target)).get();
  return rows.docs.map((d) => d.data());
}

let previousSuperAdmin: string | undefined;
before(async () => {
  if (!emulated) return;
  previousSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = uid("admin");
  for (const [name, account] of Object.entries(accounts)) {
    await getAuth().createUser({uid: uid(name), email: `${uid(name)}@example.invalid`, emailVerified: account.verified});
    await db.doc(`users/${uid(name)}`).set(account.profile);
  }
  await db.doc(`colleges/${cite}`).set({name: "CITE", code: "CITE", active: true});
  await db.doc(`colleges/${cas}`).set({name: "CAS", code: "CAS", active: true});
  await db.doc(`colleges/${old}`).set({name: "Old", code: "OLD", active: false});
});

after(async () => {
  if (!emulated) return;
  if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID; else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  await Promise.all(Object.keys(accounts).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

test("the super-administrator assigns, updates and removes colleges with revision and audit", {skip: !emulated}, async () => {
  const first = await run("admin", {userId: uid("counselor"), collegeIds: [cite, cas], expectedRevision: 0});
  assert.deepEqual(first, {ok: true, revision: 1, collegeIds: [cas, cite].sort()});
  let profile = (await db.doc(`users/${uid("counselor")}`).get()).data()!;
  assert.deepEqual(profile.assignedCollegeIds, [cas, cite].sort());
  assert.equal(profile.collegeAssignmentRevision, 1);
  assert.equal(profile.collegeAssignmentUpdatedBy, uid("admin"));
  assert.ok(profile.collegeAssignmentUpdatedAt);

  await run("admin", {userId: uid("counselor"), collegeIds: [cite], expectedRevision: 1});
  await run("admin", {userId: uid("counselor"), collegeIds: [], expectedRevision: 2});
  profile = (await db.doc(`users/${uid("counselor")}`).get()).data()!;
  assert.deepEqual(profile.assignedCollegeIds, []);
  assert.equal(profile.collegeAssignmentRevision, 3);

  const audit = await auditRows("counselor");
  assert.equal(audit.length, 3);
  const removal = audit.find((row) => (row.metadata?.after ?? []).length === 0);
  assert.deepEqual(removal?.metadata?.removed, [cite]);
  assert.equal(removal?.metadata?.reason, "Assigning for this semester");
  assert.equal(removal?.category, "USER_MANAGEMENT");
});

test("an unchanged request writes nothing", {skip: !emulated}, async () => {
  await run("admin", {userId: uid("staff"), collegeIds: [cite], expectedRevision: 0});
  const before = (await auditRows("staff")).length;
  const again = await run("admin", {userId: uid("staff"), collegeIds: [cite], expectedRevision: 1});
  assert.equal(again.revision, 1);
  assert.equal((await auditRows("staff")).length, before);
});

test("nobody but the configured super-administrator can change assignments, including for themselves", {skip: !emulated}, async () => {
  for (const actor of ["other-admin", "counselor", "staff", "student", "suspended-counselor"]) {
    await rejects(run(actor, {userId: uid("counselor"), collegeIds: [cite], expectedRevision: 3}), "permission-denied");
    await rejects(run(actor, {userId: uid(actor), collegeIds: [cite], expectedRevision: 0}), "permission-denied");
  }
  await assert.rejects(callable.run({data: {userId: uid("counselor"), collegeIds: [], expectedRevision: 0, reason: "x x x"}}), (e: unknown) => e instanceof HttpsError && e.code === "unauthenticated");
});

test("invalid targets, colleges, revisions and reasons are refused without writing", {skip: !emulated}, async () => {
  const before = (await db.doc(`users/${uid("counselor")}`).get()).data()!;
  await rejects(run("admin", {userId: uid("student"), collegeIds: [cite], expectedRevision: 0}), "failed-precondition");
  await rejects(run("admin", {userId: uid("admin"), collegeIds: [cite], expectedRevision: 0}), "failed-precondition");
  await rejects(run("admin", {userId: `${prefix}-missing`, collegeIds: [cite], expectedRevision: 0}), "failed-precondition");
  await rejects(run("admin", {userId: uid("counselor"), collegeIds: [`${prefix}-nope`], expectedRevision: 3}), "failed-precondition");
  await rejects(run("admin", {userId: uid("counselor"), collegeIds: [old], expectedRevision: 3}), "failed-precondition");
  await rejects(run("admin", {userId: uid("counselor"), collegeIds: [cite], expectedRevision: 2}), "failed-precondition");
  await rejects(run("admin", {userId: uid("counselor"), collegeIds: ["bad/id"], expectedRevision: 3}), "invalid-argument");
  await rejects(run("admin", {userId: uid("counselor"), collegeIds: [cite], expectedRevision: 3, reason: "no"}), "invalid-argument");
  const after = (await db.doc(`users/${uid("counselor")}`).get()).data()!;
  assert.equal(after.collegeAssignmentRevision, before.collegeAssignmentRevision);
  assert.deepEqual(after.assignedCollegeIds, before.assignedCollegeIds);
});

test("suspended staff can be cleared but not given new colleges; the home college is untouched", {skip: !emulated}, async () => {
  await rejects(run("admin", {userId: uid("suspended-counselor"), collegeIds: [cite, cas, old], expectedRevision: 1}), "failed-precondition");
  const cleared = await run("admin", {userId: uid("suspended-counselor"), collegeIds: [cite], expectedRevision: 1});
  assert.deepEqual(cleared.collegeIds, [cite]);
  await run("admin", {userId: uid("staff"), collegeIds: [cite, cas], expectedRevision: 1});
  const student = (await db.doc(`users/${uid("student")}`).get()).data()!;
  assert.equal(student.collegeId, cite);
  assert.equal(student.assignedCollegeIds, undefined);
});
