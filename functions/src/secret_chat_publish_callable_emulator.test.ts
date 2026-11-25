import assert from "node:assert/strict";
import {test} from "node:test";

import {getApps, initializeApp as initializeAdminApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {deleteApp, initializeApp} from "firebase/app";
import {connectAuthEmulator, createUserWithEmailAndPassword, getAuth} from "firebase/auth";
import {connectFunctionsEmulator, getFunctions, httpsCallable} from "firebase/functions";

const projectId = process.env.GCLOUD_PROJECT ?? "demo-mindmate-mood-v2";
const [authHostname, authPort] = (process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099").split(":");
const functionsHost = process.env.FUNCTIONS_EMULATOR_HOST ?? "127.0.0.1";
const functionsPort = Number(process.env.FUNCTIONS_EMULATOR_PORT ?? "5001");
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
if (!getApps().length) initializeAdminApp({projectId});

test("deployed callables publish clean posts and refuse profane aliases", {skip: !emulated}, async () => {
  const app = initializeApp({projectId, apiKey: "forum-emulator-only-api-key"}, `forum-${Date.now()}`);
  try {
    const auth = getAuth(app);
    connectAuthEmulator(auth, `http://${authHostname}:${authPort}`, {disableWarnings: true});
    const {user} = await createUserWithEmailAndPassword(auth, `forum-${Date.now()}@example.test`, "forum-test-pass");
    const functions = getFunctions(app, "us-central1");
    connectFunctionsEmulator(functions, functionsHost, functionsPort);

    const create = httpsCallable<Record<string, unknown>, {postId: string}>(functions, "createSecretChatPost");
    const {data} = await create({message: "Grateful for my friends this week.", categories: ["Gratitude"]});
    const stored = await getFirestore().doc(`secret_chats/${data.postId}`).get();
    assert.equal(stored.data()?.authorId, user.uid);

    await assert.rejects(
      create({message: "Tangina, stress sa school.", categories: ["Stress"]}),
      {code: "functions/invalid-argument"},
    );
    const saveProfile = httpsCallable(functions, "saveSecretChatProfile");
    await assert.rejects(saveProfile({alias: "Gago Ako"}), {code: "functions/invalid-argument"});
  } finally {
    await deleteApp(app);
  }
});
