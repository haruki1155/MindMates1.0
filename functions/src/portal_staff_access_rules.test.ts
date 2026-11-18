import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestContext,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {collection, doc, getDoc, getDocs, query, setDoc, updateDoc, where} from "firebase/firestore";

// Operational portalStaff read ONLY explicit monitoring assignments in
// `inquiry_statuses` (and `appointment_queue`), never raw `inquiries`.
// Counselors read assigned raw `inquiries`; unfiltered lists are denied.
const assigned = (firestore: ReturnType<RulesTestContext["firestore"]>, uid: string) =>
  getDocs(query(collection(firestore, "inquiries"), where("assigneeIds", "array-contains", uid)));
const assignedStatus = (firestore: ReturnType<RulesTestContext["firestore"]>, uid: string) =>
  getDocs(query(collection(firestore, "inquiry_statuses"), where("monitoringStaffIds", "array-contains", uid)));

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
      setDoc(doc(firestore, "users/student"), {
        accessRole: "appUser", collegeId: "cite", verificationStatus: "verified",
      }),
      setDoc(doc(firestore, "users/admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(firestore, "users/counselor"), {
        accessRole: "counselor", approvedRole: "counselor",
        staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"],
      }),
      // Pre-lifecycle record: role only, no staffAccountStatus/accountStatus.
      setDoc(doc(firestore, "users/staff-legacy"), {accessRole: "portalStaff"}),
      // Suspended while the stored clinical role string was left intact.
      setDoc(doc(firestore, "users/counselor-suspended"), {
        accessRole: "counselor", approvedRole: "counselor",
        staffAccountStatus: "disabled", accountStatus: "suspended", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "appointments/appointment-1/clinical_notes/session"), {
        summary: "Sensitive clinical note",
      }),
      setDoc(doc(firestore, "mind_aid_emergency_alerts/alert-1"), {userId: "student"}),
      // Legacy records: no staffAccountStatus. Absent or active accountStatus
      // keeps access; an explicit suspended/disabled status must not.
      setDoc(doc(firestore, "users/counselor-legacy"), {accessRole: "counselor", assignedCollegeIds: ["cite"]}),
      setDoc(doc(firestore, "users/counselor-legacy-active"), {accessRole: "counselor", accountStatus: "active", assignedCollegeIds: ["cite"]}),
      setDoc(doc(firestore, "users/counselor-legacy-suspended"), {accessRole: "counselor", accountStatus: "suspended", assignedCollegeIds: ["cite"]}),
      setDoc(doc(firestore, "users/staff-legacy-disabled"), {accessRole: "portalStaff", accountStatus: "disabled"}),
      setDoc(doc(firestore, "users/admin-suspended"), {accessRole: "admin", accountStatus: "suspended"}),
      setDoc(doc(firestore, "system_config/security"), {superAdminUid: "admin"}),
      setDoc(doc(firestore, "mind_aid_config/current"), {enabled: true}),
      setDoc(doc(firestore, "admin_audit_logs/audit-1"), {action: "TEST"}),
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
        routingStatus: "routed", collegeId: "cite",
        assigneeIds: [
          "staff-approved", "staff-legacy", "counselor", "staff-pending", "staff-stale-role",
          "staff-suspended", "counselor-legacy", "counselor-legacy-active",
          "counselor-legacy-suspended", "staff-legacy-disabled",
        ],
        monitoringStaffIds: [
          "staff-approved", "staff-legacy", "staff-pending", "staff-stale-role",
          "staff-suspended", "staff-legacy-disabled",
        ],
      }),
      setDoc(doc(firestore, "inquiry_statuses/inquiry-1"), {
        inquiryId: "inquiry-1", category: "General", operationalLabel: "General Inquiry",
        status: "pending", routingStatus: "routed", collegeId: "cite",
        assigneeIds: ["counselor", "counselor-legacy", "counselor-legacy-active", "counselor-legacy-suspended"],
        monitoringStaffIds: [
          "staff-approved", "staff-legacy", "staff-pending", "staff-stale-role",
          "staff-suspended", "staff-legacy-disabled",
        ],
      }),
      setDoc(doc(firestore, "appointment_queue/appointment-1"), {
        appointmentId: "appointment-1", studentDisplayName: "Student Name",
        scheduledTime: "5:00 PM", status: "requested",
      }),
      setDoc(doc(firestore, "appointments/appointment-1"), {
        userId: "student", collegeId: "cite", studentVerificationStatus: "verified", concern: "Sensitive concern",
      }),
    ]);
  });
});

after(async () => environment.cleanup());

test("approved, active, verified portal staff can read inquiry_statuses and appointment_queue only, never raw inquiries", async () => {
  const staff = environment.authenticatedContext("staff-approved", verified).firestore();
  await assertFails(assigned(staff, "staff-approved"));
  await assertFails(getDoc(doc(staff, "inquiries/inquiry-1")));
  await assertSucceeds(assignedStatus(staff, "staff-approved"));
  await assertFails(getDocs(collection(staff, "inquiry_statuses")));
  await assertSucceeds(getDocs(collection(staff, "appointment_queue")));
  await assertFails(getDocs(collection(staff, "appointments")));
  await assertFails(getDoc(doc(staff, "users/student")));
});

test("legacy portal staff record without lifecycle fields keeps verified inquiry_statuses and queue access, never raw inquiries", async () => {
  const legacy = environment.authenticatedContext("staff-legacy", verified).firestore();
  await assertFails(assigned(legacy, "staff-legacy"));
  await assertSucceeds(assignedStatus(legacy, "staff-legacy"));
  await assertSucceeds(getDocs(collection(legacy, "appointment_queue")));
  await assertFails(getDocs(collection(legacy, "appointments")));
  const legacyUnverified = environment.authenticatedContext("staff-legacy", unverified).firestore();
  await assertFails(assigned(legacyUnverified, "staff-legacy"));
  await assertFails(assignedStatus(legacyUnverified, "staff-legacy"));
  await assertFails(getDocs(collection(legacyUnverified, "appointment_queue")));
});

test("approved counselor can list assigned-college inquiries and appointments, never unfiltered appointments or other profiles", async () => {
  const counselor = environment.authenticatedContext("counselor", verified).firestore();
  await assertSucceeds(assigned(counselor, "counselor"));
  await assertSucceeds(getDocs(query(
    collection(counselor, "appointments"),
    where("studentVerificationStatus", "==", "verified"),
    where("collegeId", "in", ["cite"]),
  )));
  await assertFails(getDocs(collection(counselor, "appointments")));
  await assertFails(getDoc(doc(counselor, "users/student")));
  await assertFails(getDoc(doc(counselor, "users/staff-approved")));
});

test("clinical reads require the full staff lifecycle, not just the counselor role", async () => {
  const approved = environment.authenticatedContext("counselor", verified).firestore();
  await assertSucceeds(getDoc(doc(approved, "appointments/appointment-1")));
  await assertSucceeds(getDoc(doc(approved, "appointments/appointment-1/clinical_notes/session")));
  await assertSucceeds(getDocs(collection(approved, "mind_aid_emergency_alerts")));

  const suspended = environment.authenticatedContext("counselor-suspended", verified).firestore();
  await assertFails(getDoc(doc(suspended, "appointments/appointment-1")));
  await assertFails(getDoc(doc(suspended, "appointments/appointment-1/clinical_notes/session")));
  await assertFails(getDocs(collection(suspended, "appointments")));
  await assertFails(getDocs(collection(suspended, "mind_aid_emergency_alerts")));

  const unverifiedCounselor = environment.authenticatedContext("counselor", unverified).firestore();
  await assertFails(getDoc(doc(unverifiedCounselor, "appointments/appointment-1")));
  await assertFails(getDoc(doc(unverifiedCounselor, "appointments/appointment-1/clinical_notes/session")));
  await assertFails(getDocs(collection(unverifiedCounselor, "appointments")));
});

test("administrator clinical reads require a verified email token", async () => {
  await assertSucceeds(getDoc(doc(environment.authenticatedContext("admin", verified).firestore(), "appointments/appointment-1")));
  await assertFails(getDoc(doc(environment.authenticatedContext("admin", unverified).firestore(), "appointments/appointment-1")));
});

test("pending staff registration cannot read any portal data", async () => {
  const pending = environment.authenticatedContext("staff-pending", verified).firestore();
  await assertFails(assigned(pending, "staff-pending"));
  await assertFails(assignedStatus(pending, "staff-pending"));
  await assertFails(getDocs(collection(pending, "appointment_queue")));
  await assertFails(getDocs(collection(pending, "appointments")));
});

test("approvedRole alone never grants portal access", async () => {
  const stale = environment.authenticatedContext("staff-stale-role", verified).firestore();
  await assertFails(assigned(stale, "staff-stale-role"));
  await assertFails(assignedStatus(stale, "staff-stale-role"));
  await assertFails(getDocs(collection(stale, "appointment_queue")));
});

test("suspended staff cannot read inquiries, status projections, or the appointment queue", async () => {
  const suspended = environment.authenticatedContext("staff-suspended", verified).firestore();
  await assertFails(assigned(suspended, "staff-suspended"));
  await assertFails(assignedStatus(suspended, "staff-suspended"));
  await assertFails(getDocs(collection(suspended, "appointment_queue")));
});

test("approved staff without a verified email token cannot read inquiries, status projections, or the queue", async () => {
  const staff = environment.authenticatedContext("staff-approved", unverified).firestore();
  await assertFails(assigned(staff, "staff-approved"));
  await assertFails(assignedStatus(staff, "staff-approved"));
  await assertFails(getDocs(collection(staff, "appointment_queue")));
});

test("students only read their own inquiry", async () => {
  const student = environment.authenticatedContext("student", verified).firestore();
  await assertSucceeds(getDoc(doc(student, "inquiries/inquiry-1")));
  await assertFails(getDocs(collection(student, "inquiries")));
  await assertFails(getDocs(collection(student, "appointment_queue")));
});

test("explicit suspended or disabled status denies legacy records; absent or active status keeps access", async () => {
  const legacy = environment.authenticatedContext("counselor-legacy", verified).firestore();
  const legacyActive = environment.authenticatedContext("counselor-legacy-active", verified).firestore();
  await assertSucceeds(getDoc(doc(legacy, "appointments/appointment-1")));
  await assertSucceeds(getDoc(doc(legacyActive, "appointments/appointment-1/clinical_notes/session")));
  await assertSucceeds(assigned(legacyActive, "counselor-legacy-active"));

  const suspended = environment.authenticatedContext("counselor-legacy-suspended", verified).firestore();
  await assertFails(getDoc(doc(suspended, "appointments/appointment-1")));
  await assertFails(getDoc(doc(suspended, "appointments/appointment-1/clinical_notes/session")));
  await assertFails(getDocs(collection(suspended, "mind_aid_emergency_alerts")));
  await assertFails(assigned(suspended, "counselor-legacy-suspended"));

  const disabledStaff = environment.authenticatedContext("staff-legacy-disabled", verified).firestore();
  await assertFails(getDocs(collection(disabledStaff, "appointment_queue")));
  await assertFails(assigned(disabledStaff, "staff-legacy-disabled"));
  await assertFails(assignedStatus(disabledStaff, "staff-legacy-disabled"));
});

test("administrator rule gates require the verified, active lifecycle", async () => {
  const admin = environment.authenticatedContext("admin", verified).firestore();
  await assertSucceeds(getDoc(doc(admin, "users/student")));
  await assertSucceeds(getDoc(doc(admin, "admin_audit_logs/audit-1")));
  await assertSucceeds(getDoc(doc(admin, "mind_aid_config/current")));

  const adminUnverified = environment.authenticatedContext("admin", unverified).firestore();
  await assertFails(getDoc(doc(adminUnverified, "users/student")));
  await assertFails(getDoc(doc(adminUnverified, "admin_audit_logs/audit-1")));
  await assertFails(getDoc(doc(adminUnverified, "mind_aid_config/current")));

  const adminSuspended = environment.authenticatedContext("admin-suspended", verified).firestore();
  await assertFails(getDoc(doc(adminSuspended, "appointments/appointment-1")));
  await assertFails(getDoc(doc(adminSuspended, "mind_aid_config/current")));
  await environment.withSecurityRulesDisabled(async (context) =>
    setDoc(doc(context.firestore(), "system_config/security"), {superAdminUid: "admin-suspended"}));
  await assertFails(getDoc(doc(adminSuspended, "users/student")));
  await assertFails(getDoc(doc(adminSuspended, "admin_audit_logs/audit-1")));
});

test("no client may update an inquiry; status, assignment and content change only server-side", async () => {
  const counselor = environment.authenticatedContext("counselor", verified).firestore();
  await assertFails(updateDoc(doc(counselor, "inquiries/inquiry-1"), {status: "in_progress", updatedAt: new Date()}));
  await assertFails(updateDoc(doc(counselor, "inquiries/inquiry-1"), {assignedStaffId: "counselor"}));
  await assertFails(updateDoc(doc(counselor, "inquiries/inquiry-1"), {message: "rewritten"}));
  await assertFails(updateDoc(doc(counselor, "inquiries/inquiry-1"), {assigneeIds: ["counselor"]}));

  const suspended = environment.authenticatedContext("counselor-legacy-suspended", verified).firestore();
  await assertFails(updateDoc(doc(suspended, "inquiries/inquiry-1"), {status: "resolved", updatedAt: new Date()}));
  const student = environment.authenticatedContext("student", verified).firestore();
  await assertFails(updateDoc(doc(student, "inquiries/inquiry-1"), {status: "resolved", updatedAt: new Date()}));
});
