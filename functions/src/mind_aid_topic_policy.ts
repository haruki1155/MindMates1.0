// Keep vocabulary and task rules aligned with MindAidChatEngine in Flutter.
export const mindAidWelcome = "Hi! I'm MindAid, your mental wellness companion. 💙\n\nI'm here to support your emotional well-being and help you with PACC services, counseling, and MindMate wellness features.\n\nHow can I help you today?";

function normalize(text: string): string {
  return text.toLowerCase().replace(/[’']/g, "").replace(/[^a-z0-9\s]/g, " ").replace(/\s+/g, " ").trim();
}

const unrelatedRequest = new RegExp("\\b(?:write|generate|debug|fix|explain|teach|show|give|create|build|implement|solve|calculate|translate|summarize|ignore)\\b.*\\b(?:code|python|javascript|program|app|website|recipe|essay|equation|exam answers|instructions)\\b|\\b(?:how (?:do i|to|can i)|paano|pano)\\b.*\\b(?:code|cook|program|magluto|magcode|mag code)\\b|\\b(?:what is|what are|ano ang|ano yung|sino)\\b.*\\b(?:javascript|python|code|capital|president)\\b|\\b(?:who won|capital of|capital ng|weather|nba|recipe|exam answers)\\b|\\d+\\s*(?:x|\\*|\\+|/)\\s*\\d+");
const wellnessTerms = ["mental health", "mental wellness", "emotional health", "wellbeing", "well being", "wellness", "stress", "stressed", "stressful", "anxiety", "anxious", "panic", "panicking", "depression", "depressed", "sad", "sadness", "lonely", "loneliness", "alone", "burnout", "burned out", "exhausted", "overwhelmed", "worried", "worry", "fear", "afraid", "scared", "crying", "upset", "hopeless", "helpless", "mood", "emotion", "emotions", "feelings", "feeling down", "sleep problem", "insomnia", "cant sleep", "cannot sleep", "self esteem", "self confidence", "insecure", "coping", "cope", "grounding", "breathing exercise", "mindfulness", "meditation", "relaxation", "grief", "trauma", "bullying", "bullied", "relationship problems", "family problems", "academic stress", "school pressure", "exam pressure", "exam deadline", "pagod", "malungkot", "nalulungkot", "lungkot", "kinakabahan", "kabado", "takot", "naiiyak", "umiiyak", "nahihirapan", "pag aalala", "pagkabalisa", "sobrang stress", "emotional support", "hindi makatulog", "hindi ako makatulog", "di ako makatulog", "di makatulog", "masaya", "galit", "naiinis", "sama ng loob"];
const paccTerms = ["pacc", "guidance", "guidance counselor", "guidance assistant", "counselor", "counseling", "counselling", "therapy", "appointment", "book counseling", "book appointment", "schedule counseling", "mental health assessment", "self assessment", "assessment result", "assessment score", "phq 9", "gad 7", "mindmate", "mindaid", "mood tracker", "mood tracking", "secret posting", "breathing exercises", "facial tracking", "facial recognition", "insights", "journal", "wellness resources", "daily streak", "daily quest", "psychological assessment"];
const replies = ["yes", "no", "yeah", "yep", "nope", "okay", "ok", "sure", "please", "continue", "tell me more", "go on", "oo", "opo", "hindi", "sige", "salamat", "thanks"];
const contextualReplies = ["my grades", "my exam", "my exams", "my family", "my parents", "my work", "my job", "because of my family", "because of my grades", "because of my exams", "what should i do", "what can i do", "how can i cope", "how do i cope", "can you help me", "give me advice", "any advice", "tell me more about it", "what do you suggest", "help me with that", "why", "how", "bakit", "paano", "ano ang gagawin ko", "ano dapat kong gawin", "paano ko gagawin yun"];

function hasTerm(text: string, term: string): boolean {
  return (` ${text} `).includes(` ${term} `);
}

export function isMindAidTopic(text: string, hasWellnessContext = false): boolean {
  const input = normalize(text);
  if (unrelatedRequest.test(input)) return false;
  if ([...wellnessTerms, ...paccTerms].some((term) => hasTerm(input, term))) return true;
  return hasWellnessContext && [...replies, ...contextualReplies,
    "what does it mean", "how severe", "how am i doing", "what should i do next",
    "result", "results", "score", "scores", "review", "progress", "status",
  ].includes(input);
}
