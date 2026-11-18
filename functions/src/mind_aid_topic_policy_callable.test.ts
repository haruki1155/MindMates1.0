import assert from "node:assert/strict";
import {before, test} from "node:test";
import {getFirestore} from "firebase-admin/firestore";
import {sendMindAidMessage} from "./mind_aid";
import {GeminiMindAidProvider} from "./mind_aid_llm/gemini_mind_aid_provider";

const db = getFirestore();
const uid = `mindaid-topic-${Date.now()}`;
const conversationId = "conversation-12345678";

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Local Firestore emulator required");
  await db.collection("mind_aid_config").doc("rollout").set({enabled: true, percentage: 100});
  await db.collection("mind_aid_preferences").doc(uid).set({
    cloudConsent: true, consentVersion: "2026-07-13", conversationId, personalizationEnabled: false,
  });
});

test("off-topic requests are persisted without invoking Gemini", async (t) => {
  const previousProject = process.env.GCLOUD_PROJECT;
  const previousProvider = process.env.MINDAID_AI_PROVIDER;
  process.env.GCLOUD_PROJECT = "mindmate-staging";
  process.env.MINDAID_AI_PROVIDER = "gemini";
  t.mock.method(GeminiMindAidProvider.prototype, "generate", async () => {
    assert.fail("off-topic requests must be rejected before cloud generation");
  });
  try {
    const result = await sendMindAidMessage.run({auth: {uid}, data: {
      requestId: "topic-reject-12345678", conversationId, text: "How to code?",
    }} as Parameters<typeof sendMindAidMessage.run>[0]);
    assert.equal(result.source, "controlled_topic");
    assert.equal(result.fallbackReason, "topic_redirect");
    assert.match(result.text, /^Hi! I'm MindAid/);
    assert.equal((await db.collection("mind_aid_messages").doc(result.messageId).get()).data()?.text, result.text);
  } finally {
    if (previousProject === undefined) delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT = previousProject;
    if (previousProvider === undefined) delete process.env.MINDAID_AI_PROVIDER;
    else process.env.MINDAID_AI_PROVIDER = previousProvider;
  }
});

test("Tagalog wellness disclosure permits follow-up only in its conversation", async (t) => {
  const previousProject = process.env.GCLOUD_PROJECT;
  const previousProvider = process.env.MINDAID_AI_PROVIDER;
  process.env.GCLOUD_PROJECT = "mindmate-staging";
  process.env.MINDAID_AI_PROVIDER = "gemini";
  t.mock.method(GeminiMindAidProvider.prototype, "generate", async () => ({
    text: "I'm here to listen.", provider: "gemini", model: "gemini-3.8-flash",
  }));
  try {
    const disclosure = await sendMindAidMessage.run({auth: {uid}, data: {
      requestId: "topic-disclose-12345678", conversationId, text: "Kinakabahan ako sa exam.",
    }} as Parameters<typeof sendMindAidMessage.run>[0]);
    assert.equal(disclosure.source, "gemini");
    const followUp = await sendMindAidMessage.run({auth: {uid}, data: {
      requestId: "topic-followup-12345678", conversationId, text: "Sige.",
    }} as Parameters<typeof sendMindAidMessage.run>[0]);
    assert.equal(followUp.source, "gemini");
    const nextConversationId = "conversation-87654321";
    await db.collection("mind_aid_preferences").doc(uid).set({conversationId: nextConversationId}, {merge: true});
    const newConversation = await sendMindAidMessage.run({auth: {uid}, data: {
      requestId: "topic-reset-12345678", conversationId: nextConversationId, text: "Sige.",
    }} as Parameters<typeof sendMindAidMessage.run>[0]);
    assert.equal(newConversation.fallbackReason, "topic_redirect");
  } finally {
    if (previousProject === undefined) delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT = previousProject;
    if (previousProvider === undefined) delete process.env.MINDAID_AI_PROVIDER;
    else process.env.MINDAID_AI_PROVIDER = previousProvider;
  }
});