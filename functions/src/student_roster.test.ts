import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

import {
  activateStudentAccountDev, backfillStudentInfoRequirement, importStudentRoster, issueStudentActivationCodes,
  listLegacyStudentsNotInRoster, listStudentRoster, listStudentRosterImports, previewStudentRosterImport,
  resetStudentActivationLock, resolveSchoolIdAuthEmailDev, revokeStudentActivation, setStudentRosterStatus,
  updateStudentRosterRecord,
} from "./index";
import {issueCodesFor, rosterTestHooks} from "./student_roster";
import {verifyActivationCode} from "./student_roster_domain";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<unknown>};
type Preview = {rows: {index: number; studentNo: string; kind: string; changes?: Record<string, {from: string; to: string}>;
  errors?: string[]; warnings?: string[]}[];
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
// Cleanup is scoped to what this run created: the shared super-admin actor also owns imports and audit
// rows written by other suites, so deleting every STUDENT_* row of theirs would wipe their data too.
let suiteStart = Timestamp.now();
const ownedBy = (d: FirebaseFirestore.QueryDocumentSnapshot) => {
  const at = d.data().createdAt;
  return at instanceof Timestamp && at.toMillis() >= suiteStart.toMillis();
};

before(async () => {
  suiteStart = Timestamp.fromMillis(Date.now() - 1000);
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
  await Promise.all([...docs, ...rosters.docs.map((d) => d.ref), ...imports.docs.filter(ownedBy).map((d) => d.ref),
    ...audits.docs.filter((d) => String(d.data().action).startsWith("STUDENT_") && ownedBy(d)).map((d) => d.ref)]
    .map((r) => r.delete()));
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

test("a link row whose account carries a different identity is flagged but still links", async () => {
  const sameUid = `${run}-linkuid-same`;
  const diffUid = `${run}-linkuid-diff`;
  // Matching identity: no warning.
  await db.collection("users").doc(sameUid).set({firstName: "Juan", lastName: "Dela CruzW1", dateOfBirthKey: "2004-05-06"});
  // Someone else's Student No. typed into a pre-existing account.
  await db.collection("users").doc(diffUid).set({firstName: "Pedro", lastName: "Reyes", dateOfBirthKey: "1999-01-02"});
  await db.collection("student_id_reservations").doc(keyOf(`${run}-W1`)).set({userId: sameUid});
  await db.collection("student_id_reservations").doc(keyOf(`${run}-W2`)).set({userId: diffUid});
  created.push(db.collection("users").doc(sameUid), db.collection("users").doc(diffUid),
    db.collection("student_id_reservations").doc(keyOf(`${run}-W1`)), db.collection("student_id_reservations").doc(keyOf(`${run}-W2`)));

  const out = await preview.run({auth, data: {fileName: "r.xlsx", rows: [row("W1"), row("W2")]}}) as Preview;
  assert.deepEqual(out.rows.map((r) => r.kind), ["link", "link"]);
  assert.deepEqual(out.rows[0].warnings ?? [], []);
  const warnings = out.rows[1].warnings ?? [];
  assert.equal(warnings.length, 1);
  assert.ok(warnings[0].includes("Pedro Reyes"), warnings[0]);
  assert.ok(warnings[0].includes("1999-01-02"), warnings[0]);
  // A warning never blocks the import; linking must still proceed.
  const imported = await commit.run({auth, data: {fileName: "r.xlsx", rows: [row("W2")]}}) as Imported;
  assert.deepEqual(imported.counts, {new: 0, updated: 0, linked: 1});
  assert.equal((await roster("W2").get()).data()!.userId, diffUid);
  const audit = (await db.collection("admin_audit_logs").where("targetId", "==", imported.importId).get()).docs[0].data();
  const text = JSON.stringify(audit.metadata);
  assert.ok(text.includes("Pedro"), text);
  assert.ok(text.includes("Reyes"), text);
  assert.ok(text.includes("1999-01-02"), text);
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

// ------------------------------------------------------------------ management (Task 6)

const asCallable = (fn: unknown) => fn as Callable;
const listRoster = asCallable(listStudentRoster);
const listLegacy = asCallable(listLegacyStudentsNotInRoster);
const updateRecord = asCallable(updateStudentRosterRecord);
const setStatus = asCallable(setStudentRosterStatus);
const resetLock = asCallable(resetStudentActivationLock);
const listImports = asCallable(listStudentRosterImports);
const backfill = asCallable(backfillStudentInfoRequirement);
const issueCodes = asCallable(issueStudentActivationCodes);
const revoke = asCallable(revokeStudentActivation);
const activate = asCallable(activateStudentAccountDev);
const resolveEmail = asCallable(resolveSchoolIdAuthEmailDev);
const counselorUid = `${run}-counselor`;
const authUids: string[] = [];
type RowView = {studentNo: string; name: string; college: string; course: string; yearLevel: string; activated: boolean;
  status: string; personalInfoComplete: boolean; userId: string | null};
type Page = {rows: RowView[]; nextPageToken: string | null};

async function put(ref: FirebaseFirestore.DocumentReference, data: Record<string, unknown>) {
  await ref.set(data);
  created.push(ref);
  return ref;
}

async function importOne(n: string, extra: Record<string, unknown> = {}): Promise<string> {
  const out = await commit.run({auth, data: {fileName: `${run}-m.xlsx`, rows: [row(n, extra)]}}) as Imported;
  return out.codes[0].code;
}

async function activateRow(n: string, tag: string, code: string): Promise<{uid: string; email: string}> {
  const address = `${run.toLowerCase()}-${tag}@example.com`;
  await activate.run({data: {studentNo: `${run}-${n}`, activationCode: code, dateOfBirth: "2004-05-06", email: address,
    password: "Str0ngPass!"}});
  const uid = (await getAuth().getUserByEmail(address)).uid;
  authUids.push(uid);
  created.push(db.collection("users").doc(uid), db.collection("student_id_reservations").doc(keyOf(`${run}-${n}`)),
    db.collection("student_activation_attempts").doc(keyOf(`${run}-${n}`)));
  return {uid, email: address};
}

async function storedCodeVerifies(n: string, code: string): Promise<boolean> {
  const stored = (await roster(n).get()).data()!.activationCode;
  return verifyActivationCode(code, {hash: stored.hash, salt: stored.salt, issuedAt: stored.issuedAt.toDate(),
    expiresAt: stored.expiresAt.toDate()});
}

async function auditsFor(action: string): Promise<FirebaseFirestore.DocumentData[]> {
  const snap = await db.collection("admin_audit_logs").where("actorId", "==", adminUid).get();
  return snap.docs.map((d) => d.data()).filter((d) => d.action === action);
}

test("management callables are admin-only", async () => {
  await put(db.collection("users").doc(counselorUid), {accessRole: "counselor", role: "counselor", name: "C"});
  const c = {uid: counselorUid};
  await denied(listRoster.run({auth: c, data: {}}), "permission-denied");
  await denied(listLegacy.run({auth: c, data: {}}), "permission-denied");
  await denied(updateRecord.run({auth: c, data: {studentNo: `${run}-I1`, fields: {yearLevel: "1"}}}), "permission-denied");
  await denied(setStatus.run({auth: c, data: {studentNo: `${run}-I1`, status: "deactivated"}}), "permission-denied");
  await denied(resetLock.run({auth: c, data: {studentNo: `${run}-I1`}}), "permission-denied");
  await denied(listImports.run({auth: c, data: {}}), "permission-denied");
  await denied(backfill.run({auth: c, data: {}}), "permission-denied");
  await denied(issueCodes.run({auth: c, data: {studentNos: [`${run}-I1`]}}), "permission-denied");
  await denied(revoke.run({auth: c, data: {studentNo: `${run}-I1`, reason: "x"}}), "permission-denied");
});

test("listStudentRoster searches by surname prefix and Student No., filters infoIncomplete, never returns codes", async () => {
  await importOne("S1");
  await importOne("S2");
  const page = await listRoster.run({auth, data: {search: "dela", collegeId}}) as Page;
  const nos = page.rows.map((r) => r.studentNo);
  assert.ok(nos.includes(`${run}-S1`) && nos.includes(`${run}-S2`));
  assert.ok(page.rows.length <= 50);
  const s1 = page.rows.find((r) => r.studentNo === `${run}-S1`)!;
  assert.deepEqual(Object.keys(s1).sort(),
    ["activated", "college", "course", "name", "personalInfoComplete", "status", "studentNo", "userId", "yearLevel"]);
  assert.equal(s1.activated, false);
  assert.equal(s1.personalInfoComplete, false);
  assert.equal(s1.userId, null);
  assert.equal(s1.name, "Juan Santos Dela CruzS1");
  assert.ok(!JSON.stringify(page).includes("hash"));

  const exact = await listRoster.run({auth, data: {search: `${run.toLowerCase()} s1`}}) as Page;
  assert.deepEqual(exact.rows.map((r) => r.studentNo), [`${run}-S1`]);
  const none = await listRoster.run({auth, data: {search: "zzzz-no-such-surname"}}) as Page;
  assert.equal(none.rows.length, 0);

  // infoIncomplete: activated rows whose linked user still needs personal info
  const incomplete = `${run}-incomplete`;
  const complete = `${run}-complete`;
  await put(db.collection("users").doc(incomplete), {populationRole: "student", personalInfoRequired: true});
  await put(db.collection("users").doc(complete), {populationRole: "student", personalInfoRequired: false});
  await roster("S1").update({activated: true, userId: incomplete, activationCode: null});
  await roster("S2").update({activated: true, userId: complete, activationCode: null});
  const info = await listRoster.run({auth, data: {collegeId, status: "infoIncomplete"}}) as Page;
  const infoNos = info.rows.map((r) => r.studentNo);
  assert.ok(infoNos.includes(`${run}-S1`) && !infoNos.includes(`${run}-S2`));
  assert.ok(info.rows.every((r) => r.activated && !r.personalInfoComplete));
  const activated = await listRoster.run({auth, data: {collegeId, status: "activated", search: "delacruzs"}}) as Page;
  const s2 = activated.rows.find((r) => r.studentNo === `${run}-S2`)!;
  assert.equal(s2.personalInfoComplete, true);
  assert.equal(s2.userId, complete);
  const notActivated = await listRoster.run({auth, data: {collegeId, status: "notActivated"}}) as Page;
  assert.ok(!notActivated.rows.some((r) => r.studentNo === `${run}-S1` || r.studentNo === `${run}-S2`));
  await denied(listRoster.run({auth, data: {status: "bogus"}}), "invalid-argument");
  await roster("S1").update({activated: false, userId: null});
  await roster("S2").update({activated: false, userId: null});
});

test("listStudentRoster paginates 50 at a time", async () => {
  const rows = Array.from({length: 55}, (_, i) => row(`PG${String(i).padStart(2, "0")}`));
  await commit.run({auth, data: {fileName: `${run}-pg.xlsx`, rows}});
  const first = await listRoster.run({auth, data: {search: "delacruzpg", collegeId}}) as Page;
  assert.equal(first.rows.length, 50);
  assert.ok(first.nextPageToken);
  const second = await listRoster.run({auth, data: {search: "delacruzpg", collegeId, pageToken: first.nextPageToken}}) as Page;
  assert.equal(second.rows.length, 5);
  assert.equal(second.nextPageToken, null);
  const all = new Set([...first.rows, ...second.rows].map((r) => r.studentNo));
  assert.equal(all.size, 55);
  const unsearched = await listRoster.run({auth, data: {collegeId}}) as Page;
  assert.equal(unsearched.rows.length, 50);
  assert.ok(unsearched.nextPageToken);
});

test("setStudentRosterStatus disables and re-enables the linked Auth user and audits", async () => {
  const code = await importOne("ST1");
  const {uid} = await activateRow("ST1", "st1", code);
  assert.deepEqual(await setStatus.run({auth, data: {studentNo: `${run}-ST1`, status: "deactivated"}}), {ok: true});
  assert.equal((await getAuth().getUser(uid)).disabled, true);
  assert.equal((await roster("ST1").get()).data()!.status, "deactivated");
  await setStatus.run({auth, data: {studentNo: `${run}-ST1`, status: "active"}});
  assert.equal((await getAuth().getUser(uid)).disabled, false);
  assert.equal((await roster("ST1").get()).data()!.status, "active");
  const audits = (await auditsFor("STUDENT_ROSTER_STATUS_CHANGED")).filter((a) => a.targetId === keyOf(`${run}-ST1`));
  assert.equal(audits.length, 2);
  assert.equal(audits[0].category, "USER_MANAGEMENT");

  await importOne("ST2");
  await setStatus.run({auth, data: {studentNo: `${run}-ST2`, status: "deactivated"}});
  assert.equal((await roster("ST2").get()).data()!.status, "deactivated");
  // A linked uid without an Auth user is tolerated.
  await roster("ST2").update({activated: true, userId: `${run}-ghost`});
  await setStatus.run({auth, data: {studentNo: `${run}-ST2`, status: "active"}});
  await denied(setStatus.run({auth, data: {studentNo: `${run}-ST2`, status: "bogus"}}), "invalid-argument");
  await denied(setStatus.run({auth, data: {studentNo: `${run}-NOPE`, status: "active"}}), "not-found");
});

test("updateStudentRosterRecord validates, syncs linked users academic fields only, and audits", async () => {
  await importOne("UP1");
  const uid = `${run}-up1user`;
  await put(db.collection("users").doc(uid), {firstName: "Nick", lastName: "Name", yearLevel: "2nd Year", populationRole: "student"});
  await roster("UP1").update({activated: true, userId: uid});
  await denied(updateRecord.run({auth, data: {studentNo: `${run}-UP1`, fields: {yearLevel: "9"}}}), "invalid-argument");
  await denied(updateRecord.run({auth, data: {studentNo: `${run}-UP1`, fields: {course: "Nope"}}}), "invalid-argument");
  await denied(updateRecord.run({auth, data: {studentNo: `${run}-NOPE`, fields: {yearLevel: "1"}}}), "not-found");
  assert.deepEqual(await updateRecord.run({auth, data: {studentNo: `${run}-UP1`,
    fields: {yearLevel: "4", firstName: "Juanito", dateOfBirth: "2004-07-08"}}}), {ok: true});
  const r = (await roster("UP1").get()).data()!;
  assert.equal(r.yearLevel, "4th Year");
  assert.equal(r.firstName, "Juanito");
  assert.equal(r.dateOfBirthKey, "2004-07-08");
  assert.equal(r.activated, true);
  assert.equal(r.userId, uid);
  const u = (await db.collection("users").doc(uid).get()).data()!;
  assert.equal(u.yearLevel, "4th Year");
  assert.equal(u.dateOfBirthKey, "2004-07-08");
  assert.equal(u.firstName, "Nick");
  const audits = (await auditsFor("STUDENT_ROSTER_RECORD_UPDATED")).filter((a) => a.targetId === keyOf(`${run}-UP1`));
  assert.equal(audits.length, 1);
  assert.deepEqual(audits[0].metadata.changes.yearLevel, {from: "2nd Year", to: "4th Year"});
});

test("resetStudentActivationLock clears attempts and audits", async () => {
  await importOne("LK1");
  const attempts = db.collection("student_activation_attempts").doc(keyOf(`${run}-LK1`));
  await put(attempts, {failedCount: 5, lockedUntil: Timestamp.fromMillis(Date.now() + 60000)});
  assert.deepEqual(await resetLock.run({auth, data: {studentNo: `${run}-LK1`}}), {ok: true});
  assert.equal((await attempts.get()).exists, false);
  assert.equal((await auditsFor("STUDENT_ACTIVATION_LOCK_RESET")).filter((a) => a.targetId === keyOf(`${run}-LK1`)).length, 1);
});

test("listStudentRosterImports returns history with actor name", async () => {
  const out = await listImports.run({auth, data: {}}) as {imports: {id: string; fileName: string; counts: Record<string, number>;
    importedByName: string; importedAt: string}[]};
  const mine = out.imports.find((i) => i.fileName === `${run}-pg.xlsx`);
  assert.ok(mine);
  assert.deepEqual(mine.counts, {new: 55, updated: 0, linked: 0});
  assert.ok(mine.importedByName.length > 0);
  assert.ok(!Number.isNaN(Date.parse(mine.importedAt)));
});

test("issueStudentActivationCodes replaces the hash and skips ineligible rows", async () => {
  const oldCode = await importOne("IC1");
  await importOne("IC2");
  await roster("IC2").update({activated: true, userId: `${run}-ic2`});
  await importOne("IC3");
  await roster("IC3").update({status: "deactivated"});
  await denied(issueCodes.run({auth, data: {studentNos: []}}), "invalid-argument");
  await denied(issueCodes.run({auth, data: {studentNos: Array.from({length: 1001}, (_, i) => `${run}-${i}`)}}), "invalid-argument");
  const before = (await auditsFor("STUDENT_ACTIVATION_CODES_ISSUED")).length;
  const out = await issueCodes.run({auth, data: {studentNos: [`${run} ic1`, `${run}-IC2`, `${run}-IC3`, `${run}-NOPE`]}}) as
    {codes: {studentNo: string; code: string}[]; skipped: {studentNo: string; reason: string}[]};
  assert.deepEqual(out.codes.map((c) => c.studentNo), [`${run}-IC1`]);
  assert.deepEqual(out.skipped.map((s) => s.studentNo).sort(), [`${run}-IC2`, `${run}-IC3`, `${run}-NOPE`].sort());
  assert.ok(out.skipped.every((s) => s.reason.length > 0));
  assert.equal(await storedCodeVerifies("IC1", oldCode), false);
  assert.equal(await storedCodeVerifies("IC1", out.codes[0].code), true);
  const audits = await auditsFor("STUDENT_ACTIVATION_CODES_ISSUED");
  assert.equal(audits.length, before + 1);
  assert.ok(audits.some((a) => a.metadata?.count === 1 && Object.keys(a.metadata).length === 1));
  assert.ok(!JSON.stringify(audits).includes(out.codes[0].code));
});

test("revokeStudentActivation disables the claimant, frees the Student No., and issues a new code", async () => {
  const code = await importOne("RV1");
  const first = await activateRow("RV1", "rv1a", code);
  await denied(revoke.run({auth, data: {studentNo: `${run}-RV1`, reason: "  "}}), "invalid-argument");
  await denied(revoke.run({auth, data: {studentNo: `${run}-RV1`, reason: "x".repeat(501)}}), "invalid-argument");
  const out = await revoke.run({auth, data: {studentNo: `${run}-RV1`, reason: "Claimed by the wrong person"}}) as
    {code: {studentNo: string; code: string}};
  assert.equal(out.code.studentNo, `${run}-RV1`);
  assert.equal((await getAuth().getUser(first.uid)).disabled, true);
  const u = (await db.collection("users").doc(first.uid).get()).data()!;
  assert.equal(u.accountStatus, "revoked");
  assert.equal(u.rosterLinked, false);
  assert.equal(u.firstName, "Juan");
  assert.equal(u.email, first.email);
  assert.equal((await db.collection("student_id_reservations").doc(keyOf(`${run}-RV1`)).get()).exists, false);
  const r = (await roster("RV1").get()).data()!;
  assert.equal(r.activated, false);
  assert.equal(r.userId, null);
  assert.equal(r.consumedActivationCode, null);
  assert.ok(r.revokedUserIds.includes(first.uid));
  assert.ok(!JSON.stringify(r).includes(out.code.code.replace("-", "")));
  const audits = (await auditsFor("STUDENT_ACTIVATION_REVOKED")).filter((a) => a.targetId === keyOf(`${run}-RV1`));
  assert.equal(audits.length, 1);
  assert.equal(audits[0].metadata.reason, "Claimed by the wrong person");
  assert.ok(!JSON.stringify(audits[0]).includes(out.code.code.replace("-", "")));

  const second = await activateRow("RV1", "rv1b", out.code.code);
  assert.notEqual(second.uid, first.uid);
  assert.deepEqual(await resolveEmail.run({data: {schoolId: `${run}-RV1`}}), {email: second.email});

  await denied(revoke.run({auth, data: {studentNo: `${run}-S1`, reason: "nope"}}), "failed-precondition");
});

test("revokeStudentActivation tolerates a missing Auth user and users doc", async () => {
  await importOne("RV2");
  const ghost = `${run}-ghostuid`;
  const reservation = await put(db.collection("student_id_reservations").doc(keyOf(`${run}-RV2`)), {userId: ghost});
  await roster("RV2").update({activated: true, userId: ghost, activationCode: null});
  const out = await revoke.run({auth, data: {studentNo: `${run}-RV2`, reason: "Orphaned"}}) as {code: {code: string}};
  assert.ok(out.code.code);
  assert.equal((await reservation.get()).exists, false);
  assert.equal((await db.collection("users").doc(ghost).get()).exists, false);
  const r = (await roster("RV2").get()).data()!;
  assert.equal(r.activated, false);
  assert.ok(r.revokedUserIds.includes(ghost));
  assert.equal(await storedCodeVerifies("RV2", out.code.code), true);
});

/** Runs the backfill and asserts exactly one audit for this call, matched by actor, action and a time window. */
async function backfillAudited(): Promise<{flagged: number; notInRoster: number}> {
  const since = Date.now() - 1000;
  const out = await backfill.run({auth, data: {}}) as {flagged: number; notInRoster: number};
  const until = Date.now() + 1000;
  const mine = (await auditsFor("STUDENT_INFO_REQUIREMENT_BACKFILLED")).filter((a) => {
    const at = (a.createdAt as Timestamp).toMillis();
    return at >= since && at <= until && a.metadata?.flagged === out.flagged && a.metadata?.notInRoster === out.notInRoster;
  });
  assert.equal(mine.length, 1);
  assert.equal(mine[0].category, "USER_MANAGEMENT");
  assert.deepEqual(mine[0].metadata, {flagged: out.flagged, notInRoster: out.notInRoster});
  return out;
}

test("backfillStudentInfoRequirement flags students without personal info, idempotently", async () => {
  const missing = `${run}-bf-missing`;
  const has = `${run}-bf-has`;
  const teacher = `${run}-bf-teacher`;
  await put(db.collection("users").doc(missing), {populationRole: "student", schoolId: `${run}-BF1`, firstName: "Leo", lastName: "Legacy"});
  await put(db.collection("users").doc(has), {populationRole: "student", schoolId: `${run}-BF2`, rosterLinked: true});
  await put(db.collection("student_personal_info").doc(has), {sex: "Male"});
  await put(db.collection("users").doc(teacher), {populationRole: "teaching"});
  const out = await backfillAudited();
  assert.ok(out.flagged >= 1);
  assert.ok(out.notInRoster >= 1);
  assert.equal((await db.collection("users").doc(missing).get()).data()!.personalInfoRequired, true);
  assert.equal((await db.collection("users").doc(has).get()).data()!.personalInfoRequired, undefined);
  assert.equal((await db.collection("users").doc(teacher).get()).data()!.personalInfoRequired, undefined);
  const snapshot = (await db.collection("users").doc(missing).get()).updateTime;
  await backfillAudited();
  assert.deepEqual((await db.collection("users").doc(missing).get()).updateTime, snapshot);

  const legacy = await listLegacy.run({auth, data: {}}) as {rows: {userId: string; schoolId: string; name: string}[]};
  const leo = legacy.rows.find((r) => r.userId === missing);
  assert.deepEqual(leo, {userId: missing, schoolId: `${run}-BF1`, name: "Leo Legacy"});
  assert.ok(!legacy.rows.some((r) => r.userId === has || r.userId === teacher));
});

after(async () => {
  for (const uid of authUids) {
    await getAuth().deleteUser(uid).catch(() => undefined);
    const audits = await db.collection("admin_audit_logs").where("actorId", "==", uid).get();
    await Promise.all(audits.docs.map((d) => d.ref.delete()));
  }
});
