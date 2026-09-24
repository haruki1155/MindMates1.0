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
import {doc, getDoc, setDoc} from "firebase/firestore";

const projectId = "mind-mates-appointment-availability-rules-test";
let environment: RulesTestEnvironment;

const availability = {
  openDays: [1, 2, 3, 4, 5],
  opensAt: "09:00",
  closesAt: "17:00",
  presence: "in_office",
  acceptsWalkIns: false,
  notice: "",
};

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
    await setDoc(doc(context.firestore(), "pacc_availability/current"), availability);
  });
});

after(async () => environment.cleanup());

test("authenticated users can read published availability but cannot write it directly", async () => {
  const student = environment.authenticatedContext("student").firestore();
  const current = doc(student, "pacc_availability/current");
  await assertSucceeds(getDoc(current));
  await assertFails(setDoc(current, {...availability, opensAt: "10:00"}));
});
