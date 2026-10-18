import assert from "node:assert/strict";
import {after, beforeEach, test} from "node:test";

import {getApps, initializeApp as initializeAdminApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {deleteApp, initializeApp} from "firebase/app";
import {connectAuthEmulator, createUserWithEmailAndPassword, getAuth} from "firebase/auth";
import {connectFunctionsEmulator, getFunctions, httpsCallable} from "firebase/functions";

const projectId = process.env.GCLOUD_PROJECT ?? "demo-mindmate-mood-v2-local";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
const [authHostname, authPort] = authHost.split(":");
const functionsHost = process.env.FUNCTIONS_EMULATOR_HOST ?? "127.0.0.1";
const functionsPort = Number(process.env.FUNCTIONS_EMULATOR_PORT ?? "5001");
if (!getApps().length) initializeAdminApp({projectId});
const db = getFirestore();
let sequence = 0;

function requestId(seed: number): string {
  return `11111111-1111-4111-8111-${seed.toString().padStart(12, "0")}`;
}

beforeEach(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("mood_entries_callable_emulator.test.ts requires Firebase emulators.");
  }
});

after(async () => {
  // Every test owns its client Firebase app and deletes it inline. This hook
  // remains intentionally empty to make node:test await module-level cleanup.
});

test("authenticated client invokes createMoodEntryDev through Auth, Functions, and Firestore emulators", async () => {
  sequence += 1;
  const app = initializeApp(
    {projectId, apiKey: "phase2-emulator-only-api-key"},
    `mood-v2-callable-${sequence}`,
  );
  try {
    const auth = getAuth(app);
    connectAuthEmulator(auth, `http://${authHostname}:${authPort}`, {disableWarnings: true});
    const credential = await createUserWithEmailAndPassword(
      auth,
      `mood-v2-${Date.now()}-${sequence}@example.test`,
      "phase2-test-password",
    );
    await db.collection("users").doc(credential.user.uid).set({
      accessRole: "appUser",
      populationRole: "student",
      accountStatus: "active",
      verificationStatus: "verified",
    });
    const functions = getFunctions(app, "us-central1");
    connectFunctionsEmulator(functions, functionsHost, functionsPort);
    const invoke = httpsCallable<Record<string, unknown>, Record<string, unknown>>(
      functions,
      "createMoodEntryDev",
    );
    const result = await invoke({
      level: 4,
      label: "Steady",
      note: "",
      entryMethod: "manual",
      expressionAssistUsed: false,
      expressionSuggestionAccepted: false,
      clientRequestId: requestId(sequence),
    });
    const entryId = String(result.data.entryId);
    const stored = await db.collection("moodEntries").doc(entryId).get();
    assert.equal(result.data.userId, credential.user.uid);
    assert.equal(stored.exists, true);
    assert.equal(stored.data()?.calculationAuthority, "server");
    assert.equal(stored.data()?.userId, credential.user.uid);
  } finally {
    await deleteApp(app);
  }
});
