import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, setDoc} from "firebase/firestore";
import {deleteObject, getMetadata, ref, uploadBytes} from "firebase/storage";

const projectId = process.env.GCLOUD_PROJECT || "demo-mindmate-clinical-attachments";
const appointmentId = "appointment-1";
const unverifiedAppointmentId = "appointment-unverified";
const path = "counseling_session_files/appointment-1/counselor/0123456789abcdef0123456789abcdef.pdf";
const unverifiedPath = "counseling_session_files/appointment-unverified/admin/0123456789abcdef0123456789abcdef.pdf";
let env: RulesTestEnvironment;

function storageFor(uid: string, emailVerified = true) {
  return env.authenticatedContext(uid, {email_verified: emailVerified}).storage();
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    storage: {rules: readFileSync(resolve(__dirname, "../../storage.rules"), "utf8")},
  });
});

beforeEach(async () => {
  await Promise.all([env.clearFirestore(), env.clearStorage()]);
  await env.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all([
      setDoc(doc(firestore, "system_config/security"), {superAdminUid: "admin"}),
      setDoc(doc(firestore, "users/counselor"), {
        accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/other-counselor"), {
        accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cas"],
      }),
      setDoc(doc(firestore, "users/counselor-legacy-suspended"), {
        accessRole: "counselor", accountStatus: "suspended", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(firestore, "users/other-admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(firestore, "users/admin-suspended"), {accessRole: "admin", accountStatus: "suspended"}),
      setDoc(doc(firestore, "users/portal-staff"), {
        accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/student"), {
        accessRole: "appUser", collegeId: "cite", verificationStatus: "verified",
      }),
      setDoc(doc(firestore, "users/student-unverified"), {
        accessRole: "appUser", collegeId: "cite", verificationStatus: "needsReview",
      }),
      setDoc(doc(firestore, `appointments/${appointmentId}`), {
        status: "confirmed", userId: "student", collegeId: "cite", studentVerificationStatus: "verified",
      }),
      setDoc(doc(firestore, `appointments/${unverifiedAppointmentId}`), {
        status: "confirmed", userId: "student-unverified", collegeId: "cite", studentVerificationStatus: "needsReview",
      }),
    ]);
  });
});

after(async () => env.cleanup());

const payload = new Uint8Array([1, 2, 3, 4]);
const meta = {
  contentType: "application/pdf",
  customMetadata: {uploadedBy: "counselor", appointmentId},
};

test("assigned-college approved verified counselor and super-admin can upload and review clinical attachments", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));
  await assertSucceeds(getMetadata(ref(clinician, path)));
  await assertSucceeds(getMetadata(ref(storageFor("admin"), path)));
});

test("cross-college, revoked, suspended, unverified, operational staff, non-super admin, and student are denied", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));
  for (const account of [
    "student", "portal-staff", "other-counselor", "counselor-legacy-suspended", "other-admin", "admin-suspended",
  ]) {
    await assertFails(getMetadata(ref(storageFor(account), path)));
    await assertFails(uploadBytes(ref(storageFor(account), path.replace("counselor/", account + "/")), payload,
      {...meta, customMetadata: {uploadedBy: account, appointmentId}}));
  }
  await assertFails(getMetadata(ref(storageFor("counselor", false), path)));

  // Losing college assignment immediately revokes attachment read/delete.
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/counselor"), {
      accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cas"],
    });
  });
  await assertFails(getMetadata(ref(clinician, path)));
  await assertFails(deleteObject(ref(clinician, path)));
});

test("unverified student's appointment attachments are restricted to super-admin triage", async () => {
  const superAdmin = storageFor("admin");
  const unvMeta = {
    contentType: "application/pdf",
    customMetadata: {uploadedBy: "admin", appointmentId: unverifiedAppointmentId},
  };
  await assertSucceeds(uploadBytes(ref(superAdmin, unverifiedPath), payload, unvMeta));
  await assertSucceeds(getMetadata(ref(superAdmin, unverifiedPath)));
  await assertFails(getMetadata(ref(storageFor("counselor"), unverifiedPath)));
  await assertFails(uploadBytes(
    ref(storageFor("counselor"), unverifiedPath.replace("/admin/", "/counselor/")),
    payload,
    {contentType: "application/pdf", customMetadata: {uploadedBy: "counselor", appointmentId: unverifiedAppointmentId}},
  ));
});

test("wrong owner, type, oversize or metadata cannot upload", async () => {
  const clinician = storageFor("counselor");
  await assertFails(uploadBytes(ref(clinician, path.replace("/counselor/", "/admin/")), payload, meta));
  await assertFails(uploadBytes(ref(clinician, path), payload, {...meta, contentType: "text/html"}));
  await assertFails(uploadBytes(ref(clinician, path), payload, {
    ...meta, customMetadata: {uploadedBy: "admin", appointmentId},
  }));
  await assertFails(uploadBytes(ref(clinician, path), new Uint8Array(5 * 1024 * 1024 + 1), meta));
});

test("clinical evidence becomes read-only after the session is completed", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `appointments/${appointmentId}`), {
      status: "completed", userId: "student", collegeId: "cite", studentVerificationStatus: "verified",
    });
  });
  await assertSucceeds(getMetadata(ref(clinician, path)));
  await assertFails(deleteObject(ref(clinician, path)));
  const second = path.replace("0123456789abcdef", "fedcba9876543210");
  await assertFails(uploadBytes(ref(clinician, second), payload, meta));
});
