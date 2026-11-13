import assert from "node:assert/strict";
import {before, test} from "node:test";
import {getFirestore} from "firebase-admin/firestore";
import {sendMindAidMessage} from "./mind_aid";
import {GeminiMindAidProvider} from "./mind_aid_llm/gemini_mind_aid_provider";

const db = getFirestore();
const uid = `mindaid-persistence-${Date.now()}`;
const conversationId = "conversation-12345678";
function send(requestId: string, text = "I feel anxious", conversationMode = "listening") {
  return sendMindAidMessage.run({auth: {uid}, data: {
    requestId, conversationId, text, conversationMode,
  }} as Parameters<typeof sendMindAidMessage.run>[0]);
}

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Local Firestore emulator required");
  await db.collection("mind_aid_config").doc("rollout").set({enabled: true, percentage: 100});
  await db.collection("mind_aid_preferences").doc(uid).set({
    cloudConsent: true, consentVersion: "2026-07-13", conversationId,
    personalizationEnabled: false,
  });
});

test("successful callable persists exactly two documents and retries preserve server fields", async (t) => {
  const previous = process.env.GCLOUD_PROJECT;
  const provider = process.env.MINDAID_AI_PROVIDER;
  process.env.GCLOUD_PROJECT = "mindmate-staging";
  process.env.MINDAID_AI_PROVIDER = "gemini";
  t.mock.method(GeminiMindAidProvider.prototype, "generate", async () => ({
    text: "I'm here to listen.", provider: "gemini", model: "gemini-3.8-flash",
  }));
  try {
    const first = await send("success-12345678");
    const retry = await send("success-12345678", "I feel anxious", "casual");
    assert.deepEqual(retry, first);
    const messages = await db.collection("mind_aid_messages").where("userId", "==", uid).get();
    assert.equal(messages.size, 2);
    assert.equal(messages.docs.find((doc) => doc.id.endsWith("_user"))?.data().text, "I feel anxious");
    const assistant = messages.docs.find((doc) => doc.id === first.messageId)?.data();
    assert.equal(assistant?.source, "gemini");
    assert.equal(assistant?.model, "gemini-3.8-flash");
    assert.equal(assistant?.effectiveConversationMode, "listening");
  } finally {
    if (previous === undefined) delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT = previous;
    if (provider === undefined) delete process.env.MINDAID_AI_PROVIDER;
    else process.env.MINDAID_AI_PROVIDER = provider;
  }
});

test("server safety intercept persists controlled escalation without invoking Gemini", async (t) => {
  t.mock.method(GeminiMindAidProvider.prototype, "generate", async () => assert.fail("safety must bypass Gemini"));
  const result = await send("safety-12345678", "Hindi ako safe right now");
  assert.equal(result.source, "controlled_safety");
  assert.equal(result.safetyLevel, "highDistress");
  assert.equal(result.requiresEscalation, true);
  assert.equal((await db.collection("mind_aid_messages").doc(result.messageId).get()).data()?.requiresEscalation, true);
});

test("cached Dialogflow response retains persisted suggestions and mode", async () => {
  await db.collection("mind_aid_messages").doc(`${uid}_cached-12345678_assistant`).set({
    userId: uid, text: "Server support", source: "dialogflow", primaryIntent: "server_intent",
    confidence: 0.9, safetyLevel: "safeSupport", requiresEscalation: false,
    fallbackReason: "gemini_timeout", actions: [], suggestions: ["Take a pause"],
    effectiveConversationMode: "reflective",
  });
  const result = await send("cached-12345678");
  assert.deepEqual(result.suggestions, ["Take a pause"]);
  assert.equal(result.effectiveConversationMode, "reflective");
  assert.equal(result.fallbackReason, "gemini_timeout");
});

for (const [label, model, expected] of [
  ["historical", "gemini-2.5-flash", "gemini-2.5-flash"],
  ["unsupported", "untrusted-model", undefined],
] as const) {
  test(`cached ${label} model attribution is validated without rewriting history`, async () => {
    const requestId = `${label}-model-12345678`;
    const reference = db.collection("mind_aid_messages").doc(`${uid}_${requestId}_assistant`);
    await reference.set({
      userId: uid, text: "Earlier support", source: "gemini", model,
      confidence: 1, safetyLevel: "highDistress", requiresEscalation: true,
      effectiveConversationMode: "supportive",
    });
    const result = await send(requestId);
    assert.equal(result.model, expected);
    assert.equal(result.requiresEscalation, true);
    assert.equal(result.safetyLevel, "highDistress");
    assert.equal((await reference.get()).data()?.model, model);
  });
}
