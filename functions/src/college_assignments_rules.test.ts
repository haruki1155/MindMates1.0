import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, updateDoc} from "firebase/firestore";

// College assignments on users/{uid} are written only by the
// setStaffCollegeAssignments callable. No client, including the
// super-administrator and the assignee, may write them directly.
const projectId = "mind-mates-college-assignment-rules-test";
let environment: RulesTestEnvironment;
const verified = {email_verified: true};

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all([
      setDoc(doc(firestore, "system_config/security"), {superAdminUid: "admin"}),
      setDoc(doc(firestore, "users/admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(firestore, "users/counselor"), {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", firstName: "C", assignedCollegeIds: ["cite"], collegeAssignmentRevision: 1}),
      setDoc(doc(firestore, "users/staff"), {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", firstName: "S"}),
      setDoc(doc(firestore, "users/student"), {accessRole: "appUser", firstName: "St"}),
    ]);
  });
});

after(async () => environment.cleanup());

const assignmentWrites = [
  {assignedCollegeIds: ["cite", "cas"]},
  {assignedCollegeIds: []},
  {collegeAssignmentRevision: 99},
  {collegeAssignmentUpdatedBy: "someone"},
];

test("students, staff and counselors cannot change their own college assignments", async () => {
  for (const uid of ["counselor", "staff", "student"]) {
    const firestore = environment.authenticatedContext(uid, verified).firestore();
    for (const patch of assignmentWrites) {
      await assertFails(updateDoc(doc(firestore, `users/${uid}`), patch));
      await assertFails(updateDoc(doc(firestore, `users/${uid}`), {...patch, firstName: "Renamed"}));
    }
  }
});

test("no client, not even the super-administrator, writes assignments on another account", async () => {
  for (const uid of ["admin", "staff", "counselor"]) {
    const firestore = environment.authenticatedContext(uid, verified).firestore();
    await assertFails(updateDoc(doc(firestore, "users/student"), {assignedCollegeIds: ["cite"]}));
    await assertFails(updateDoc(doc(firestore, uid === "counselor" ? "users/staff" : "users/counselor"), {assignedCollegeIds: ["cas"]}));
  }
});

test("owners still read their own profile and make allowed self-updates; others cannot read it", async () => {
  const counselor = environment.authenticatedContext("counselor", verified).firestore();
  await assertSucceeds(getDoc(doc(counselor, "users/counselor")));
  await assertSucceeds(updateDoc(doc(counselor, "users/counselor"), {firstName: "Renamed"}));
  await assertSucceeds(getDoc(doc(environment.authenticatedContext("admin", verified).firestore(), "users/counselor")));
  await assertFails(getDoc(doc(environment.authenticatedContext("staff", verified).firestore(), "users/counselor")));
});
