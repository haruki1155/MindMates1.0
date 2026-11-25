import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {after, before, beforeEach, test} from "node:test";
import {assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, Firestore, getDoc, serverTimestamp, setDoc, Timestamp, updateDoc, writeBatch} from "firebase/firestore";

// Mirrors lib/features/counseling/data/guidance_quick_replies.dart.
const QUICK_REPLIES = [
  "I understand.",
  "Noted.",
  "Thank you for your guidance.",
  "I need clarification.",
  "I am available.",
  "I am not available.",
  "I would like a follow-up session.",
  "I need further assistance.",
  "My concern has been addressed.",
];

let environment: RulesTestEnvironment;
before(async () => {
  environment = await initializeTestEnvironment({
    projectId: "mind-mates-counselor-messaging-rules-test",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
});
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users/s1"), {role: "student", accessRole: "appUser", collegeId: "c-cite", name: "Ana Cruz"});
    await setDoc(doc(db, "users/s2"), {role: "student", accessRole: "appUser", collegeId: "c-cite", name: "Ben Reyes"});
    await setDoc(doc(db, "users/c1"), {role: "counselor", accessRole: "counselor", accountStatus: "active", staffAccountStatus: "approved"});
  });
});
after(async () => environment.cleanup());

const student = (uid = "s1", claims: Record<string, unknown> = {}) => environment.authenticatedContext(uid, claims).firestore();
const counselor = () => environment.authenticatedContext("c1", {email_verified: true}).firestore();

/** The app's send transaction: create or touch the thread and add one message. */
function studentSend(db: ReturnType<typeof student>, threadId: string, messageId: string, message: Record<string, unknown>) {
  // The rules-testing context hands back the compat type; the modular API accepts it at runtime.
  const batch = writeBatch(db as unknown as Firestore);
  batch.set(doc(db, `counselor_threads/${threadId}`), {
    userId: threadId,
    collegeId: "c-cite",
    updatedAt: serverTimestamp(),
    lastStudentMessageAt: serverTimestamp(),
    lastStudentMessageId: messageId,
  }, {merge: true});
  batch.set(doc(db, `counselor_threads/${threadId}/messages/${messageId}`), message);
  return batch.commit();
}

const reply = (text: string, extra: Record<string, unknown> = {}) =>
  ({senderId: "s1", senderRole: "user", text, createdAt: serverTimestamp(), ...extra});

async function seedThread() {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "counselor_threads/s1"), {userId: "s1", collegeId: "c-cite", updatedAt: Timestamp.now()});
    await setDoc(doc(db, "counselor_threads/s1/messages/legacy"), {
      senderId: "s1", senderRole: "user", text: "A free-text message from before quick replies.", createdAt: Timestamp.now(),
    });
  });
}

test("an app user can send each of the nine approved replies", async () => {
  for (const [index, text] of QUICK_REPLIES.entries()) {
    await assertSucceeds(studentSend(student(), "s1", `m${index}`, reply(text)));
  }
});

test("an app user cannot send free text or a near-miss of an approved reply", async () => {
  for (const text of ["Hello counselor", "Noted", "Noted. ", "noted.", "I UNDERSTAND."]) {
    await assertFails(studentSend(student(), "s1", "m1", reply(text)));
  }
});

test("an app user cannot forge the counselor role or add fields", async () => {
  await assertFails(studentSend(student(), "s1", "m1", reply("Noted.", {senderRole: "counselor"})));
  await assertFails(studentSend(student(), "s1", "m2", reply("Noted.", {replyId: "noted"})));
  await assertFails(studentSend(student(), "s1", "m3", reply("Noted.", {createdAt: Timestamp.now()})));
});

test("a first-login session cannot send even an approved reply", async () => {
  await assertFails(studentSend(student("s1", {firstLoginPending: true}), "s1", "m1", reply("Noted.")));
});

test("a student cannot write to or read another student's thread", async () => {
  await seedThread();
  await assertFails(studentSend(student("s2"), "s1", "m1", reply("Noted.", {senderId: "s2"})));
  await assertFails(getDoc(doc(student("s2"), "counselor_threads/s1/messages/legacy")));
});

test("an approved counselor can still send personalised free text", async () => {
  await seedThread();
  const db = counselor();
  // The rules-testing context hands back the compat type; the modular API accepts it at runtime.
  const batch = writeBatch(db as unknown as Firestore);
  batch.update(doc(db, "counselor_threads/s1"), {
    updatedAt: serverTimestamp(), lastCounselorMessageAt: serverTimestamp(), lastCounselorMessageId: "c-msg",
  });
  batch.set(doc(db, "counselor_threads/s1/messages/c-msg"), {
    senderId: "c1", senderRole: "counselor", text: "Please visit PACC on Monday at 10 AM.", createdAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
});

test("a signed-in non-counselor cannot write as a counselor", async () => {
  await seedThread();
  const db = student("s2", {email_verified: true});
  await assertFails(setDoc(doc(db, "counselor_threads/s1/messages/x"), {
    senderId: "s2", senderRole: "counselor", text: "Fake guidance", createdAt: serverTimestamp(),
  }));
});

const past = (minutes: number) => Timestamp.fromMillis(Date.now() - minutes * 60_000);
const future = (minutes: number) => Timestamp.fromMillis(Date.now() + minutes * 60_000);

test("an approved counselor stamps counselorReadAt with the student message time they saw", async () => {
  await seedThread();
  const thread = () => doc(counselor(), "counselor_threads/s1");
  await assertSucceeds(updateDoc(thread(), {counselorReadAt: past(10)}));
  await assertSucceeds(updateDoc(thread(), {counselorReadAt: serverTimestamp()}));
  await assertFails(updateDoc(thread(), {counselorReadAt: past(30)})); // never moves backwards
  await assertFails(updateDoc(doc(counselor(), "counselor_threads/s1"), {counselorReadAt: future(10)}));
  await assertFails(updateDoc(doc(student(), "counselor_threads/s1"), {counselorReadAt: past(1)}));
});

test("counselorReadAt cannot carry other thread changes", async () => {
  await seedThread();
  const thread = doc(counselor(), "counselor_threads/s1");
  await assertFails(updateDoc(thread, {counselorReadAt: past(1), collegeId: "c-other"}));
  await assertFails(updateDoc(thread, {counselorReadAt: past(1), studentName: "Someone"}));
  await assertFails(updateDoc(thread, {
    counselorReadAt: past(1), updatedAt: serverTimestamp(), lastCounselorMessageAt: serverTimestamp(),
    lastCounselorMessageId: "no-such-message",
  }));
});

test("a student records the counselor message time they saw, never a future time", async () => {
  await seedThread();
  const thread = doc(student(), "counselor_threads/s1");
  await assertSucceeds(updateDoc(thread, {studentReadAt: past(5)}));
  await assertSucceeds(updateDoc(thread, {studentReadAt: serverTimestamp()}));
  await assertFails(updateDoc(thread, {studentReadAt: future(5)}));
});

test("a student cannot create a message outside the send batch", async () => {
  await seedThread();
  await assertFails(setDoc(doc(student(), "counselor_threads/s1/messages/lone"), reply("Hello there")));
});

test("historical free-text messages stay readable by the student and counselor", async () => {
  await seedThread();
  await assertSucceeds(getDoc(doc(student(), "counselor_threads/s1/messages/legacy")));
  await assertSucceeds(getDoc(doc(counselor(), "counselor_threads/s1/messages/legacy")));
});
