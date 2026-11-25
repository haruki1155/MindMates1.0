import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {Timestamp, getFirestore} from "firebase-admin/firestore";

import {LoginDeps, completePasswordChange, requestLogin, requestStudentLoginDev} from "./student_login";
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

// ------------------------------------------------------------------ completeStudentPasswordChange

const PERMANENT = "Perm4nent-Pass";
type Row = Awaited<ReturnType<typeof seedRow>>;
async function issue(tag: string) {
  const s = await seedRow(tag);
  emails.push(s.alias);
  mails.length = 0;
  await ask({studentId: s.studentNo});
  const user = (await userOf(s.alias))!;
  return {s, temp: passwordIn(mails[0]), uid: user.uid};
}
const complete = (uid: string, data: unknown, token: Record<string, unknown> = {}) =>
  completePasswordChange(
    {auth: {uid, token: {auth_time: Math.floor(clock.t / 1000), firstLoginPending: true, ...token}}, data},
    {now: () => clock.t},
  );
const code = (p: Promise<unknown>) => p.then(() => "ok", (e: {code?: string}) => e.code);
const issuanceOf = async (s: Row) => (await db.collection("student_login_issuance").doc(s.key).get()).data()!;

test("password change needs the first-login claim", async () => {
  const {uid} = await issue("c1");
  assert.equal(await code(complete(uid, {newPassword: PERMANENT}, {firstLoginPending: undefined})), "failed-precondition");
});

test("an account that is not a roster student account cannot use it, even with a forged claim", async () => {
  const other = await getAuth().createUser({email: `${run}-plain@example.com`, password: "Plain-Pass-123"});
  try {
    assert.equal(await code(complete(other.uid, {newPassword: PERMANENT})), "failed-precondition");
  } finally {
    await getAuth().deleteUser(other.uid);
  }
});

test("one student's change never touches another student's account", async () => {
  const a = await issue("c2a");
  const b = await issue("c2b");
  assert.equal(await code(complete(b.uid, {newPassword: PERMANENT})), "ok");
  assert.ok(await signIn(a.s.alias, a.temp), "A still has only the temporary password");
  assert.equal((await issuanceOf(a.s)).state, "issued");
});

test("an expired temporary issuance cannot complete", async () => {
  const {uid} = await issue("c3");
  clock.t += 25 * HOUR;
  assert.equal(await code(complete(uid, {newPassword: PERMANENT})), "failed-precondition");
});

test("a stale sign-in cannot complete", async () => {
  const {uid} = await issue("c4");
  assert.equal(await code(complete(uid, {newPassword: PERMANENT}, {auth_time: Math.floor(clock.t / 1000) - 10 * 60})), "failed-precondition");
});

test("the temporary password and weak passwords are refused", async () => {
  const {uid, temp} = await issue("c5");
  assert.equal(await code(complete(uid, {newPassword: temp})), "invalid-argument");
  assert.equal(await code(complete(uid, {newPassword: "short"})), "invalid-argument");
  assert.equal(await code(complete(uid, {})), "invalid-argument");
});

test("completion sets the permanent password, clears the gate and leaves no secrets behind", async () => {
  const {s, uid, temp} = await issue("c6");
  assert.equal(await code(complete(uid, {newPassword: PERMANENT})), "ok");
  assert.ok(await signIn(s.alias, PERMANENT));
  assert.ok(!(await signIn(s.alias, temp)));
  assert.equal((await getAuth().getUser(uid)).customClaims?.[FIRST_LOGIN_CLAIM], undefined);
  assert.equal((await db.collection("users").doc(uid).get()).data()?.mustChangePassword, false);
  const issuance = await issuanceOf(s);
  assert.equal(issuance.state, "completed");
  assert.equal(issuance.hash, undefined);
  const audits = await db.collection("admin_audit_logs").where("targetId", "==", s.key).where("action", "==", "STUDENT_PASSWORD_SET").get();
  assert.equal(audits.size, 1);
  docs.push(audits.docs[0].ref);
  assert.ok(!JSON.stringify(audits.docs[0].data()).includes(PERMANENT));
  // A request for a login never replaces a finished account's password.
  mails.length = 0;
  clock.t += 25 * HOUR;
  await ask({studentId: s.studentNo});
  assert.equal(mails.length, 0);
  assert.ok(await signIn(s.alias, PERMANENT));
  // The gate cannot be replayed: without the claim nothing runs, and a stale claim only gets cleared, never a new password.
  assert.equal(await code(complete(uid, {newPassword: "Another-Perm-9"}, {firstLoginPending: undefined})), "failed-precondition");
  assert.equal(await code(complete(uid, {newPassword: "Another-Perm-9"})), "ok");
  assert.ok(await signIn(s.alias, PERMANENT));
  assert.ok(!(await signIn(s.alias, "Another-Perm-9")));
});

// Auth refuses refresh tokens issued before tokensValidAfterTime, so a session opened with a replaced password
// is dead once that time moves past it. The emulator does not enforce it on refresh, so the recorded time is checked.
const validAfter = async (uid: string) => Date.parse((await getAuth().getUser(uid)).tokensValidAfterTime ?? "") || 0;
const pause = () => new Promise((r) => setTimeout(r, 1100)); // token times have one-second resolution

test("the permanent password revokes every session opened with the temporary one", async () => {
  const {uid} = await issue("c8");
  const before = await validAfter(uid);
  await pause();
  assert.equal(await code(complete(uid, {newPassword: PERMANENT})), "ok");
  assert.ok((await validAfter(uid)) > before, "sessions older than the change are revoked, so none can pick up the cleared claim");
});

test("reissuing a temporary password revokes sessions opened with the old one", async () => {
  const {s, uid} = await issue("c9");
  const before = await validAfter(uid);
  await pause();
  clock.t += 25 * HOUR;
  mails.length = 0;
  await ask({studentId: s.studentNo});
  assert.equal(mails.length, 1);
  assert.ok((await validAfter(uid)) > before);
});

test("an interrupted completion is reconciled by the next sign-in with the new password", async () => {
  const {s, uid} = await issue("c7");
  await assert.rejects(
    completePasswordChange(
      {auth: {uid, token: {auth_time: Math.floor(clock.t / 1000), firstLoginPending: true}}, data: {newPassword: PERMANENT}},
      {now: () => clock.t, afterAuthUpdate: async () => { throw new Error("crash after auth update"); }},
    ),
    /crash after auth update/,
  );
  assert.ok(await signIn(s.alias, PERMANENT), "Auth already holds the permanent password");
  assert.equal((await db.collection("users").doc(uid).get()).data()?.mustChangePassword, true);
  // The old session cannot finish it; a sign-in made after the change can, without sending the password again.
  assert.equal(await code(complete(uid, {}, {auth_time: Math.floor(clock.t / 1000) - 60})), "failed-precondition");
  assert.equal(await code(complete(uid, {}, {auth_time: Math.floor(clock.t / 1000) + 2})), "ok");
  assert.equal((await db.collection("users").doc(uid).get()).data()?.mustChangePassword, false);
  assert.equal((await getAuth().getUser(uid)).customClaims?.[FIRST_LOGIN_CLAIM], undefined);
  assert.equal((await issuanceOf(s)).state, "completed");
});
