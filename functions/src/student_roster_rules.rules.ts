import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {after, before, beforeEach, test} from "node:test";
import {assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment} from "@firebase/rules-unit-testing";
import {collection, doc, getDoc, getDocs, setDoc, Timestamp, updateDoc} from "firebase/firestore";

let environment: RulesTestEnvironment;
before(async () => {
  environment = await initializeTestEnvironment({
    projectId: "mind-mates-roster-rules-test",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
});
beforeEach(async () => environment.clearFirestore());
after(async () => environment.cleanup());

function profile(id: string, accessRole = "appUser") {
  return {
    id, email: `${id}@mindmate.local`, name: "Profile User",
    firstName: "Profile", middleName: "", lastName: "User",
    schoolId: "S-1", yearLevel: "2nd Year", role: "student",
    accessRole, personalInfoRequired: true, rosterLinked: false,
    createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
  };
}

async function seed() {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users/u1"), profile("u1"));
    await setDoc(doc(db, "users/u2"), profile("u2"));
    await setDoc(doc(db, "users/staff"), profile("staff", "portalStaff"));
    await setDoc(doc(db, "users/counselor"), profile("counselor", "counselor"));
    await setDoc(doc(db, "users/admin"), profile("admin", "admin"));
    await setDoc(doc(db, "student_roster/X"), {studentNo: "X"});
    await setDoc(doc(db, "student_roster_imports/X"), {count: 1});
    await setDoc(doc(db, "student_activation_attempts/X"), {failures: 1});
    await setDoc(doc(db, "student_personal_info/u1"), {civilStatus: "Single"});
    await setDoc(doc(db, "student_personal_info/u2"), {civilStatus: "Single"});
    await setDoc(doc(db, "student_correction_requests/r1"), {userId: "u1", status: "pending"});
  });
}

for (const name of ["student_roster", "student_roster_imports", "student_activation_attempts"]) {
  test(`${name} is closed to every client role`, async () => {
    await seed();
    for (const uid of ["u1", "counselor", "admin"]) {
      const db = environment.authenticatedContext(uid).firestore();
      await assertFails(getDoc(doc(db, `${name}/X`)));
      await assertFails(getDocs(collection(db, name)));
      await assertFails(setDoc(doc(db, `${name}/X`), {tampered: true}));
    }
  });
}

test("student_personal_info is readable only by its owner and never writable", async () => {
  await seed();
  const owner = environment.authenticatedContext("u1").firestore();
  await assertSucceeds(getDoc(doc(owner, "student_personal_info/u1")));
  await assertFails(getDoc(doc(environment.authenticatedContext("u2").firestore(), "student_personal_info/u1")));
  await assertFails(getDoc(doc(environment.authenticatedContext("staff").firestore(), "student_personal_info/u1")));
  await assertFails(getDoc(doc(environment.authenticatedContext("counselor").firestore(), "student_personal_info/u1")));
  await assertFails(setDoc(doc(owner, "student_personal_info/u1"), {civilStatus: "Married"}));
  await assertFails(updateDoc(doc(owner, "student_personal_info/u1"), {civilStatus: "Married"}));
  await assertFails(getDocs(collection(owner, "student_personal_info")));
});

test("student_correction_requests are readable only by their requester and never writable", async () => {
  await seed();
  const owner = environment.authenticatedContext("u1").firestore();
  await assertSucceeds(getDoc(doc(owner, "student_correction_requests/r1")));
  await assertFails(getDoc(doc(environment.authenticatedContext("u2").firestore(), "student_correction_requests/r1")));
  await assertFails(setDoc(doc(owner, "student_correction_requests/r1"), {userId: "u1", status: "approved"}));
  await assertFails(updateDoc(doc(owner, "student_correction_requests/r1"), {status: "approved"}));
  await assertFails(setDoc(doc(owner, "student_correction_requests/r2"), {userId: "u1"}));
});

test("owners cannot write roster-managed profile fields", async () => {
  await seed();
  const ref = doc(environment.authenticatedContext("u1").firestore(), "users/u1");
  for (const patch of [
    {personalInfoRequired: false}, {rosterLinked: true},
    {yearLevel: "4th Year"}, {dateOfBirthKey: "2005-02-03"},
  ]) {
    await assertFails(updateDoc(ref, patch));
  }
});
