import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {collection, deleteDoc, doc, getDoc, getDocs, orderBy, query, setDoc, updateDoc, where} from "firebase/firestore";

const projectId = "mind-mates-mood-v2-rules-test";
let environment: RulesTestEnvironment;
const owner = "mood-v2-owner";
const other = "mood-v2-other";
const entry = "mood_v2_owner_request";

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "moodEntries", entry), {
      userId: owner,
      level: 3,
      dateKey: "2026-01-01",
      occurredAt: new Date("2026-01-01T00:00:00.000Z"),
    });
  });
});

after(async () => environment.cleanup());

test("only the authenticated V2 owner can read owner-scoped history", async () => {
  const ownerStore = environment.authenticatedContext(owner).firestore();
  const otherStore = environment.authenticatedContext(other).firestore();
  const ownerEntry = doc(ownerStore, "moodEntries", entry);
  await assertSucceeds(getDoc(ownerEntry));
  await assertSucceeds(getDocs(query(collection(ownerStore, "moodEntries"), where("userId", "==", owner))));
  await assertFails(getDoc(doc(otherStore, "moodEntries", entry)));
  await assertFails(getDocs(query(collection(otherStore, "moodEntries"), where("userId", "==", owner))));
});

test("owner-scoped V2 history supports the bounded timestamp ordering used by the combined reader", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "moodEntries", "later"), {
      userId: owner,
      level: 4,
      dateKey: "2026-01-02",
      occurredAt: new Date("2026-01-02T00:00:00.000Z"),
    });
  });
  const store = environment.authenticatedContext(owner).firestore();
  const history = query(
    collection(store, "moodEntries"),
    where("userId", "==", owner),
    where("occurredAt", ">=", new Date("2026-01-01T00:00:00.000Z")),
    orderBy("occurredAt", "desc"),
  );

  const snapshot = await assertSucceeds(getDocs(history));
  if (snapshot.docs.map((item) => item.id).join(",") !== "later,mood_v2_owner_request") {
    throw new Error("Unexpected owner-scoped history ordering.");
  }
});

test("all direct V2 creates, edits, and deletes are denied", async () => {
  const store = environment.authenticatedContext(owner).firestore();
  const ref = doc(store, "moodEntries", entry);
  await assertFails(setDoc(doc(store, "moodEntries", "client-created"), {userId: owner, level: 5}));
  await assertFails(updateDoc(ref, {level: 5}));
  await assertFails(deleteDoc(ref));
  const anonymous = environment.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anonymous, "moodEntries", entry)));
});
