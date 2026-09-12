import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {after, before, beforeEach, test} from "node:test";
import {assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, setDoc, Timestamp, updateDoc} from "firebase/firestore";

let environment: RulesTestEnvironment;
before(async () => {
  environment = await initializeTestEnvironment({
    projectId: "mind-mates-profile-rules-test",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
});
beforeEach(async () => environment.clearFirestore());
after(async () => environment.cleanup());

function profile(id: string, accessRole = "appUser") {
  return {
    id, email: `${id}@mindmate.local`, name: "Profile User",
    firstName: "Profile", middleName: "", lastName: "User",
    schoolId: "S-1", employeeId: "", department: "CITE", course: "BSIT",
    yearLevel: "2", sector: "", position: "", role: "student",
    populationRole: "student", declaredRole: "student", accessRole,
    verificationStatus: "pending", profileVersion: 2, verifiedAt: null,
    verifiedBy: "", createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
  };
}

test("only the backend creates profiles and owners can edit display fields", async () => {
  const db = environment.authenticatedContext("owner").firestore();
  const ref = doc(db, "users/owner");
  await assertFails(setDoc(ref, profile("owner")));
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/owner"), profile("owner"));
  });
  await assertSucceeds(updateDoc(ref, {firstName: "Updated", name: "Updated User"}));
});

test("owner cannot promote, verify, or change institutional identity", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/owner"), profile("owner"));
  });
  const ref = doc(environment.authenticatedContext("owner").firestore(), "users/owner");
  await assertFails(updateDoc(ref, {accessRole: "admin"}));
  await assertFails(updateDoc(ref, {verificationStatus: "verified"}));
  await assertFails(updateDoc(ref, {schoolId: "OTHER"}));
  await assertFails(updateDoc(ref, {populationRole: "teaching"}));
});

test("owners cannot transfer stored records to another user", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/owner"), profile("owner"));
    await setDoc(doc(context.firestore(), "reports/report-1"), {
      userId: "owner", title: "Private report", generatedAt: Timestamp.now(),
    });
  });
  const ref = doc(environment.authenticatedContext("owner").firestore(), "reports/report-1");
  await assertFails(updateDoc(ref, {userId: "another-user"}));
});

test("counselors cannot edit administrator-curated insight configuration", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/counselor"), profile("counselor", "counselor"));
    await setDoc(doc(context.firestore(), "users/admin"), profile("admin", "admin"));
  });
  await assertFails(setDoc(
    doc(environment.authenticatedContext("counselor").firestore(), "insight_categories/cat-1"),
    {name: "Private category"},
  ));
  await assertSucceeds(setDoc(
    doc(environment.authenticatedContext("admin").firestore(), "insight_categories/cat-1"),
    {name: "Curated category"},
  ));
});
