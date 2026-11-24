import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {Timestamp, getFirestore} from "firebase-admin/firestore";

import {LoginDeps, requestLogin, requestStudentLoginDev} from "./student_login";
import {FIRST_LOGIN_CLAIM, passwordMatches} from "./student_login_domain";
import {studentAuthAliasEmail} from "./student_auth_alias";
import {RECOVERY_CONTACTS, RECOVERY_EMAILS, recoveryEmailHash} from "./student_recovery_contacts";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

const db = getFirestore();
const run = `SL${Date.now()}`;
const HOUR = 60 * 60 * 1000;
const clock = {t: Date.now()};
const mails: {to: string; subject: string; text: string}[] = [];
let failMail = false;
const deps: LoginDeps = {
  now: () => clock.t,
  minResponseMs: 0,
  sendMail: async (m) => {
    if (failMail) throw new Error("smtp down");
    mails.push(m);
  },
};
let ipSeq = 0;
const nextIp = () => `10.9.${(ipSeq >> 8) & 255}.${ipSeq++ & 255}`;
const ask = (data: unknown, ip = nextIp()) => requestLogin({data, rawRequest: {ip}}, deps);
const keyOf = (n: string) => n.toUpperCase().replace(/[^A-Z0-9]/g, "");
const docs: FirebaseFirestore.DocumentReference[] = [];
const emails: string[] = [];

async function seedRow(tag: string, extra: Record<string, unknown> = {}) {
  const studentNo = `${run}-${tag}`;
  const key = keyOf(studentNo);
  docs.push(
    db.collection("student_roster").doc(key), db.collection("student_id_reservations").doc(key),
    db.collection("student_login_issuance").doc(key),
  );
  await db.collection("student_roster").doc(key).set({
    studentNo, studentKey: key, surname: "Dela Cruz", surnameNormalized: "delacruz", firstName: "Juan", middleName: "S",
    dateOfBirth: Timestamp.fromDate(new Date("2005-03-15T00:00:00Z")), dateOfBirthKey: "2005-03-15",
    collegeId: "c1", college: "College of Testing", courseId: "k1", course: "BS Testing", departmentId: "d1", department: "Testing Dept",
    yearLevel: "2nd Year", status: "active", activated: false, userId: null, activationCode: null,
    contactEmail: `${tag}-${run}@Example.com`.toLowerCase(), ...extra,
  });
  return {studentNo, key, alias: studentAuthAliasEmail(key), email: String((extra.contactEmail as string) ?? `${tag}-${run}@example.com`).trim().toLowerCase()};
}

async function signIn(alias: string, password: string): Promise<boolean> {
  const res = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`, {
    method: "POST", headers: {"content-type": "application/json"},
    body: JSON.stringify({email: alias, password, returnSecureToken: true}),
  });
  return res.ok;
}
const passwordIn = (mail: {text: string}) => /Temporary password:\s*(\S{12})/.exec(mail.text)![1];
const userOf = (alias: string) => getAuth().getUserByEmail(alias).catch(() => null);

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST, "emulators required");
});

after(async () => {
  const users = await Promise.all(emails.map((a) => userOf(a)));
  const uids = users.filter(Boolean).map((u) => u!.uid);
  const limits = await db.collection("_student_recovery_limits").get();
  await Promise.all([
    ...docs.map((d) => d.delete()), ...uids.map((u) => getAuth().deleteUser(u).catch(() => undefined)),
    ...uids.map((u) => db.collection("users").doc(u).delete()), ...uids.map((u) => db.collection(RECOVERY_CONTACTS).doc(u).delete()),
    ...limits.docs.map((d) => d.ref.delete()),
  ]);
});

test("unknown Student ID and a row without an email get the neutral response and create nothing", async () => {
  const none = await seedRow("noemail", {contactEmail: ""});
  emails.push(none.alias);
  mails.length = 0;
  assert.deepEqual(await ask({studentId: `${run}-DOESNOTEXIST`}), {accepted: true});
  assert.deepEqual(await ask({studentId: none.studentNo}), {accepted: true});
  assert.equal(mails.length, 0);
  assert.equal(await userOf(none.alias), null);
});

test("an eligible student gets one email at the normalized roster address, and the account is linked and confined", async () => {
  const s = await seedRow("real", {contactEmail: "  Real.Student@Example.COM "});
  emails.push(s.alias);
  mails.length = 0;
  // A caller-supplied email or recipient must never redirect delivery.
  assert.deepEqual(await ask({studentId: s.studentNo, email: "evil@example.net", to: "evil@example.net"}), {accepted: true});
  assert.equal(mails.length, 1);
  assert.equal(mails[0].to, "real.student@example.com");
  assert.ok(mails[0].text.includes(s.studentNo));
  const password = passwordIn(mails[0]);
  assert.ok(await signIn(s.alias, password), "temporary password signs in");
  const user = (await userOf(s.alias))!;
  assert.equal(user.customClaims?.[FIRST_LOGIN_CLAIM], true);
  const profile = (await db.collection("users").doc(user.uid).get()).data()!;
  assert.equal(profile.mustChangePassword, true);
  assert.equal(profile.personalInfoRequired, true);
  assert.equal(profile.schoolId, s.studentNo);
  const roster = (await db.collection("student_roster").doc(s.key).get()).data()!;
  assert.equal(roster.activated, true);
  assert.equal(roster.userId, user.uid);
  assert.equal(roster.claimMethod, "roster-email-login");
  assert.equal((await db.collection("student_id_reservations").doc(s.key).get()).data()?.userId, user.uid);
  const contact = (await db.collection(RECOVERY_CONTACTS).doc(user.uid).get()).data()!;
  assert.equal(contact.email, "real.student@example.com");
  assert.ok(contact.verifiedAt);
  docs.push(db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash("real.student@example.com")));
  const issuance = (await db.collection("student_login_issuance").doc(s.key).get()).data()!;
  assert.ok(passwordMatches(password, issuance as {hash: string; salt: string}));
  assert.ok(!JSON.stringify(issuance).includes(password), "the password is never stored");
});

test("spacing, case and hyphens in the Student ID resolve to the same record", async () => {
  const s = await seedRow("canon");
  emails.push(s.alias);
  mails.length = 0;
  await ask({studentId: `  ${s.studentNo.toLowerCase().replace(run.toLowerCase(), `${run.toLowerCase()} `)}  `});
  assert.equal(mails.length, 1);
  assert.equal(mails[0].to, s.email);
});

test("concurrent requests create one identity and send one email", async () => {
  const s = await seedRow("race");
  emails.push(s.alias);
  mails.length = 0;
  await Promise.all(Array.from({length: 8}, () => ask({studentId: s.studentNo})));
  assert.equal(mails.length, 1);
  const found = await getAuth().listUsers(1000);
  assert.equal(found.users.filter((u) => u.email === s.alias).length, 1);
});

test("a repeat request inside the cooldown neither emails nor rotates the password", async () => {
  const s = await seedRow("cool");
  emails.push(s.alias);
  mails.length = 0;
  await ask({studentId: s.studentNo});
  const first = passwordIn(mails[0]);
  clock.t += 10 * 60 * 1000;
  await ask({studentId: s.studentNo});
  assert.equal(mails.length, 1);
  assert.ok(await signIn(s.alias, first));
});

test("after expiry a new request reissues and the old password stops working", async () => {
  const s = await seedRow("expire");
  emails.push(s.alias);
  mails.length = 0;
  await ask({studentId: s.studentNo});
  const first = passwordIn(mails[0]);
  clock.t += 25 * HOUR;
  await ask({studentId: s.studentNo});
  assert.equal(mails.length, 2);
  const second = passwordIn(mails[1]);
  assert.notEqual(first, second);
  assert.ok(!(await signIn(s.alias, first)));
  assert.ok(await signIn(s.alias, second));
  assert.equal((await userOf(s.alias))?.customClaims?.[FIRST_LOGIN_CLAIM], true);
});

test("reissue inside a day is capped at three and spaced by the cooldown", async () => {
  const s = await seedRow("cap");
  emails.push(s.alias);
  mails.length = 0;
  for (let i = 0; i < 5; i++) {
    await ask({studentId: s.studentNo});
    clock.t += HOUR + 60 * 1000;
  }
  assert.equal(mails.length, 3);
});

test("a student already activated by the old flow is never touched", async () => {
  const s = await seedRow("old", {activated: true, userId: `${run}-uid`});
  emails.push(s.alias);
  mails.length = 0;
  await ask({studentId: s.studentNo});
  assert.equal(mails.length, 0);
  assert.equal(await userOf(s.alias), null);
});

test("an email already used by an unrelated account creates no identity", async () => {
  const s = await seedRow("taken");
  emails.push(s.alias);
  const other = await getAuth().createUser({email: s.email, password: "Other-Pass-123"});
  try {
    mails.length = 0;
    await ask({studentId: s.studentNo});
    assert.equal(mails.length, 0);
    assert.equal(await userOf(s.alias), null);
  } finally {
    await getAuth().deleteUser(other.uid);
  }
});

test("a failed send is retried by the next request even inside the cooldown", async () => {
  const s = await seedRow("smtp");
  emails.push(s.alias);
  mails.length = 0;
  failMail = true;
  assert.deepEqual(await ask({studentId: s.studentNo}), {accepted: true});
  failMail = false;
  assert.equal(mails.length, 0);
  await ask({studentId: s.studentNo});
  assert.equal(mails.length, 1);
  assert.ok(await signIn(s.alias, passwordIn(mails[0])));
});

test("the per-caller limit refuses a flood from one address", async () => {
  const ip = "10.250.0.1";
  for (let i = 0; i < 10; i++) await ask({studentId: `${run}-FLOOD${i}`}, ip);
  await assert.rejects(ask({studentId: `${run}-FLOOD11`}, ip), (e: {code?: string}) => e.code === "resource-exhausted");
});

test("the Dev endpoint refuses to run outside non-production projects", async () => {
  const previous = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = "mindmate-prod-example";
  try {
    await assert.rejects(
      (requestStudentLoginDev as unknown as {run: (r: unknown) => Promise<unknown>}).run({data: {studentId: "ABC123"}, rawRequest: {ip: nextIp()}}),
      (e: {code?: string}) => e.code === "failed-precondition",
    );
  } finally {
    process.env.GCLOUD_PROJECT = previous;
  }
});
