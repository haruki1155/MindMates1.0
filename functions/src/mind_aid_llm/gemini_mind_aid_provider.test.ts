import assert from "node:assert/strict";
import {test} from "node:test";
import {GoogleGenAI} from "@google/genai";
import {GeminiMindAidProvider} from "./gemini_mind_aid_provider";

const request = {
  message: "I feel anxious", conversationMode: "listening" as const,
  explicitListening: true,
  recentTurns: [{role: "assistant" as const, text: "I'm listening."}],
};
// Stub only HTTP transport; exercise the installed SDK's Vertex serialization.
const sdk = new GoogleGenAI({vertexai: true, project: "mindmate-staging", location: "global"});
const transport = (sdk.models as unknown as {apiClient: {
  getProject(): string; getLocation(): string; isVertexAI(): boolean;
}}).apiClient;

test("Gemini 3.8 Flash sends compatible Vertex configuration through the installed SDK", async (t) => {
  t.mock.method(Object.getPrototypeOf(transport), "request", async function(
    this: typeof transport, input: {body: string; path: string},
  ) {
    assert.equal(this.isVertexAI(), true);
    assert.equal(this.getProject(), "mindmate-staging");
    assert.equal(this.getLocation(), "global");
    assert.match(input.path, /gemini-3.8-flash:generateContent$/);
    const body = JSON.parse(input.body);
    assert.equal(body.generationConfig.thinkingConfig.thinkingLevel, "LOW");
    assert.equal(body.generationConfig.thinkingConfig.thinkingBudget, undefined);
    assert.equal(body.contents[0].role, "model");
    return new Response(JSON.stringify({candidates: [{content: {parts: [{text: "I'm here with you."}]}}]}));
  });
  const result = await new GeminiMindAidProvider("mindmate-staging", 50).generate(request);
  assert.equal(result.text, "I'm here with you.");
  assert.equal(result.model, "gemini-3.8-flash");
});

test("Gemini provider itself rejects every non-staging project", async (t) => {
  t.mock.method(Object.getPrototypeOf(transport), "request", async () => {
    assert.fail("must never call Vertex outside staging");
  });
  for (const project of ["mind-mates-cd2cf", "mindmate-dev-4e91c", "", "mindmate-staging-other"]) {
    await assert.rejects(new GeminiMindAidProvider(project, 50).generate(request), /gemini_staging_only/);
  }
});
