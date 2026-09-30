import assert from "node:assert/strict";
import test, {after} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, updateDoc} from "firebase/firestore";

let environment: RulesTestEnvironment;
const alertPath = "mind_aid_emergency_alerts/alert-1";

test("emergency alerts are clinical-read-only", async () => {
  environment ??= await initializeTestEnvironment({projectId: "mind-aid-emergency-rules", firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")}});
  await environment.withSecurityRulesDisabled(async (context) => {
    const store = context.firestore();
    await setDoc(doc(store, "users/student"), {accessRole: "appUser"});
    await setDoc(doc(store, "users/staff"), {accessRole: "portalStaff"});
    await setDoc(doc(store, "users/counselor"), {accessRole: "counselor"});
    await setDoc(doc(store, "users/admin"), {accessRole: "admin"});
    await setDoc(doc(store, alertPath), {status: "open", userId: "student"});
  });
  const student = environment.authenticatedContext("student").firestore();
  const staff = environment.authenticatedContext("staff").firestore();
  const counselor = environment.authenticatedContext("counselor").firestore();
  const admin = environment.authenticatedContext("admin").firestore();
  await assertFails(getDoc(doc(student, alertPath)));
  await assertFails(getDoc(doc(staff, alertPath)));
  await assertSucceeds(getDoc(doc(counselor, alertPath)));
  await assertSucceeds(getDoc(doc(admin, alertPath)));
  for (const store of [student, staff, counselor, admin]) {
    await assertFails(setDoc(doc(store, alertPath), {status: "open"}));
    await assertFails(updateDoc(doc(store, alertPath), {status: "resolved"}));
  }
  assert.ok(true);
});

after(async () => environment?.cleanup());
