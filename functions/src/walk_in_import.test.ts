import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  archiveWalkInImport,
  deleteWalkInImport,
  importWalkInAppointments,
  listWalkInImports,
} from "./index";

const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `walkin-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const cite = `${prefix}-cite`;
const cas = `${prefix}-cas`;
const db = getFirestore();

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<any>};
const call = (fn: unknown, actor: string, data: Record<string, unknown>) =>
  (fn as Callable).run({auth: {uid: uid(actor)}, data});

async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => e instanceof HttpsError && e.code === code, `expected ${code}`);
}

const accounts: Record<string, {verified: boolean; disabled?: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  otherAdmin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Other Admin"}},
  adminSuspended: {verified: true, profile: {accessRole: "admin", accountStatus: "suspended", name: "Suspended Admin"}},
  cCite: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "CITE Counselor", assignedCollegeIds: [cite]}},
  cCas: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "CAS Counselor", assignedCollegeIds: [cas]}},
  cEmpty: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Empty Counselor", assignedCollegeIds: []}},
  cSuspended: {verified: true, profile: {accessRole: "counselor", staffAccountStatus: "disabled", accountStatus: "suspended", name: "Suspended Counselor", assignedCollegeIds: [cite]}},
  cLegacySuspended: {verified: true, profile: {accessRole: "counselor", accountStatus: "suspended", name: "Legacy Suspended", assignedCollegeIds: [cite]}},
  cUnverified: {verified: false, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Unverified Counselor", assignedCollegeIds: [cite]}},
  cDisabledAuth: {verified: true, disabled: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", name: "Disabled Auth", assignedCollegeIds: [cite]}},
  staff: {verified: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", name: "Portal Staff"}},
  student: {verified: true, profile: {accessRole: "appUser", role: "student", name: "Student"}},
};

let previousSuperAdmin: string | undefined;
before(async () => {
  if (!emulated) return;
  previousSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = uid("admin");
  for (const [name, account] of Object.entries(accounts)) {
    await getAuth().createUser({
      uid: uid(name),
      email: `${uid(name)}@example.invalid`,
      emailVerified: account.verified,
      disabled: account.disabled === true,
    });
    await db.doc(`users/${uid(name)}`).set(account.profile);
  }
  await db.doc(`colleges/${cite}`).set({name: "College of IT", code: "CITE", active: true});
  await db.doc(`colleges/${cas}`).set({name: "College of Arts", code: "CAS", active: true});
});

after(async () => {
  if (!emulated) return;
  if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID;
  else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  await Promise.all(Object.keys(accounts).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

const row = (department: string) => ({
  fullName: "Walk In Student",
  studentId: "2026-0001",
  department,
  course: "BSIT",
  yearLevel: "Year 1",
  loggedAt: "2026-11-18",
});

test("walk-in import denies suspended, unverified, disabled, operational staff, non-super admin, and cross-college counselors", {skip: !emulated}, async () => {
  for (const actor of ["cSuspended", "cLegacySuspended", "cUnverified", "cDisabledAuth", "staff", "student", "otherAdmin", "adminSuspended", "cEmpty", "cCas"]) {
    await rejects(call(importWalkInAppointments, actor, {rows: [row("College of IT")], fileName: "cite.csv"}), "permission-denied");
  }
  await rejects(call(importWalkInAppointments, "cCite", {
    rows: [row("College of IT"), row("College of Arts")],
    fileName: "mixed.csv",
  }), "permission-denied");
});

test("walk-in import allows assigned-college counselor and super-admin with audit", {skip: !emulated}, async () => {
  const counselorRes = await call(importWalkInAppointments, "cCite", {
    rows: [row("College of IT")],
    fileName: "cite-only.csv",
  });
  assert.equal(counselorRes.imported, 1);

  const adminRes = await call(importWalkInAppointments, "admin", {
    rows: [row("College of Arts")],
    fileName: "cas-admin.csv",
  });
  assert.equal(adminRes.imported, 1);

  const audits = await db.collection("admin_audit_logs")
    .where("action", "==", "WALK_IN_APPOINTMENTS_IMPORTED")
    .where("actorId", "in", [uid("cCite"), uid("admin")])
    .get();
  assert.equal(audits.size, 2);
});

test("walk-in management callables require configured active verified super-admin", {skip: !emulated}, async () => {
  for (const actor of ["cCite", "staff", "student", "otherAdmin", "adminSuspended"]) {
    await rejects(call(listWalkInImports, actor, {}), "permission-denied");
    await rejects(call(archiveWalkInImport, actor, {importId: "missing", archived: true}), "permission-denied");
    await rejects(call(deleteWalkInImport, actor, {importId: "missing"}), "permission-denied");
  }

  const listed = await call(listWalkInImports, "admin", {});
  assert.ok(Array.isArray(listed.files));
  const target = listed.files.find((f: {fileName: string}) => f.fileName === "cas-admin.csv");
  assert.ok(target);
  await call(archiveWalkInImport, "admin", {importId: target.id, archived: true});
  await call(deleteWalkInImport, "admin", {importId: target.id});
});
