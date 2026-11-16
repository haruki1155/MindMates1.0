import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {assertFails, initializeTestEnvironment, RulesTestEnvironment} from "@firebase/rules-unit-testing";
import {collection, deleteDoc, doc, getDoc, getDocs, setDoc} from "firebase/firestore";

// Case remarks (requirement #10) are server-only: no client role, including
// the assigned counselor and administrators, may read or write them directly.
// Access is only through the getCaseRemarks / saveCaseRemarks callables.
const projectId = "demo-mind-mates-case-remarks-rules-test";
let environment: RulesTestEnvironment;
const current = "appointments/appointment-1/case_remarks/current";
const version = `${current}/versions/1`;

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
      setDoc(doc(firestore, "users/student"), {accessRole: "appUser"}),
      setDoc(doc(firestore, "users/portal-staff"), {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"}),
      setDoc(doc(firestore, "users/counselor"), {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"}),
      setDoc(doc(firestore, "users/other-counselor"), {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"}),
      setDoc(doc(firestore, "users/admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(firestore, "appointments/appointment-1"), {userId: "student", assignedStaffId: "counselor"}),
      setDoc(doc(firestore, current), {text: "Private remark", revision: 1, studentId: "student"}),
      setDoc(doc(firestore, version), {text: "Private remark", revision: 1}),
    ]);
  });
});

after(async () => environment.cleanup());

test("no client role can read or list case remarks or their versions", async () => {
  for (const uid of ["student", "portal-staff", "counselor", "other-counselor", "admin"]) {
    const firestore = environment.authenticatedContext(uid, {email_verified: true}).firestore();
    await assertFails(getDoc(doc(firestore, current)));
    await assertFails(getDoc(doc(firestore, version)));
    await assertFails(getDocs(collection(firestore, "appointments/appointment-1/case_remarks")));
    await assertFails(getDocs(collection(firestore, `${current}/versions`)));
  }
  await assertFails(getDoc(doc(environment.unauthenticatedContext().firestore(), current)));
});

test("no client role can create, change or delete case remarks or their versions", async () => {
  for (const uid of ["student", "portal-staff", "counselor", "other-counselor", "admin"]) {
    const firestore = environment.authenticatedContext(uid, {email_verified: true}).firestore();
    await assertFails(setDoc(doc(firestore, current), {text: "Forged", revision: 2}));
    await assertFails(setDoc(doc(firestore, `${current}/versions/2`), {text: "Forged", revision: 2}));
    await assertFails(setDoc(doc(firestore, "appointments/appointment-1/case_remarks/other"), {text: "Forged"}));
    await assertFails(deleteDoc(doc(firestore, current)));
    await assertFails(deleteDoc(doc(firestore, version)));
  }
});
