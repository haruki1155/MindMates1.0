import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

import {getAuditLogPage} from "./index";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<{events: Array<{id: string; action: string}>; hasMore: boolean}>};
const page = getAuditLogPage as unknown as Callable;
const db = getFirestore();
const run = `AL${Date.now()}`;
const adminUid = process.env.SUPER_ADMIN_UID ?? "";
const counselorUid = `${run}-counselor`;
const studentUid = `${run}-student`;
const ids: string[] = [];

async function seed(fields: Record<string, unknown>): Promise<string> {
  const ref = db.collection("admin_audit_logs").doc();
  await ref.set({metadata: {}, timestamp: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp(), ...fields});
  ids.push(ref.id);
  return ref.id;
}

const query = (targetUserId: string, action?: string) =>
  page.run({auth: {uid: adminUid}, data: {targetUserId, ...(action ? {action} : {})}});

let roleChangeId = "";
let viewId = "";

let adminCreated = false;

before(async () => {
  assert.ok(adminUid, "SUPER_ADMIN_UID is required");
  adminCreated = !(await db.doc(`users/${adminUid}`).get()).exists;
  await db.doc(`users/${adminUid}`).set({id: adminUid, accessRole: "admin", role: "admin", name: "Test Admin"}, {merge: true});
  // Pre-existing shape: an action about a staff account.
  roleChangeId = await seed({actorId: adminUid, action: "STAFF_ROLE_CHANGED", category: "USER_MANAGEMENT",
    targetType: "staff", targetId: counselorUid, targetUserId: counselorUid});
  // View written by writeAudit: targets the student, targetUserId null.
  viewId = await seed({actorId: counselorUid, action: "STUDENT_PERSONAL_INFO_VIEWED", category: "SECURITY",
    targetType: "student", targetId: studentUid, targetUserId: null});
});

after(async () => {
  await Promise.all(ids.map((id) => db.doc(`admin_audit_logs/${id}`).delete()));
  // The super-admin profile is shared with every other suite: only remove it if this run created it.
  if (adminCreated) await db.doc(`users/${adminUid}`).delete().catch(() => undefined);
});

test("staff-scoped action and the no-filter case are unchanged", async () => {
  const all = await query(counselorUid);
  assert.deepEqual(all.events.map((e) => e.id), [roleChangeId]);
  const scoped = await query(counselorUid, "STAFF_ROLE_CHANGED");
  assert.deepEqual(scoped.events.map((e) => e.id), [roleChangeId]);
});

test("student information views are listed under the acting counselor only", async () => {
  const mine = await query(counselorUid, "STUDENT_PERSONAL_INFO_VIEWED");
  assert.deepEqual(mine.events.map((e) => e.id), [viewId]);
  const aboutStudent = await query(studentUid, "STUDENT_PERSONAL_INFO_VIEWED");
  assert.deepEqual(aboutStudent.events, []);
});

test("All actions does not include student information views", async () => {
  const all = await query(counselorUid);
  assert.ok(!all.events.some((e) => e.id === viewId));
});
