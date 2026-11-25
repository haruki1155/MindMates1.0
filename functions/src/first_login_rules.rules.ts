import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {after, before, beforeEach, test} from "node:test";
import {assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, Timestamp, updateDoc} from "firebase/firestore";

let environment: RulesTestEnvironment;
before(async () => {
  environment = await initializeTestEnvironment({
    projectId: "mind-mates-first-login-rules-test",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
});
beforeEach(async () => environment.clearFirestore());
after(async () => environment.cleanup());

const PENDING = {firstLoginPending: true};
const student = (id: string) => ({
  id, email: `${id}@students.mindmate.local`, name: "Pending Student", firstName: "Pending", middleName: "", lastName: "Student",
  schoolId: "QA-2026-0001", role: "student", populationRole: "student", declaredRole: "student", accessRole: "appUser",
  verificationStatus: "verified", profileVersion: 3, personalInfoRequired: true, mustChangePassword: true,
  createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
});

async function seed() {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users/s1"), student("s1"));
    await setDoc(doc(db, "users/s2"), student("s2"));
    await setDoc(doc(db, "moodEntries/m1"), {userId: "s1", mood: "Great", createdAt: Timestamp.now()});
    await setDoc(doc(db, "student_personal_info/s1"), {userId: "s1"});
  });
}

test("a first-login session can read only its own profile", async () => {
  await seed();
  const db = environment.authenticatedContext("s1", PENDING).firestore();
  await assertSucceeds(getDoc(doc(db, "users/s1")));
  await assertFails(getDoc(doc(db, "users/s2")));
});

test("a first-login session cannot read student data or edit its profile", async () => {
  await seed();
  const db = environment.authenticatedContext("s1", PENDING).firestore();
  await assertFails(getDoc(doc(db, "moodEntries/m1")));
  await assertFails(getDoc(doc(db, "student_personal_info/s1")));
  await assertFails(updateDoc(doc(db, "users/s1"), {firstName: "Changed"}));
  await assertFails(updateDoc(doc(db, "users/s1"), {mustChangePassword: false}));
  await assertFails(updateDoc(doc(db, "users/s1"), {personalInfoRequired: false}));
});

test("the same student without the claim keeps normal access", async () => {
  await seed();
  const db = environment.authenticatedContext("s1").firestore();
  await assertSucceeds(getDoc(doc(db, "users/s1")));
  await assertSucceeds(getDoc(doc(db, "moodEntries/m1")));
  await assertSucceeds(getDoc(doc(db, "student_personal_info/s1")));
  await assertSucceeds(updateDoc(doc(db, "users/s1"), {firstName: "Changed"}));
  await assertFails(updateDoc(doc(db, "users/s1"), {mustChangePassword: false}));
});

test("no client can read or write login issuance records, which hold password hashes", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "student_login_issuance/QA20260001"), {studentKey: "QA20260001", uid: "s1", hash: "x", salt: "y"});
  });
  for (const db of [environment.authenticatedContext("s1").firestore(), environment.authenticatedContext("s1", PENDING).firestore()]) {
    await assertFails(getDoc(doc(db, "student_login_issuance/QA20260001")));
    await assertFails(setDoc(doc(db, "student_login_issuance/QA20260001"), {hash: "z"}));
  }
});
