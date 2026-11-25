import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";

import {archiveOrganizationRecord, getAuditLogPage, saveOrganizationRecord} from "./index";
import {ensureAuthUser} from "./test_auth_helper";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type AuditEventRow = {
  id: string;
  action: string;
  actorId?: string;
  actorNameSnapshot?: string;
  actorRoleSnapshot?: string;
  category?: string;
  targetType?: string | null;
  targetId?: string | null;
  metadata?: Record<string, unknown>;
  createdAt?: string | null;
};

type Callable = {
  run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<{
    events: AuditEventRow[];
    hasMore: boolean;
    nextCursor?: string | null;
  }>;
};

type OrgCallable = {
  run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<{ok: boolean; id?: string}>;
};

const page = getAuditLogPage as unknown as Callable;
const saveOrg = saveOrganizationRecord as unknown as OrgCallable;
const archiveOrg = archiveOrganizationRecord as unknown as OrgCallable;

const db = getFirestore();
const run = `AL${Date.now()}`;
const adminUid = process.env.SUPER_ADMIN_UID ?? "";
const counselorUid = `${run}-counselor`;
const staffUid = `${run}-staff`;
const studentUid = `${run}-student`;
const ids: string[] = [];
const orgDocsToCleanup: string[] = [];

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
let staffPublishId = "";
let studentSelfId = "";

let adminCreated = false;

before(async () => {
  assert.ok(adminUid, "SUPER_ADMIN_UID is required");
  await Promise.all([
    ensureAuthUser(adminUid, true),
    ensureAuthUser(counselorUid, true),
    ensureAuthUser(staffUid, true),
    ensureAuthUser(studentUid, true),
  ]);
  adminCreated = !(await db.doc(`users/${adminUid}`).get()).exists;
  await Promise.all([
    db.doc(`users/${adminUid}`).set({id: adminUid, accessRole: "admin", role: "admin", name: "Test Admin", accountStatus: "active"}, {merge: true}),
    db.doc(`users/${counselorUid}`).set({id: counselorUid, accessRole: "counselor", approvedRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Test Counselor"}, {merge: true}),
    db.doc(`users/${staffUid}`).set({id: staffUid, accessRole: "portalStaff", approvedRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", name: "Test PAACC Staff"}, {merge: true}),
  ]);
  // Pre-existing shape: an action about a staff account.
  roleChangeId = await seed({
    actorId: adminUid,
    actorNameSnapshot: "Test Admin",
    actorRoleSnapshot: "admin",
    action: "STAFF_ROLE_CHANGED",
    category: "USER_MANAGEMENT",
    targetType: "staff",
    targetId: counselorUid,
    targetUserId: counselorUid,
    metadata: {
      assignedRole: "counselor",
      password: "SHOULD_BE_STRIPPED",
      token: "SECRET_TOKEN",
    },
  });
  // View written by writeAudit: targets the student, targetUserId null.
  viewId = await seed({
    actorId: counselorUid,
    actorNameSnapshot: "Test Counselor",
    actorRoleSnapshot: "counselor",
    action: "STUDENT_PERSONAL_INFO_VIEWED",
    category: "SECURITY",
    targetType: "student",
    targetId: studentUid,
    targetUserId: null,
    metadata: {
      studentName: "Confidential Student",
      message: "Confidential clinical note",
      studentNo: "SYNTHETIC-STUDENT-NUMBER",
      userId: studentUid,
      before: {status: "active", studentKey: "SYNTHETIC-ROSTER-KEY"},
    },
  });
  // PAACC Staff action.
  staffPublishId = await seed({
    actorId: staffUid,
    actorNameSnapshot: "Test PAACC Staff",
    actorRoleSnapshot: "portalStaff",
    action: "ANNOUNCEMENT_PUBLISHED",
    category: "SYSTEM",
    targetType: "announcement",
    targetId: `${run}-ann-1`,
    targetUserId: null,
    metadata: {status: "published", revision: 1},
  });
  // Student self-action (must be excluded from Admin/Counselor/PAACC Staff feed).
  studentSelfId = await seed({
    actorId: studentUid,
    actorNameSnapshot: "Student",
    actorRoleSnapshot: "appUser",
    action: "APPOINTMENT_SCHEDULE_PROPOSED",
    category: "APPOINTMENTS",
    targetType: "appointment",
    targetId: `${run}-appt-1`,
    targetUserId: null,
  });
});

after(async () => {
  await Promise.all([
    ...ids.map((id) => db.doc(`admin_audit_logs/${id}`).delete().catch(() => undefined)),
    ...orgDocsToCleanup.map((path) => db.doc(path).delete().catch(() => undefined)),
    db.doc(`users/${counselorUid}`).delete().catch(() => undefined),
    db.doc(`users/${staffUid}`).delete().catch(() => undefined),
  ]);
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

test("Admin-wide Activity Logs feed denies Counselor, PAACC Staff, and unauthenticated callers", async () => {
  await assert.rejects(
    () => page.run({data: {}}),
    (err: {code?: string}) => err.code === "unauthenticated"
  );
  await assert.rejects(
    () => page.run({auth: {uid: counselorUid}, data: {}}),
    (err: {code?: string}) => err.code === "permission-denied"
  );
  await assert.rejects(
    () => page.run({auth: {uid: staffUid}, data: {}}),
    (err: {code?: string}) => err.code === "permission-denied"
  );
});

test("Admin-wide Activity Logs feed monitors Admin, Counselor, and PAACC Staff, excludes appUser, redacts student IDs, and strips secrets", async () => {
  const feed = await page.run({
    auth: {uid: adminUid},
    data: {pageSize: 50},
  });
  const byId = new Map(feed.events.map((e) => [e.id, e]));

  assert.ok(byId.has(roleChangeId), "Admin event should be returned");
  assert.ok(byId.has(viewId), "Counselor event should be returned");
  assert.ok(byId.has(staffPublishId), "PAACC Staff event should be returned");
  assert.ok(!byId.has(studentSelfId), "Student/appUser event must be excluded from staff activity feed");

  const adminEv = byId.get(roleChangeId)!;
  assert.equal(adminEv.actorRoleSnapshot, "admin");
  assert.equal(adminEv.metadata?.assignedRole, "counselor");
  assert.equal("password" in (adminEv.metadata ?? {}), false);
  assert.equal("token" in (adminEv.metadata ?? {}), false);

  const counselorEv = byId.get(viewId)!;
  assert.equal(counselorEv.actorRoleSnapshot, "counselor");
  assert.equal(counselorEv.targetId, `student••••${studentUid.slice(-4)}`);
  assert.equal("studentName" in (counselorEv.metadata ?? {}), false);
  assert.equal("message" in (counselorEv.metadata ?? {}), false);
  assert.equal("studentNo" in (counselorEv.metadata ?? {}), false);
  assert.equal("userId" in (counselorEv.metadata ?? {}), false);
  assert.deepEqual(counselorEv.metadata?.before, {status: "active"});

  // Filter by actorRole = portalStaff
  const staffOnly = await page.run({
    auth: {uid: adminUid},
    data: {actorRole: "portalStaff", filterActorId: staffUid},
  });
  assert.deepEqual(staffOnly.events.map((e) => e.id), [staffPublishId]);

  // Filter by category = SECURITY and actorId = counselorUid
  const securityOnly = await page.run({
    auth: {uid: adminUid},
    data: {category: "SECURITY", filterActorId: counselorUid},
  });
  assert.deepEqual(securityOnly.events.map((e) => e.id), [viewId]);

  // Search by humanized action label ("Student personal information viewed") or role label ("PAACC Staff")
  const byActionLabel = await page.run({
    auth: {uid: adminUid},
    data: {search: "Student personal information viewed", filterActorId: counselorUid},
  });
  assert.deepEqual(byActionLabel.events.map((e) => e.id), [viewId]);

  const byRoleLabel = await page.run({
    auth: {uid: adminUid},
    data: {search: "PAACC Staff", filterActorId: staffUid},
  });
  assert.deepEqual(byRoleLabel.events.map((e) => e.id), [staffPublishId]);
});

test("saveOrganizationRecord and archiveOrganizationRecord write server-authoritative audit records with actor snapshots", async () => {
  const collegeCode = `C${Date.now().toString().slice(-5)}`;
  const created = await saveOrg.run({
    auth: {uid: adminUid},
    data: {
      kind: "college",
      name: `Audit Test College ${collegeCode}`,
      code: collegeCode,
      active: true,
    },
  });
  assert.equal(created.ok, true);
  assert.ok(created.id);
  orgDocsToCleanup.push(`colleges/${created.id}`);

  await archiveOrg.run({
    auth: {uid: adminUid},
    data: {
      kind: "college",
      id: created.id,
      archived: true,
    },
  });

  const orgAudits = await db
    .collection("admin_audit_logs")
    .where("targetId", "==", created.id)
    .get();
  for (const doc of orgAudits.docs) ids.push(doc.id);

  const actions = orgAudits.docs.map((d) => d.data().action);
  assert.ok(actions.includes("COLLEGE_CREATED"));
  assert.ok(actions.includes("COLLEGE_ARCHIVED"));
  for (const doc of orgAudits.docs) {
    const d = doc.data();
    assert.equal(d.actorId, adminUid);
    assert.equal(d.actorRoleSnapshot, "admin");
    assert.equal(d.actorNameSnapshot, "Test Admin");
  }

  // Verify the feed retains safe organization code metadata (metadata.code) while stripping secrets
  const orgFeed = await page.run({
    auth: {uid: adminUid},
    data: {category: "SYSTEM", action: "COLLEGE_CREATED", filterActorId: adminUid},
  });
  const createdEvent = orgFeed.events.find((e) => e.targetId === created.id);
  assert.ok(createdEvent, "COLLEGE_CREATED event should be visible in feed");
  assert.equal(createdEvent?.metadata?.code, collegeCode.toUpperCase());
});


test("global feed continues across a sparse window and preserves tied timestamps", async () => {
  const date = new Timestamp(1700000000, 456000);
  const older = await seed({actorId: run, actorRoleSnapshot: "admin", action: "AUDIT_PAGE_TEST", createdAt: date});
  const tied = await seed({actorId: run, actorRoleSnapshot: "admin", action: "AUDIT_PAGE_TEST", createdAt: date});
  const newest = await seed({actorId: run, actorRoleSnapshot: "admin", action: "AUDIT_PAGE_TEST", createdAt: new Timestamp(1700000000, 457000)});
  const batch = db.batch();
  for (let i = 0; i < 120; i++) {
    const ref = db.collection("admin_audit_logs").doc();
    ids.push(ref.id);
    batch.create(ref, {createdAt: new Timestamp(1700000001, 0), actorRoleSnapshot: "admin", action: "OTHER"});
  }
  await batch.commit();
  const data = {filterActorId: run, action: "AUDIT_PAGE_TEST", afterMillis: 1700000000000, beforeMillis: 1700000001000, pageSize: 1};
  let result = await page.run({auth: {uid: adminUid}, data});
  assert.deepEqual(result.events, []);
  assert.equal(result.hasMore, true);
  const seen: string[] = [];
  for (let i = 0; result.hasMore && i < 5; i++) {
    assert.ok(result.nextCursor);
    result = await page.run({auth: {uid: adminUid}, data: {...data, cursor: result.nextCursor}});
    seen.push(...result.events.map((event) => event.id));
  }
  assert.equal(seen[0], newest);
  assert.deepEqual(new Set(seen.slice(1)), new Set([older, tied]));
  assert.equal(seen.length, 3);
  assert.equal(result.hasMore, false);
});

test("an invalid explicit per-user target cannot select the global feed", async () => {
  await assert.rejects(
    page.run({auth: {uid: adminUid}, data: {targetUserId: ""}}),
    {code: "invalid-argument"},
  );
});
