import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {getStudentCaseHistory, readStudentAppointments} from "./student_case_history_callable";

// Auth + Firestore emulators. Exercises the real callable and the shared
// staff gate (functions/src/access.ts), so every actor is a real verified
// Auth user created here.
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `history-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const cite = `${prefix}-cite`;
const cas = `${prefix}-cas`;
const db = getFirestore();

type Result = {
  student: {id: string; displayName: string; collegeId: string};
  basis: string;
  items: Array<Record<string, unknown>>;
  nextCursor: string | null;
  truncated: boolean;
};
const callable = getStudentCaseHistory as unknown as {run: (r: {auth?: {uid: string}; data?: unknown}) => Promise<Result>};

const counselorProfile = {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"};
const accounts: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active", name: "Super Admin"}},
  "other-admin": {verified: true, profile: {accessRole: "admin", accountStatus: "active"}},
  "cite-counselor": {verified: true, profile: {...counselorProfile, name: "Coach Cite", assignedCollegeIds: [cite]}},
  "cas-counselor": {verified: true, profile: {...counselorProfile, assignedCollegeIds: [cas]}},
  "case-counselor": {verified: true, profile: {...counselorProfile, assignedCollegeIds: []}},
  "suspended-counselor": {verified: true, profile: {...counselorProfile, accountStatus: "suspended", assignedCollegeIds: [cite]}},
  "unverified-counselor": {verified: false, profile: {...counselorProfile, assignedCollegeIds: [cite]}},
  staff: {verified: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: [cite]}},
  ana: {verified: true, profile: {accessRole: "appUser", role: "student", firstName: "Ana", lastName: "Cruz", collegeId: cite, verificationStatus: "verified"}},
  // Same display name, different verified identity.
  "ana-twin": {verified: true, profile: {accessRole: "appUser", role: "student", firstName: "Ana", lastName: "Cruz", collegeId: cite, verificationStatus: "verified"}},
};

const at = (iso: string) => Timestamp.fromDate(new Date(iso));
const appointments: Record<string, Record<string, unknown>> = {
  "ana-2025": {userId: uid("ana"), fullName: "Ana Cruz", status: "completed", scheduledAt: at("2025-09-10T01:00:00Z"), createdAt: at("2025-09-01T01:00:00Z"), archivedAt: at("2025-12-01T00:00:00Z"), concern: "Exams", actionByName: "Coach Cite", contactNumber: "0917-000", email: "ana@example.invalid"},
  "ana-2026-a": {userId: uid("ana"), fullName: "Ana Cruz", status: "confirmed", scheduledAt: at("2026-03-02T01:00:00Z"), createdAt: at("2026-02-20T01:00:00Z"), concern: "Sleep", assignedStaffId: uid("case-counselor")},
  "ana-2026-b": {userId: uid("ana"), fullName: "Ana Cruz", status: "pending", scheduledAt: at("2026-04-02T01:00:00Z"), createdAt: at("2026-03-20T01:00:00Z"), concern: "Follow-up"},
  "ana-legacy": {userId: uid("ana"), fullName: "Ana Cruz", status: "completed", concern: "Legacy walk-in"},
  "twin-2026": {userId: uid("ana-twin"), fullName: "Ana Cruz", status: "requested", scheduledAt: at("2026-05-02T01:00:00Z"), concern: "Not Ana's"},
};
const anaOrder = ["ana-2026-b", "ana-2026-a", "ana-2025", "ana-legacy"];
const id = (name: string) => `${prefix}-${name}`;

async function run(actor: string, data: Record<string, unknown>) {
  return callable.run({auth: {uid: uid(actor)}, data});
}
async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => e instanceof HttpsError && e.code === code);
}
async function audits(student: string): Promise<FirebaseFirestore.DocumentData[]> {
  const rows = await db.collection("admin_audit_logs").where("action", "==", "COUNSELING_HISTORY_VIEWED").where("targetId", "==", uid(student)).get();
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
  for (const [name, data] of Object.entries(appointments)) await db.doc(`appointments/${id(name)}`).set(data);
  await db.doc(`appointments/${id("ana-2025")}/clinical_notes/n1`).set({note: "PRIVATE CLINICAL NOTE"});
});

after(async () => {
  if (!emulated) return;
  if (previousSuperAdmin == null) delete process.env.SUPER_ADMIN_UID; else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  await Promise.all(Object.keys(accounts).map((name) => getAuth().deleteUser(uid(name)).catch(() => undefined)));
});

test("a counselor for the student's college sees every current and archived case for that userId, newest first", {skip: !emulated}, async () => {
  const result = await run("cite-counselor", {studentId: uid("ana")});
  assert.equal(result.basis, "college");
  assert.deepEqual(result.student, {id: uid("ana"), displayName: "Ana Cruz", collegeId: cite});
  assert.deepEqual(result.items.map((item) => item.id), anaOrder.map(id));
  assert.equal(result.nextCursor, null);
  assert.equal(result.truncated, false);
  const archived = result.items.find((item) => item.id === id("ana-2025"))!;
  assert.deepEqual([archived.archived, archived.status, archived.counselorName], [true, "completed", "Coach Cite"]);
  assert.equal(result.items.find((item) => item.id === id("ana-2026-b"))!.status, "requested");
  assert.equal(result.items.find((item) => item.id === id("ana-legacy"))!.hasSchedule, false);
});

test("matching is by verified userId: a student with the same name is never included", {skip: !emulated}, async () => {
  const ana = await run("cite-counselor", {studentId: uid("ana")});
  assert.ok(!ana.items.some((item) => item.id === id("twin-2026")));
  const twin = await run("cite-counselor", {studentId: uid("ana-twin")});
  assert.deepEqual(twin.items.map((item) => item.id), [id("twin-2026")]);
});

test("entries never carry contact details or clinical notes", {skip: !emulated}, async () => {
  const text = JSON.stringify(await run("cite-counselor", {studentId: uid("ana")}));
  for (const secret of ["PRIVATE CLINICAL NOTE", "0917-000", "ana@example.invalid", "clinical_notes", "contactNumber"]) {
    assert.ok(!text.includes(secret), `${secret} leaked`);
  }
});

test("pagination returns every case exactly once and every page is audited", {skip: !emulated}, async () => {
  const before = (await audits("ana-twin")).length;
  const first = await run("cite-counselor", {studentId: uid("ana-twin"), pageSize: 1});
  assert.equal(first.nextCursor, null);
  assert.equal((await audits("ana-twin")).length, before + 1);

  const auditsBefore = (await audits("ana")).length;
  const seen: string[] = [];
  let cursor: string | null = null;
  let pages = 0;
  do {
    const page: Result = await run("cite-counselor", {studentId: uid("ana"), pageSize: 3, ...(cursor ? {cursor} : {})});
    seen.push(...page.items.map((item) => String(item.id)));
    cursor = page.nextCursor;
    pages++;
  } while (cursor && pages < 5);
  assert.deepEqual(seen, anaOrder.map(id));
  assert.equal(pages, 2);
  const rows = await audits("ana");
  assert.equal(rows.length, auditsBefore + 2, "each page read is audited");
  const row = rows.find((r) => r.actorId === uid("cite-counselor") && r.metadata.page === "first")!;
  assert.deepEqual([row.targetType, row.metadata.basis, row.category], ["student", "college", "SECURITY"]);
  assert.ok(rows.some((r) => r.metadata.page === "next" && r.metadata.returned === 1));
  await rejects(run("cite-counselor", {studentId: uid("ana"), cursor: "garbage"}), "invalid-argument");
});

test("a counselor assigned to a past case without current college assignment is refused, and losing college assignment revokes access immediately", {skip: !emulated}, async () => {
  await rejects(run("case-counselor", {studentId: uid("ana")}), "permission-denied");
  await rejects(run("case-counselor", {studentId: uid("ana-twin")}), "permission-denied");

  // Granting cite allows access; revoking cite immediately denies subsequent access.
  await db.doc(`users/${uid("case-counselor")}`).update({assignedCollegeIds: [cite]});
  const granted = await run("case-counselor", {studentId: uid("ana")});
  assert.equal(granted.basis, "college");
  await db.doc(`users/${uid("case-counselor")}`).update({assignedCollegeIds: []});
  await rejects(run("case-counselor", {studentId: uid("ana")}), "permission-denied");
});

test("the configured super-administrator may view any student's history", {skip: !emulated}, async () => {
  const result = await run("admin", {studentId: uid("ana-twin")});
  assert.equal(result.basis, "super_admin");
  await rejects(run("admin", {studentId: uid("nobody")}), "not-found");
  await rejects(run("admin", {studentId: uid("cite-counselor")}), "failed-precondition");
});

test("unauthorized actors are refused and leave no audit record", {skip: !emulated}, async () => {
  const before = (await audits("ana")).length;
  for (const actor of ["cas-counselor", "other-admin", "staff", "suspended-counselor", "unverified-counselor", "ana", "ana-twin"]) {
    await rejects(run(actor, {studentId: uid("ana")}), "permission-denied");
  }
  await rejects(callable.run({data: {studentId: uid("ana")}}), "unauthenticated");
  assert.equal((await audits("ana")).length, before);
});

test("unknown students and staff targets look the same to a counselor; bad input is rejected", {skip: !emulated}, async () => {
  await rejects(run("cite-counselor", {studentId: uid("nobody")}), "permission-denied");
  await rejects(run("cite-counselor", {studentId: uid("cas-counselor")}), "permission-denied");
  await rejects(run("cite-counselor", {studentId: "../users"}), "invalid-argument");
  await rejects(run("cite-counselor", {}), "invalid-argument");
});

test("a forged cursor cannot read the history without an audit record", {skip: !emulated}, async () => {
  const before = (await audits("ana")).length;
  const forged = await run("cite-counselor", {studentId: uid("ana"), cursor: "9999999999999999|0", pageSize: 50});
  assert.deepEqual(forged.items.map((item) => item.id), anaOrder.map(id));
  const rows = await audits("ana");
  assert.equal(rows.length, before + 1);
  assert.ok(rows.some((r) => r.metadata.page === "next" && r.metadata.returned === anaOrder.length));
});

test("reading a long history keeps going past one batch and reports truncation at the cap", {skip: !emulated}, async () => {
  const all = await readStudentAppointments(db, uid("ana"), 2, 10);
  assert.deepEqual(all.records.map((r: {id: string}) => r.id).sort(), anaOrder.map(id).sort());
  assert.equal(all.truncated, false);
  const capped = await readStudentAppointments(db, uid("ana"), 2, 3);
  assert.equal(capped.records.length, 3);
  assert.equal(capped.truncated, true);
});
