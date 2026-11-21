import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  archiveAppointments,
  changeAppointmentAgreement,
  notifyPortalOfAppointment,
  notifyPortalOfStudentAppointmentAction,
  savePaccAvailability,
} from "./index";

const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `stage2-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const cite = `${prefix}-cite`;
const cas = `${prefix}-cas`;
const db = getFirestore();

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<any>};
const call = (fn: unknown, actor: string, data: Record<string, unknown>) =>
  (fn as Callable).run({auth: {uid: uid(actor)}, data});

async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => (e as {code?: string})?.code === code, `expected ${code}`);
}

const staff: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  otherAdmin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Other Admin"}},
  cCite: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "CITE Counselor", assignedCollegeIds: [cite]}},
  cCas: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "CAS Counselor", assignedCollegeIds: [cas]}},
  cSuspended: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "disabled", accountStatus: "suspended", name: "Suspended", assignedCollegeIds: [cite]}},
  cUnverified: {verified: false, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Unverified", assignedCollegeIds: [cite]}},
  ops: {verified: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", name: "Portal Staff", assignedCollegeIds: [cite]}},
};

const students: Record<string, Record<string, unknown>> = {
  cite: {accessRole: "appUser", verificationStatus: "verified", collegeId: cite},
  cas: {accessRole: "appUser", verificationStatus: "verified", collegeId: cas},
  unverified: {accessRole: "appUser", verificationStatus: "needsReview", collegeId: cite},
};

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
    await db.doc(`users/${uid(`student-${name}`)}`).set(profile);
  }
  await db.doc(`colleges/${cite}`).set({name: "CITE", code: "CITE", active: true});
  await db.doc(`colleges/${cas}`).set({name: "CAS", code: "CAS", active: true});
});

after(async () => {
  if (!emulated) return;
  if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID;
  else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  await Promise.all(Object.keys(staff).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

test("archiveAppointments enforces counselor-only college scope and denies admins without writes", {skip: !emulated}, async () => {
  const citeAppt = `${prefix}-arch-cite`;
  const unvAppt = `${prefix}-arch-unv`;
  await Promise.all([
    db.doc(`appointments/${citeAppt}`).set({userId: uid("student-cite"), status: "completed", scheduledAt: Timestamp.now()}),
    db.doc(`appointments/${unvAppt}`).set({userId: uid("student-unverified"), status: "completed", scheduledAt: Timestamp.now()}),
  ]);

  for (const actor of ["ops", "admin", "otherAdmin", "cCas", "cSuspended", "cUnverified"]) {
    await rejects(call(archiveAppointments, actor, {appointmentIds: [citeAppt], archived: true}), "permission-denied");
  }
  // Counselor cannot archive unverified student's appointment (triage only).
  await rejects(call(archiveAppointments, "cCite", {appointmentIds: [unvAppt], archived: true}), "permission-denied");
  // Mixed batch containing an out-of-scope appointment fails atomically without writing either.
  await rejects(call(archiveAppointments, "cCite", {appointmentIds: [citeAppt, unvAppt], archived: true}), "permission-denied");
  assert.equal((await db.doc(`appointments/${citeAppt}`).get()).data()?.archivedAt, undefined);

  // Assigned counselor archives and restores cite appointment; admins are denied even with an exceptionReason.
  await call(archiveAppointments, "cCite", {appointmentIds: [citeAppt], archived: true});
  assert.ok((await db.doc(`appointments/${citeAppt}`).get()).data()?.archivedAt);
  await rejects(call(archiveAppointments, "admin", {appointmentIds: [citeAppt], archived: false}), "permission-denied");
  await rejects(call(archiveAppointments, "admin", {appointmentIds: [citeAppt], archived: false, exceptionReason: "Restore after review"}), "permission-denied");
  assert.ok((await db.doc(`appointments/${citeAppt}`).get()).data()?.archivedAt);
  await call(archiveAppointments, "cCite", {appointmentIds: [citeAppt], archived: false});
  assert.equal((await db.doc(`appointments/${citeAppt}`).get()).data()?.archivedAt, undefined);

  // Admin cannot archive unverified student's appointment either (read-only).
  await rejects(call(archiveAppointments, "admin", {appointmentIds: [unvAppt], archived: true}), "permission-denied");
  assert.equal((await db.doc(`appointments/${unvAppt}`).get()).data()?.archivedAt, undefined);
});

test("appointment portal notifications route only to assigned college counselors or super-admin for exceptions", {skip: !emulated}, async () => {
  const day = new Date(Date.now() + 60 * 86_400_000);
  while ([0, 6].includes(day.getUTCDay())) day.setUTCDate(day.getUTCDate() + 1);
  const a = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 1);
  const b = a + 3600_000;
  await db.doc("pacc_availability/current").set({
    openDays: [1, 2, 3, 4, 5], opensAt: "08:00", closesAt: "17:00",
    presence: "in_office", acceptsWalkIns: false, notice: "", blackoutDates: [],
  });

  const citeAppt = `${prefix}-notif-cite`;
  const unvAppt = `${prefix}-notif-unv`;
  await Promise.all([
    db.doc(`appointments/${citeAppt}`).set({
      userId: uid("student-cite"), status: "confirmed", scheduleRevision: 0, proposalRevision: 0,
      scheduledAt: Timestamp.fromMillis(a), scheduledTime: "9:00 AM", concern: "PRIVATE",
    }),
    db.doc(`appointment_slots/pacc_${a}`).set({appointmentId: citeAppt}),
    db.doc(`appointment_user_locks/${uid("student-cite")}`).set({appointmentId: citeAppt}),
    db.doc(`appointments/${unvAppt}`).set({
      userId: uid("student-unverified"), status: "requested", scheduleRevision: 0, proposalRevision: 0,
      scheduledAt: Timestamp.fromMillis(b), scheduledTime: "10:00 AM", concern: "PRIVATE",
    }),
  ]);

  const onCreate = notifyPortalOfAppointment as unknown as {run: (event: unknown) => Promise<void>};
  await onCreate.run({params: {appointmentId: citeAppt}});
  await onCreate.run({params: {appointmentId: unvAppt}});

  const citeNotes = (await db.collection("notifications").where("appointmentId", "==", citeAppt).get()).docs.map((d) => d.data().userId);
  assert.deepEqual(citeNotes.sort(), [uid("cCite")]);

  const unvNotes = (await db.collection("notifications").where("appointmentId", "==", unvAppt).get()).docs.map((d) => d.data().userId);
  assert.deepEqual(unvNotes.sort(), [uid("admin")]);

  // Student agreement proposal routes only to assigned college counselors.
  await call(changeAppointmentAgreement, "student-cite", {
    appointmentId: citeAppt, action: "propose", requestId: `${prefix}_prop_1`,
    scheduledAt: b, expectedScheduledAt: a, expectedScheduleRevision: 0, expectedProposalRevision: 0,
  });
  const agreementNotes = (await db.collection("notifications")
    .where("appointmentId", "==", citeAppt)
    .where("agreementEvent", "==", "appointment_schedule_proposed")
    .get()).docs.map((d) => d.data().userId);
  assert.deepEqual(agreementNotes.sort(), [uid("cCite")]);

  // Legacy student schedule edit trigger routes only to assigned college counselors.
  const beforeSnap = await db.doc(`appointments/${citeAppt}`).get();
  await db.doc(`appointments/${citeAppt}`).update({status: "requested", studentScheduleRequestId: `${prefix}_legacy_req`});
  const afterSnap = await db.doc(`appointments/${citeAppt}`).get();
  const onUpdate = notifyPortalOfStudentAppointmentAction as unknown as {run: (event: unknown) => Promise<void>};
  await onUpdate.run({params: {appointmentId: citeAppt}, data: {before: beforeSnap, after: afterSnap}});
  const legacyTriggerNotes = (await db.collection("notifications")
    .where("appointmentId", "==", citeAppt)
    .where("studentScheduleRequestId", "==", `${prefix}_legacy_req`)
    .get()).docs.map((d) => d.data().userId);
  assert.deepEqual(legacyTriggerNotes.sort(), [uid("cCite")]);
});

test("savePaccAvailability scopes returned conflict details for counselors to their assigned colleges", {skip: !emulated}, async () => {
  const scheduledAt = new Date("2027-02-01T01:00:00.000Z"); // Monday 09:00 Asia/Manila
  const citeConflict = `${prefix}-conf-cite`;
  const casConflict = `${prefix}-conf-cas`;
  const unvConflict = `${prefix}-conf-unv`;
  await Promise.all([
    db.doc(`appointments/${citeConflict}`).set({userId: uid("student-cite"), status: "confirmed", scheduledAt}),
    db.doc(`appointments/${casConflict}`).set({userId: uid("student-cas"), status: "confirmed", scheduledAt}),
    db.doc(`appointments/${unvConflict}`).set({userId: uid("student-unverified"), status: "confirmed", scheduledAt}),
  ]);
  const v2 = {
    schemaVersion: 2, timezone: "Asia/Manila", notice: "",
    weekdays: Object.fromEntries(Array.from({length: 7}, (_, i) => [
      String(i + 1),
      {enabled: i < 5, opensAt: "09:00", closesAt: "17:00", presence: i < 5 ? "in_office" : "out_of_office", appointmentsEnabled: i < 5, acceptsWalkIns: false},
    ])),
    overrides: [{date: "2027-02-01", closedAllDay: true, reason: "Holiday"}],
  };
  await db.doc("pacc_availability/current").set({...v2, overrides: [], revision: 0});
  const res = await call(savePaccAvailability, "cCite", {
    availability: v2, expectedRevision: 0, confirmConflicts: true,
  }) as {conflicts: Array<{appointmentId: string}>};
  const ids = res.conflicts.map((c) => c.appointmentId);
  assert.equal(ids.includes(citeConflict), true);
  assert.equal(ids.includes(casConflict), false);
  assert.equal(ids.includes(unvConflict), false);
});
