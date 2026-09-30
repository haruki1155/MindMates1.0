export type MindAidConversationMode = "supportive" | "listening" | "reflective" | "coaching" | "casual" | "navigation";

export interface MindAidRecentTurn {
  // `assistant` is the only assistant role accepted from the callable. The
  // Gemini adapter maps it to Gemini's transport-specific `model` role.
  role: "user" | "assistant";
  text: string;
}

export interface MindAidLlmRequest {
  message: string;
  conversationMode: MindAidConversationMode;
  explicitListening: boolean;
  recentTurns: MindAidRecentTurn[];
}

export interface MindAidLlmResponse {
  text: string;
  provider: "gemini";
  model: "gemini-3.8-flash";
}
