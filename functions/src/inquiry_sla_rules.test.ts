import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {addDoc, collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc} from "firebase/firestore";

// Reply timelines follow their inquiry's visibility; the response target is
// readable by portal accounts and written only by the super-admin callable.
const projectId = "mind-mates-inquiry-sla-rules-test";
let environment: RulesTestEnvironment;
const verified = {email_verified: true};
const active = {staffAccountStatus: "approved", accountStatus: "active"};

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const fs = context.firestore();
    await Promise.all([
      setDoc(doc(fs, "system_config/security"), {superAdminUid: "admin"}),
      setDoc(doc(fs, "system_config/inquiry_sla"), {hours: 48}),
      setDoc(doc(fs, "users/admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(fs, "users/c1"), {accessRole: "counselor", ...active}),
      setDoc(doc(fs, "users/c2"), {accessRole: "counselor", ...active}),
      setDoc(doc(fs, "users/sus"), {accessRole: "counselor", staffAccountStatus: "disabled", accountStatus: "suspended"}),
      setDoc(doc(fs, "users/student"), {accessRole: "appUser"}),
      setDoc(doc(fs, "users/other-student"), {accessRole: "appUser"}),
      setDoc(doc(fs, "inquiries/cite"), {userId: "student", status: "in_progress", routingStatus: "routed", assigneeIds: ["c1", "sus"]}),
      setDoc(doc(fs, "inquiries/cite/replies/r1"), {message: "We will call you.", authorId: "c1", authorRole: "counselor"}),
    ]);
  });
});

after(async () => environment.cleanup());

const ctx = (uid: string, token = verified) => environment.authenticatedContext(uid, token).firestore();

test("the student, the assignees and the super-admin read the reply timeline; nobody else", async () => {
  for (const uid of ["student", "c1", "admin"]) {
    await assertSucceeds(getDoc(doc(ctx(uid), "inquiries/cite/replies/r1")));
    await assertSucceeds(getDocs(collection(ctx(uid), "inquiries/cite/replies")));
  }
  for (const uid of ["c2", "other-student", "sus"]) {
    await assertFails(getDoc(doc(ctx(uid), "inquiries/cite/replies/r1")));
    await assertFails(getDocs(collection(ctx(uid), "inquiries/cite/replies")));
  }
  await assertFails(getDoc(doc(ctx("c1", {email_verified: false}), "inquiries/cite/replies/r1")));
});

test("no client writes replies, not even assignees or the super-admin", async () => {
  for (const uid of ["student", "c1", "admin"]) {
    await assertFails(addDoc(collection(ctx(uid), "inquiries/cite/replies"), {message: "x", authorId: uid}));
    await assertFails(updateDoc(doc(ctx(uid), "inquiries/cite/replies/r1"), {message: "edited"}));
    await assertFails(deleteDoc(doc(ctx(uid), "inquiries/cite/replies/r1")));
  }
});

test("portal accounts read the response target; students and suspended staff do not; nobody writes it", async () => {
  for (const uid of ["c1", "admin"]) await assertSucceeds(getDoc(doc(ctx(uid), "system_config/inquiry_sla")));
  for (const uid of ["student", "sus"]) await assertFails(getDoc(doc(ctx(uid), "system_config/inquiry_sla")));
  for (const uid of ["c1", "admin"]) await assertFails(setDoc(doc(ctx(uid), "system_config/inquiry_sla"), {hours: 24}));
  await assertSucceeds(getDoc(doc(ctx("student"), "system_config/security")));
});
