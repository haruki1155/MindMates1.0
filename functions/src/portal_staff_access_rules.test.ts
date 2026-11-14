import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {collection, doc, getDoc, getDocs, setDoc} from "firebase/firestore";

// Role matrix for PACC portal data visibility. Every portal account state that
// the staff lifecycle can produce is represented, so a client that resolves a
// role more leniently than the server is caught here instead of in staging.
const projectId = "mind-mates-portal-staff-access-rules-test";
let environment: RulesTestEnvironment;

const verified = {email_verified: true};
const unverified = {email_verified: false};

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
      setDoc(doc(firestore, "users/admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(firestore, "users/counselor"), {
        accessRole: "counselor", approvedRole: "counselor",
        staffAccountStatus: "approved", accountStatus: "active",
      }),
      // Pre-lifecycle record: role only, no staffAccountStatus/accountStatus.
      setDoc(doc(firestore, "users/staff-legacy"), {accessRole: "portalStaff"}),
      setDoc(doc(firestore, "users/staff-approved"), {
        accessRole: "portalStaff", approvedRole: "portalStaff",
        staffAccountStatus: "approved", accountStatus: "active",
      }),
      // Registered, email verified, awaiting super-admin review.
      setDoc(doc(firestore, "users/staff-pending"), {
        accessRole: "appUser", approvedRole: null, requestedRole: "portalStaff",
        staffAccountStatus: "pending", accountStatus: "pending",
      }),
      // Approved role recorded, but the canonical access role was never
      // promoted. The Flutter client would resolve this as portal staff.
      setDoc(doc(firestore, "users/staff-stale-role"), {
        accessRole: "appUser", approvedRole: "portalStaff",
        staffAccountStatus: "approved", accountStatus: "active",
      }),
      // Suspended while the stored role string was left intact.
      setDoc(doc(firestore, "users/staff-suspended"), {
        accessRole: "portalStaff", approvedRole: "portalStaff",
        staffAccountStatus: "disabled", accountStatus: "suspended",
      }),
      setDoc(doc(firestore, "inquiries/inquiry-1"), {
        userId: "student", subject: "Schedule", message: "When is PACC open?",
        category: "General", email: "student@example.edu", status: "pending",
      }),
      setDoc(doc(firestore, "appointment_queue/appointment-1"), {
        appointmentId: "appointment-1", studentDisplayName: "Student Name",
        scheduledTime: "5:00 PM", status: "requested",
      }),
      setDoc(doc(firestore, "appointments/appointment-1"), {
        userId: "student", concern: "Sensitive concern",
      }),
    ]);
  });
});

after(async () => environment.cleanup());

test("approved, active, verified portal staff can list inquiries and the queue only", async () => {
  const staff = environment.authenticatedContext("staff-approved", verified).firestore();
  await assertSucceeds(getDocs(collection(staff, "inquiries")));
  await assertSucceeds(getDocs(collection(staff, "appointment_queue")));
  await assertFails(getDocs(collection(staff, "appointments")));
  await assertFails(getDoc(doc(staff, "users/student")));
});

test("legacy portal staff record without lifecycle fields keeps read access when verified", async () => {
  const legacy = environment.authenticatedContext("staff-legacy", verified).firestore();
  await assertSucceeds(getDocs(collection(legacy, "inquiries")));
  await assertSucceeds(getDocs(collection(legacy, "appointment_queue")));
  await assertFails(getDocs(collection(legacy, "appointments")));
  const legacyUnverified = environment.authenticatedContext("staff-legacy", unverified).firestore();
  await assertFails(getDocs(collection(legacyUnverified, "inquiries")));
  await assertFails(getDocs(collection(legacyUnverified, "appointment_queue")));
});

test("approved counselor can list inquiries and appointments but not other profiles", async () => {
  const counselor = environment.authenticatedContext("counselor", verified).firestore();
  await assertSucceeds(getDocs(collection(counselor, "inquiries")));
  await assertSucceeds(getDocs(collection(counselor, "appointments")));
  await assertFails(getDoc(doc(counselor, "users/student")));
  await assertFails(getDoc(doc(counselor, "users/staff-approved")));
});

test("pending staff registration cannot read any portal data", async () => {
  const pending = environment.authenticatedContext("staff-pending", verified).firestore();
  await assertFails(getDocs(collection(pending, "inquiries")));
  await assertFails(getDocs(collection(pending, "appointment_queue")));
  await assertFails(getDocs(collection(pending, "appointments")));
});

test("approvedRole alone never grants portal access", async () => {
  const stale = environment.authenticatedContext("staff-stale-role", verified).firestore();
  await assertFails(getDocs(collection(stale, "inquiries")));
  await assertFails(getDocs(collection(stale, "appointment_queue")));
});

test("suspended staff cannot read inquiries or the appointment queue", async () => {
  const suspended = environment.authenticatedContext("staff-suspended", verified).firestore();
  await assertFails(getDocs(collection(suspended, "inquiries")));
  await assertFails(getDocs(collection(suspended, "appointment_queue")));
});

test("approved staff without a verified email token cannot read inquiries or the queue", async () => {
  const staff = environment.authenticatedContext("staff-approved", unverified).firestore();
  await assertFails(getDocs(collection(staff, "inquiries")));
  await assertFails(getDocs(collection(staff, "appointment_queue")));
});

test("students only read their own inquiry", async () => {
  const student = environment.authenticatedContext("student", verified).firestore();
  await assertSucceeds(getDoc(doc(student, "inquiries/inquiry-1")));
  await assertFails(getDocs(collection(student, "inquiries")));
  await assertFails(getDocs(collection(student, "appointment_queue")));
});
