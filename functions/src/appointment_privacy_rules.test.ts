import assert from "node:assert/strict";
import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {collection, doc, getDoc, getDocs, query, setDoc, where} from "firebase/firestore";

const projectId = "mind-mates-appointment-privacy-rules-test";
let environment: RulesTestEnvironment;

const verified = {email_verified: true};

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
      setDoc(doc(firestore, "system_config/security"), {superAdminUid: "super-admin"}),
      setDoc(doc(firestore, "users/student"), {
        accessRole: "appUser", collegeId: "cite", verificationStatus: "verified",
      }),
      setDoc(doc(firestore, "users/student-cas"), {
        accessRole: "appUser", collegeId: "cas", verificationStatus: "verified",
      }),
      setDoc(doc(firestore, "users/student-unverified"), {
        accessRole: "appUser", collegeId: "cite", verificationStatus: "needsReview",
      }),
      setDoc(doc(firestore, "users/other-student"), {
        accessRole: "appUser", collegeId: "cite", verificationStatus: "verified",
      }),
      setDoc(doc(firestore, "users/portal-staff"), {
        accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/counselor"), {
        accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/other-counselor"), {
        accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cas"],
      }),
      setDoc(doc(firestore, "users/counselor-suspended"), {
        accessRole: "counselor", staffAccountStatus: "disabled", accountStatus: "suspended", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/counselor-legacy-suspended"), {
        accessRole: "counselor", accountStatus: "suspended", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/super-admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(firestore, "users/other-admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(firestore, "appointments/appointment-1"), {
        userId: "student",
        assignedStaffId: "counselor",
        collegeId: "cite",
        studentVerificationStatus: "verified",
        concern: "Sensitive concern",
      }),
      setDoc(doc(firestore, "appointments/appointment-1/history/terminal"), {
        outcome: "Sensitive history",
      }),
      setDoc(doc(firestore, "appointments/appointment-1/clinical_notes/session"), {
        summary: "Sensitive clinical note",
      }),
      setDoc(doc(firestore, "appointments/appointment-cas"), {
        userId: "student-cas",
        collegeId: "cas",
        studentVerificationStatus: "verified",
        concern: "CAS sensitive concern",
      }),
      setDoc(doc(firestore, "appointments/appointment-cas/history/terminal"), {
        outcome: "CAS history",
      }),
      setDoc(doc(firestore, "appointments/appointment-cas/clinical_notes/session"), {
        summary: "CAS clinical note",
      }),
      setDoc(doc(firestore, "appointments/appointment-unverified"), {
        userId: "student-unverified",
        collegeId: "cite",
        studentVerificationStatus: "needsReview",
        concern: "Unverified concern",
      }),
      setDoc(doc(firestore, "appointments/appointment-unverified/history/terminal"), {
        outcome: "Unverified history",
      }),
      setDoc(doc(firestore, "appointments/appointment-unverified/clinical_notes/session"), {
        summary: "Unverified clinical note",
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

test("counselors read assigned-college verified appointments only; cross-college and unfiltered reads are denied", async () => {
  const counselor = environment.authenticatedContext("counselor", verified).firestore();
  const otherCounselor = environment.authenticatedContext("other-counselor", verified).firestore();

  // Assigned college get + structured query allowed.
  await assertSucceeds(getDoc(doc(counselor, "appointments/appointment-1")));
  await assertSucceeds(getDoc(doc(counselor, "appointments/appointment-1/history/terminal")));
  await assertSucceeds(getDoc(doc(counselor, "appointments/appointment-1/clinical_notes/session")));
  await assertSucceeds(getDocs(query(
    collection(counselor, "appointments"),
    where("studentVerificationStatus", "==", "verified"),
    where("collegeId", "in", ["cite"]),
  )));

  // Cross-college get and queries denied.
  await assertFails(getDoc(doc(counselor, "appointments/appointment-cas")));
  await assertFails(getDoc(doc(counselor, "appointments/appointment-cas/history/terminal")));
  await assertFails(getDoc(doc(counselor, "appointments/appointment-cas/clinical_notes/session")));
  await assertFails(getDoc(doc(otherCounselor, "appointments/appointment-1")));
  await assertFails(getDoc(doc(otherCounselor, "appointments/appointment-1/history/terminal")));
  await assertFails(getDoc(doc(otherCounselor, "appointments/appointment-1/clinical_notes/session")));

  // Unfiltered collection list or assignedStaffId-only query without college scope must fail.
  await assertFails(getDocs(collection(counselor, "appointments")));
  await assertFails(getDocs(query(collection(counselor, "appointments"), where("assignedStaffId", "==", "counselor"))));
  await assertFails(getDocs(query(
    collection(counselor, "appointments"),
    where("studentVerificationStatus", "==", "verified"),
    where("collegeId", "in", ["cas"]),
  )));
});

test("counselors list verified assigned-college appointments without assignedStaffId while cross-college counselors are denied", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "appointments/appointment-no-staff"), {
      userId: "student",
      collegeId: "cite",
      studentVerificationStatus: "verified",
      concern: "Synthetic concern without assignedStaffId",
    });
  });

  const citeCounselor = environment.authenticatedContext("counselor", verified).firestore();
  const casCounselor = environment.authenticatedContext("other-counselor", verified).firestore();

  const snapshot = await assertSucceeds(getDocs(query(
    collection(citeCounselor, "appointments"),
    where("studentVerificationStatus", "==", "verified"),
    where("collegeId", "in", ["cite"]),
  )));
  assert.ok(snapshot.docs.some((d) => d.id === "appointment-no-staff"));

  await assertFails(getDoc(doc(casCounselor, "appointments/appointment-no-staff")));
  await assertFails(getDocs(query(
    collection(casCounselor, "appointments"),
    where("studentVerificationStatus", "==", "verified"),
    where("collegeId", "in", ["cite"]),
  )));
});

test("losing college assignment or student college/verification change immediately revokes counselor access", async () => {
  const counselor = environment.authenticatedContext("counselor", verified).firestore();
  await assertSucceeds(getDoc(doc(counselor, "appointments/appointment-1")));

  // Counselor loses cite assignment -> immediate denial on get, subcollections, and list.
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/counselor"), {
      accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cas"],
    });
  });
  await assertFails(getDoc(doc(counselor, "appointments/appointment-1")));
  await assertFails(getDoc(doc(counselor, "appointments/appointment-1/history/terminal")));
  await assertFails(getDoc(doc(counselor, "appointments/appointment-1/clinical_notes/session")));
  await assertFails(getDocs(query(
    collection(counselor, "appointments"),
    where("studentVerificationStatus", "==", "verified"),
    where("collegeId", "in", ["cite"]),
  )));

  // Restore cite assignment, then change live student profile even while appointment fields lag -> get immediately denied.
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/counselor"), {
      accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"],
    });
    await setDoc(doc(context.firestore(), "users/student"), {
      accessRole: "appUser", collegeId: "cas", verificationStatus: "verified",
    });
  });
  await assertFails(getDoc(doc(counselor, "appointments/appointment-1")));
  await assertFails(getDoc(doc(counselor, "appointments/appointment-1/history/terminal")));
  await assertFails(getDoc(doc(counselor, "appointments/appointment-1/clinical_notes/session")));
});

test("suspended counselors cannot read any appointments", async () => {
  for (const uid of ["counselor-suspended", "counselor-legacy-suspended"]) {
    const firestore = environment.authenticatedContext(uid, verified).firestore();
    await assertFails(getDoc(doc(firestore, "appointments/appointment-1")));
    await assertFails(getDoc(doc(firestore, "appointments/appointment-1/history/terminal")));
    await assertFails(getDoc(doc(firestore, "appointments/appointment-1/clinical_notes/session")));
    await assertFails(getDocs(query(
      collection(firestore, "appointments"),
      where("studentVerificationStatus", "==", "verified"),
      where("collegeId", "in", ["cite"]),
    )));
  }
});

test("portal staff can read only the minimal appointment queue, never clinical appointments", async () => {
  const portalStaff = environment.authenticatedContext("portal-staff", verified).firestore();
  await assertFails(getDoc(doc(portalStaff, "appointments/appointment-1")));
  await assertFails(getDoc(doc(portalStaff, "appointments/appointment-1/history/terminal")));
  await assertFails(getDoc(doc(portalStaff, "appointments/appointment-1/clinical_notes/session")));
  await assertFails(getDocs(collection(portalStaff, "appointments")));
  await assertFails(getDocs(query(
    collection(portalStaff, "appointments"),
    where("studentVerificationStatus", "==", "verified"),
    where("collegeId", "in", ["cite"]),
  )));
  await assertSucceeds(getDoc(doc(portalStaff, "appointment_queue/appointment-1")));
  await assertSucceeds(getDocs(collection(portalStaff, "appointment_queue")));
});

test("students access only their own appointments and history, never clinical notes or other students", async () => {
  const student = environment.authenticatedContext("student").firestore();
  const otherStudent = environment.authenticatedContext("other-student").firestore();

  await assertSucceeds(getDoc(doc(student, "appointments/appointment-1")));
  await assertSucceeds(getDoc(doc(student, "appointments/appointment-1/history/terminal")));
  await assertSucceeds(getDocs(query(collection(student, "appointments"), where("userId", "==", "student"))));
  await assertFails(getDoc(doc(student, "appointments/appointment-1/clinical_notes/session")));
  await assertFails(getDocs(collection(student, "appointments")));

  await assertFails(getDoc(doc(otherStudent, "appointments/appointment-1")));
  await assertFails(getDoc(doc(otherStudent, "appointments/appointment-1/history/terminal")));
  await assertFails(getDoc(doc(otherStudent, "appointments/appointment-1/clinical_notes/session")));
  await assertFails(getDocs(query(collection(otherStudent, "appointments"), where("userId", "==", "student"))));
});

test("super-admin accesses appointments within administrative scope including unverified triage; non-super admins and counselors on unverified are denied", async () => {
  const superAdmin = environment.authenticatedContext("super-admin", verified).firestore();
  const otherAdmin = environment.authenticatedContext("other-admin", verified).firestore();
  const counselor = environment.authenticatedContext("counselor", verified).firestore();

  // Super-admin allowed.
  await assertSucceeds(getDoc(doc(superAdmin, "appointments/appointment-unverified")));
  await assertSucceeds(getDoc(doc(superAdmin, "appointments/appointment-unverified/history/terminal")));
  await assertSucceeds(getDoc(doc(superAdmin, "appointments/appointment-unverified/clinical_notes/session")));
  await assertSucceeds(getDocs(collection(superAdmin, "appointments")));

  // Non-super admin denied.
  await assertFails(getDoc(doc(otherAdmin, "appointments/appointment-1")));
  await assertFails(getDoc(doc(otherAdmin, "appointments/appointment-1/history/terminal")));
  await assertFails(getDoc(doc(otherAdmin, "appointments/appointment-1/clinical_notes/session")));
  await assertFails(getDocs(collection(otherAdmin, "appointments")));

  // Unverified student's appointment denied to assigned-college counselor.
  await assertFails(getDoc(doc(counselor, "appointments/appointment-unverified")));
  await assertFails(getDoc(doc(counselor, "appointments/appointment-unverified/history/terminal")));
  await assertFails(getDoc(doc(counselor, "appointments/appointment-unverified/clinical_notes/session")));

  // Legacy verified-student appointment missing projection fields: readable via direct get
  // (live student profile), excluded from list until backfilled with scoping fields.
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "appointments/appointment-legacy"), {
      userId: "student",
      status: "completed",
      concern: "Legacy record",
    });
  });
  await assertSucceeds(getDoc(doc(counselor, "appointments/appointment-legacy")));
  await assertFails(getDocs(query(collection(counselor, "appointments"), where("userId", "==", "student"))));
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "appointments/appointment-legacy"), {
      collegeId: "cite",
      studentVerificationStatus: "verified",
    }, {merge: true});
  });
  const backfilledList = await assertSucceeds(getDocs(query(
    collection(counselor, "appointments"),
    where("studentVerificationStatus", "==", "verified"),
    where("collegeId", "in", ["cite"]),
  )));
  assert.ok(backfilledList.docs.some((d) => d.id === "appointment-legacy"));
});

test("direct appointment revision, schedule, and reservation mutations are denied", async () => {
  for (const uid of ["student", "other-student", "portal-staff", "counselor", "super-admin"]) {
    const firestore = environment.authenticatedContext(uid, verified).firestore();
    await assertFails(setDoc(doc(firestore, "appointments/appointment-1"), {scheduleRevision: 0, status: "confirmed", scheduledAt: 123}, {merge: true}));
    await assertFails(setDoc(doc(firestore, "appointment_slots/pacc_123"), {appointmentId: "appointment-1"}));
    await assertFails(setDoc(doc(firestore, "appointment_user_locks/student"), {appointmentId: "appointment-1"}));
  }
});
