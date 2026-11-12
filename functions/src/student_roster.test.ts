import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

import {importStudentRoster, previewStudentRosterImport} from "./index";
import {issueCodesFor, rosterTestHooks} from "./student_roster";
import {verifyActivationCode} from "./student_roster_domain";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<unknown>};
type Preview = {rows: {index: number; studentNo: string; kind: string; changes?: Record<string, {from: string; to: string}>; errors?: string[]}[];
  counts: Record<string, number>};
type Imported = {importId: string; counts: Record<string, number>; codes: {studentNo: string; code: string; expiresAt: string; name: string}[]};

const db = getFirestore();
const preview = previewStudentRosterImport as unknown as Callable;
const commit = importStudentRoster as unknown as Callable;
const run = `RT${Date.now()}`;
const adminUid = process.env.SUPER_ADMIN_UID ?? "";
const collegeId = `${run}-college`;
const departmentId = `${run}-dept`;
const courseId = `${run}-course`;
const collegeName = `${run} College`;
const courseName = `${run} Course`;
const keyOf = (n: string) => n.toUpperCase().replace(/[^A-Z0-9]/g, "");
const created: FirebaseFirestore.DocumentReference[] = [];
let adminCreated = false;

function row(n: string, extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {studentNo: `${run}-${n}`, surname: `Dela Cruz${n}`, firstName: "Juan", middleName: "Santos",
    dateOfBirth: "2004-05-06", college: collegeName, course: courseName, yearLevel: "2nd Year", ...extra};
}
const roster = (n: string) => db.collection("student_roster").doc(keyOf(`${run}-${n}`));
const rosterRange = () => db.collection("student_roster").where("studentKey", ">=", run).where("studentKey", "<", `${run}~`);
const rosterCount = async () => (await rosterRange().get()).size;
async function denied(p: Promise<unknown>, code: string) {
  await assert.rejects(p, (e: {code?: unknown}) => e?.code === code);
}
const auth = {uid: adminUid};

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST && adminUid, "emulator + SUPER_ADMIN_UID required");
  const admin = db.collection("users").doc(adminUid);
  if (!(await admin.get()).exists) {
    adminCreated = true;
    await admin.set({accessRole: "admin", firstName: "Test", lastName: "Admin", email: "a@example.com"});
  }
  await Promise.all([
    db.collection("colleges").doc(collegeId).set({name: collegeName, code: `${run}C`, active: true}),
    db.collection("departments").doc(departmentId).set({name: `${run} Dept`, collegeId, active: true}),
    db.collection("courses").doc(courseId).set({name: courseName, code: `${run}K`, collegeId, departmentId, active: true}),
  ]);
});

after(async () => {
  const docs = [
    db.collection("colleges").doc(collegeId), db.collection("departments").doc(departmentId),
    db.collection("courses").doc(courseId), ...created,
  ];
  const rosters = await rosterRange().get();
  const imports = await db.collection("student_roster_imports").where("actorId", "==", adminUid).get();
  const audits = await db.collection("admin_audit_logs").where("actorId", "==", adminUid).get();
  await Promise.all([...docs, ...rosters.docs.map((d) => d.ref), ...imports.docs.map((d) => d.ref),
    ...audits.docs.filter((d) => String(d.data().action).startsWith("STUDENT_")).map((d) => d.ref)].map((r) => r.delete()));
  if (adminCreated) await db.collection("users").doc(adminUid).delete();
});

test("callers must be admin and row counts bounded", async () => {
  await denied(preview.run({auth: {uid: `${run}-nobody`}, data: {fileName: "x", rows: [row("A")]}}), "permission-denied");
  await denied(preview.run({auth, data: {fileName: "x", rows: []}}), "invalid-argument");
  await denied(preview.run({auth, data: {fileName: "x", rows: "nope"}}), "invalid-argument");
  await denied(commit.run({auth, data: {fileName: "x", rows: Array.from({length: 1001}, (_, i) => row(`B${i}`))}}), "invalid-argument");
});

test("preview classifies rows and writes nothing", async () => {
  await roster("U1").set({studentKey: keyOf(`${run}-U1`), studentNo: `${run}-U1`, surname: "Dela CruzU1", firstName: "Juan", middleName: "Santos",
    dateOfBirthKey: "2004-05-06", college: collegeName, course: courseName, yearLevel: "2nd Year", status: "active", activated: false, userId: null});
  const linkUid = `${run}-linkuid-p`;
  await db.collection("users").doc(linkUid).set({firstName: "L", lastName: "P"});
  await db.collection("student_id_reservations").doc(keyOf(`${run}-L1`)).set({userId: linkUid});
  created.push(db.collection("users").doc(linkUid), db.collection("student_id_reservations").doc(keyOf(`${run}-L1`)));
  const before = await rosterCount();
  const out = await preview.run({auth, data: {fileName: "r.xlsx", rows: [
    row("N1"), row("U1", {yearLevel: "3"}), row("L1"), row("E1", {course: "Nope"}), null, "str",
  ]}}) as Preview;
  assert.deepEqual(out.rows.map((r) => r.kind), ["new", "update", "link", "error", "error", "error"]);
  assert.deepEqual(out.rows[1].changes?.yearLevel, {from: "2nd Year", to: "3rd Year"});
  assert.deepEqual(out.counts, {new: 1, update: 1, link: 1, error: 3});
  assert.equal(await rosterCount(), before);
});

test("import with an error row writes nothing", async () => {
  const before = await rosterCount();
  await denied(commit.run({auth, data: {fileName: "r.xlsx", rows: [row("G1"), row("G2", {course: "Nope"})]}}), "invalid-argument");
  assert.equal(await rosterCount(), before);
});

test("import creates roster rows, record, audit, and hashed codes only", async () => {
  const out = await commit.run({auth, data: {fileName: "r.xlsx", rows: [row("I1"), row("I2")]}}) as Imported;
  assert.deepEqual(out.counts, {new: 2, updated: 0, linked: 0});
  assert.equal(out.codes.length, 2);
  const doc = (await roster("I1").get()).data()!;
  assert.equal(doc.activated, false);
  assert.equal(doc.userId, null);
  assert.equal(doc.status, "active");
  assert.equal(doc.dateOfBirthKey, "2004-05-06");
  assert.ok(doc.dateOfBirth instanceof Timestamp);
  assert.equal(doc.dateOfBirth.toDate().toISOString(), "2004-05-06T00:00:00.000Z");
  assert.equal(doc.studentKey, keyOf(`${run}-I1`));
  assert.equal(doc.surnameNormalized, "delacruzi1");
  assert.ok(doc.activationCode.hash && doc.activationCode.salt);
  const rec = (await db.collection("student_roster_imports").doc(out.importId).get()).data()!;
  assert.deepEqual(rec.counts, {new: 2, updated: 0, linked: 0});
  const audits = await db.collection("admin_audit_logs").where("targetId", "==", out.importId).get();
  assert.equal(audits.size, 1);
  assert.equal(audits.docs[0].data().action, "STUDENT_ROSTER_IMPORTED");
  const blobs = [JSON.stringify(doc), JSON.stringify(rec), JSON.stringify(audits.docs[0].data())];
  for (const c of out.codes) for (const b of blobs) assert.ok(!b.includes(c.code) && !b.includes(c.code.replace("-", "")));
  assert.ok(out.codes.find((c) => c.studentNo === `${run}-I1`));
});

test("link case sets academic fields, keeps names, and records previous values", async () => {
  const uid = `${run}-linkuid`;
  const uid2 = `${run}-linkuid2`;
  await db.collection("users").doc(uid).set({firstName: "Old", lastName: "Name", name: "Old Name", yearLevel: "1st Year", course: "Old Course"});
  await db.collection("users").doc(uid2).set({firstName: "Two", lastName: "Name"});
  await db.collection("student_personal_info").doc(uid2).set({sex: "Male"});
  await db.collection("student_id_reservations").doc(keyOf(`${run}-K1`)).set({userId: uid});
  await db.collection("student_id_reservations").doc(keyOf(`${run}-K2`)).set({userId: uid2});
  created.push(db.collection("users").doc(uid), db.collection("users").doc(uid2), db.collection("student_personal_info").doc(uid2),
    db.collection("student_id_reservations").doc(keyOf(`${run}-K1`)), db.collection("student_id_reservations").doc(keyOf(`${run}-K2`)));
  const out = await commit.run({auth, data: {fileName: "r.xlsx", rows: [row("K1"), row("K2")]}}) as Imported;
  assert.deepEqual(out.counts, {new: 0, updated: 0, linked: 2});
  assert.equal(out.codes.length, 0);
  const r = (await roster("K1").get()).data()!;
  assert.equal(r.activated, true);
  assert.equal(r.userId, uid);
  assert.equal(r.activationCode, null);
  const u = (await db.collection("users").doc(uid).get()).data()!;
  assert.equal(u.firstName, "Old");
  assert.equal(u.lastName, "Name");
  assert.equal(u.name, "Old Name");
  assert.equal(u.rosterLinked, true);
  assert.equal(u.personalInfoRequired, true);
  assert.equal(u.yearLevel, "2nd Year");
  assert.equal(u.courseId, courseId);
  assert.equal(u.schoolId, `${run}-K1`);
  assert.equal(u.populationRole, "student");
  assert.equal((await db.collection("users").doc(uid2).get()).data()!.personalInfoRequired, false);
  const audit = (await db.collection("admin_audit_logs").where("targetId", "==", out.importId).get()).docs[0].data();
  assert.ok(JSON.stringify(audit.metadata).includes("1st Year"));
  assert.ok(JSON.stringify(audit.metadata).includes("Old Course"));
});

test("re-import keeps unactivated code and activated state", async () => {
  const first = (await roster("I1").get()).data()!;
  const out = await commit.run({auth, data: {fileName: "r.xlsx", rows: [row("I1", {yearLevel: "4"})]}}) as Imported;
  assert.deepEqual(out.counts, {new: 0, updated: 1, linked: 0});
  assert.equal(out.codes.length, 0);
  const again = (await roster("I1").get()).data()!;
  assert.equal(again.activationCode.hash, first.activationCode.hash);
  assert.equal(again.yearLevel, "4th Year");

  const uid = `${run}-actuid`;
  await db.collection("users").doc(uid).set({firstName: "A", lastName: "B", yearLevel: "1st Year"});
  await db.collection("student_personal_info").doc(uid).set({sex: "Female"});
  created.push(db.collection("users").doc(uid), db.collection("student_personal_info").doc(uid));
  await roster("A1").set({studentKey: keyOf(`${run}-A1`), studentNo: `${run}-A1`, surname: "Dela CruzA1", firstName: "Juan", middleName: "Santos",
    dateOfBirthKey: "2004-05-06", college: collegeName, course: courseName, yearLevel: "1st Year", status: "inactive", activated: true, userId: uid});
  const out2 = await commit.run({auth, data: {fileName: "r.xlsx", rows: [row("A1", {yearLevel: "3rd"})]}}) as Imported;
  assert.deepEqual(out2.counts, {new: 0, updated: 1, linked: 0});
  const a = (await roster("A1").get()).data()!;
  assert.equal(a.activated, true);
  assert.equal(a.userId, uid);
  assert.equal(a.status, "inactive");
  assert.equal(a.yearLevel, "3rd Year");
  const u = (await db.collection("users").doc(uid).get()).data()!;
  assert.equal(u.yearLevel, "3rd Year");
  assert.equal(u.firstName, "A");
  assert.deepEqual((await db.collection("student_personal_info").doc(uid).get()).data(), {sex: "Female"});
});

test("issueCodesFor overwrites codes only for active unactivated rows", async () => {
  const before = (await roster("I2").get()).data()!;
  const codes = await issueCodesFor([keyOf(`${run}-I2`), keyOf(`${run}-A1`), keyOf(`${run}-MISSING`)], adminUid);
  assert.equal(codes.length, 1);
  assert.equal(codes[0].studentNo, `${run}-I2`);
  const after = (await roster("I2").get()).data()!;
  assert.notEqual(after.activationCode.hash, before.activationCode.hash);
  assert.ok(!JSON.stringify(after).includes(codes[0].code));
});

test("successful import reports complete on response and record", async () => {
  const out = await commit.run({auth, data: {fileName: "r.xlsx", rows: [row("C1")]}}) as Imported & {status: string};
  assert.equal(out.status, "complete");
  const rec = (await db.collection("student_roster_imports").doc(out.importId).get()).data()!;
  assert.equal(rec.status, "complete");
  assert.deepEqual(rec.counts, {new: 1, updated: 0, linked: 0});
});

test("a failing later batch yields a partial result with codes only for committed rows", async () => {
  rosterTestHooks.batchLimit = 1;
  rosterTestHooks.afterClassify = async () => {
    await roster("P2").set({studentKey: keyOf(`${run}-P2`), concurrent: true});
  };
  try {
    const out = await commit.run({auth, data: {fileName: "r.xlsx", rows: [row("P1"), row("P2"), row("P3")]}}) as
      Imported & {status: string; failedRows: {studentNo: string}[]; message: string};
    assert.equal(out.status, "partial");
    assert.deepEqual(out.counts, {new: 1, updated: 0, linked: 0});
    assert.deepEqual(out.codes.map((c) => c.studentNo), [`${run}-P1`]);
    assert.deepEqual(out.failedRows.map((f) => f.studentNo), [`${run}-P2`, `${run}-P3`]);
    const stored = (await roster("P1").get()).data()!.activationCode;
    assert.ok(await verifyActivationCode(out.codes[0].code, {
      hash: stored.hash, salt: stored.salt, issuedAt: stored.issuedAt.toDate(), expiresAt: stored.expiresAt.toDate()}));
    assert.equal((await roster("P3").get()).exists, false);
    const rec = (await db.collection("student_roster_imports").doc(out.importId).get()).data()!;
    assert.equal(rec.status, "partial");
    assert.deepEqual(rec.counts, {new: 1, updated: 0, linked: 0});
    const audit = (await db.collection("admin_audit_logs").where("targetId", "==", out.importId).get()).docs[0].data();
    assert.deepEqual(audit.metadata.counts, {new: 1, updated: 0, linked: 0});
    assert.equal(audit.metadata.partial, true);
    assert.ok(!JSON.stringify([rec, audit]).includes(out.codes[0].code));
  } finally {
    rosterTestHooks.batchLimit = undefined;
    rosterTestHooks.afterClassify = undefined;
  }
});
