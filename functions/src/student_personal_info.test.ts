import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

import {
  getMyStudentInformation, getStudentPersonalInfo, listStudentCorrectionRequests, requestStudentCorrection,
  reviewStudentCorrection, saveStudentPersonalInfo,
} from "./index";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<unknown>};
type Err = {code?: string; details?: {errors?: Record<string, string>}};
const call = (fn: unknown) => fn as Callable;
const save = call(saveStudentPersonalInfo);
const mine = call(getMyStudentInformation);
const view = call(getStudentPersonalInfo);
const requestFix = call(requestStudentCorrection);
const review = call(reviewStudentCorrection);
const list = call(listStudentCorrectionRequests);

const db = getFirestore();
const run = `PI${Date.now()}`;
const adminUid = process.env.SUPER_ADMIN_UID ?? "";
const counselorUid = `${run}-counselor`;
const staffUid = `${run}-staff`;
const key = (n: string) => `${run}${n}`.toUpperCase();
const uidOf = (n: string) => `${run}-u${n}`;
const created: FirebaseFirestore.DocumentReference[] = [];
const collegeA = `${run}-colA`;
const collegeB = `${run}-colB`;
const courseA = `${run}-crsA`;
const courseB = `${run}-crsB`;

const INFO = {
  sex: "Female", civilStatus: "Single", spouse: "", nationality: "Filipino", placeOfBirth: "Pasig",
  cityAddress: null,
  homeAddress: {number: "1", street: "Main", barangay: "Sta. Lucia", cityTown: "Pasig", province: "Metro Manila", zipCode: "1600"},
  father: "", fatherOccupation: "", mother: "", motherOccupation: "",
  guardian: "Maria Cruz", guardianRelationship: "Mother", guardianAddress: "Pasig City",
  telephone: "", cellphone: "0917 123 4567",
};

async function put(path: string, data: Record<string, unknown>) {
  const ref = db.doc(path);
  await ref.set(data);
  created.push(ref);
  return ref;
}

async function seedStudent(n: string, opts: {roster?: boolean; user?: Record<string, unknown>; roster2?: Record<string, unknown>} = {}) {
  const uid = uidOf(n);
  const studentNo = `${run}-${n}`;
  const k = key(n);
  await put(`users/${uid}`, {
    id: uid, email: `${uid}@example.com`, schoolId: studentNo, populationRole: "student", role: "student",
    accessRole: "appUser", firstName: "Nick", middleName: "", lastName: "Name", name: "Nick Name", gender: "",
    college: "College of Testing", course: "BS Testing", yearLevel: "2nd Year", dateOfBirthKey: "2004-05-06",
    personalInfoRequired: true, rosterLinked: opts.roster !== false, ...opts.user,
  });
  if (opts.roster !== false) {
    await put(`student_roster/${k}`, {
      studentNo, studentKey: k, surname: "Dela Cruz", surnameNormalized: "delacruz", firstName: "Juan", middleName: "Santos",
      dateOfBirth: Timestamp.fromDate(new Date("2004-05-06T00:00:00Z")), dateOfBirthKey: "2004-05-06",
      collegeId: collegeA, college: "College of Testing", courseId: courseA, course: "BS Testing",
      departmentId: `${run}-dept`, department: "Testing Dept", yearLevel: "2nd Year", status: "active", activated: true,
      userId: uid, activationCode: null, consumedActivationCode: {hash: "h", salt: "s"}, revokedUserIds: ["old-uid"],
      ...opts.roster2,
    });
  }
  return {uid, studentNo, k};
}

async function rejects(p: Promise<unknown>, code: string) {
  await assert.rejects(p, (e: Err) => {
    assert.equal(e?.code, code);
    return true;
  });
}

async function audits(action: string, targetId: string) {
  const snap = await db.collection("admin_audit_logs").where("targetId", "==", targetId).get();
  return snap.docs.filter((d) => d.data().action === action);
}

before(async () => {
  assert.ok(adminUid, "SUPER_ADMIN_UID is required");
  await put(`users/${adminUid}`, {id: adminUid, accessRole: "admin", role: "admin", name: "Test Admin", email: "a@example.com"});
  await put(`users/${counselorUid}`, {id: counselorUid, accessRole: "counselor", role: "counselor", name: "Test Counselor"});
  await put(`users/${staffUid}`, {id: staffUid, accessRole: "portalStaff", role: "portalStaff", name: "Test Staff"});
  await put(`colleges/${collegeA}`, {name: "College of Testing", code: "COT", active: true});
  await put(`colleges/${collegeB}`, {name: "College of Other", code: "COO", active: true});
  await put(`departments/${run}-dept`, {name: "Testing Dept", active: true});
  await put(`courses/${courseA}`, {name: "BS Testing", code: "BST", collegeId: collegeA, departmentId: `${run}-dept`, active: true});
  await put(`courses/${courseB}`, {name: "BS Other", code: "BSO", collegeId: collegeB, departmentId: `${run}-dept`, active: true});
});

after(async () => {
  const reqs = await db.collection("student_correction_requests").where("studentNo", ">=", run).where("studentNo", "<=", `${run}~`).get();
  await Promise.all(reqs.docs.map((d) => d.ref.delete()));
  await Promise.all(created.map((r) => r.delete()));
  for (let i = 1; i <= 14; i++) await db.doc(`student_personal_info/${uidOf(String(i))}`).delete();
  const aud = await db.collection("admin_audit_logs").where("targetType", "==", "student").get();
  await Promise.all(aud.docs.filter((d) => String(d.data().targetId).startsWith(run)).map((d) => d.ref.delete()));
});

// ------------------------------------------------------------------ save

test("save rejects non-students", async () => {
  await put(`users/${run}-nonstudent`, {populationRole: "teaching", role: "teaching"});
  await rejects(save.run({auth: {uid: `${run}-nonstudent`}, data: {info: INFO, privacyConsent: true}}), "permission-denied");
});

test("effective role: a profile with only declaredRole student can use the student callables", async () => {
  const {uid} = await seedStudent("13", {user: {populationRole: null, role: "", declaredRole: "student"}});
  assert.deepEqual(await save.run({auth: {uid}, data: {info: INFO, privacyConsent: true}}), {ok: true});
  await db.doc(`student_personal_info/${uid}`).delete();
  const {uid: legacy} = await seedStudent("14", {user: {populationRole: null, declaredRole: null, role: "student"}});
  assert.deepEqual(await save.run({auth: {uid: legacy}, data: {info: INFO, privacyConsent: true}}), {ok: true});
  await db.doc(`student_personal_info/${legacy}`).delete();
});

test("first save needs consent, invalid payload reports errors, valid save writes everything", async () => {
  const {uid} = await seedStudent("1");
  await rejects(save.run({auth: {uid}, data: {info: INFO}}), "failed-precondition");
  await assert.rejects(save.run({auth: {uid}, data: {info: {...INFO, cellphone: "x"}, privacyConsent: true}}), (e: Err) => {
    assert.equal(e.code, "invalid-argument");
    assert.ok(e.details?.errors?.cellphone);
    return true;
  });
  assert.deepEqual(await save.run({auth: {uid}, data: {info: INFO, privacyConsent: true}}), {ok: true});
  const first = (await db.doc(`student_personal_info/${uid}`).get()).data()!;
  assert.equal(first.privacyConsent.policyVersion, "2026-11-ra10173-v1");
  assert.equal(first.cellphone, "09171234567");
  const user = (await db.doc(`users/${uid}`).get()).data()!;
  assert.equal(user.personalInfoRequired, false);
  assert.equal(user.gender, "Female");

  await save.run({auth: {uid}, data: {info: {...INFO, nationality: "Other"}}});
  const again = (await db.doc(`student_personal_info/${uid}`).get()).data()!;
  assert.equal(again.nationality, "Other");
  assert.deepEqual(again.createdAt, first.createdAt);
  assert.deepEqual(again.privacyConsent, first.privacyConsent);
});

test("save keeps an existing gender", async () => {
  const {uid} = await seedStudent("2", {user: {gender: "Prefer not to say"}});
  await save.run({auth: {uid}, data: {info: INFO, privacyConsent: true}});
  assert.equal((await db.doc(`users/${uid}`).get()).data()!.gender, "Prefer not to say");
});

// ------------------------------------------------------------------ reads

test("official fields come from the roster, legacy falls back to users", async () => {
  const {uid} = await seedStudent("3");
  const res = await mine.run({auth: {uid}, data: {}}) as {official: Record<string, string>; personal: unknown; corrections: unknown[]};
  assert.equal(res.official.firstName, "Juan");
  assert.equal(res.official.surname, "Dela Cruz");
  assert.equal(res.official.dateOfBirth, "2004-05-06");
  assert.equal(res.personal, null);
  assert.deepEqual(res.corrections, []);

  const legacy = await seedStudent("4", {roster: false, user: {firstName: "Leo", lastName: "Legacy", middleName: "M", rosterLinked: false}});
  const l = await mine.run({auth: {uid: legacy.uid}, data: {}}) as {official: Record<string, string>};
  assert.equal(l.official.firstName, "Leo");
  assert.equal(l.official.surname, "Legacy");
  assert.equal(l.official.studentNo, legacy.studentNo);
});

test("counselor view is audited, allowlisted, and clinical only", async () => {
  const {uid} = await seedStudent("5");
  await rejects(view.run({auth: {uid: staffUid}, data: {userId: uid}}), "permission-denied");
  await rejects(view.run({auth: {uid}, data: {userId: uid}}), "permission-denied");
  assert.equal((await audits("STUDENT_PERSONAL_INFO_VIEWED", uid)).length, 0);

  // audited even when nothing is on file
  const empty = await view.run({auth: {uid: counselorUid}, data: {userId: uid}}) as {official: Record<string, unknown>; personal: unknown};
  assert.equal(empty.personal, null);
  assert.equal((await audits("STUDENT_PERSONAL_INFO_VIEWED", uid)).length, 1);

  await save.run({auth: {uid}, data: {info: INFO, privacyConsent: true}});
  const res = await view.run({auth: {uid: counselorUid}, data: {userId: uid}}) as
    {official: Record<string, unknown>; personal: Record<string, unknown>};
  assert.deepEqual(Object.keys(res.official).sort(),
    ["college", "course", "dateOfBirth", "email", "firstName", "middleName", "studentNo", "surname", "yearLevel"]);
  assert.deepEqual(Object.keys(res.personal).sort(), [...Object.keys(INFO), "updatedAt"].sort());
  assert.equal(res.official.firstName, "Juan");
  const text = JSON.stringify(res);
  for (const banned of ["activationCode", "consumedActivationCode", "revokedUserIds", "privacyConsent"]) {
    assert.equal(text.includes(banned), false, banned);
  }
  const all = await audits("STUDENT_PERSONAL_INFO_VIEWED", uid);
  assert.equal(all.length, 2);
  assert.equal(all[0].data().category, "SECURITY");
  assert.equal(all[0].data().actorId, counselorUid);
});

// ------------------------------------------------------------------ corrections

test("correction requests validate field, dedupe pending, and list for admin", async () => {
  const {uid, studentNo} = await seedStudent("6");
  await rejects(requestFix.run({auth: {uid}, data: {field: "studentNo", requestedValue: "X", reason: "typo"}}), "invalid-argument");
  await rejects(requestFix.run({auth: {uid}, data: {field: "yearLevel", requestedValue: "9", reason: "typo"}}), "invalid-argument");
  await rejects(requestFix.run({auth: {uid}, data: {field: "yearLevel", requestedValue: "3", reason: ""}}), "invalid-argument");
  const {requestId} = await requestFix.run({auth: {uid}, data: {field: "yearLevel", requestedValue: "3", reason: "Moved up"}}) as {requestId: string};
  assert.ok(requestId);
  await rejects(requestFix.run({auth: {uid}, data: {field: "yearLevel", requestedValue: "4", reason: "again"}}), "already-exists");

  const res = await mine.run({auth: {uid}, data: {}}) as
    {corrections: {id: string; status: string; currentValue: string; requestedValue: string; studentNo: string}[]};
  assert.equal(res.corrections.length, 1);
  assert.equal(res.corrections[0].currentValue, "2nd Year");
  assert.equal(res.corrections[0].requestedValue, "3rd Year");
  assert.equal(res.corrections[0].studentNo, studentNo);

  await rejects(list.run({auth: {uid: counselorUid}, data: {status: "pending"}}), "permission-denied");
  const l = await list.run({auth: {uid: adminUid}, data: {status: "pending"}}) as {requests: {id: string}[]};
  assert.ok(l.requests.some((r) => r.id === requestId));
});

test("review: non-admin denied, approve updates roster and users and audits", async () => {
  const {uid, k} = await seedStudent("7");
  const {requestId} = await requestFix.run({auth: {uid}, data: {field: "yearLevel", requestedValue: "4", reason: "Fix"}}) as {requestId: string};
  await rejects(review.run({auth: {uid: counselorUid}, data: {requestId, decision: "approve", reason: "ok"}}), "permission-denied");
  assert.deepEqual(await review.run({auth: {uid: adminUid}, data: {requestId, decision: "approve", reason: "verified"}}), {status: "approved"});
  assert.equal((await db.doc(`student_roster/${k}`).get()).data()!.yearLevel, "4th Year");
  assert.equal((await db.doc(`users/${uid}`).get()).data()!.yearLevel, "4th Year");
  assert.equal((await db.doc(`student_correction_requests/${requestId}`).get()).data()!.status, "approved");
  assert.equal((await audits("STUDENT_CORRECTION_APPROVED", uid)).length, 1);
  await rejects(review.run({auth: {uid: adminUid}, data: {requestId, decision: "approve", reason: "again"}}), "failed-precondition");
});

test("name corrections touch the roster only; dateOfBirth writes key and timestamp", async () => {
  const {uid, k} = await seedStudent("8");
  const a = await requestFix.run({auth: {uid}, data: {field: "firstName", requestedValue: "Juanito", reason: "Spelling"}}) as {requestId: string};
  await review.run({auth: {uid: adminUid}, data: {requestId: a.requestId, decision: "approve", reason: "ok"}});
  assert.equal((await db.doc(`student_roster/${k}`).get()).data()!.firstName, "Juanito");
  const user = (await db.doc(`users/${uid}`).get()).data()!;
  assert.equal(user.firstName, "Nick");
  assert.equal(user.name, "Nick Name");

  const b = await requestFix.run({auth: {uid}, data: {field: "dateOfBirth", requestedValue: "2004-07-08", reason: "Wrong"}}) as {requestId: string};
  await review.run({auth: {uid: adminUid}, data: {requestId: b.requestId, decision: "approve", reason: "ok"}});
  const r2 = (await db.doc(`student_roster/${k}`).get()).data()!;
  const u2 = (await db.doc(`users/${uid}`).get()).data()!;
  assert.equal(r2.dateOfBirthKey, "2004-07-08");
  assert.equal(u2.dateOfBirthKey, "2004-07-08");
  assert.equal((u2.dateOfBirth as Timestamp).toDate().toISOString(), "2004-07-08T00:00:00.000Z");
});

test("college/course corrections validate ids and pairing", async () => {
  const {uid, k} = await seedStudent("9");
  await rejects(requestFix.run({auth: {uid}, data: {field: "course", requestedValue: "nope", reason: "x"}}), "invalid-argument");
  const bad = await requestFix.run({auth: {uid}, data: {field: "course", requestedValue: courseB, reason: "x"}}) as {requestId: string};
  await rejects(review.run({auth: {uid: adminUid}, data: {requestId: bad.requestId, decision: "approve", reason: "ok"}}), "failed-precondition");
  assert.equal((await db.doc(`student_correction_requests/${bad.requestId}`).get()).data()!.status, "pending");
  assert.equal((await db.doc(`student_roster/${k}`).get()).data()!.courseId, courseA);

  await review.run({auth: {uid: adminUid}, data: {requestId: bad.requestId, decision: "reject", reason: "Not a valid shift"}});
  const rejected = (await db.doc(`student_correction_requests/${bad.requestId}`).get()).data()!;
  assert.equal(rejected.status, "rejected");
  assert.equal(rejected.reviewReason, "Not a valid shift");
  assert.equal((await audits("STUDENT_CORRECTION_REJECTED", uid)).length, 1);

  const col = await requestFix.run({auth: {uid}, data: {field: "college", requestedValue: collegeB, reason: "x"}}) as {requestId: string};
  await rejects(review.run({auth: {uid: adminUid}, data: {requestId: col.requestId, decision: "approve", reason: "ok"}}), "failed-precondition");
});

test("course correction within the college updates academic fields in roster and users", async () => {
  const course2 = `${run}-crsA2`;
  await put(`courses/${course2}`, {name: "BS Testing Two", code: "BST2", collegeId: collegeA, departmentId: `${run}-dept`, active: true});
  const {uid, k} = await seedStudent("10");
  const r = await requestFix.run({auth: {uid}, data: {field: "course", requestedValue: course2, reason: "Shifted"}}) as {requestId: string};
  await review.run({auth: {uid: adminUid}, data: {requestId: r.requestId, decision: "approve", reason: "ok"}});
  const roster = (await db.doc(`student_roster/${k}`).get()).data()!;
  const user = (await db.doc(`users/${uid}`).get()).data()!;
  assert.equal(roster.courseId, course2);
  assert.equal(roster.course, "BS Testing Two");
  assert.equal(user.courseId, course2);
  assert.equal(user.course, "BS Testing Two");
});

test("save rejects a revoked student account", async () => {
  const {uid} = await seedStudent("11", {user: {accountStatus: "revoked", rosterLinked: false}});
  await rejects(save.run({auth: {uid}, data: {info: INFO, privacyConsent: true}}), "permission-denied");
  assert.equal((await db.doc(`student_personal_info/${uid}`).get()).exists, false);
});
