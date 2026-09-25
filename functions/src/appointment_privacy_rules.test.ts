import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc} from "firebase/firestore";

const projectId = "mind-mates-appointment-privacy-rules-test";
let environment: RulesTestEnvironment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
    },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all([
      setDoc(doc(firestore, "users/student"), {accessRole: "appUser"}),
      setDoc(doc(firestore, "users/other-student"), {accessRole: "appUser"}),
      setDoc(doc(firestore, "users/portal-staff"), {accessRole: "portalStaff"}),
      setDoc(doc(firestore, "users/counselor"), {accessRole: "counselor"}),
      setDoc(doc(firestore, "users/other-counselor"), {accessRole: "counselor"}),
      setDoc(doc(firestore, "users/admin"), {accessRole: "admin"}),
      setDoc(doc(firestore, "appointments/appointment-1"), {
        userId: "student",
        assignedStaffId: "counselor",
        concern: "Sensitive concern",
      }),
      setDoc(doc(firestore, "appointments/appointment-1/history/terminal"), {
        outcome: "Sensitive history",
      }),
      setDoc(doc(firestore, "appointments/appointment-1/clinical_notes/session"), {
        summary: "Sensitive clinical note",
      }),
      setDoc(doc(firestore, "appointment_queue/appointment-1"), {
        appointmentId: "appointment-1",
        studentDisplayName: "Student Name",
        scheduledTime: "5:00 PM",
        status: "requested",
      }),
    ]);
  });
});

after(async () => environment.cleanup());

test("appointment and history reads follow ownership and clinical assignment", async () => {
  const student = environment.authenticatedContext("student").firestore();
  const otherStudent = environment.authenticatedContext("other-student").firestore();
  const counselor = environment.authenticatedContext("counselor").firestore();
  const otherCounselor = environment.authenticatedContext("other-counselor").firestore();
  const admin = environment.authenticatedContext("admin").firestore();

  await assertSucceeds(getDoc(doc(student, "appointments/appointment-1")));
  await assertFails(getDoc(doc(otherStudent, "appointments/appointment-1")));
  await assertSucceeds(getDoc(doc(counselor, "appointments/appointment-1")));
  await assertFails(getDoc(doc(otherCounselor, "appointments/appointment-1")));
  await assertSucceeds(getDoc(doc(admin, "appointments/appointment-1")));
  await assertSucceeds(getDoc(doc(counselor, "appointments/appointment-1/history/terminal")));
  await assertFails(getDoc(doc(otherCounselor, "appointments/appointment-1/history/terminal")));
});

test("portal staff can read only the minimal appointment queue", async () => {
  const portalStaff = environment.authenticatedContext("portal-staff").firestore();
  await assertFails(getDoc(doc(portalStaff, "appointments/appointment-1")));
  await assertFails(getDoc(doc(portalStaff, "appointments/appointment-1/history/terminal")));
  await assertSucceeds(getDoc(doc(portalStaff, "appointment_queue/appointment-1")));
});

test("clinical notes are visible only to the assigned counselor or admin", async () => {
  const student = environment.authenticatedContext("student").firestore();
  const portalStaff = environment.authenticatedContext("portal-staff").firestore();
  const counselor = environment.authenticatedContext("counselor").firestore();
  const otherCounselor = environment.authenticatedContext("other-counselor").firestore();
  const admin = environment.authenticatedContext("admin").firestore();
  const note = "appointments/appointment-1/clinical_notes/session";

  await assertFails(getDoc(doc(student, note)));
  await assertFails(getDoc(doc(portalStaff, note)));
  await assertSucceeds(getDoc(doc(counselor, note)));
  await assertFails(getDoc(doc(otherCounselor, note)));
  await assertSucceeds(getDoc(doc(admin, note)));
  await assertFails(setDoc(doc(counselor, note), {summary: "Client write"}));
});
