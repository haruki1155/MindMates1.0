import {GoogleGenAI, ThinkingLevel} from "@google/genai";
import {MindAidLlmProvider} from "./mind_aid_llm_provider";
import {GEMINI_MINDAID_MODEL, MindAidLlmRequest, MindAidLlmResponse} from "./mind_aid_llm_models";
import {buildMindAidSystemInstruction} from "./mind_aid_system_prompt";

export {GEMINI_MINDAID_MODEL} from "./mind_aid_llm_models";

export class GeminiMindAidProvider implements MindAidLlmProvider {
  constructor(
    private readonly projectId: string,
    private readonly timeoutMs = 8000,
  ) {}

  async generate(request: MindAidLlmRequest): Promise<MindAidLlmResponse> {
    if (this.projectId !== "mindmate-staging") throw new Error("gemini_staging_only");
    const client = new GoogleGenAI({vertexai: true, project: this.projectId, location: "global"});
    const contents = [
      ...request.recentTurns.map((turn) => ({
        role: turn.role === "assistant" ? "model" as const : "user" as const,
        parts: [{text: turn.text}],
      })),
      {role: "user" as const, parts: [{text: request.message}]},
    ];
    const response = await Promise.race([
      client.models.generateContent({
        model: GEMINI_MINDAID_MODEL,
        contents,
        config: {
          systemInstruction: buildMindAidSystemInstruction({
            conversationMode: request.conversationMode,
            explicitListening: request.explicitListening,
          }),
          thinkingConfig: {thinkingLevel: ThinkingLevel.LOW},
        },
      }),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error("gemini_timeout")), this.timeoutMs)),
    ]);
    const text = String(response.text ?? "").trim();
    if (!text) throw new Error("gemini_empty_response");
    return {text, provider: "gemini", model: GEMINI_MINDAID_MODEL};
  }
}
