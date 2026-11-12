import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

import {activateStudentAccountDev, cancelPendingRegistrationDev} from "./index";
import {generateActivationCode, hashActivationCode} from "./student_roster_domain";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<unknown>};
type Err = {code?: string; message?: string; details?: {reason?: string}};

const db = getFirestore();
const activate = activateStudentAccountDev as unknown as Callable;
const cancel = cancelPendingRegistrationDev as unknown as Callable;
const extraUids: string[] = [];
const run = `SA${Date.now()}`;
const runLower = run.toLowerCase();
const MISMATCH = "Those details don't match our records.";
const EXPIRED = "This activation code has expired. Ask the PACC office for a new one.";
const ACTIVATED = "This account is already activated. Sign in or use Forgot password.";
const EMAIL_IN_USE = "This email address is already registered.";
const DOB = "2004-05-06";
const PASSWORD = "Str0ngPass!";
const keyOf = (n: string) => n.toUpperCase().replace(/[^A-Z0-9]/g, "");
const emails = new Set<string>();
const extraDocs: FirebaseFirestore.DocumentReference[] = [];
const nextCode = generateActivationCode;

function email(tag: string): string {
  const value = `${runLower}-${tag}@example.com`;
  emails.add(value);
  return value;
}

async function seed(n: string, extra: Record<string, unknown> = {}, opts: {expired?: boolean; code?: string | null} = {}) {
  const studentNo = `${run}-${n}`;
  const key = keyOf(studentNo);
  const code = opts.code === undefined ? nextCode() : opts.code;
  let activationCode: Record<string, unknown> | null = null;
  if (code) {
    const issued = opts.expired ? new Date(Date.now() - 61 * 24 * 60 * 60 * 1000) : new Date();
    const stored = await hashActivationCode(code, issued);
    activationCode = {hash: stored.hash, salt: stored.salt, issuedAt: Timestamp.fromDate(stored.issuedAt),
      expiresAt: Timestamp.fromDate(stored.expiresAt)};
  }
  await db.collection("student_roster").doc(key).set({
    studentNo, studentKey: key, surname: `Dela Cruz ${n}`, surnameNormalized: `delacruz${n.toLowerCase()}`,
    firstName: "Juan", middleName: "Santos",
    dateOfBirth: Timestamp.fromDate(new Date(`${DOB}T00:00:00Z`)), dateOfBirthKey: DOB,
    collegeId: `${run}-college`, college: "College of Testing", courseId: `${run}-course`, course: "BS Testing",
    departmentId: `${run}-dept`, department: "Testing Dept", yearLevel: "2nd Year",
    status: "active", activated: false, userId: null, activationCode, ...extra,
  });
  return {studentNo, key, code: code ?? "AAAAA-AAAAA"};
}

const rosterRef = (key: string) => db.collection("student_roster").doc(key);
const attemptsRef = (key: string) => db.collection("student_activation_attempts").doc(key);

async function rejectsWith(p: Promise<unknown>, code: string, reason: string, message?: string) {
  await assert.rejects(p, (e: Err) => {
    assert.equal(e?.code, code);
    assert.equal(e?.details?.reason, reason);
    if (message) assert.equal(e?.message, message);
    return true;
  });
}
const mismatch = (p: Promise<unknown>) => rejectsWith(p, "not-found", "mismatch", MISMATCH);

async function authUserExists(address: string): Promise<boolean> {
  try {
    await getAuth().getUserByEmail(address);
    return true;
  } catch (error) {
    assert.equal((error as {code?: string}).code, "auth/user-not-found");
    return false;
  }
}

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST, "emulators required");
});

after(async () => {
  const uids: string[] = [...extraUids];
  for (const address of emails) {
    try {
      const user = await getAuth().getUserByEmail(address);
      uids.push(user.uid);
      await getAuth().deleteUser(user.uid);
    } catch {
      // not created
    }
  }
  const range = (name: string) => db.collection(name)
    .where("__name__", ">=", db.collection(name).doc(run)).where("__name__", "<", db.collection(name).doc(`${run}~`)).get();
  const [rosters, attempts, reservations] = await Promise.all(
    [range("student_roster"), range("student_activation_attempts"), range("student_id_reservations")]);
  const audits = uids.length
    ? await db.collection("admin_audit_logs").where("actorId", "in", uids.slice(0, 30)).get()
    : {docs: [] as FirebaseFirestore.QueryDocumentSnapshot[]};
  await Promise.all([
    ...rosters.docs, ...attempts.docs, ...reservations.docs, ...audits.docs,
  ].map((d) => d.ref.delete()).concat(uids.map((uid) => db.collection("users").doc(uid).delete()))
    .concat(extraDocs.map((r) => r.delete())));
});

test("does not require sign-in and validates input format", async () => {
  const s = await seed("V1");
  const base = {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: email("v1"), password: PASSWORD};
  await rejectsWith(activate.run({data: {...base, email: "not-an-email"}}), "invalid-argument", "invalid-input");
  await rejectsWith(activate.run({data: {...base, password: "short7!"}}), "invalid-argument", "invalid-input");
  await rejectsWith(activate.run({data: {...base, dateOfBirth: "05/06/2004"}}), "invalid-argument", "invalid-input");
  await rejectsWith(activate.run({data: null}), "invalid-argument", "invalid-input");
  assert.equal((await attemptsRef(s.key).get()).exists, false);
});

test("success creates Auth user, profile, reservation, roster link and audit", async () => {
  const s = await seed("OK1");
  const address = email("ok1");
  const result = await activate.run({data: {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB,
    email: address, password: PASSWORD}}) as {ok: boolean; email: string};
  assert.deepEqual(result, {ok: true, email: address});

  const user = await getAuth().getUserByEmail(address);
  assert.equal(user.emailVerified, false);
  const profile = (await db.collection("users").doc(user.uid).get()).data() ?? {};
  assert.equal(profile.accessRole, "appUser");
  assert.equal(profile.verificationStatus, "verified");
  assert.equal(profile.verifiedBy, "roster-activation");
  assert.equal(profile.personalInfoRequired, true);
  assert.equal(profile.rosterLinked, true);
  assert.equal(profile.profileVersion, 3);
  assert.equal(profile.quickAssessmentCompleted, false);
  assert.equal(profile.profileSetupCompleted, false);
  assert.equal(profile.dayStreak, 0);
  assert.deepEqual(profile.activeDateKeys, []);
  assert.equal(profile.populationRole, "student");
  assert.equal(profile.schoolId, s.studentNo);
  assert.equal(profile.email, address);
  assert.equal(profile.firstName, "Juan");
  assert.equal(profile.middleName, "Santos");
  assert.equal(profile.lastName, "Dela Cruz OK1");
  assert.equal(profile.name, "Juan Santos Dela Cruz OK1");
  assert.equal(profile.course, "BS Testing");
  assert.equal(profile.courseId, `${run}-course`);
  assert.equal(profile.collegeId, `${run}-college`);
  assert.equal(profile.department, "Testing Dept");
  assert.equal(profile.yearLevel, "2nd Year");
  assert.equal(profile.dateOfBirthKey, DOB);

  const reservation = (await db.collection("student_id_reservations").doc(s.key).get()).data();
  assert.equal(reservation?.userId, user.uid);
  const rosterData = (await rosterRef(s.key).get()).data() ?? {};
  assert.equal(rosterData.activated, true);
  assert.equal(rosterData.userId, user.uid);
  assert.equal(rosterData.activationCode, null);
  const audits = await db.collection("admin_audit_logs").where("actorId", "==", user.uid).get();
  assert.ok(audits.docs.some((d) => d.data().action === "STUDENT_ACCOUNT_ACTIVATED" &&
    d.data().category === "USER_MANAGEMENT" && d.data().targetId === s.key));
  const auditText = JSON.stringify(audits.docs.map((d) => d.data()));
  assert.ok(!auditText.includes(s.code.replace("-", "")) && !auditText.includes(DOB) && !auditText.includes(PASSWORD));
});

test("formatted Student No. and loosely typed code hit the canonical roster key", async () => {
  const key = keyOf(`${run}2021-00123`);
  const code = nextCode();
  const stored = await hashActivationCode(code);
  await rosterRef(key).set({studentNo: `${run}2021-00123`, studentKey: key, surname: "Reyes", firstName: "Ana", middleName: "",
    dateOfBirth: Timestamp.fromDate(new Date(`${DOB}T00:00:00Z`)), dateOfBirthKey: DOB, collegeId: "c", college: "C",
    courseId: "k", course: "K", departmentId: "d", department: "D", yearLevel: "1st Year", status: "active", activated: false,
    userId: null, activationCode: {hash: stored.hash, salt: stored.salt, issuedAt: Timestamp.fromDate(stored.issuedAt),
      expiresAt: Timestamp.fromDate(stored.expiresAt)}});
  const address = email("fmt");
  await activate.run({data: {studentNo: `${runLower} 2021 00123`, activationCode: ` ${code.replace("-", "").toLowerCase()} `,
    dateOfBirth: DOB, email: address, password: PASSWORD}});
  const user = await getAuth().getUserByEmail(address);
  assert.equal((await rosterRef(key).get()).data()?.userId, user.uid);
  assert.equal((await db.collection("student_id_reservations").doc(key).get()).data()?.userId, user.uid);
});

test("every mismatch kind returns the identical generic error", async () => {
  const good = await seed("M1");
  const nullCode = await seed("M2", {}, {code: null});
  const deactivated = await seed("M3", {status: "deactivated"});
  const base = (s: {studentNo: string; code: string}, tag: string) =>
    ({studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: email(tag), password: PASSWORD});
  await mismatch(activate.run({data: {...base(good, "m1a"), activationCode: nextCode()}}));
  await mismatch(activate.run({data: {...base(good, "m1b"), dateOfBirth: "2004-05-07"}}));
  await mismatch(activate.run({data: {...base(good, "m1c"), activationCode: "not a code"}}));
  await mismatch(activate.run({data: {...base(good, "m1d"), studentNo: `${run}-UNKNOWN`}}));
  await mismatch(activate.run({data: {...base(good, "m1e"), studentNo: "!"}}));
  await mismatch(activate.run({data: base(nullCode, "m2")}));
  await mismatch(activate.run({data: base(deactivated, "m3")}));
  for (const tag of ["m1a", "m1b", "m1c", "m1d", "m1e", "m2", "m3"]) {
    assert.equal(await authUserExists(`${runLower}-${tag}@example.com`), false);
  }
  assert.equal((await attemptsRef(good.key).get()).data()?.failedCount, 3);
  assert.equal((await attemptsRef(keyOf(`${run}-UNKNOWN`)).get()).data()?.failedCount, 1);
  assert.equal((await attemptsRef(nullCode.key).get()).data()?.failedCount, 1);
  assert.equal((await attemptsRef(deactivated.key).get()).data()?.failedCount, 1);
  assert.equal((await rosterRef(good.key).get()).data()?.activated, false);
});

test("expiry is only revealed after a full match", async () => {
  const s = await seed("E1", {}, {expired: true});
  const data = {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: email("e1"), password: PASSWORD};
  await mismatch(activate.run({data: {...data, dateOfBirth: "2004-05-07"}}));
  assert.equal((await attemptsRef(s.key).get()).data()?.failedCount, 1);
  await rejectsWith(activate.run({data}), "deadline-exceeded", "expired", EXPIRED);
  assert.equal(await authUserExists(data.email), false);
  assert.equal((await rosterRef(s.key).get()).data()?.activated, false);
});

test("five failures lock the Student No.; an expired lock allows success and clears attempts", async () => {
  const s = await seed("L1");
  const data = {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: email("l1"), password: PASSWORD};
  for (let i = 0; i < 5; i++) await mismatch(activate.run({data: {...data, dateOfBirth: "2004-05-07"}}));
  await mismatch(activate.run({data}));
  assert.equal(await authUserExists(data.email), false);
  const locked = (await attemptsRef(s.key).get()).data() ?? {};
  assert.ok(locked.lockedUntil instanceof Timestamp && locked.lockedUntil.toMillis() > Date.now());
  await attemptsRef(s.key).update({lockedUntil: Timestamp.fromMillis(Date.now() - 1000)});
  await activate.run({data});
  assert.equal(await authUserExists(data.email), true);
  assert.equal((await attemptsRef(s.key).get()).exists, false);
});

test("already activated row returns the activated copy after a full match", async () => {
  const s = await seed("A1", {activated: true, userId: `${run}-existing`});
  const data = {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: email("a1"), password: PASSWORD};
  await rejectsWith(activate.run({data}), "already-exists", "already-activated", ACTIVATED);
  assert.equal(await authUserExists(data.email), false);
});

test("email used by another Auth user is rejected without roster change", async () => {
  const s = await seed("D1");
  const address = email("d1");
  await getAuth().createUser({email: address, password: PASSWORD});
  await rejectsWith(activate.run({data: {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: address,
    password: PASSWORD}}), "already-exists", "email-in-use", EMAIL_IN_USE);
  const rosterData = (await rosterRef(s.key).get()).data() ?? {};
  assert.equal(rosterData.activated, false);
  assert.ok(rosterData.activationCode);
});

test("transaction failure deletes the orphaned Auth user", async () => {
  const s = await seed("O1");
  const reservation = db.collection("student_id_reservations").doc(s.key);
  await reservation.set({userId: "someone-else", studentId: s.studentNo});
  const address = email("o1");
  await assert.rejects(activate.run({data: {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: address,
    password: PASSWORD}}));
  await assert.rejects(getAuth().getUserByEmail(address), (e: {code?: string}) => e.code === "auth/user-not-found");
  assert.equal((await rosterRef(s.key).get()).data()?.activated, false);
  assert.equal((await reservation.get()).data()?.userId, "someone-else");
});

test("two simultaneous activations: exactly one wins and the loser's Auth user is deleted", async () => {
  const s = await seed("R1");
  const [a, b] = [email("r1a"), email("r1b")];
  const results = await Promise.allSettled([a, b].map((address) => activate.run({data: {studentNo: s.studentNo,
    activationCode: s.code, dateOfBirth: DOB, email: address, password: PASSWORD}})));
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  const loser = results[0].status === "rejected" ? a : b;
  const winner = loser === a ? b : a;
  assert.equal(await authUserExists(loser), false);
  const winnerUser = await getAuth().getUserByEmail(winner);
  assert.equal((await rosterRef(s.key).get()).data()?.userId, winnerUser.uid);
});

test("R6: redeemed code is kept as consumedActivationCode; re-entering the slip says already activated", async () => {
  const s = await seed("C1");
  const data = {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: email("c1"), password: PASSWORD};
  await activate.run({data});
  const rosterData = (await rosterRef(s.key).get()).data() ?? {};
  assert.equal(rosterData.activationCode, null);
  assert.equal(typeof rosterData.consumedActivationCode?.hash, "string");
  assert.equal(typeof rosterData.consumedActivationCode?.salt, "string");
  assert.ok(rosterData.consumedActivationCode?.consumedAt instanceof Timestamp);
  assert.equal(rosterData.consumedActivationCode?.userId, (await getAuth().getUserByEmail(data.email)).uid);
  assert.ok(!JSON.stringify(rosterData).includes(s.code.replace("-", "")));

  await mismatch(activate.run({data: {...data, email: email("c1b"), dateOfBirth: "2004-05-07"}}));
  assert.equal((await attemptsRef(s.key).get()).data()?.failedCount, 1);
  await rejectsWith(activate.run({data: {...data, email: email("c1c")}}), "already-exists", "already-activated", ACTIVATED);
  assert.equal((await attemptsRef(s.key).get()).exists, false);
  assert.equal(await authUserExists(`${runLower}-c1c@example.com`), false);
});

test("R6: cancelling an unverified activation resets the roster row so the same slip works again", async () => {
  const s = await seed("X1");
  const first = email("x1a");
  await activate.run({data: {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: first, password: PASSWORD}});
  const firstUid = (await getAuth().getUserByEmail(first)).uid;
  extraUids.push(firstUid);

  assert.deepEqual(await cancel.run({auth: {uid: firstUid}, data: {}}), {ok: true});
  assert.equal(await authUserExists(first), false);
  assert.equal((await db.collection("users").doc(firstUid).get()).exists, false);
  assert.equal((await db.collection("student_id_reservations").doc(s.key).get()).exists, false);
  const reset = (await rosterRef(s.key).get()).data() ?? {};
  assert.equal(reset.activated, false);
  assert.equal(reset.userId, null);
  assert.equal(reset.consumedActivationCode, null);
  assert.equal(typeof reset.activationCode?.hash, "string");
  assert.ok(reset.activationCode?.expiresAt instanceof Timestamp);
  assert.equal(reset.activationCode?.consumedAt, undefined);
  assert.equal(reset.activationCode?.userId, undefined);

  const second = email("x1b");
  await activate.run({data: {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: second, password: PASSWORD}});
  const secondUid = (await getAuth().getUserByEmail(second)).uid;
  assert.notEqual(secondUid, firstUid);
  assert.equal((await rosterRef(s.key).get()).data()?.userId, secondUid);
});

test("R6: cancelling leaves a roster row owned by someone else untouched", async () => {
  const s = await seed("X2");
  const address = email("x2");
  await activate.run({data: {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: address, password: PASSWORD}});
  const uid = (await getAuth().getUserByEmail(address)).uid;
  extraUids.push(uid);
  await rosterRef(s.key).update({userId: `${run}-other`});
  await cancel.run({auth: {uid}, data: {}});
  const rosterData = (await rosterRef(s.key).get()).data() ?? {};
  assert.equal(rosterData.activated, true);
  assert.equal(rosterData.userId, `${run}-other`);
  assert.equal(rosterData.activationCode, null);
});

test("R6: legacy (non-roster) student cancellation is unchanged and never touches the roster", async () => {
  const schoolId = `2026${String(Math.floor(Math.random() * 10000)).padStart(4, "0")}`;
  const address = email("legacy");
  const uid = (await getAuth().createUser({email: address, password: PASSWORD})).uid;
  extraUids.push(uid);
  const reservation = db.collection("student_id_reservations").doc(schoolId);
  const roster = rosterRef(schoolId);
  extraDocs.push(reservation, roster, db.collection("pending_registration_cancellations").doc(uid));
  await db.collection("users").doc(uid).set({accessRole: "appUser", populationRole: "student", schoolId,
    profileSetupCompleted: false, quickAssessmentCompleted: false, verifiedBy: "automatic-registration"});
  await reservation.set({userId: uid, studentId: schoolId});
  await roster.set({studentKey: schoolId, status: "active", activated: true, userId: uid, activationCode: null});

  assert.deepEqual(await cancel.run({auth: {uid}, data: {}}), {ok: true});
  assert.equal(await authUserExists(address), false);
  assert.equal((await db.collection("users").doc(uid).get()).exists, false);
  assert.equal((await reservation.get()).exists, false);
  const rosterData = (await roster.get()).data() ?? {};
  assert.equal(rosterData.activated, true);
  assert.equal(rosterData.userId, uid);
});

test("cancelling a roster-linked legacy student resets the roster row for reissue", async () => {
  const studentNo = `${run}-LG1`;
  const key = keyOf(studentNo);
  const address = email("lg1");
  const uid = (await getAuth().createUser({email: address, password: PASSWORD})).uid;
  extraUids.push(uid);
  extraDocs.push(db.collection("pending_registration_cancellations").doc(uid));
  await db.collection("users").doc(uid).set({accessRole: "appUser", populationRole: "student", schoolId: studentNo,
    profileSetupCompleted: false, quickAssessmentCompleted: false, verifiedBy: "automatic-registration", rosterLinked: true});
  await db.collection("student_id_reservations").doc(key).set({userId: uid, studentId: studentNo});
  await rosterRef(key).set({studentNo, studentKey: key, status: "active", activated: true, userId: uid, activationCode: null});

  assert.deepEqual(await cancel.run({auth: {uid}, data: {}}), {ok: true});
  assert.equal(await authUserExists(address), false);
  assert.equal((await db.collection("users").doc(uid).get()).exists, false);
  assert.equal((await db.collection("student_id_reservations").doc(key).get()).exists, false);
  const rosterData = (await rosterRef(key).get()).data() ?? {};
  assert.equal(rosterData.activated, false);
  assert.equal(rosterData.userId, null);
  assert.equal(rosterData.activationCode, null);
});
