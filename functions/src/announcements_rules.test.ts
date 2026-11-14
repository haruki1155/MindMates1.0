import {test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {initializeTestEnvironment, assertFails, assertSucceeds} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, collection, getDocs, query, where} from "firebase/firestore";

test("announcement Rules enforce publication boundary and deny client mutations", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: "demo-announcements", firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")}});
  try {
    await env.withSecurityRulesDisabled(async ({firestore}) => {
      const db = firestore();
      for (const role of ["appUser", "portalStaff", "counselor", "admin"]) await setDoc(doc(db, "users", role), {accessRole: role, accountStatus: "active", staffAccountStatus: "approved"});
      await setDoc(doc(db, "announcements", "draft"), {status: "draft"});
      await setDoc(doc(db, "announcements", "public"), {status: "published"});
      await setDoc(doc(db, "announcements", "archived"), {status: "archived"});
    });
    for (const role of ["appUser", "portalStaff", "counselor", "admin"]) {
      const db = env.authenticatedContext(role, {email_verified: true}).firestore();
      await assertSucceeds(getDoc(doc(db, "announcements/public")));
      await assertSucceeds(getDocs(query(collection(db, "announcements"), where("status", "==", "published"))));
      await assertFails(setDoc(doc(db, "announcements/new"), {status: "published"}));
      if (["portalStaff", "admin"].includes(role)) await assertSucceeds(getDoc(doc(db, "announcements/draft")));
      else { await assertFails(getDoc(doc(db, "announcements/draft"))); await assertFails(getDoc(doc(db, "announcements/archived"))); await assertFails(getDocs(collection(db, "announcements"))); }
    }
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "announcements/public")));
    await assertFails(getDoc(doc(env.authenticatedContext("admin", {email_verified: false}).firestore(), "announcements/draft")));
  } finally { await env.cleanup(); }
});
