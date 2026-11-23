import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {Timestamp, getFirestore} from "firebase-admin/firestore";

import {activateStudentAccount, activateStudentAccountDev} from "./index";
import {generateActivationCode, hashActivationCode} from "./student_roster_domain";
import {studentAuthAliasEmail} from "./student_auth_alias";
import {CLAIM_PENDING, RECOVERY_CONTACTS, RECOVERY_EMAILS, recoveryEmailHash} from "./student_recovery_contacts";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown; rawRequest?: unknown}) => Promise<unknown>};
type Err = {code?: string; details?: {reason?: string}};

const db = getFirestore();
const run = `RET${Date.now()}`;
const DOB = "2004-05-06";
const PASSWORD = "Str0ngPass!";
const keyOf = (n: string) => n.toUpperCase().replace(/[^A-Z0-9]/g, "");
const endpoints: [string, Callable][] = [
  ["activateStudentAccount", activateStudentAccount as unknown as Callable],
  ["activateStudentAccountDev", activateStudentAccountDev as unknown as Callable],
];
const rows: string[] = [];
const emails: string[] = [];

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST, "emulators required");
});

after(async () => {
  await Promise.all(rows.flatMap((key) => [
    db.collection("student_roster").doc(key).delete(), db.collection("student_id_reservations").doc(key).delete(),
    db.collection("student_activation_attempts").doc(key).delete(),
  ]));
  await Promise.all(emails.map((e) => db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(e)).delete()));
});

/** A roster row that still holds a perfectly valid, unexpired activation code (as rows imported earlier do). */
async function seedRowWithValidCode(tag: string) {
  const studentNo = `${run}-${tag}`;
  const key = keyOf(studentNo);
  rows.push(key);
  const code = generateActivationCode();
  const stored = await hashActivationCode(code, new Date());
  await db.collection("student_roster").doc(key).set({
    studentNo, studentKey: key, surname: "Dela Cruz", surnameNormalized: "delacruz", firstName: "Juan", middleName: "Santos",
    dateOfBirth: Timestamp.fromDate(new Date(`${DOB}T00:00:00Z`)), dateOfBirthKey: DOB,
    collegeId: "c1", college: "College of Testing", courseId: "k1", course: "BS Testing", departmentId: "d1", department: "Testing Dept",
    yearLevel: "2nd Year", status: "active", activated: false, userId: null,
    activationCode: {hash: stored.hash, salt: stored.salt, issuedAt: Timestamp.fromDate(stored.issuedAt), expiresAt: Timestamp.fromDate(stored.expiresAt)},
  });
  return {studentNo, key, code};
}

async function authExists(address: string) {
  try {
    await getAuth().getUserByEmail(address);
    return true;
  } catch (error) {
    assert.equal((error as {code?: string}).code, "auth/user-not-found");
    return false;
  }
}

for (const [name, endpoint] of endpoints) {
  test(`${name}: a valid old activation code and date of birth cannot create or link a student identity`, async () => {
    const s = await seedRowWithValidCode(name.endsWith("Dev") ? "DEV" : "PROD");
    const address = `${run.toLowerCase()}-${name.toLowerCase()}@example.com`;
    emails.push(address);
    const before = (await db.collection("student_roster").doc(s.key).get()).data();

    await assert.rejects(endpoint.run({data: {
      studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: address, password: PASSWORD,
    }, rawRequest: {ip: "10.8.0.1"}}), (e: Err) => {
      assert.equal(e.code, "failed-precondition");
      assert.equal(e.details?.reason, "activation-retired");
      return true;
    });

    // Nothing was created or linked.
    assert.equal(await authExists(studentAuthAliasEmail(s.studentNo)), false, "no alias login");
    assert.equal(await authExists(address), false, "no login with the real email");
    assert.deepEqual((await db.collection("student_roster").doc(s.key).get()).data(), before, "roster row untouched, code not consumed");
    assert.equal((await db.collection("student_id_reservations").doc(s.key).get()).exists, false);
    assert.equal((await db.collection("student_activation_attempts").doc(s.key).get()).exists, false, "no attempt counter either");
    assert.equal((await db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(address)).get()).exists, false);
    const claims = await db.collection(CLAIM_PENDING).where("studentKey", "==", s.key).get();
    assert.equal(claims.size, 0);
    const contacts = await db.collection(RECOVERY_CONTACTS).where("studentKey", "==", s.key).get();
    assert.equal(contacts.size, 0);
  });

  test(`${name}: refuses every request the same way, signed in or not, valid or malformed, without reading it`, async () => {
    for (const data of [undefined, null, "x", [], {}, {studentNo: 1, activationCode: {}, dateOfBirth: [], email: 5, password: 6}]) {
      await assert.rejects(endpoint.run({data}), (e: Err) => e.code === "failed-precondition" && e.details?.reason === "activation-retired");
    }
    await assert.rejects(endpoint.run({auth: {uid: "someone"}, data: {}}), (e: Err) => e.code === "failed-precondition");
  });
}

test("a valid old code cannot be used to skip PACC approval: the only way to a roster-linked profile is the administrator approval", async () => {
  const s = await seedRowWithValidCode("BYPASS");
  for (const [, endpoint] of endpoints) {
    await assert.rejects(endpoint.run({data: {studentNo: s.studentNo, activationCode: s.code, dateOfBirth: DOB, email: "x@example.com", password: PASSWORD}}));
  }
  const row = (await db.collection("student_roster").doc(s.key).get()).data()!;
  assert.equal(row.activated, false);
  assert.equal(row.userId, null);
  assert.ok(row.activationCode?.hash, "the old code is left in place, to be swept after cutover, but is inert");
});
