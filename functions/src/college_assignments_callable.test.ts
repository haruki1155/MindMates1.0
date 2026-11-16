import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {
  COLLEGE_OWNERSHIP_COLLECTION,
  reassignCollegeCounselor,
  setStaffCollegeAssignments,
} from "./college_assignments_callable";

// Auth + Firestore emulators. Exercises both counselor-only callables,
// per-college transactional locks, concurrency collisions, and audit logs.
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `assign-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const db = getFirestore();
const callable = setStaffCollegeAssignments as unknown as {
  run: (r: {auth?: {uid: string}; data?: unknown}) => Promise<{ok: boolean; revision: number; collegeIds: string[]}>;
};
const transferCallable = reassignCollegeCounselor as unknown as {
  run: (r: {auth?: {uid: string}; data?: unknown}) => Promise<{
    ok: boolean;
    changed: boolean;
    collegeId: string;
    counselorId: string | null;
    revisions: Record<string, number>;
  }>;
};

const cite = `${prefix}-cite`;
const cas = `${prefix}-cas`;
const cba = `${prefix}-cba`;
const eng = `${prefix}-eng`;
const old = `${prefix}-old`;

const accounts: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  "other-admin": {verified: true, profile: {accessRole: "admin", accountStatus: "active"}},
  counselor: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", collegeId: cite}},
  "counselor-2": {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", collegeId: cas}},
  staff: {verified: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"}},
  "legacy-staff": {
    verified: true,
    profile: {
      accessRole: "portalStaff",
      staffAccountStatus: "approved",
      accountStatus: "active",
      assignedCollegeIds: [cite, cas],
      collegeAssignmentRevision: 1,
    },
  },
  "suspended-counselor": {
    verified: true,
    profile: {
      accessRole: "counselor",
      staffAccountStatus: "disabled",
      accountStatus: "suspended",
      assignedCollegeIds: [old],
      collegeAssignmentRevision: 1,
    },
  },
  student: {verified: true, profile: {accessRole: "appUser", role: "student", collegeId: cite}},
};

async function run(actor: string, data: Record<string, unknown>) {
  return callable.run({auth: {uid: uid(actor)}, data: {reason: "Assigning for this semester", ...data}});
}
async function runTransfer(actor: string, data: Record<string, unknown>) {
  return transferCallable.run({auth: {uid: uid(actor)}, data: {reason: "Authorized transfer", ...data}});
}
async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => e instanceof HttpsError && e.code === code);
}
async function auditRows(target: string): Promise<FirebaseFirestore.DocumentData[]> {
  const rows = await db
    .collection("admin_audit_logs")
    .where("action", "==", "STAFF_COLLEGE_ASSIGNMENTS_UPDATED")
    .where("targetId", "==", uid(target))
    .get();
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
  await Promise.all([
    db.doc(`colleges/${cite}`).set({name: "CITE", code: "CITE", active: true}),
    db.doc(`colleges/${cas}`).set({name: "CAS", code: "CAS", active: true}),
    db.doc(`colleges/${cba}`).set({name: "CBA", code: "CBA", active: true}),
    db.doc(`colleges/${eng}`).set({name: "CEA", code: "CEA", active: true}),
    db.doc(`colleges/${old}`).set({name: "Old", code: "OLD", active: false}),
  ]);
});

after(async () => {
  if (!emulated) return;
  if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID; else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  await Promise.all(Object.keys(accounts).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

test("super-admin assigns, multi-assigns, updates, and clears a counselor while maintaining locks and audits", {skip: !emulated}, async () => {
  const first = await run("admin", {userId: uid("counselor"), collegeIds: [cite, cas], expectedRevision: 0});
  assert.deepEqual(first, {ok: true, revision: 1, collegeIds: [cas, cite].sort()});

  let profile = (await db.doc(`users/${uid("counselor")}`).get()).data()!;
  assert.deepEqual(profile.assignedCollegeIds, [cas, cite].sort());
  assert.equal(profile.collegeAssignmentRevision, 1);
  assert.equal(profile.collegeId, cite); // Home college unchanged.
  assert.equal((await db.doc(`${COLLEGE_OWNERSHIP_COLLECTION}/${cite}`).get()).data()?.counselorId, uid("counselor"));
  assert.equal((await db.doc(`${COLLEGE_OWNERSHIP_COLLECTION}/${cas}`).get()).data()?.counselorId, uid("counselor"));

  await run("admin", {userId: uid("counselor"), collegeIds: [cite], expectedRevision: 1});
  assert.equal((await db.doc(`${COLLEGE_OWNERSHIP_COLLECTION}/${cas}`).get()).exists, false);

  await run("admin", {userId: uid("counselor"), collegeIds: [], expectedRevision: 2});
  profile = (await db.doc(`users/${uid("counselor")}`).get()).data()!;
  assert.deepEqual(profile.assignedCollegeIds, []);
  assert.equal(profile.collegeAssignmentRevision, 3);
  assert.equal((await db.doc(`${COLLEGE_OWNERSHIP_COLLECTION}/${cite}`).get()).exists, false);

  const audit = await auditRows("counselor");
  assert.equal(audit.length, 3);
  const removal = audit.find((row) => (row.metadata?.after ?? []).length === 0);
  assert.deepEqual(removal?.metadata?.removed, [cite]);
  assert.equal(removal?.category, "USER_MANAGEMENT");
});

test("an unchanged request is a no-op with zero duplicate audits", {skip: !emulated}, async () => {
  await run("admin", {userId: uid("counselor"), collegeIds: [cite], expectedRevision: 3});
  const beforeCount = (await auditRows("counselor")).length;
  const again = await run("admin", {userId: uid("counselor"), collegeIds: [cite], expectedRevision: 4});
  assert.equal(again.revision, 4);
  assert.equal((await auditRows("counselor")).length, beforeCount);
  await run("admin", {userId: uid("counselor"), collegeIds: [], expectedRevision: 4});
});

test("portal staff cannot receive new assignments, while legacy staff assignments can be cleared only", {skip: !emulated}, async () => {
  await rejects(run("admin", {userId: uid("staff"), collegeIds: [cite], expectedRevision: 0}), "failed-precondition");
  await rejects(run("admin", {userId: uid("staff"), collegeIds: [], expectedRevision: 0}), "failed-precondition");
  await rejects(run("admin", {userId: uid("legacy-staff"), collegeIds: [cite, cas, cba], expectedRevision: 1}), "failed-precondition");
  const beforeAdd = (await db.doc(`users/${uid("legacy-staff")}`).get()).data()!;
  assert.deepEqual(beforeAdd.assignedCollegeIds, [cite, cas]);

  const narrowed = await run("admin", {userId: uid("legacy-staff"), collegeIds: [cite], expectedRevision: 1});
  assert.deepEqual(narrowed, {ok: true, revision: 2, collegeIds: [cite]});
  const cleared = await run("admin", {userId: uid("legacy-staff"), collegeIds: [], expectedRevision: 2});
  assert.deepEqual(cleared, {ok: true, revision: 3, collegeIds: []});
  const audits = await auditRows("legacy-staff");
  assert.equal(audits.length, 2);
  assert.equal(audits[0].metadata?.legacyStaffCleanup, true);
});

test("one counselor per college prevents duplicate ownership across counselors and supports compatible routing queries", {skip: !emulated}, async () => {
  await run("admin", {userId: uid("counselor"), collegeIds: [cite], expectedRevision: 5});
  // Different counselor can receive a different college.
  await run("admin", {userId: uid("counselor-2"), collegeIds: [cas], expectedRevision: 0});

  // Second counselor cannot receive already-owned cite through ordinary picker.
  await rejects(run("admin", {userId: uid("counselor-2"), collegeIds: [cas, cite], expectedRevision: 1}), "failed-precondition");
  const c2After = (await db.doc(`users/${uid("counselor-2")}`).get()).data()!;
  assert.deepEqual(c2After.assignedCollegeIds, [cas]);
  assert.equal(c2After.collegeAssignmentRevision, 1);

  // Downstream inquiry/approval/history queries find strictly the single assigned counselor.
  const citeHolders = await db.collection("users").where("assignedCollegeIds", "array-contains", cite).get();
  assert.deepEqual(citeHolders.docs.map((d) => d.id), [uid("counselor")]);

  // Authorized transfer moves cite from counselor to counselor-2 atomically.
  const transferRes = await runTransfer("admin", {
    collegeId: cite,
    toCounselorId: uid("counselor-2"),
    expectedOwnerIds: [uid("counselor")],
    expectedRevisions: {[uid("counselor")]: 6, [uid("counselor-2")]: 1},
  });
  assert.equal(transferRes.changed, true);
  assert.equal(transferRes.counselorId, uid("counselor-2"));
  assert.deepEqual((await db.doc(`users/${uid("counselor")}`).get()).data()?.assignedCollegeIds, []);
  assert.deepEqual((await db.doc(`users/${uid("counselor-2")}`).get()).data()?.assignedCollegeIds, [cas, cite].sort());
  assert.equal((await db.doc(`${COLLEGE_OWNERSHIP_COLLECTION}/${cite}`).get()).data()?.counselorId, uid("counselor-2"));

  // Downstream query reflects the new single counselor immediately.
  const postTransferHolders = await db.collection("users").where("assignedCollegeIds", "array-contains", cite).get();
  assert.deepEqual(postTransferHolders.docs.map((d) => d.id), [uid("counselor-2")]);
});

test("concurrent collision on an unassigned college allows at most one counselor to win", {skip: !emulated}, async () => {
  const c1Before = (await db.doc(`users/${uid("counselor")}`).get()).data()!;
  const c2Before = (await db.doc(`users/${uid("counselor-2")}`).get()).data()!;
  const [res1, res2] = await Promise.allSettled([
    run("admin", {
      userId: uid("counselor"),
      collegeIds: [cba],
      expectedRevision: c1Before.collegeAssignmentRevision,
    }),
    run("admin", {
      userId: uid("counselor-2"),
      collegeIds: [...(c2Before.assignedCollegeIds as string[]), cba],
      expectedRevision: c2Before.collegeAssignmentRevision,
    }),
  ]);
  const fulfilled = [res1, res2].filter((r) => r.status === "fulfilled").length;
  const rejected = [res1, res2].filter((r) => r.status === "rejected").length;
  assert.equal(fulfilled, 1);
  assert.equal(rejected, 1);

  const holders = await db.collection("users").where("assignedCollegeIds", "array-contains", cba).get();
  assert.equal(holders.size, 1);
  const lock = (await db.doc(`${COLLEGE_OWNERSHIP_COLLECTION}/${cba}`).get()).data();
  assert.equal(lock?.counselorId, holders.docs[0].id);
});

test("existing duplicate conflict is detected, blocks ordinary additions, and resolves cleanly via transfer", {skip: !emulated}, async () => {
  // Simulate pre-existing legacy duplicate state directly via Admin SDK test setup.
  const c1Snap = (await db.doc(`users/${uid("counselor")}`).get()).data()!;
  const c2Snap = (await db.doc(`users/${uid("counselor-2")}`).get()).data()!;
  await Promise.all([
    db.doc(`users/${uid("counselor")}`).update({assignedCollegeIds: [...new Set([...(c1Snap.assignedCollegeIds ?? []), eng])]}),
    db.doc(`users/${uid("counselor-2")}`).update({assignedCollegeIds: [...new Set([...(c2Snap.assignedCollegeIds ?? []), eng])]}),
  ]);

  const c1Rev = Number((await db.doc(`users/${uid("counselor")}`).get()).data()?.collegeAssignmentRevision ?? 0);
  const c2Rev = Number((await db.doc(`users/${uid("counselor-2")}`).get()).data()?.collegeAssignmentRevision ?? 0);

  // Conflict resolution selects counselor as the single rightful owner.
  const resolved = await runTransfer("admin", {
    collegeId: eng,
    toCounselorId: uid("counselor"),
    expectedOwnerIds: [uid("counselor"), uid("counselor-2")].sort(),
    expectedRevisions: {[uid("counselor")]: c1Rev, [uid("counselor-2")]: c2Rev},
    reason: "Resolve pre-existing duplicate counselor conflict",
  });
  assert.equal(resolved.changed, true);
  assert.equal(resolved.counselorId, uid("counselor"));
  const holdersAfter = await db.collection("users").where("assignedCollegeIds", "array-contains", eng).get();
  assert.deepEqual(holdersAfter.docs.map((d) => d.id), [uid("counselor")]);
  assert.equal((await db.doc(`${COLLEGE_OWNERSHIP_COLLECTION}/${eng}`).get()).data()?.counselorId, uid("counselor"));
});

test("unauthorized callers are rejected on both callables", {skip: !emulated}, async () => {
  for (const actor of ["other-admin", "counselor", "staff", "student", "suspended-counselor"]) {
    await rejects(run(actor, {userId: uid("counselor"), collegeIds: [cite], expectedRevision: 0}), "permission-denied");
    await rejects(runTransfer(actor, {collegeId: cite, toCounselorId: uid("counselor"), expectedOwnerIds: [], expectedRevisions: {}}), "permission-denied");
  }
  await assert.rejects(
    callable.run({data: {userId: uid("counselor"), collegeIds: [], expectedRevision: 0, reason: "unauth check"}}),
    (e: unknown) => e instanceof HttpsError && e.code === "unauthenticated",
  );
  await assert.rejects(
    transferCallable.run({data: {collegeId: cite, toCounselorId: uid("counselor"), expectedOwnerIds: [], expectedRevisions: {}, reason: "unauth check"}}),
    (e: unknown) => e instanceof HttpsError && e.code === "unauthenticated",
  );
});

test("invalid targets, suspended additions, archived colleges, stale revisions and short reasons fail without writes", {skip: !emulated}, async () => {
  const before = (await db.doc(`users/${uid("counselor")}`).get()).data()!;
  await rejects(run("admin", {userId: uid("student"), collegeIds: [cite], expectedRevision: 0}), "failed-precondition");
  await rejects(run("admin", {userId: uid("admin"), collegeIds: [cite], expectedRevision: 0}), "failed-precondition");
  await rejects(run("admin", {userId: `${prefix}-missing`, collegeIds: [cite], expectedRevision: 0}), "failed-precondition");
  await rejects(run("admin", {userId: uid("counselor"), collegeIds: [`${prefix}-nope`], expectedRevision: before.collegeAssignmentRevision}), "failed-precondition");
  await rejects(run("admin", {userId: uid("counselor"), collegeIds: [old], expectedRevision: before.collegeAssignmentRevision}), "failed-precondition");
  await rejects(run("admin", {userId: uid("counselor"), collegeIds: [], expectedRevision: Number(before.collegeAssignmentRevision) + 1}), "failed-precondition");
  await rejects(run("admin", {userId: uid("counselor"), collegeIds: ["bad/id"], expectedRevision: before.collegeAssignmentRevision}), "invalid-argument");
  await rejects(run("admin", {userId: uid("counselor"), collegeIds: [], expectedRevision: before.collegeAssignmentRevision, reason: "no"}), "invalid-argument");

  // Suspended counselor cannot add an active college, but can release archived college.
  await rejects(run("admin", {userId: uid("suspended-counselor"), collegeIds: [old, cite], expectedRevision: 1}), "failed-precondition");
  const cleared = await run("admin", {userId: uid("suspended-counselor"), collegeIds: [], expectedRevision: 1});
  assert.deepEqual(cleared.collegeIds, []);

  const afterDoc = (await db.doc(`users/${uid("counselor")}`).get()).data()!;
  assert.equal(afterDoc.collegeAssignmentRevision, before.collegeAssignmentRevision);
  assert.deepEqual(afterDoc.assignedCollegeIds, before.assignedCollegeIds);
});
