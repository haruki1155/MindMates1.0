import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc} from "firebase/firestore";

// `backup_jobs` is written only by Cloud Functions and read only by the
// configured super-administrator. No other portal role, and no client write.
const projectId = "mind-mates-backup-rules-test";
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
      setDoc(doc(firestore, "users/admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(firestore, "users/other-admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(firestore, "users/counselor"), {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"}),
      setDoc(doc(firestore, "users/portal-staff"), {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"}),
      setDoc(doc(firestore, "users/student"), {accessRole: "appUser"}),
      setDoc(doc(firestore, "system_config/security"), {superAdminUid: "admin"}),
      setDoc(doc(firestore, "backup_jobs/job-1"), {status: "completed", trigger: "manual", requestedBy: "admin"}),
    ]);
  });
});

after(async () => environment.cleanup());

test("only the configured super-administrator can read backup jobs", async () => {
  const admin = environment.authenticatedContext("admin", verified).firestore();
  await assertSucceeds(getDoc(doc(admin, "backup_jobs/job-1")));
  await assertSucceeds(getDocs(collection(admin, "backup_jobs")));
  for (const uid of ["other-admin", "counselor", "portal-staff", "student"]) {
    const user = environment.authenticatedContext(uid, verified).firestore();
    await assertFails(getDoc(doc(user, "backup_jobs/job-1")));
    await assertFails(getDocs(collection(user, "backup_jobs")));
  }
  await assertFails(getDocs(collection(environment.unauthenticatedContext().firestore(), "backup_jobs")));
});

test("no client may create, update or delete backup jobs, not even the super-administrator", async () => {
  const admin = environment.authenticatedContext("admin", verified).firestore();
  await assertFails(setDoc(doc(admin, "backup_jobs/job-2"), {status: "completed"}));
  await assertFails(updateDoc(doc(admin, "backup_jobs/job-1"), {status: "failed"}));
  await assertFails(deleteDoc(doc(admin, "backup_jobs/job-1")));
});
