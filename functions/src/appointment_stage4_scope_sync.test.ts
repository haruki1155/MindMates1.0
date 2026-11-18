import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

import {
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

  const beforeList = (await db.collection("admin_audit_logs")
    .where("actorId", "==", uid("admin"))
    .where("action", "==", "APPOINTMENT_APPROVALS_LISTED")
    .get()).size;
  const listRes = await call(listAppointmentApprovals, "admin", {limit: 10});
  assert.ok(listRes.items.some((item: {appointmentId: string}) => item.appointmentId === apptId));
  const afterList = (await db.collection("admin_audit_logs")
    .where("actorId", "==", uid("admin"))
    .where("action", "==", "APPOINTMENT_APPROVALS_LISTED")
    .get()).size;
  assert.equal(afterList, beforeList + 1);

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
});
