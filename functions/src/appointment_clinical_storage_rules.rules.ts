import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, setDoc} from "firebase/firestore";
import {deleteObject, getMetadata, ref, uploadBytes} from "firebase/storage";

const projectId = "demo-mindmate-clinical-attachments";
const appointmentId = "appointment-1";
const path = "counseling_session_files/appointment-1/counselor/0123456789abcdef0123456789abcdef.pdf";
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
      setDoc(doc(firestore, "users/counselor"), {
        accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active",
      }),
      setDoc(doc(firestore, "users/admin"), {accessRole: "admin"}),
      setDoc(doc(firestore, "users/portal-staff"), {accessRole: "portalStaff"}),
      setDoc(doc(firestore, "users/student"), {accessRole: "appUser"}),
      setDoc(doc(firestore, "appointments/appointment-1"), {
        status: "confirmed", userId: "student",
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

test("approved verified counselor can upload and review its private document", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));
  await assertSucceeds(getMetadata(ref(clinician, path)));
  await assertSucceeds(getMetadata(ref(storageFor("admin"), path)));
});

test("student, portal staff and unverified counselor cannot read or create", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));
  for (const account of ["student", "portal-staff"]) {
    await assertFails(getMetadata(ref(storageFor(account), path)));
    await assertFails(uploadBytes(ref(storageFor(account), path.replace("counselor/", account + "/")), payload,
      {...meta, customMetadata: {uploadedBy: account, appointmentId}}));
  }
  await assertFails(getMetadata(ref(storageFor("counselor", false), path)));
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
    await setDoc(doc(context.firestore(), "appointments/appointment-1"), {
      status: "completed", userId: "student",
    });
  });
  await assertSucceeds(getMetadata(ref(clinician, path)));
  await assertFails(deleteObject(ref(clinician, path)));
  const second = path.replace("0123456789abcdef", "fedcba9876543210");
  await assertFails(uploadBytes(ref(clinician, second), payload, meta));
});
