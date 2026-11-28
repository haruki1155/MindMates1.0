import {test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {initializeTestEnvironment, assertFails, assertSucceeds} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, collection, getDocs, query, where, orderBy, limit} from "firebase/firestore";

const ALL = ["student", "teaching", "nonTeaching"];
const readers: Record<string, {profile: Record<string, unknown>; audience: string}> = {
  student: {profile: {accessRole: "appUser", populationRole: "student"}, audience: "student"},
  declaredTeacher: {profile: {accessRole: "appUser", populationRole: "", declaredRole: "teaching"}, audience: "teaching"},
  legacyFaculty: {profile: {role: "faculty"}, audience: "teaching"},
  legacyStaff: {profile: {accessRole: "appUser", populationRole: "", declaredRole: "", role: "staff"}, audience: "nonTeaching"},
  legacyStudent: {profile: {accessRole: "appUser", role: "student"}, audience: "student"},
  nonTeaching: {profile: {accessRole: "appUser", populationRole: "nonTeaching"}, audience: "nonTeaching"},
};
const scoped = (db: ReturnType<ReturnType<Awaited<ReturnType<typeof initializeTestEnvironment>>["authenticatedContext"]>["firestore"]>, audience: string) =>
  query(collection(db, "announcements"), where("status", "==", "published"), where("audienceRoles", "array-contains", audience), orderBy("publishedAt", "desc"), limit(20));

test("announcement Rules enforce publication and audience boundaries and deny client mutations", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: "demo-announcements", firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")}});
  try {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      for (const role of ["portalStaff", "admin"]) await setDoc(doc(db, "users", role), {accessRole: role, accountStatus: "active", staffAccountStatus: "approved"});
      await setDoc(doc(db, "users", "counselor"), {accessRole: "counselor", accountStatus: "active", staffAccountStatus: "approved"});
      await setDoc(doc(db, "users", "noRole"), {accessRole: "appUser", populationRole: "", declaredRole: ""});
      await setDoc(doc(db, "users", "suspended"), {accessRole: "appUser", populationRole: "student", accountStatus: "suspended"});
      for (const [uid, reader] of Object.entries(readers)) await setDoc(doc(db, "users", uid), {accountStatus: "active", ...reader.profile});
      await setDoc(doc(db, "announcements", "draft"), {status: "draft", audienceRoles: ALL, publishedAt: null});
      await setDoc(doc(db, "announcements", "archived"), {status: "archived", audienceRoles: ALL, publishedAt: 1});
      await setDoc(doc(db, "announcements", "legacy"), {status: "published", publishedAt: 1});
      for (const audience of ALL) await setDoc(doc(db, "announcements", `only-${audience}`), {status: "published", audienceRoles: [audience], publishedAt: 2});
    });
    for (const [uid, {audience}] of Object.entries(readers)) {
      const db = env.authenticatedContext(uid, {email_verified: true}).firestore();
      await assertSucceeds(getDoc(doc(db, `announcements/only-${audience}`)));
      await assertSucceeds(getDocs(scoped(db, audience)));
      for (const other of ALL.filter((value) => value !== audience)) {
        await assertFails(getDoc(doc(db, `announcements/only-${other}`)));
        await assertFails(getDocs(scoped(db, other)));
      }
      await assertFails(getDocs(query(collection(db, "announcements"), where("status", "==", "published"))));
      await assertFails(getDoc(doc(db, "announcements/legacy")));
      await assertFails(getDoc(doc(db, "announcements/draft")));
      await assertFails(getDoc(doc(db, "announcements/archived")));
      await assertFails(setDoc(doc(db, "announcements/new"), {status: "published", audienceRoles: ALL}));
    }
    for (const uid of ["counselor", "noRole", "suspended"]) {
      const db = env.authenticatedContext(uid, {email_verified: true}).firestore();
      for (const audience of ALL) { await assertFails(getDoc(doc(db, `announcements/only-${audience}`))); await assertFails(getDocs(scoped(db, audience))); }
    }
    for (const role of ["portalStaff", "admin"]) {
      const db = env.authenticatedContext(role, {email_verified: true}).firestore();
      for (const id of ["draft", "archived", "legacy", "only-student"]) await assertSucceeds(getDoc(doc(db, `announcements/${id}`)));
      await assertSucceeds(getDocs(collection(db, "announcements")));
      await assertFails(setDoc(doc(db, "announcements/new"), {status: "published"}));
    }
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "announcements/only-student")));
    await assertFails(getDoc(doc(env.authenticatedContext("student", {email_verified: false}).firestore(), "announcements/only-student")));
    await assertFails(getDoc(doc(env.authenticatedContext("student", {email_verified: true, firstLoginPending: true}).firestore(), "announcements/only-student")));
    await assertFails(getDoc(doc(env.authenticatedContext("admin", {email_verified: false}).firestore(), "announcements/draft")));
  } finally { await env.cleanup(); }
});
