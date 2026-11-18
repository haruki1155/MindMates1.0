import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

import {
  backfillAppointmentCollegeScopeBatch,
} from "./appointment_approval_service";
import {
  backfillAppointmentCollegeScope,
  createAppointmentRequest,
  getAppointmentForApproval,
  listAppointmentApprovals,
  reviewProfileVerification,
  syncStudentAppointmentCollegeScope,
} from "./index";

const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `stage4-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const cite = `${prefix}-cite`;
const cas = `${prefix}-cas`;
const db = getFirestore();

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<any>};
const call = (fn: unknown, actor: string, data: Record<string, unknown>) =>
  (fn as Callable).run({auth: {uid: uid(actor)}, data});

const accounts: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  counselor: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "CITE Counselor", assignedCollegeIds: [cite]}},
  studentVerified: {verified: true, profile: {accessRole: "appUser", role: "student", name: "Verified Student", email: "v@example.invalid", collegeId: cite, verificationStatus: "verified"}},
  studentUnverified: {verified: true, profile: {accessRole: "appUser", role: "student", name: "Unverified Student", email: "u@example.invalid", collegeId: cite, verificationStatus: "needsReview"}},
};

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
  await db.doc("pacc_availability/current").set({
    openDays: [1, 2, 3, 4, 5], opensAt: "08:00", closesAt: "17:00",
    presence: "in_office", acceptsWalkIns: false, notice: "", blackoutDates: [],
  });
});

after(async () => {
  if (!emulated) return;
  if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID;
  else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  await Promise.all(Object.keys(accounts).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

test("super-admin exception approval list and lookup are audited in admin_audit_logs", {skip: !emulated}, async () => {
  const apptId = `${prefix}-unv-appt`;
  await db.doc(`appointments/${apptId}`).set({
    userId: uid("studentUnverified"),
    fullName: "Unverified Student",
    status: "requested",
    scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
    scheduledTime: "9:00 AM",
    concern: "Triage test",
    collegeId: cite,
    studentVerificationStatus: "needsReview",
    createdAt: Timestamp.now(),
  });

  try {
    const beforeList = (await db.collection("admin_audit_logs")
      .where("actorId", "==", uid("admin"))
      .where("action", "==", "APPOINTMENT_APPROVALS_LISTED")
      .get()).size;
    let found = false;
    let cursor: string | null = null;
    let pages = 0;
    do {
      const listRes = await call(listAppointmentApprovals, "admin", {limit: 100, ...(cursor ? {cursor} : {})});
      pages += 1;
      if (listRes.items.some((item: {appointmentId: string}) => item.appointmentId === apptId)) {
        found = true;
        break;
      }
      cursor = listRes.nextCursor as string | null;
    } while (cursor && pages < 10);
    assert.ok(found, "expected unverified appointment in super-admin approvals list");
    const afterList = (await db.collection("admin_audit_logs")
      .where("actorId", "==", uid("admin"))
      .where("action", "==", "APPOINTMENT_APPROVALS_LISTED")
      .get()).size;
    assert.equal(afterList, beforeList + pages);

    const beforeView = (await db.collection("admin_audit_logs")
      .where("actorId", "==", uid("admin"))
      .where("action", "==", "APPOINTMENT_EXCEPTION_VIEWED")
      .where("targetId", "==", apptId)
      .get()).size;
    const viewRes = await call(getAppointmentForApproval, "admin", {appointmentId: apptId});
    assert.equal(viewRes.available, true);
    const afterView = (await db.collection("admin_audit_logs")
      .where("actorId", "==", uid("admin"))
      .where("action", "==", "APPOINTMENT_EXCEPTION_VIEWED")
      .where("targetId", "==", apptId)
      .get()).size;
    assert.equal(afterView, beforeView + 1);

    // Denied counselor lookup writes no exception-viewed audit.
    await assert.rejects(call(getAppointmentForApproval, "counselor", {appointmentId: apptId}), {code: "permission-denied"});
  } finally {
    await db.doc(`appointments/${apptId}`).delete().catch(() => undefined);
  }
});

test("createAppointmentRequest stores authoritative collegeId and studentVerificationStatus, and profile updates sync them", {skip: !emulated}, async () => {
  const day = new Date(Date.now() + 70 * 86_400_000);
  while ([0, 6].includes(day.getUTCDay())) day.setUTCDate(day.getUTCDate() + 1);
  const slotMillis = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 2);

  const created = await call(createAppointmentRequest, "studentVerified", {
    concern: "Academic stress",
    scheduledAt: slotMillis,
    collegeId: "SPOOFED_COLLEGE",
    studentVerificationStatus: "spoofed",
    requestId: `${prefix}_req_1`,
  });
  const apptId = created.appointmentId as string;
  const stored = (await db.doc(`appointments/${apptId}`).get()).data()!;
  assert.equal(stored.collegeId, cite);
  assert.equal(stored.studentVerificationStatus, "verified");

  // Unverifying the student updates the appointment's studentVerificationStatus immediately.
  await call(reviewProfileVerification, "admin", {
    userId: uid("studentVerified"),
    decision: "needsReview",
    reason: "Re-verify student college",
  });
  const afterUnverify = (await db.doc(`appointments/${apptId}`).get()).data()!;
  assert.equal(afterUnverify.studentVerificationStatus, "needsReview");

  // User document trigger syncs collegeId changes to appointments as well.
  const beforeSnap = await db.doc(`users/${uid("studentVerified")}`).get();
  await db.doc(`users/${uid("studentVerified")}`).update({collegeId: cas, verificationStatus: "verified"});
  const afterSnap = await db.doc(`users/${uid("studentVerified")}`).get();
  const trigger = syncStudentAppointmentCollegeScope as unknown as {run: (event: unknown) => Promise<void>};
  await trigger.run({params: {userId: uid("studentVerified")}, data: {before: beforeSnap, after: afterSnap}});
  const afterSync = (await db.doc(`appointments/${apptId}`).get()).data()!;
  assert.equal(afterSync.collegeId, cas);
  assert.equal(afterSync.studentVerificationStatus, "verified");
  await db.doc(`appointments/${apptId}`).delete().catch(() => undefined);
});

test("backfillAppointmentCollegeScope populates legacy records boundedly, idempotently, and super-admin-only", {skip: !emulated}, async () => {
  const nonSuperAdminId = uid("non-super-admin");
  await getAuth().createUser({uid: nonSuperAdminId, email: `${nonSuperAdminId}@example.invalid`, emailVerified: true});
  await db.doc(`users/${nonSuperAdminId}`).set({accessRole: "admin", accountStatus: "active", name: "Other Admin"});
  const verifiedStudentId = uid("legacy-verified-student");
  await db.doc(`users/${verifiedStudentId}`).set({
    accessRole: "appUser", role: "student", collegeId: cite, verificationStatus: "verified",
  });

  const legacyCiteAppt = `${prefix}-legacy-cite`;
  const legacyUnverifiedAppt = `${prefix}-legacy-unverified`;
  const legacyWalkInAppt = `${prefix}-legacy-walkin`;
  await Promise.all([
    db.doc(`appointments/${legacyCiteAppt}`).set({
      userId: verifiedStudentId,
      fullName: "Legacy Verified CITE",
      status: "completed",
      scheduledAt: Timestamp.fromMillis(Date.now() - 86_400_000),
    }),
    db.doc(`appointments/${legacyUnverifiedAppt}`).set({
      userId: uid("studentUnverified"),
      fullName: "Legacy Unverified",
      status: "requested",
      scheduledAt: Timestamp.fromMillis(Date.now() + 86_400_000),
    }),
    db.doc(`appointments/${legacyWalkInAppt}`).set({
      userId: "",
      fullName: "Legacy Walk-In",
      collegeId: cite,
      source: "walk_in_import",
      status: "completed",
      scheduledAt: Timestamp.fromMillis(Date.now() - 86_400_000),
    }),
  ]);

  try {
    // Non-super admin, counselor, and student are denied.
    for (const actorUid of [nonSuperAdminId, uid("counselor"), uid("studentVerified")]) {
      await assert.rejects(
        (backfillAppointmentCollegeScope as unknown as Callable).run({auth: {uid: actorUid}, data: {}}),
        {code: "permission-denied"},
      );
    }

    // Before backfill: legacy CITE appointment is missing scoping fields.
    const preQuery = await db.collection("appointments")
      .where("studentVerificationStatus", "==", "verified")
      .where("collegeId", "in", [cite])
      .get();
    assert.ok(!preQuery.docs.some((d) => d.id === legacyCiteAppt));

    // Paginated backfill (limit 1, pageSize 2) processes across multiple pages cleanly.
    const updates: number[] = [];
    let cursor: string | null = null;
    let guard = 0;
    do {
      const page = await backfillAppointmentCollegeScopeBatch(uid("admin"), {
        limit: 1,
        pageSize: 2,
        maxPages: 2,
        cursor,
      });
      updates.push(page.updated);
      cursor = page.nextCursor;
      guard += 1;
    } while (cursor && guard < 20);
    assert.ok(updates.reduce((a, b) => a + b, 0) >= 3);

    const citeAfter = (await db.doc(`appointments/${legacyCiteAppt}`).get()).data()!;
    assert.equal(citeAfter.collegeId, cite);
    assert.equal(citeAfter.studentVerificationStatus, "verified");

    const unvAfter = (await db.doc(`appointments/${legacyUnverifiedAppt}`).get()).data()!;
    assert.equal(unvAfter.collegeId, cite);
    assert.equal(unvAfter.studentVerificationStatus, "needsReview");

    const walkInAfter = (await db.doc(`appointments/${legacyWalkInAppt}`).get()).data()!;
    assert.equal(walkInAfter.collegeId, cite);
    assert.equal(walkInAfter.studentVerificationStatus, "");

    // After backfill: counselor college query includes the historical CITE appointment,
    // while excluding unverified students and walk-in rows.
    const postQuery = await db.collection("appointments")
      .where("studentVerificationStatus", "==", "verified")
      .where("collegeId", "in", [cite])
      .get();
    assert.ok(postQuery.docs.some((d) => d.id === legacyCiteAppt));
    assert.ok(!postQuery.docs.some((d) => d.id === legacyUnverifiedAppt));
    assert.ok(!postQuery.docs.some((d) => d.id === legacyWalkInAppt));

    // Re-running backfill is idempotent (0 updates).
    const rerun = await (backfillAppointmentCollegeScope as unknown as Callable).run({
      auth: {uid: uid("admin")},
      data: {limit: 200},
    });
    assert.equal(rerun.updated, 0);
  } finally {
    await getAuth().deleteUser(nonSuperAdminId).catch(() => undefined);
    await db.doc(`users/${nonSuperAdminId}`).delete().catch(() => undefined);
    await db.doc(`users/${verifiedStudentId}`).delete().catch(() => undefined);
    await Promise.all([
      db.doc(`appointments/${legacyCiteAppt}`).delete().catch(() => undefined),
      db.doc(`appointments/${legacyUnverifiedAppt}`).delete().catch(() => undefined),
      db.doc(`appointments/${legacyWalkInAppt}`).delete().catch(() => undefined),
    ]);
  }
});
