import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {Timestamp, getFirestore} from "firebase-admin/firestore";

import {
  RecoveryDeps, RecoveryMail, assertDevEndpointAllowed, confirmRecoveryEmailCode, requestRecoveryEmailCode,
  resetPasswordForStudentId,
} from "./student_account_recovery";
import {
  activateStudentAccountDev, confirmStudentRecoveryEmailCodeDev, confirmStudentRecoveryEmailCode,
  requestStudentPasswordResetDev, requestStudentPasswordReset as requestStudentPasswordResetProd,
  requestStudentRecoveryEmailCodeDev, requestStudentRecoveryEmailCode,
} from "./index";
import {studentAuthAliasEmail} from "./student_auth_alias";
import {
  RECOVERY_CONTACTS, RECOVERY_EMAILS, RECOVERY_VERIFICATIONS, recoveryEmailHash,
} from "./student_recovery_contacts";
import {generateActivationCode, hashActivationCode} from "./student_roster_domain";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type Err = {code?: string; message?: string; details?: {reason?: string; attemptsRemaining?: number}};
const db = getFirestore();
const run = `RC${Date.now()}`;
const runLower = run.toLowerCase();
const PASSWORD = "Str0ngPass!";
const DOB = "2004-05-06";
const keyOf = (n: string) => n.toUpperCase().replace(/[^A-Z0-9]/g, "");

const mails: RecoveryMail[] = [];
const clock = {t: Date.now()};
let codes: string[] = [];
let failMail = false;
let linkCalls: string[] = [];
const deps: RecoveryDeps = {
  sendMail: async (mail) => {
    if (failMail) throw new Error("smtp down");
    mails.push(mail);
  },
  now: () => clock.t,
  newCode: () => codes.shift() ?? generateActivationCode(),
  resetLink: async (alias) => {
    linkCalls.push(alias);
    return `https://example.test/__/auth/action?mode=resetPassword&oobCode=oob-${alias.split("@")[0]}`;
  },
  minResetResponseMs: 0,
};

const created = {uids: [] as string[], docs: [] as FirebaseFirestore.DocumentReference[]};

type Student = {tag: string; studentNo: string; key: string; alias: string; address: string; uid: string};

async function seedStudent(tag: string, opts: {verified?: boolean; disabled?: boolean} = {}): Promise<Student> {
  const studentNo = `${run}-${tag}`;
  const key = keyOf(studentNo);
  const alias = studentAuthAliasEmail(studentNo);
  const address = `${runLower}-${tag.toLowerCase()}@example.com`;
  const user = await getAuth().createUser({email: alias, password: PASSWORD, emailVerified: opts.verified === true,
    disabled: opts.disabled === true});
  const uid = user.uid;
  created.uids.push(uid);
  const refs = [
    db.collection("users").doc(uid), db.collection(RECOVERY_CONTACTS).doc(uid), db.collection(RECOVERY_VERIFICATIONS).doc(uid),
    db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(address)), db.collection("student_id_reservations").doc(key),
  ];
  created.docs.push(...refs);
  await Promise.all([
    refs[0].set({id: uid, email: address, schoolId: studentNo, populationRole: "student", studentIdLogin: true, firstName: "Juan"}),
    refs[1].set({uid, studentKey: key, email: address, emailHash: recoveryEmailHash(address),
      verifiedAt: opts.verified ? Timestamp.now() : null}),
    refs[3].set({uid, studentKey: key}),
    refs[4].set({userId: uid, studentId: studentNo}),
  ]);
  return {tag, studentNo, key, alias, address, uid};
}

let ipSeq = 0;
const as = (uid?: string, data: unknown = {}, ip = `10.${(ipSeq >> 8) & 255}.${ipSeq++ & 255}.1`) =>
  ({auth: uid ? {uid} : null, data, rawRequest: {ip}});
async function rejects(p: Promise<unknown>, code: string, reason?: string) {
  await assert.rejects(p, (e: Err) => {
    assert.equal(e?.code, code, `${e?.code}: ${e?.message}`);
    if (reason) assert.equal(e?.details?.reason, reason);
    return true;
  });
}
const lastCode = () => {
  const mail = mails.at(-1);
  assert.ok(mail, "a mail was sent");
  const found = /([A-Z2-9]{5}-[A-Z2-9]{5})/.exec(mail.text);
  assert.ok(found, "the mail carries a code");
  return found[1];
};
const verificationDoc = (uid: string) => db.collection(RECOVERY_VERIFICATIONS).doc(uid);
const contactDoc = (uid: string) => db.collection(RECOVERY_CONTACTS).doc(uid);

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST, "emulators required");
});

after(async () => {
  const limits = await db.collection("_student_recovery_limits").get();
  await Promise.all([
    ...created.docs.map((d) => d.delete()),
    ...created.uids.map((uid) => getAuth().deleteUser(uid).catch(() => undefined)),
    ...created.uids.map((uid) => db.collection("admin_audit_logs").where("actorId", "==", uid).get()
      .then((s) => Promise.all(s.docs.map((d) => d.ref.delete())))),
    ...limits.docs.map((d) => d.ref.delete()),
  ]);
});

function reset() {
  mails.length = 0;
  codes = [];
  failMail = false;
  linkCalls = [];
  clock.t = Date.now();
}

// ------------------------------------------------------------------ request code

test("requesting a code needs a signed-in student account", async () => {
  reset();
  await rejects(requestRecoveryEmailCode(as(undefined), deps), "unauthenticated");
  const other = await getAuth().createUser({email: `${runLower}-other@example.com`, password: PASSWORD});
  created.uids.push(other.uid);
  await rejects(requestRecoveryEmailCode(as(other.uid), deps), "failed-precondition");
  assert.equal(mails.length, 0);
});

test("the code is emailed to the recovery address only, never to or about the internal alias, and only its hash is stored", async () => {
  reset();
  const s = await seedStudent("RQ1");
  codes = ["ABCDE-FGHJK"];
  const result = await requestRecoveryEmailCode(as(s.uid), deps) as {accepted: boolean; maskedEmail: string; expiresInSeconds: number};
  assert.equal(result.accepted, true);
  assert.equal(result.expiresInSeconds, 900);
  assert.equal(result.maskedEmail, `${s.address[0]}***@example.com`);
  assert.equal(mails.length, 1);
  assert.equal(mails[0].to, s.address);
  assert.ok(mails[0].text.includes("ABCDE-FGHJK") && mails[0].html.includes("ABCDE-FGHJK"));
  const everything = JSON.stringify(mails[0]);
  assert.ok(!everything.includes("mindmate.local") && !everything.includes(s.alias) && !everything.includes(s.studentNo));
  const stored = (await verificationDoc(s.uid).get()).data() ?? {};
  assert.equal(stored.emailHash, recoveryEmailHash(s.address));
  assert.equal(stored.attempts, 0);
  assert.equal(stored.expiresAt.toMillis(), clock.t + 15 * 60 * 1000);
  assert.ok(!JSON.stringify(stored).includes("ABCDEFGHJK"), "the plaintext code is never stored");
  assert.ok(!JSON.stringify(result).includes("ABCDE"), "the plaintext code is never returned");
});

test("resending is throttled, replaces the previous code, and is rate limited per hour window", async () => {
  reset();
  const s = await seedStudent("RQ2");
  codes = ["AAAAA-BBBBB", "CCCCC-DDDDD"];
  await requestRecoveryEmailCode(as(s.uid), deps);
  await rejects(requestRecoveryEmailCode(as(s.uid), deps), "resource-exhausted");
  assert.equal(mails.length, 1);
  clock.t += 31_000;
  await requestRecoveryEmailCode(as(s.uid), deps);
  assert.equal(mails.length, 2);
  // The first code no longer works once a new one is issued.
  await rejects(confirmRecoveryEmailCode(as(s.uid, {code: "AAAAA-BBBBB"}), deps), "failed-precondition", "invalid-code");
  await confirmRecoveryEmailCode(as(s.uid, {code: "CCCCC-DDDDD"}), deps);

  const heavy = await seedStudent("RQ3");
  let sent = 0;
  for (let i = 0; i < 20; i++) {
    clock.t += 31_000;
    try {
      await requestRecoveryEmailCode(as(heavy.uid), deps);
      sent++;
    } catch (error) {
      assert.equal((error as Err).code, "resource-exhausted");
      break;
    }
  }
  assert.ok(sent >= 1 && sent <= 5, `limited after ${sent} sends`);
});

test("a delivery failure leaves no pending code and can be retried immediately", async () => {
  reset();
  const s = await seedStudent("RQ4");
  failMail = true;
  await rejects(requestRecoveryEmailCode(as(s.uid), deps), "unavailable");
  assert.equal((await verificationDoc(s.uid).get()).exists, false);
  failMail = false;
  await requestRecoveryEmailCode(as(s.uid), deps);
  assert.equal(mails.length, 1);
});

test("an already verified student is not mailed and a stale Auth flag is repaired", async () => {
  reset();
  const s = await seedStudent("RQ5", {verified: true});
  assert.deepEqual(await requestRecoveryEmailCode(as(s.uid), deps), {accepted: true, alreadyVerified: true});
  assert.equal(mails.length, 0);

  const half = await seedStudent("RQ6");
  await contactDoc(half.uid).update({verifiedAt: Timestamp.now()});
  assert.equal((await getAuth().getUser(half.uid)).emailVerified, false);
  assert.deepEqual(await requestRecoveryEmailCode(as(half.uid), deps), {accepted: true, alreadyVerified: true});
  assert.equal((await getAuth().getUser(half.uid)).emailVerified, true);
  assert.equal(mails.length, 0);
});

// ------------------------------------------------------------------ confirm code

test("the correct code verifies the recovery email, updates the Auth flag, audits without emails, and cannot be replayed", async () => {
  reset();
  const s = await seedStudent("CF1");
  codes = ["KKKKK-MMMMM"];
  await requestRecoveryEmailCode(as(s.uid), deps);
  assert.deepEqual(await confirmRecoveryEmailCode(as(s.uid, {code: "kkkkk mmmmm"}), deps), {verified: true});
  assert.equal((await getAuth().getUser(s.uid)).emailVerified, true);
  assert.ok((await contactDoc(s.uid).get()).data()?.verifiedAt instanceof Timestamp);
  assert.equal((await verificationDoc(s.uid).get()).exists, false);
  const audits = (await db.collection("admin_audit_logs").where("actorId", "==", s.uid).get()).docs.map((d) => d.data());
  assert.ok(audits.some((a) => a.action === "STUDENT_RECOVERY_EMAIL_VERIFIED" && a.targetId === s.key));
  const text = JSON.stringify(audits);
  assert.ok(!text.includes(s.address) && !text.includes("mindmate.local") && !text.includes("KKKKK"));

  // Replay: the code was consumed, so it cannot verify a later (changed) recovery address.
  const changed = `${runLower}-cf1-changed@example.com`;
  await contactDoc(s.uid).update({email: changed, emailHash: recoveryEmailHash(changed), verifiedAt: null});
  await getAuth().updateUser(s.uid, {emailVerified: false});
  await rejects(confirmRecoveryEmailCode(as(s.uid, {code: "KKKKK-MMMMM"}), deps), "failed-precondition", "expired");
  assert.equal((await getAuth().getUser(s.uid)).emailVerified, false);
  assert.equal((await contactDoc(s.uid).get()).data()?.verifiedAt, null);
});

test("wrong codes are counted, five of them lock the code, and a new code starts again", async () => {
  reset();
  const s = await seedStudent("CF2");
  codes = ["PPPPP-QQQQQ", "RRRRR-SSSSS"];
  await requestRecoveryEmailCode(as(s.uid), deps);
  for (let i = 1; i <= 4; i++) {
    await assert.rejects(confirmRecoveryEmailCode(as(s.uid, {code: "ZZZZZ-ZZZZZ"}), deps), (e: Err) => {
      assert.equal(e.code, "failed-precondition");
      assert.equal(e.details?.reason, "invalid-code");
      assert.equal(e.details?.attemptsRemaining, 5 - i);
      return true;
    });
  }
  await rejects(confirmRecoveryEmailCode(as(s.uid, {code: "ZZZZZ-ZZZZZ"}), deps), "failed-precondition", "invalid-code");
  // Locked: even the right code is refused now.
  await rejects(confirmRecoveryEmailCode(as(s.uid, {code: "PPPPP-QQQQQ"}), deps), "failed-precondition", "expired");
  assert.equal((await getAuth().getUser(s.uid)).emailVerified, false);
  clock.t += 31_000;
  await requestRecoveryEmailCode(as(s.uid), deps);
  assert.deepEqual(await confirmRecoveryEmailCode(as(s.uid, {code: "RRRRR-SSSSS"}), deps), {verified: true});
});

test("a malformed code is rejected without spending an attempt, and an expired code is rejected and removed", async () => {
  reset();
  const s = await seedStudent("CF3");
  codes = ["TTTTT-VVVVV"];
  await requestRecoveryEmailCode(as(s.uid), deps);
  await rejects(confirmRecoveryEmailCode(as(s.uid, {code: "short"}), deps), "invalid-argument");
  await rejects(confirmRecoveryEmailCode(as(s.uid, {}), deps), "invalid-argument");
  assert.equal((await verificationDoc(s.uid).get()).data()?.attempts, 0);
  clock.t += 15 * 60 * 1000 + 1;
  await rejects(confirmRecoveryEmailCode(as(s.uid, {code: "TTTTT-VVVVV"}), deps), "failed-precondition", "expired");
  assert.equal((await verificationDoc(s.uid).get()).exists, false);
  assert.equal((await getAuth().getUser(s.uid)).emailVerified, false);
});

test("a code is bound to the signed-in student and to the exact recovery address it was sent to", async () => {
  reset();
  const a = await seedStudent("CF4");
  const b = await seedStudent("CF5");
  codes = ["WWWWW-XXXXX"];
  await requestRecoveryEmailCode(as(a.uid), deps);
  // Another student's session cannot redeem it.
  await rejects(confirmRecoveryEmailCode(as(b.uid, {code: "WWWWW-XXXXX"}), deps), "failed-precondition", "expired");
  assert.equal((await getAuth().getUser(b.uid)).emailVerified, false);
  // If the recovery address changes after the code was sent, the code is void.
  const changed = `${runLower}-changed@example.com`;
  await contactDoc(a.uid).update({email: changed, emailHash: recoveryEmailHash(changed)});
  await rejects(confirmRecoveryEmailCode(as(a.uid, {code: "WWWWW-XXXXX"}), deps), "failed-precondition", "expired");
  assert.equal((await getAuth().getUser(a.uid)).emailVerified, false);
  assert.equal((await verificationDoc(a.uid).get()).exists, false);
  await rejects(confirmRecoveryEmailCode(as(undefined, {code: "WWWWW-XXXXX"}), deps), "unauthenticated");
});

test("confirming after the contact was verified but the Auth flag was not set repairs it safely", async () => {
  reset();
  const s = await seedStudent("CF6");
  await contactDoc(s.uid).update({verifiedAt: Timestamp.now()});
  assert.deepEqual(await confirmRecoveryEmailCode(as(s.uid, {code: "AAAAA-AAAAA"}), deps), {verified: true});
  assert.equal((await getAuth().getUser(s.uid)).emailVerified, true);
});

// ------------------------------------------------------------------ password reset

test("a verified student gets a reset link by email at the verified recovery address, with a generic response", async () => {
  reset();
  const s = await seedStudent("PR1", {verified: true});
  const result = await resetPasswordForStudentId(as(undefined, {studentId: s.studentNo}), deps);
  assert.deepEqual(result, {accepted: true});
  assert.equal(mails.length, 1);
  assert.equal(mails[0].to, s.address);
  assert.deepEqual(linkCalls, [s.alias]);
  assert.ok(mails[0].text.includes("oobCode=oob-"));
  const everything = JSON.stringify(mails[0]);
  assert.ok(!everything.includes(s.alias) && !everything.includes("students.mindmate.local"), "the alias is never shown");
  // Formatting of the Student ID does not matter.
  reset();
  await resetPasswordForStudentId(as(undefined, {studentId: ` ${s.studentNo.toLowerCase().replace("-", " ")} `}), deps);
  assert.equal(mails.length, 1);
});

test("every other case gets the identical response and no email (no account enumeration)", async () => {
  reset();
  const unverified = await seedStudent("PR2");
  const disabled = await seedStudent("PR3", {verified: true, disabled: true});
  const mismatched = await seedStudent("PR4", {verified: true});
  await contactDoc(mismatched.uid).update({studentKey: "SOMEONEELSE"});
  const noContact = await seedStudent("PR5", {verified: true});
  await contactDoc(noContact.uid).delete();
  const wrongAlias = await seedStudent("PR6", {verified: true});
  await getAuth().updateUser(wrongAlias.uid, {email: `${runLower}-pr6@revoked.mindmate.local`});
  // Each guard is independent: a contact that is unverified while Auth says verified, and the reverse, both get nothing.
  const contactUnverified = await seedStudent("PR11");
  await getAuth().updateUser(contactUnverified.uid, {emailVerified: true});
  const authUnverified = await seedStudent("PR12", {verified: true});
  await getAuth().updateUser(authUnverified.uid, {emailVerified: false});
  const ids = [unverified, disabled, mismatched, noContact, wrongAlias, contactUnverified, authUnverified].map((s) => s.studentNo)
    .concat([`${run}-DOES-NOT-EXIST`, "ABCDEFG123"]);
  for (const studentId of ids) {
    assert.deepEqual(await resetPasswordForStudentId(as(undefined, {studentId}), deps), {accepted: true}, studentId);
  }
  assert.equal(mails.length, 0);
  assert.equal(linkCalls.length, 0);
  // Only a malformed identifier is rejected, and that rule is public.
  await rejects(resetPasswordForStudentId(as(undefined, {studentId: "ab"}), deps), "invalid-argument");
  await rejects(resetPasswordForStudentId(as(undefined, {}), deps), "invalid-argument");
});

test("a mail delivery failure for a real account is indistinguishable from every other response", async () => {
  reset();
  const s = await seedStudent("PR7", {verified: true});
  failMail = true;
  assert.deepEqual(await resetPasswordForStudentId(as(undefined, {studentId: s.studentNo}), deps), {accepted: true});
});

test("the reset goes to the verified recovery contact even if the profile email was edited", async () => {
  reset();
  const s = await seedStudent("PR8", {verified: true});
  await db.collection("users").doc(s.uid).update({email: "attacker@example.net"});
  await resetPasswordForStudentId(as(undefined, {studentId: s.studentNo}), deps);
  assert.equal(mails.length, 1);
  assert.equal(mails[0].to, s.address);
});

test("reset requests are rate limited per Student ID and per caller, equally for real and unknown IDs", async () => {
  reset();
  const s = await seedStudent("PR9", {verified: true});
  const outcomes: string[] = [];
  for (let i = 0; i < 6; i++) {
    try {
      await resetPasswordForStudentId(as(undefined, {studentId: s.studentNo}, "198.51.100.9"), deps);
      outcomes.push("ok");
    } catch (error) {
      outcomes.push((error as Err).code ?? "?");
    }
  }
  assert.deepEqual(outcomes.slice(0, 3), ["ok", "ok", "ok"]);
  assert.ok(outcomes.slice(3).every((o) => o === "resource-exhausted"), outcomes.join());
  const unknown: string[] = [];
  for (let i = 0; i < 6; i++) {
    try {
      await resetPasswordForStudentId(as(undefined, {studentId: `${run}-NOPE`}, "198.51.100.10"), deps);
      unknown.push("ok");
    } catch (error) {
      unknown.push((error as Err).code ?? "?");
    }
  }
  assert.deepEqual(unknown, outcomes, "unknown IDs are limited exactly like real ones");
  const perIp: string[] = [];
  for (let i = 0; i < 16; i++) {
    try {
      await resetPasswordForStudentId(as(undefined, {studentId: `${run}-SPRAY${i}`}, "198.51.100.11"), deps);
      perIp.push("ok");
    } catch (error) {
      perIp.push((error as Err).code ?? "?");
    }
  }
  assert.ok(perIp.includes("resource-exhausted"), "a single caller cannot spray many IDs");
});

test("responses wait for a minimum time so existing and unknown IDs take the same time", async () => {
  reset();
  const slowDeps = {...deps, minResetResponseMs: 200};
  const s = await seedStudent("PR10", {verified: true});
  for (const studentId of [s.studentNo, `${run}-GHOST`]) {
    const started = Date.now();
    await resetPasswordForStudentId(as(undefined, {studentId}, `192.0.2.${studentId.length}`), slowDeps);
    assert.ok(Date.now() - started >= 190, `${studentId} answered too quickly`);
  }
});

// ------------------------------------------------------------------ endpoints

test("the callables exist for production and for Staging, and Dev endpoints refuse to run in production", () => {
  for (const callable of [
    requestStudentRecoveryEmailCode, requestStudentRecoveryEmailCodeDev, confirmStudentRecoveryEmailCode,
    confirmStudentRecoveryEmailCodeDev, requestStudentPasswordResetProd, requestStudentPasswordResetDev,
  ]) assert.equal(typeof (callable as unknown as {run: unknown}).run, "function");
  assert.doesNotThrow(() => assertDevEndpointAllowed("mindmate-staging"));
  assert.doesNotThrow(() => assertDevEndpointAllowed("demo-mindmate-mood-v2"));
  assert.throws(() => assertDevEndpointAllowed("mind-mates-cd2cf"), (e: Err) => e.code === "failed-precondition");
});

// ------------------------------------------------------------------ end to end

test("activate, verify the recovery email with the emailed code, then reset the password with the Student ID", async () => {
  reset();
  const studentNo = `${run}-E2E`;
  const key = keyOf(studentNo);
  const code = generateActivationCode();
  const stored = await hashActivationCode(code);
  const rosterRef = db.collection("student_roster").doc(key);
  created.docs.push(rosterRef, db.collection("student_id_reservations").doc(key));
  await rosterRef.set({studentNo, studentKey: key, surname: "Cruz", firstName: "Ana", middleName: "", dateOfBirth:
    Timestamp.fromDate(new Date(`${DOB}T00:00:00Z`)), dateOfBirthKey: DOB, collegeId: "c", college: "C", courseId: "k",
  course: "K", departmentId: "d", department: "D", yearLevel: "1st Year", status: "active", activated: false, userId: null,
  activationCode: {hash: stored.hash, salt: stored.salt, issuedAt: Timestamp.fromDate(stored.issuedAt),
    expiresAt: Timestamp.fromDate(stored.expiresAt)}});
  const address = `${runLower}-e2e@example.com`;
  const activated = await (activateStudentAccountDev as unknown as {run: (r: unknown) => Promise<{authEmail: string}>})
    .run({data: {studentNo, activationCode: code, dateOfBirth: DOB, email: address, password: PASSWORD}});
  assert.equal(activated.authEmail, studentAuthAliasEmail(studentNo));
  const user = await getAuth().getUserByEmail(studentAuthAliasEmail(studentNo));
  created.uids.push(user.uid);
  created.docs.push(db.collection("users").doc(user.uid), contactDoc(user.uid), verificationDoc(user.uid),
    db.collection(RECOVERY_EMAILS).doc(recoveryEmailHash(address)), db.collection("student_activation_attempts").doc(key));

  // Before verification a reset is silently ignored.
  await resetPasswordForStudentId(as(undefined, {studentId: studentNo}), deps);
  assert.equal(mails.length, 0);

  await requestRecoveryEmailCode(as(user.uid), deps);
  assert.equal(mails.at(-1)?.to, address);
  assert.deepEqual(await confirmRecoveryEmailCode(as(user.uid, {code: lastCode()}), deps), {verified: true});
  assert.equal((await getAuth().getUser(user.uid)).emailVerified, true);

  await resetPasswordForStudentId(as(undefined, {studentId: studentNo}, "192.0.2.200"), deps);
  assert.equal(mails.at(-1)?.to, address);
  assert.ok(mails.at(-1)?.text.includes("oobCode="));
});
