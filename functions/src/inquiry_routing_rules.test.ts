import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {addDoc, collection, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp, setDoc, updateDoc, where} from "firebase/firestore";

// Inquiry visibility is scoped to the routed assignees, the owning student and
// the configured super-administrator. Every transition is server-side.
const projectId = "mind-mates-inquiry-routing-rules-test";
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
    const routed = {userId: "student", subject: "S", message: "M", category: "Service Form", email: "s@x", status: "pending", formData: {q: "private"}};
    await Promise.all([
      setDoc(doc(fs, "system_config/security"), {superAdminUid: "admin"}),
      setDoc(doc(fs, "users/admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(fs, "users/other-admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(fs, "users/c1"), {accessRole: "counselor", ...active, assignedCollegeIds: ["cite"]}),
      setDoc(doc(fs, "users/s1"), {accessRole: "portalStaff", ...active, assignedCollegeIds: ["cite"]}),
      setDoc(doc(fs, "users/c2"), {accessRole: "counselor", ...active, assignedCollegeIds: ["cas"]}),
      setDoc(doc(fs, "users/student"), {accessRole: "appUser"}),
      setDoc(doc(fs, "users/other-student"), {accessRole: "appUser"}),
      setDoc(doc(fs, "inquiries/cite"), {...routed, routingStatus: "routed", collegeId: "cite", assigneeIds: ["c1", "s1"]}),
      setDoc(doc(fs, "inquiries/cas"), {...routed, userId: "other-student", routingStatus: "routed", collegeId: "cas", assigneeIds: ["c2"]}),
      setDoc(doc(fs, "inquiries/triage"), {...routed, routingStatus: "needs_triage", routingReason: "missing_college", collegeId: "", assigneeIds: []}),
      setDoc(doc(fs, "inquiries/legacy"), {...routed}),
    ]);
  });
});

after(async () => environment.cleanup());

const ctx = (uid: string) => environment.authenticatedContext(uid, verified).firestore();
const mine = (uid: string) => query(collection(ctx(uid), "inquiries"), where("assigneeIds", "array-contains", uid));

test("assignees read only their college's inquiries, through an assignee-filtered query", async () => {
  await assertSucceeds(getDoc(doc(ctx("c1"), "inquiries/cite")));
  await assertSucceeds(getDoc(doc(ctx("s1"), "inquiries/cite")));
  await assertSucceeds(getDocs(mine("c1")));
  await assertSucceeds(getDocs(mine("c2")));
  await assertFails(getDoc(doc(ctx("c2"), "inquiries/cite")));
  await assertFails(getDoc(doc(ctx("c1"), "inquiries/cas")));
  await assertFails(getDocs(collection(ctx("c1"), "inquiries")));
  await assertFails(getDocs(query(collection(ctx("c2"), "inquiries"), where("assigneeIds", "array-contains", "c1"))));
});

test("triage and legacy unrouted inquiries are visible only to the owner and the super-administrator", async () => {
  for (const id of ["triage", "legacy"]) {
    await assertSucceeds(getDoc(doc(ctx("admin"), `inquiries/${id}`)));
    await assertSucceeds(getDoc(doc(ctx("student"), `inquiries/${id}`)));
    for (const uid of ["c1", "s1", "c2", "other-admin", "other-student"]) {
      await assertFails(getDoc(doc(ctx(uid), `inquiries/${id}`)));
    }
  }
});

test("only the configured super-administrator has organisation-wide inquiry access", async () => {
  await assertSucceeds(getDocs(collection(ctx("admin"), "inquiries")));
  await assertFails(getDocs(collection(ctx("other-admin"), "inquiries")));
  await assertFails(getDoc(doc(ctx("other-admin"), "inquiries/cite")));
  await assertFails(getDocs(collection(environment.authenticatedContext("admin", {email_verified: false}).firestore(), "inquiries")));
});

test("no client may update or delete an inquiry; transitions are server-side", async () => {
  for (const uid of ["c1", "s1", "admin", "student"]) {
    await assertFails(updateDoc(doc(ctx(uid), "inquiries/cite"), {status: "resolved", updatedAt: new Date()}));
    await assertFails(updateDoc(doc(ctx(uid), "inquiries/cite"), {assigneeIds: [uid]}));
    await assertFails(deleteDoc(doc(ctx(uid), "inquiries/cite")));
  }
});

test("students create inquiries but cannot set routing fields", async () => {
  const base = {userId: "student", subject: "Hello", message: "Question", category: "Service Form", email: "s@x", name: "S", role: "User", status: "pending", createdAt: serverTimestamp()};
  await assertSucceeds(addDoc(collection(ctx("student"), "inquiries"), base));
  for (const extra of [{assigneeIds: ["c1"]}, {routingStatus: "routed"}, {collegeId: "cite"}, {ownerId: "c1"}]) {
    await assertFails(addDoc(collection(ctx("student"), "inquiries"), {...base, ...extra}));
  }
  await assertFails(getDoc(doc(ctx("other-student"), "inquiries/cite")));
  await assertSucceeds(getDoc(doc(ctx("student"), "inquiries/cite")));
});
