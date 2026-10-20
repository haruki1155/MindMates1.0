import assert from "node:assert/strict";
import {after, beforeEach, test} from "node:test";

import {getApps, initializeApp as initializeAdminApp} from "firebase-admin/app";
import {getAuth as getAdminAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {deleteApp, initializeApp} from "firebase/app";
import {connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signInWithEmailAndPassword} from "firebase/auth";
import {connectFunctionsEmulator, getFunctions, httpsCallable} from "firebase/functions";

const projectId = process.env.GCLOUD_PROJECT ?? "demo-mindmate-mood-v2-local";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
const [authHostname, authPort] = authHost.split(":");
const functionsHost = process.env.FUNCTIONS_EMULATOR_HOST ?? "127.0.0.1";
const functionsPort = Number(process.env.FUNCTIONS_EMULATOR_PORT ?? "5001");
const pilotUid = process.env.MOOD_V2_TEST_PILOT_UID;
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

test("authenticated non-pilot is rejected by createMoodEntryDev without a Firestore write", async () => {
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
    await assert.rejects(
      () => invoke({
        level: 4,
        label: "Steady",
        note: "",
        entryMethod: "manual",
        expressionAssistUsed: false,
        expressionSuggestionAccepted: false,
        clientRequestId: requestId(sequence),
      }),
      (error: unknown) => String(error).includes("permission-denied"),
    );
    const stored = await db.collection("moodEntries")
      .where("userId", "==", credential.user.uid).get();
    assert.equal(stored.empty, true);
  } finally {
    await deleteApp(app);
  }
});

test("configured staging pilot creates one idempotent server-authoritative entry", {
  skip: projectId !== "mindmate-staging" || !pilotUid,
}, async () => {
  const configuredPilotUid = pilotUid!;
  const email = `mood-v2-pilot-${Date.now()}@example.test`;
  const password = "phase2-test-password";
  await getAdminAuth().createUser({
    uid: configuredPilotUid,
    email,
    password,
    emailVerified: true,
  });
  await db.collection("users").doc(configuredPilotUid).set({
    accessRole: "appUser",
    populationRole: "student",
    accountStatus: "active",
    verificationStatus: "verified",
  });

  sequence += 1;
  const app = initializeApp(
    {projectId, apiKey: "phase2-emulator-only-api-key"},
    `mood-v2-pilot-${sequence}`,
  );
  try {
    const auth = getAuth(app);
    connectAuthEmulator(auth, `http://${authHostname}:${authPort}`, {disableWarnings: true});
    await signInWithEmailAndPassword(auth, email, password);
    const functions = getFunctions(app, "us-central1");
    connectFunctionsEmulator(functions, functionsHost, functionsPort);
    const invoke = httpsCallable<Record<string, unknown>, Record<string, unknown>>(
      functions,
      "createMoodEntryDev",
    );
    const request = {
      level: 4,
      label: "Steady",
      note: "",
      entryMethod: "manual",
      expressionAssistUsed: false,
      expressionSuggestionAccepted: false,
      clientRequestId: requestId(900000 + sequence),
    };
    const first = (await invoke(request)).data;
    const retry = (await invoke(request)).data;
    assert.equal(retry.entryId, first.entryId);
    assert.equal(retry.occurredAt, first.occurredAt);
    assert.equal(retry.dateKey, first.dateKey);
    assert.equal(first.calculationAuthority, "server");

    await assert.rejects(
      () => invoke({...request, level: 3}),
      (error: unknown) => String(error).includes("already-exists"),
    );
    const entries = await db.collection("moodEntries")
      .where("userId", "==", configuredPilotUid).get();
    assert.equal(entries.size, 1);
  } finally {
    await deleteApp(app);
  }
});
