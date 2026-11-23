import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {Timestamp, getFirestore} from "firebase-admin/firestore";

import {
  activateStudentAccountDev, cancelPendingRegistrationDev, importStudentRoster, issueStudentActivationCodes,
  previewStudentRosterImport, provisionAppUserProfile, provisionAppUserProfileDev, repairMyStudentCollegeDev,
  revokeStudentActivation,
} from "./index";
import {studentAuthAliasEmail} from "./student_auth_alias";
import {RECOVERY_CONTACTS, RECOVERY_EMAILS, RECOVERY_VERIFICATIONS, recoveryEmailHash} from "./student_recovery_contacts";
import {generateActivationCode, hashActivationCode} from "./student_roster_domain";
import {ensureAuthUser} from "./test_auth_helper";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<unknown>};
type Err = {code?: string; details?: {reason?: string}};
const asCallable = (fn: unknown) => fn as Callable;
const db = getFirestore();
const run = `SS${Date.now()}`;
const runLower = run.toLowerCase();
const PASSWORD = "Str0ngPass!";
const DOB = "2004-05-06";
const adminUid = process.env.SUPER_ADMIN_UID ?? "";
const keyOf = (n: string) => n.toUpperCase().replace(/[^A-Z0-9]/g, "");
const aliasOf = (studentNo: string) => studentAuthAliasEmail(studentNo);

const docs: FirebaseFirestore.DocumentReference[] = [];
const uids: string[] = [];
let adminCreated = false;

async function rejects(p: Promise<unknown>, code: string) {
  await assert.rejects(p, (e: Err) => {
    assert.equal(e?.code, code);
    return true;
  });
}

async function seedRoster(tag: string) {
  const studentNo = `${run}-${tag}`;
  const key = keyOf(studentNo);
  const code = generateActivationCode();
  const stored = await hashActivationCode(code);
  const ref = db.collection("student_roster").doc(key);
  docs.push(ref, db.collection("student_id_reservations").doc(key), db.collection("student_activation_attempts").doc(key));
  await ref.set({
    studentNo, studentKey: key, surname: "Cruz", firstName: "Ana", middleName: "", dateOfBirth: Timestamp.fromDate(new Date(`${DOB}T00:00:00Z`)),
    dateOfBirthKey: DOB, collegeId: "c", college: "C", courseId: "k", course: "K", departmentId: "d", department: "D",
    yearLevel: "1st Year", status: "active", activated: false, userId: null,
    activationCode: {hash: stored.hash, salt: stored.salt, issuedAt: Timestamp.fromDate(stored.issuedAt), expiresAt: Timestamp.fromDate(stored.expiresAt)},
  });
  return {studentNo, key, code};
}

async function activate(s: {studentNo: string; code: string}, address: string): Promise<string> {
  await asCallable(activateStudentAccountDev).run({data: {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB,
    email: address, password: PASSWORD}});
  const user = await getAuth().getUserByEmail(aliasOf(s.studentNo));
  uids.push(user.uid);
  docs.push(db.collection("users").doc(user.uid), db.collection(RECOVERY_CONTACTS).doc(user.uid),
    db.collection(RECOVERY_VERIFICATIONS).doc(user.uid), db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(address)));
  return user.uid;
}

const email = (tag: string) => `${runLower}-${tag}@example.com`;
const exists = async (ref: FirebaseFirestore.DocumentReference) => (await ref.get()).exists;

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST && adminUid, "emulators + SUPER_ADMIN_UID required");
  await ensureAuthUser(adminUid, true);
  const admin = db.collection("users").doc(adminUid);
  if (!(await admin.get()).exists) {
    adminCreated = true;
    await admin.set({accessRole: "admin", firstName: "Test", lastName: "Admin", email: "a@example.com"});
  }
});

after(async () => {
  const audits = await db.collection("admin_audit_logs").where("actorId", "in", [adminUid, ...uids].slice(0, 30)).get();
  await Promise.all([
    ...docs.map((d) => d.delete()),
    ...uids.map((uid) => getAuth().deleteUser(uid).catch(() => undefined)),
    ...audits.docs.map((d) => d.ref.delete()),
    adminCreated ? db.collection("users").doc(adminUid).delete() : Promise.resolve(),
  ]);
});

// ---------------------------------------------------------------- 1 and 2: no profile, no reservation, no roster link

const STUDENT_INPUT = {populationRole: "student", firstName: "Evil", lastName: "User", gender: "Male", dateOfBirth: DOB,
  department: "College", course: "Course", yearLevel: "1st Year"};

test("an unrelated signed-in account cannot claim a Student ID reservation through profile provisioning", async () => {
  const victimNo = `${run}-VICTIM`;
  const victimKey = keyOf(victimNo);
  const victimReservation = db.collection("student_id_reservations").doc(victimKey);
  docs.push(victimReservation);
  await victimReservation.set({userId: "the-real-student", studentId: victimNo});
  const freeNo = `${run}-FREE`;
  const freeReservation = db.collection("student_id_reservations").doc(keyOf(freeNo));
  docs.push(freeReservation);

  const outsider = await getAuth().createUser({email: email("outsider"), password: PASSWORD});
  const squatter = await getAuth().createUser({email: aliasOf(victimNo), password: PASSWORD});
  const employee = await getAuth().createUser({email: `${runLower}@ucu.edu.ph`, password: PASSWORD});
  uids.push(outsider.uid, squatter.uid, employee.uid);

  for (const callable of [provisionAppUserProfile, provisionAppUserProfileDev].map(asCallable)) {
    for (const account of [outsider, squatter, employee]) {
      for (const schoolId of [victimNo, freeNo]) {
        await assert.rejects(callable.run({auth: {uid: account.uid}, data: {...STUDENT_INPUT, schoolId}}), (e: Err) => {
          assert.equal(e.code, "failed-precondition");
          return true;
        });
      }
    }
  }
  assert.equal((await victimReservation.get()).data()?.userId, "the-real-student", "the victim's reservation is untouched");
  assert.equal(await exists(freeReservation), false, "no reservation was created for an unreserved Student ID");
  for (const account of [outsider, squatter, employee]) {
    assert.equal(await exists(db.collection("users").doc(account.uid)), false, "no profile was created");
  }
});

test("an account on the Student ID alias domain cannot become a student profile, repair one, or touch roster administration", async () => {
  const studentNo = `${run}-SQ`;
  const squatter = await getAuth().createUser({email: aliasOf(studentNo), password: PASSWORD});
  uids.push(squatter.uid);
  const as = {uid: squatter.uid};

  await assert.rejects(asCallable(repairMyStudentCollegeDev).run({auth: as, data: {}}), (e: Err) => {
    assert.ok(["not-found", "permission-denied"].includes(String(e.code)), String(e.code));
    return true;
  });
  for (const callable of [previewStudentRosterImport, importStudentRoster, issueStudentActivationCodes, revokeStudentActivation].map(asCallable)) {
    await rejects(callable.run({auth: as, data: {studentNo, rows: [], reason: "x"}}), "permission-denied");
  }
  assert.equal(await exists(db.collection("users").doc(squatter.uid)), false);
  assert.equal(await exists(db.collection("student_id_reservations").doc(keyOf(studentNo))), false);
});

// ---------------------------------------------------------------- 5: duplicate and concurrent activation

test("two students racing for the same recovery email: exactly one activates and only one reservation exists", async () => {
  const a = await seedRoster("RA");
  const b = await seedRoster("RB");
  const address = email("race");
  docs.push(db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(address)));
  const results = await Promise.allSettled([a, b].map((s) => asCallable(activateStudentAccountDev).run({data: {
    studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: address, password: PASSWORD}})));
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1, JSON.stringify(results.map((r) => r.status)));
  const [winner, loser] = results[0].status === "fulfilled" ? [a, b] : [b, a];
  const winnerUser = await getAuth().getUserByEmail(aliasOf(winner.studentNo));
  uids.push(winnerUser.uid);
  docs.push(db.collection("users").doc(winnerUser.uid), db.collection(RECOVERY_CONTACTS).doc(winnerUser.uid));
  assert.equal((await db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(address)).get()).data()?.uid, winnerUser.uid);
  await assert.rejects(getAuth().getUserByEmail(aliasOf(loser.studentNo)), (e: {code?: string}) => e.code === "auth/user-not-found");
  const loserRow = (await db.collection("student_roster").doc(loser.key).get()).data() ?? {};
  assert.equal(loserRow.activated, false);
  assert.ok(loserRow.activationCode, "the loser's code is intact");
  const contacts = await db.collection(RECOVERY_CONTACTS).where("emailHash", "==", recoveryEmailHash(address)).get();
  assert.equal(contacts.size, 1, "one contact per recovery address");
});

test("two simultaneous activations of one Student ID create exactly one identity", async () => {
  const s = await seedRoster("RC");
  const results = await Promise.allSettled([email("rc1"), email("rc2")].map((address) => asCallable(activateStudentAccountDev).run({data: {
    studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: address, password: PASSWORD}})));
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  const user = await getAuth().getUserByEmail(aliasOf(s.studentNo));
  uids.push(user.uid);
  docs.push(db.collection("users").doc(user.uid), db.collection(RECOVERY_CONTACTS).doc(user.uid));
  for (const address of [email("rc1"), email("rc2")]) docs.push(db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(address)));
  const reservations = await db.collection("student_id_reservations").where("userId", "==", user.uid).get();
  assert.equal(reservations.size, 1);
  const owned = await db.collection(RECOVERY_EMAILS).where("uid", "==", user.uid).get();
  assert.equal(owned.size, 1, "exactly one recovery reservation for the winner");
  const all = await db.collection(RECOVERY_EMAILS).where("studentKey", "==", s.key).get();
  assert.equal(all.size, 1, "the loser reserved nothing");
});

// ---------------------------------------------------------------- 4: releases touch only the caller's own records

test("cancelling an unverified activation releases only the caller's own records", async () => {
  const a = await seedRoster("CA");
  const b = await seedRoster("CB");
  const aEmail = email("ca");
  const bEmail = email("cb");
  const aUid = await activate(a, aEmail);
  const bUid = await activate(b, bEmail);
  // Corrupt state: A's recovery-address reservation is owned by B. A's cancellation must not free it.
  const aReservation = db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(aEmail));
  await aReservation.set({uid: bUid, studentKey: b.key});

  assert.deepEqual(await asCallable(cancelPendingRegistrationDev).run({auth: {uid: aUid}, data: {}}), {ok: true});
  assert.equal(await exists(db.collection(RECOVERY_CONTACTS).doc(aUid)), false, "A's contact is released");
  assert.equal((await aReservation.get()).data()?.uid, bUid, "a reservation owned by someone else is not deleted");
  assert.equal(await exists(db.collection(RECOVERY_CONTACTS).doc(bUid)), true, "B's contact is untouched");
  assert.equal((await db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(bEmail)).get()).data()?.uid, bUid, "B's own reservation is untouched");
  assert.equal(await exists(db.collection("users").doc(bUid)), true);
  assert.equal((await getAuth().getUser(bUid)).email, aliasOf(b.studentNo));
});

test("revoking an activation releases only the revoked student's own records", async () => {
  const a = await seedRoster("VA");
  const b = await seedRoster("VB");
  const aEmail = email("va");
  const bEmail = email("vb");
  const aUid = await activate(a, aEmail);
  const bUid = await activate(b, bEmail);
  const aReservation = db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(aEmail));
  await aReservation.set({uid: bUid, studentKey: b.key});

  await asCallable(revokeStudentActivation).run({auth: {uid: adminUid}, data: {studentNo: a.studentNo, reason: "test"}});
  assert.equal(await exists(db.collection(RECOVERY_CONTACTS).doc(aUid)), false);
  assert.equal((await aReservation.get()).data()?.uid, bUid, "a reservation owned by someone else is not deleted");
  assert.equal(await exists(db.collection(RECOVERY_CONTACTS).doc(bUid)), true);
  assert.equal((await db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(bEmail)).get()).data()?.uid, bUid);
  assert.equal((await getAuth().getUser(bUid)).disabled, false, "the other student is untouched");
  assert.equal((await db.collection("student_roster").doc(b.key).get()).data()?.userId, bUid);
});
