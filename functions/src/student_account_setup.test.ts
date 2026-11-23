import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {Timestamp, getFirestore} from "firebase-admin/firestore";

import {cancelAccountSetup, completeAccountSetup, startAccountSetup} from "./student_account_setup";
import {RecoveryDeps, RecoveryMail, confirmRecoveryEmailCode, requestRecoveryEmailCode} from "./student_account_recovery";
import {studentAuthAliasEmail} from "./student_auth_alias";
import {CLAIM_PENDING, RECOVERY_CONTACTS, RECOVERY_EMAILS, RECOVERY_VERIFICATIONS, recoveryEmailHash} from "./student_recovery_contacts";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type Err = {code?: string; message?: string};
const db = getFirestore();
const run = `NS${Date.now()}`;
const runLower = run.toLowerCase();
const PASSWORD = "Str0ngPass!";
const DOB = "2005-03-15";
const GENERIC = "We couldn't verify these details. Check them and try again.";
const keyOf = (n: string) => n.toUpperCase().replace(/[^A-Z0-9]/g, "");
const aliasOf = (n: string) => studentAuthAliasEmail(n);
const clock = {t: Date.now()};
const start = (data: unknown, ip = nextIp()) => startAccountSetup({auth: null, data, rawRequest: {ip}}, {now: () => clock.t});
let ipSeq = 0;
function nextIp() { return `10.7.${(ipSeq >> 8) & 255}.${ipSeq++ & 255}`; }

const mails: RecoveryMail[] = [];
const recoveryDeps: RecoveryDeps = {
  sendMail: async (m) => { mails.push(m); },
  now: () => clock.t,
  newCode: () => "ABCDE-FGHJK",
  resetLink: async (alias) => `https://example.test/${alias}`,
  minResetResponseMs: 0,
};

const docs: FirebaseFirestore.DocumentReference[] = [];
const authEmails = new Set<string>();
const uids: string[] = [];

async function seedRow(tag: string, extra: Record<string, unknown> = {}) {
  const studentNo = `${run}-${tag}`;
  const key = keyOf(studentNo);
  const ref = db.collection("student_roster").doc(key);
  docs.push(ref, db.collection("student_id_reservations").doc(key), db.collection("student_activation_attempts").doc(key));
  authEmails.add(aliasOf(studentNo));
  await ref.set({
    studentNo, studentKey: key, surname: "Dela Cruz", surnameNormalized: "delacruz", firstName: "Juan Carlos", middleName: "Santos",
    dateOfBirth: Timestamp.fromDate(new Date(`${DOB}T00:00:00Z`)), dateOfBirthKey: DOB,
    collegeId: "c1", college: "College of Testing", courseId: "k1", course: "BS Testing", departmentId: "d1", department: "Testing Dept",
    yearLevel: "2nd Year", status: "active", activated: false, userId: null, activationCode: null, ...extra,
  });
  return {studentNo, key, alias: aliasOf(studentNo), ref};
}

const email = (tag: string) => `${runLower}-${tag}@example.com`;
const payload = (s: {studentNo: string}, address: string, patch: Record<string, unknown> = {}) => ({
  studentNo: s.studentNo, firstName: "Juan Carlos", middleName: "Santos", lastName: "Dela Cruz", dateOfBirth: DOB,
  email: address, password: PASSWORD, ...patch,
});
async function rejects(p: Promise<unknown>, code: string, message?: string) {
  await assert.rejects(p, (e: Err) => {
    assert.equal(e.code, code, `${e.code}: ${e.message}`);
    if (message) assert.equal(e.message, message);
    return true;
  });
}
async function track(s: {studentNo: string}, address: string): Promise<string> {
  const user = await getAuth().getUserByEmail(aliasOf(s.studentNo));
  uids.push(user.uid);
  docs.push(db.collection("users").doc(user.uid), db.collection(RECOVERY_CONTACTS).doc(user.uid), db.collection(CLAIM_PENDING).doc(user.uid),
    db.collection(RECOVERY_VERIFICATIONS).doc(user.uid), db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(address.toLowerCase())));
  return user.uid;
}
const as = (uid?: string, ip = nextIp()) => ({auth: uid ? {uid} : null, data: {}, rawRequest: {ip}});
const authedConfirm = async (uid: string) => {
  mails.length = 0;
  await requestRecoveryEmailCode({...as(uid)}, recoveryDeps);
  const code = /([A-Z2-9]{5}-[A-Z2-9]{5})/.exec(mails.at(-1)!.text)![1];
  await confirmRecoveryEmailCode({...as(uid), data: {code}}, recoveryDeps);
};
const exists = async (ref: FirebaseFirestore.DocumentReference) => (await ref.get()).exists;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST, "emulators required");
});

after(async () => {
  const limits = await db.collection("_student_recovery_limits").get();
  const found: string[] = [...uids];
  for (const address of authEmails) {
    try { const u = await getAuth().getUserByEmail(address); found.push(u.uid); } catch { /* none */ }
  }
  const audits = found.length ? await db.collection("admin_audit_logs").where("actorId", "in", found.slice(0, 30)).get() : {docs: []};
  await Promise.all([
    ...docs.map((d) => d.delete()), ...found.map((uid) => getAuth().deleteUser(uid).catch(() => undefined)),
    ...found.map((uid) => db.collection(RECOVERY_CONTACTS).doc(uid).delete()),
    ...found.map((uid) => db.collection(CLAIM_PENDING).doc(uid).delete()),
    ...found.map((uid) => db.collection("users").doc(uid).delete()),
    ...limits.docs.map((d) => d.ref.delete()), ...audits.docs.map((d) => d.ref.delete()),
  ]);
});

test("start, verify the personal email, then complete: the claim is created only at the end and needs no code", async () => {
  const s = await seedRow("OK1");
  const address = email("ok1");
  clock.t = Date.now();
  const started = await start({...payload(s, address), activationCode: "IGNORED-CODE"}) as {ok: boolean; authEmail: string; email: string};
  assert.deepEqual(started, {ok: true, authEmail: s.alias, email: address});
  const uid = await track(s, address);

  // Setup has started: a login exists but nothing is claimed.
  const user = await getAuth().getUser(uid);
  assert.equal(user.email, s.alias);
  assert.equal(user.emailVerified, false);
  assert.equal(await exists(db.collection("users").doc(uid)), false, "no profile yet");
  assert.equal(await exists(db.collection("student_id_reservations").doc(s.key)), false, "no Student ID reservation yet");
  const rowBefore = (await s.ref.get()).data() ?? {};
  assert.equal(rowBefore.activated, false);
  assert.equal(rowBefore.userId, null);
  const pending = (await db.collection(CLAIM_PENDING).doc(uid).get()).data() ?? {};
  assert.equal(pending.studentKey, s.key);
  assert.equal(pending.expiresAt.toMillis(), clock.t + 15 * 60 * 1000);
  assert.equal((await db.collection(RECOVERY_CONTACTS).doc(uid).get()).data()?.verifiedAt, null);

  // Completing before the email is verified is refused.
  await rejects(completeAccountSetup({...as(uid)}, {now: () => clock.t}), "failed-precondition");
  assert.equal(await exists(db.collection("users").doc(uid)), false);

  await authedConfirm(uid);
  const verifiedPending = (await db.collection(CLAIM_PENDING).doc(uid).get()).data() ?? {};
  assert.equal(verifiedPending.expiresAt.toMillis(), clock.t + 24 * 60 * 60 * 1000, "a verified setup has a day to finish");

  const done = await completeAccountSetup({...as(uid)}, {now: () => clock.t});
  assert.deepEqual(done, {ok: true, alreadyComplete: false});
  const profile = (await db.collection("users").doc(uid).get()).data() ?? {};
  assert.equal(profile.schoolId, s.studentNo);
  assert.equal(profile.email, address, "the profile keeps the real contact email");
  assert.equal(profile.emailVerified, true);
  assert.equal(profile.claimMethod, "self-roster-match");
  assert.equal(profile.personalInfoRequired, true);
  assert.equal(profile.verifiedBy, "roster-activation");
  assert.equal(profile.college, "College of Testing");
  assert.ok(!JSON.stringify(profile).includes("mindmate.local"));
  assert.equal((await db.collection("student_id_reservations").doc(s.key).get()).data()?.userId, uid);
  const row = (await s.ref.get()).data() ?? {};
  assert.equal(row.activated, true);
  assert.equal(row.userId, uid);
  assert.equal(row.claimMethod, "self-roster-match");
  assert.equal(await exists(db.collection(CLAIM_PENDING).doc(uid)), false);
  const audits = (await db.collection("admin_audit_logs").where("actorId", "==", uid).get()).docs.map((d) => d.data());
  assert.ok(audits.some((a) => a.action === "STUDENT_ACCOUNT_CLAIMED" && a.targetId === s.key));
  assert.ok(!JSON.stringify(audits).includes(address) && !JSON.stringify(audits).includes("mindmate.local"));

  // Safe to repeat.
  assert.deepEqual(await completeAccountSetup({...as(uid)}, {now: () => clock.t}), {ok: true, alreadyComplete: true});
});

test("every mismatch returns the identical generic error and creates nothing", async () => {
  const good = await seedRow("MM1");
  const inactive = await seedRow("MM2", {status: "deactivated"});
  const claimed = await seedRow("MM3", {activated: true, userId: "someone"});
  const address = email("mm");
  const cases: Array<[string, unknown]> = [
    ["wrong first name", payload(good, address, {firstName: "Pedro"})],
    ["wrong last name", payload(good, address, {lastName: "Reyes"})],
    ["wrong middle name", payload(good, address, {middleName: "Lopez"})],
    ["wrong birth date", payload(good, address, {dateOfBirth: "2005-03-16"})],
    ["unknown Student ID", payload({studentNo: `${run}-NOPE`}, address)],
    ["inactive row", payload(inactive, address)],
    ["already claimed row", payload(claimed, address)],
  ];
  for (const [label, data] of cases) await rejects(start(data), "not-found", GENERIC).catch((e) => { throw new Error(`${label}: ${e.message}`); });
  for (const s of [good, inactive, claimed]) {
    await assert.rejects(getAuth().getUserByEmail(s.alias), (e: {code?: string}) => e.code === "auth/user-not-found");
    assert.equal(await exists(db.collection("student_id_reservations").doc(s.key)), s === claimed ? false : false);
  }
  assert.equal((await good.ref.get()).data()?.activated, false);
  // A malformed request (not a mismatch) is reported as invalid input, and format rules are public.
  await rejects(start(payload(good, address, {firstName: ""})), "invalid-argument");
  await rejects(start(payload(good, address, {dateOfBirth: "15/03/2005"})), "invalid-argument");
  await rejects(start(null), "invalid-argument");
});

test("five failed attempts lock a Student ID with the same generic answer", async () => {
  const s = await seedRow("LK1");
  for (let i = 0; i < 5; i++) await rejects(start(payload(s, email("lk"), {lastName: "Wrong"})), "not-found", GENERIC);
  await rejects(start(payload(s, email("lk"))), "not-found", GENERIC);
  await assert.rejects(getAuth().getUserByEmail(s.alias), (e: {code?: string}) => e.code === "auth/user-not-found");
});

test("only an unused personal email is accepted, and a rejected start leaves nothing behind", async () => {
  const s = await seedRow("EM1");
  for (const bad of ["staff@ucu.edu.ph", "x@students.mindmate.local", "a@mindmate.local", "not-an-email"]) {
    await rejects(start(payload(s, bad)), "invalid-argument");
  }
  const taken = email("taken");
  await getAuth().createUser({email: taken, password: PASSWORD}).then((u) => uids.push(u.uid));
  authEmails.add(taken);
  await rejects(start(payload(s, taken)), "already-exists");
  const other = await seedRow("EM2");
  await db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(email("reserved"))).set({uid: "another-student", studentKey: "X"});
  docs.push(db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(email("reserved"))));
  await rejects(start(payload(other, email("RESERVED").toUpperCase())), "already-exists");
  for (const row of [s, other]) {
    await assert.rejects(getAuth().getUserByEmail(row.alias), (e: {code?: string}) => e.code === "auth/user-not-found");
  }
});

test("a pending setup blocks others for 15 minutes, is then replaced, and a verified setup is not replaceable early", async () => {
  const s = await seedRow("PD1");
  clock.t = Date.now();
  await start(payload(s, email("pd1a")));
  const first = await track(s, email("pd1a"));
  // Someone else (or a retry) cannot take over within the window, and the first account is untouched.
  await rejects(start(payload(s, email("pd1b"))), "resource-exhausted");
  assert.equal((await getAuth().getUserByEmail(s.alias)).uid, first);

  clock.t += 16 * 60 * 1000;
  await start(payload(s, email("pd1b")));
  const second = await track(s, email("pd1b"));
  assert.notEqual(second, first, "an unverified, expired setup is replaced");
  await assert.rejects(getAuth().getUser(first), (e: {code?: string}) => e.code === "auth/user-not-found");
  assert.equal(await exists(db.collection(CLAIM_PENDING).doc(first)), false);
  assert.equal(await exists(db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(email("pd1a")))), false, "the old address is released");

  // Once the email is verified the setup is protected until it expires after a day.
  await authedConfirm(second);
  clock.t += 16 * 60 * 1000;
  await rejects(start(payload(s, email("pd1c"))), "resource-exhausted");
  assert.equal((await getAuth().getUserByEmail(s.alias)).uid, second);
});

test("an alias held by an account that is not a pending setup is never touched", async () => {
  const s = await seedRow("UH1");
  const holder = await getAuth().createUser({email: s.alias, password: "Holder!123"});
  uids.push(holder.uid);
  clock.t = Date.now() + 3600_000;
  await rejects(start(payload(s, email("uh1"))), "already-exists");
  const after = await getAuth().getUserByEmail(s.alias);
  assert.equal(after.uid, holder.uid);
  assert.equal(after.email, s.alias);
  assert.equal(await exists(db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(email("uh1")))), false);
});

test("two simultaneous setups for one Student ID: exactly one account and one reservation", async () => {
  const s = await seedRow("CC1");
  clock.t = Date.now();
  const results = await Promise.allSettled([email("cc1a"), email("cc1b")].map((a) => start(payload(s, a))));
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1, JSON.stringify(results.map((r) => r.status)));
  const winner = results[0].status === "fulfilled" ? email("cc1a") : email("cc1b");
  const loser = winner === email("cc1a") ? email("cc1b") : email("cc1a");
  const uid = await track(s, winner);
  docs.push(db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(loser)));
  assert.equal(await exists(db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(loser))), false, "the loser reserves nothing");
  assert.equal((await db.collection(RECOVERY_CONTACTS).where("studentKey", "==", s.key).get()).size, 1);
  assert.equal((await db.collection(CLAIM_PENDING).where("studentKey", "==", s.key).get()).size, 1);
  assert.equal((await getAuth().getUserByEmail(s.alias)).uid, uid);
});

test("completing re-checks the roster: a changed or already-claimed row cannot be claimed", async () => {
  const changed = await seedRow("RC1");
  await start(payload(changed, email("rc1")));
  const uid1 = await track(changed, email("rc1"));
  await authedConfirm(uid1);
  await changed.ref.update({surname: "Different"});
  await rejects(completeAccountSetup({...as(uid1)}, {now: () => clock.t}), "not-found", GENERIC);
  assert.equal(await exists(db.collection("users").doc(uid1)), false);

  const raced = await seedRow("RC2");
  await start(payload(raced, email("rc2")));
  const uid2 = await track(raced, email("rc2"));
  await authedConfirm(uid2);
  await raced.ref.update({activated: true, userId: "someone-else"});
  await rejects(completeAccountSetup({...as(uid2)}, {now: () => clock.t}), "not-found", GENERIC);
  assert.equal((await raced.ref.get()).data()?.userId, "someone-else");
  assert.equal(await exists(db.collection("student_id_reservations").doc(raced.key)), false);
});

test("completing needs a signed-in account that has a pending setup", async () => {
  await rejects(completeAccountSetup({...as(undefined)}, {now: () => clock.t}), "unauthenticated");
  const stranger = await getAuth().createUser({email: email("stranger"), password: PASSWORD});
  uids.push(stranger.uid);
  await rejects(completeAccountSetup({...as(stranger.uid)}, {now: () => clock.t}), "failed-precondition");
});

test("cancelling a pending setup removes only that setup and frees the email and Student ID", async () => {
  const s = await seedRow("CX1");
  const other = await seedRow("CX2");
  await start(payload(s, email("cx1")));
  const uid = await track(s, email("cx1"));
  await start(payload(other, email("cx2")));
  const otherUid = await track(other, email("cx2"));

  assert.deepEqual(await cancelAccountSetup({...as(uid)}), {ok: true});
  await assert.rejects(getAuth().getUser(uid), (e: {code?: string}) => e.code === "auth/user-not-found");
  assert.equal(await exists(db.collection(CLAIM_PENDING).doc(uid)), false);
  assert.equal(await exists(db.collection(RECOVERY_CONTACTS).doc(uid)), false);
  assert.equal(await exists(db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(email("cx1")))), false);
  assert.equal((await s.ref.get()).data()?.activated, false);
  // The other student's setup is untouched, and the first student can start again with the same email.
  assert.equal((await getAuth().getUser(otherUid)).email, other.alias);
  assert.equal(await exists(db.collection(CLAIM_PENDING).doc(otherUid)), true);
  await start(payload(s, email("cx1")));
  await track(s, email("cx1"));

  // A claimed account (profile exists) cannot be cancelled this way.
  await authedConfirm(otherUid);
  await completeAccountSetup({...as(otherUid)}, {now: () => clock.t});
  await rejects(cancelAccountSetup({...as(otherUid)}), "failed-precondition");
  assert.equal((await getAuth().getUser(otherUid)).email, other.alias);
});

test("each half of email verification is required on its own, and a held Student ID reservation blocks the claim", async () => {
  // Recovery contact verified but the Firebase account is not.
  const a = await seedRow("HV1");
  await start(payload(a, email("hv1")));
  const uidA = await track(a, email("hv1"));
  await db.collection(RECOVERY_CONTACTS).doc(uidA).update({verifiedAt: Timestamp.now()});
  await rejects(completeAccountSetup({...as(uidA)}, {now: () => clock.t}), "failed-precondition");
  assert.equal(await exists(db.collection("users").doc(uidA)), false);

  // Firebase account verified but the recovery contact is not.
  const b = await seedRow("HV2");
  await start(payload(b, email("hv2")));
  const uidB = await track(b, email("hv2"));
  await getAuth().updateUser(uidB, {emailVerified: true});
  await rejects(completeAccountSetup({...as(uidB)}, {now: () => clock.t}), "failed-precondition");
  assert.equal(await exists(db.collection("users").doc(uidB)), false);

  // Fully verified, but the Student ID reservation is held by another account.
  const c = await seedRow("HV3");
  await start(payload(c, email("hv3")));
  const uidC = await track(c, email("hv3"));
  await authedConfirm(uidC);
  await db.collection("student_id_reservations").doc(c.key).set({userId: "another-uid", studentId: c.studentNo});
  await rejects(completeAccountSetup({...as(uidC)}, {now: () => clock.t}), "not-found", GENERIC);
  assert.equal((await db.collection("student_id_reservations").doc(c.key).get()).data()?.userId, "another-uid");
  assert.equal((await c.ref.get()).data()?.activated, false);

  // An expired pending setup cannot be completed even if everything else is in order.
  const d = await seedRow("HV4");
  await start(payload(d, email("hv4")));
  const uidD = await track(d, email("hv4"));
  await authedConfirm(uidD);
  await db.collection(CLAIM_PENDING).doc(uidD).update({expiresAt: Timestamp.fromMillis(clock.t - 1000)});
  await rejects(completeAccountSetup({...as(uidD)}, {now: () => clock.t}), "failed-precondition");
});
