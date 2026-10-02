import {createHash} from "node:crypto";

import type {protos} from "@google-cloud/dialogflow-cx";
import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {GeminiMindAidProvider} from "./mind_aid_llm/gemini_mind_aid_provider";
import type {MindAidLlmResponse, MindAidRecentTurn} from "./mind_aid_llm/mind_aid_llm_models";
import {GEMINI_MINDAID_MODEL} from "./mind_aid_llm/gemini_mind_aid_provider";
import {createOrUpdateMindAidEmergencyAlert} from "./mind_aid_emergency";

if (!getApps().length) initializeApp();

const db = getFirestore();
const REGION = "asia-southeast1";
const CONSENT_VERSION = "2026-07-13";
const MAX_MESSAGE_LENGTH = 1200;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 12;
const REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/;
const CONVERSATION_ID = /^[A-Za-z0-9_-]{8,64}$/;

type SafetyLevel = "safeSupport" | "needsClarification" | "highDistress" | "crisisOrImmediateRisk";
type ConversationMode = "supportive" | "listening" | "reflective" | "coaching" | "casual" | "navigation";
type MindAidSource = "dialogflow" | "gemini" | "controlled_safety";

interface MindAidAction {
  type: string;
  label: string;
  payload?: Record<string, unknown>;
}

interface MindAidResponse {
  messageId: string;
  text: string;
  intent: string;
  confidence: number;
  safetyLevel: SafetyLevel;
  source: MindAidSource;
  model?: "gemini-3.8-flash";
  suggestions: string[];
  actions: MindAidAction[];
  requiresEscalation: boolean;
  fallbackReason: string;
  effectiveConversationMode: ConversationMode;
}

const conversationModes = new Set<ConversationMode>([
  "supportive", "listening", "reflective", "coaching", "casual", "navigation",
]);

// Behavioral metadata only. This must not be used for authorization, safety,
// assessment interpretation, or access-control decisions.
export function effectiveConversationMode(value: unknown): ConversationMode {
  const mode = String(value ?? "").trim();
  return conversationModes.has(mode as ConversationMode)
    ? mode as ConversationMode
    : "supportive";
}

export function dialogflowModeEvent(mode: ConversationMode): string {
  return `mind_aid_mode_${mode}`;
}

type AiProvider = "dialogflow" | "gemini" | "local";

export function aiProvider(value = process.env.MINDAID_AI_PROVIDER): AiProvider {
  const configured = String(value ?? "").trim().toLowerCase();
  return configured === "gemini" || configured === "local" || configured === "dialogflow"
    ? configured
    : "dialogflow";
}

export function geminiFallbackReason(error: unknown): string {
  const code = String((error as {code?: unknown})?.code ?? "").toLowerCase();
  const message = String((error as {message?: unknown})?.message ?? "").toLowerCase();
  const detail = `${code} ${message}`;
  if (detail.includes("gemini_timeout") || detail.includes("deadline") || detail.includes("timeout")) return "gemini_timeout";
  if (detail.includes("permission_denied") || detail.includes("permission denied")) return "gemini_permission_denied";
  if (detail.includes("unauthenticated") || detail.includes("authentication") || detail.includes("credentials")) return "gemini_auth_error";
  if (detail.includes("unavailable") || detail.includes("vertex ai api") || detail.includes("api disabled")) return "gemini_api_unavailable";
  if (detail.includes("model") || detail.includes("not found") || detail.includes("invalid argument")) return "gemini_model_error";
  if (detail.includes("gemini_empty_response")) return "gemini_empty_response";
  if (detail.includes("gemini_unsafe_response")) return "gemini_unsafe_response";
  return "gemini_unknown_error";
}

export function geminiErrorDiagnostic(error: unknown): {code: string; message: string} {
  const code = String((error as {code?: unknown})?.code ?? "unknown")
    .replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 80) || "unknown";
  const message = String((error as {message?: unknown})?.message ?? "unknown error")
    .replace(/[\r\n\t]+/g, " ").replace(/[^A-Za-z0-9 .,:/_'()=-]/g, "_")
    .slice(0, 180) || "unknown error";
  return {code, message};
}

export async function attemptGemini<T extends MindAidLlmResponse>(
  projectId: string,
  configuredProvider: AiProvider,
  generate: () => Promise<T>,
): Promise<{attempted: boolean; response?: T; fallbackReason: string; error?: {code: string; message: string}}> {
  if (configuredProvider !== "gemini" || projectId !== "mindmate-staging") {
    return {attempted: false, fallbackReason: ""};
  }
  try {
    return {attempted: true, response: await generate(), fallbackReason: ""};
  } catch (error) {
    return {
      attempted: true, fallbackReason: geminiFallbackReason(error),
      error: geminiErrorDiagnostic(error),
    };
  }
}

export function sanitizeRecentTurns(value: unknown): MindAidRecentTurn[] {
  // This is untrusted callable input. Reject an oversized request rather than
  // silently accepting a client-controlled context window.
  if (!Array.isArray(value) || value.length > 8) return [];
  let totalCharacters = 0;
  return value.flatMap((item): MindAidRecentTurn[] => {
    if (!item || typeof item !== "object") return [];
    const data = item as Record<string, unknown>;
    const role = data.role === "user" || data.role === "assistant" ? data.role : null;
    // Never stringify arbitrary client objects into prompt content.
    if (typeof data.text !== "string") return [];
    const text = data.text.trim().slice(0, 600);
    if (!role || !text || totalCharacters + text.length > 4800) return [];
    totalCharacters += text.length;
    return [{role, text}];
  });
}

export function eligibleRecentTurns(personalizationEnabled: boolean, value: unknown): MindAidRecentTurn[] {
  return personalizationEnabled ? sanitizeRecentTurns(value) : [];
}

export function dialogflowSessionId(
  uid: string,
  conversationId: string,
  sessionInstanceId: unknown,
  requestId: string,
): string {
  const session = String(sessionInstanceId ?? "").trim();
  // Invalid client metadata must not recreate a cross-session CX identity.
  // requestId is validated before this helper is called, so this fallback is
  // isolated to one callable request rather than a reusable legacy session.
  const safeSession = /^[A-Za-z0-9_-]{16,96}$/.test(session) ? session : `request:${requestId}`;
  return createHash("sha256").update(`${uid}:${conversationId}:${safeSession}`).digest("hex").slice(0, 36);
}

const crisisPhrases = [
  "kill myself", "kill my self", "end my life", "end it all", "take my life",
  "no reason to live", "cant go on", "cannot go on", "want to disappear",
  "unalive myself", "suicide", "self harm", "hurt myself", "hurt my self", "cut myself",
  "i want to die", "i dont want to live", "do not want to live", "ayoko nang mabuhay",
  "gusto kong mamatay", "magpakamatay",
];

const highDistressPhrases = [
  "panic attack", "cant breathe", "cannot breathe", "i am unsafe",
  "not safe right now", "someone might hurt me", "i might hurt someone",
  "breaking down", "out of control", "hindi ako safe", "sasaktan ako",
];

const blockedOutputPhrases = [
  "you have depression", "you have anxiety disorder", "you are diagnosed",
  "i diagnose", "as your therapist", "as a licensed counselor",
  "you have bipolar", "you have ptsd", "stop taking", "increase your dose",
  "take this medication", "keep this secret", "do not tell anyone",
  "guaranteed to work",
];

const allowedActions = new Set([
  "logMood", "startBreathing", "openAssessment", "openInsights",
  "openCounselingServices", "bookAppointment", "viewAppointments",
]);

function normalize(value: string): string {
  return value.toLowerCase().replace(/[’']/g, "").replace(/[^a-z0-9\s]/g, " ").replace(/\s+/g, " ").trim();
}

export function classifyMindAidSafety(text: string): SafetyLevel {
  const value = normalize(text);
  if (!value) return "needsClarification";
  if (isCurrentFirstPersonRisk(value)) return "crisisOrImmediateRisk";
  if (highDistressPhrases.some((phrase) => value.includes(phrase))) return "highDistress";
  return "safeSupport";
}

export function isCurrentFirstPersonRisk(value: string): boolean {
  const phraseDetected = crisisPhrases.some((phrase) => value.includes(phrase)) || /(^|\s)kms(\s|$)/.test(value);
  if (!phraseDetected) return false;
  if (value === "kms" || value.startsWith("i cannot go on") || value.startsWith("i cant go on")) return true;
  if (/\b(i|ako)\s+(do not|dont|did not|didnt|never)\s+(want to )?(kill|hurt|end)\b/.test(value) ||
      /\b(i|ako)\s+(used to|no longer|dati)\b/.test(value) ||
      /\b(my friend|friend|he|she|they|someone|story|article|nabasa ko)\b/.test(value)) return false;
  return /\b(i|im|ive|me|myself|my self|ako|kong|ko)\b/.test(value) ||
    /\b(magpakamatay|gusto kong mamatay|ayoko nang mabuhay)\b/.test(value);
}

export function isSafeMindAidOutput(text: string): boolean {
  const value = normalize(text);
  return Boolean(value) && !blockedOutputPhrases.some((phrase) => value.includes(phrase));
}

interface SupportContacts {
  paccName: string;
  paccPhone: string;
  campusSecurityPhone: string;
  emergencyLabel: string;
  emergencyPhone: string;
  shortName: string;
  ncmhLandline: string;
  ncmhGlobe: string;
  ncmhSmart: string;
  ncmhAlternate: string;
  hopelineTollFree: string;
  hopelineGlobe: string;
  hopelineSmart: string;
  hopelinePldt: string;
  inTouchLandline: string;
  inTouchSmart: string;
  inTouchGlobe: string;
  tawagPaglaumSmart: string;
  tawagPaglaumGlobe: string;
}

async function loadSupportContacts(): Promise<SupportContacts> {
  const data = (await db.collection("mind_aid_config").doc("support_contacts").get()).data() ?? {};
  const phone = (value: unknown): string => {
    const text = String(value ?? "").trim();
    return /^[+0-9() -]{7,24}$/.test(text) ? text : "";
  };
  const configuredShortName = String(data.shortName ?? "PACC").trim().slice(0, 20);
  return {
    paccName: String(data.displayName ?? data.paccName ?? "Psychological Assessment and Counseling Center").trim().slice(0, 100) || "Psychological Assessment and Counseling Center",
    paccPhone: phone(data.paccPhone),
    campusSecurityPhone: phone(data.campusSecurityPhone),
    emergencyLabel: String(data.emergencyLabel ?? "local emergency services").trim().slice(0, 80) || "local emergency services",
    emergencyPhone: phone(data.emergencyNumber ?? data.emergencyPhone),
    shortName: /^paacc$/i.test(configuredShortName) ? "PACC" : (configuredShortName || "PACC"),
    ncmhLandline: phone(data.ncmhLandline), ncmhGlobe: phone(data.ncmhGlobe), ncmhSmart: phone(data.ncmhSmart), ncmhAlternate: phone(data.ncmhAlternate),
    hopelineTollFree: phone(data.hopelineTollFree), hopelineGlobe: phone(data.hopelineGlobe), hopelineSmart: phone(data.hopelineSmart), hopelinePldt: phone(data.hopelinePldt),
    inTouchLandline: phone(data.inTouchLandline), inTouchSmart: phone(data.inTouchSmart), inTouchGlobe: phone(data.inTouchGlobe),
    tawagPaglaumSmart: phone(data.tawagPaglaumSmart), tawagPaglaumGlobe: phone(data.tawagPaglaumGlobe),
  };
}

export function controlledCrisisResponse(contacts: SupportContacts, emergencyAlertNotified = false): {text: string; actions: MindAidAction[]} {
  return buildControlledCrisisResponse(contacts, emergencyAlertNotified);
}

function buildControlledCrisisResponse(contacts: SupportContacts, emergencyAlertNotified: boolean): {text: string; actions: MindAidAction[]} {
  const section = (heading: string, values: Array<[string, string]>) => {
    const configured = values.filter(([number]) => number.trim().length > 0);
    return configured.length
      ? [heading, ...configured.map(([number, label]) => `- ${number} - ${label}`), ""]
      : [];
  };
  const contactsLines = [
    ...section("**NCMH Crisis Hotline - National Center for Mental Health**", [[contacts.ncmhLandline, "landline"], [contacts.ncmhGlobe, "Globe / TM"], [contacts.ncmhSmart, "Smart / TNT"], [contacts.ncmhAlternate, "Smart / Sun / TNT"]]),
    ...section("**HOPELINE - Natasha Goulbourn Foundation**", [[contacts.hopelineTollFree, "Globe / TM toll-free"], [contacts.hopelineGlobe, "Globe"], [contacts.hopelineSmart, "Smart"], [contacts.hopelinePldt, "PLDT"]]),
    ...section("**In Touch Crisis Line**", [[contacts.inTouchLandline, "landline"], [contacts.inTouchSmart, "Smart"], [contacts.inTouchGlobe, "Globe"]]),
    ...section("**Tawag Paglaum - Centro Bisaya**\nCebu and Central Visayas", [[contacts.tawagPaglaumSmart, "Smart / Sun / TNT"], [contacts.tawagPaglaumGlobe, "Globe / TM"]]),
  ];
  const emergencyInstruction = contacts.emergencyPhone
    ? `If you may hurt yourself or are in immediate danger, call ${contacts.emergencyPhone} or go to the nearest emergency department.`
    : "If you may hurt yourself or are in immediate danger, contact local emergency services or go to the nearest emergency department.";
  const ending = emergencyAlertNotified
    ? `${contacts.shortName} has been notified so a counselor can follow up.`
    : `MindAid could not automatically notify ${contacts.shortName}. Please contact ${contacts.shortName}, ${contacts.emergencyPhone || contacts.emergencyLabel}, a trusted person, or one of the crisis-support lines above directly.`;
  return {
    text: ["**Emergency Support**", "", "Your safety matters right now.", "", `${emergencyInstruction} Please stay with someone you trust and move away from anything you could use to hurt yourself.`, "", ...(contactsLines.length ? ["**Crisis and Mental Health Support**", "For mental health crises, depression, or suicidal thoughts, these verified crisis-support lines are available:", "", ...contactsLines] : []), ending].join("\n"),
    actions: [{type: "openCounselingServices", label: `View ${contacts.shortName} Support`}],
  };
}

function legacyControlledCrisisResponse(contacts: SupportContacts, emergencyAlertNotified = false): {text: string; actions: MindAidAction[]} {
  const section = (heading: string, values: Array<[string, string]>) => {
    const configured = values.filter(([number]) => number.trim().length > 0);
    return configured.length ? [heading, ...configured.map(([number, label]) => `- ${number} — ${label}`), ""] : [];
  };
  const contactsLines = [
    ...section("**NCMH Crisis Hotline — National Center for Mental Health**", [[contacts.ncmhLandline, "landline"], [contacts.ncmhGlobe, "Globe / TM"], [contacts.ncmhSmart, "Smart / TNT"], [contacts.ncmhAlternate, "Smart / Sun / TNT"]]),
    ...section("**HOPELINE — Natasha Goulbourn Foundation**", [[contacts.hopelineTollFree, "Globe / TM toll-free"], [contacts.hopelineGlobe, "Globe"], [contacts.hopelineSmart, "Smart"], [contacts.hopelinePldt, "PLDT"]]),
    ...section("**In Touch Crisis Line**", [[contacts.inTouchLandline, "landline"], [contacts.inTouchSmart, "Smart"], [contacts.inTouchGlobe, "Globe"]]),
    ...section("**Tawag Paglaum – Centro Bisaya**\nCebu and Central Visayas", [[contacts.tawagPaglaumSmart, "Smart / Sun / TNT"], [contacts.tawagPaglaumGlobe, "Globe / TM"]]),
  ];
  const emergencyInstruction = contacts.emergencyPhone
    ? `If you may hurt yourself or are in immediate danger, call ${contacts.emergencyPhone} or go to the nearest emergency department.`
    : "If you may hurt yourself or are in immediate danger, contact local emergency services or go to the nearest emergency department.";
  const ending = emergencyAlertNotified
    ? `${contacts.shortName} has been notified so a counselor can follow up.`
    : `MindAid could not automatically notify ${contacts.shortName}. Please contact ${contacts.shortName}, 911, a trusted person, or one of the crisis-support lines above directly.`;
  return {
    text: ["**Emergency Support**", "", "Your safety matters right now.", "", `${emergencyInstruction} Please stay with someone you trust and move away from anything you could use to hurt yourself.`, "", ...(contactsLines.length ? ["**Crisis and Mental Health Support**", "For mental health crises, depression, or suicidal thoughts, these verified crisis-support lines are available:", "", ...contactsLines] : []), ending].join("\n"),
    actions: [{type: "openCounselingServices", label: `View ${contacts.shortName} Support`}],
  };
}

function safetyResponse(level: SafetyLevel, contacts: SupportContacts, emergencyAlertNotified = false): {text: string; actions: MindAidAction[]} {
  if (level === "crisisOrImmediateRisk") return controlledCrisisResponse(contacts, emergencyAlertNotified);
  if (false) {
    const lines = [
      "**Emergency Support**", "", "Your safety matters right now.", "",
      `If you may hurt yourself or are in immediate danger, call ${contacts.emergencyPhone} or go to the nearest emergency department. Please stay with someone you trust and move away from anything you could use to hurt yourself.`, "",
      "**Crisis and Mental Health Support**", "For mental health crises, depression, or suicidal thoughts, the following free and confidential crisis-support lines are available:", "",
      "**NCMH Crisis Hotline — National Center for Mental Health**", `- ${contacts.ncmhLandline} — landline`, `- ${contacts.ncmhGlobe} — Globe / TM`, `- ${contacts.ncmhSmart} — Smart / TNT`, `- ${contacts.ncmhAlternate} — Smart / Sun / TNT`, "",
      "**HOPELINE — Natasha Goulbourn Foundation**", `- ${contacts.hopelineTollFree} — Globe / TM toll-free`, `- ${contacts.hopelineGlobe} — Globe`, `- ${contacts.hopelineSmart} — Smart`, `- ${contacts.hopelinePldt} — PLDT`, "",
      "**In Touch Crisis Line**", `- ${contacts.inTouchLandline} — landline`, `- ${contacts.inTouchSmart} — Smart`, `- ${contacts.inTouchGlobe} — Globe`, "",
      "**Tawag Paglaum – Centro Bisaya**", "Cebu and Central Visayas", `- ${contacts.tawagPaglaumSmart} — Smart / Sun / TNT`, `- ${contacts.tawagPaglaumGlobe} — Globe / TM`, "",
      emergencyAlertNotified ? `${contacts.shortName} has been notified so a counselor can follow up.` : `MindAid could not automatically notify ${contacts.shortName}. Please contact ${contacts.shortName}, 911, a trusted person, or one of the crisis-support lines above directly.`,
    ];
    return {text: lines.join("\n"), actions: [{type: "openCounselingServices", label: `View ${contacts.shortName} Support`}]} ;
  }
  const verified = [
    contacts.paccPhone ? `${contacts.paccName}: ${contacts.paccPhone}` : "",
    contacts.campusSecurityPhone ? `Campus security: ${contacts.campusSecurityPhone}` : "",
    contacts.emergencyPhone ? `${contacts.emergencyLabel}: ${contacts.emergencyPhone}` : "",
  ].filter(Boolean);
  const contactLine = verified.length ? `\n\nVerified contacts: ${verified.join(" • ")}` : "";
  if (false) {
    return {
      text: `I’m really sorry you’re carrying this much pain. MindAid is an automated wellness assistant and cannot provide emergency care. Your safety matters right now. Please move near a trusted person and contact local emergency services, campus security, ${contacts.paccName}, or the nearest emergency room. If you can, tell someone clearly: “I may not be safe alone right now.”${contactLine}`,
      actions: [
        {type: "openCounselingServices", label: "View support services"},
        {type: "bookAppointment", label: "Contact PACC"},
      ],
    };
  }
  return {
    text: `This sounds very intense, and you do not have to manage it alone. MindAid is an automated wellness assistant and cannot provide emergency care. Please pause and move toward a trusted person or safe place. If you may be in immediate danger, contact local emergency services, campus security, ${contacts.paccName}, or the nearest emergency room now.${contactLine}`,
    actions: [
      {type: "startBreathing", label: "Start a grounding exercise"},
      {type: "openCounselingServices", label: "View support services"},
    ],
  };
}

function manilaDateKey(date: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(date);
}

function safeMetricKey(value: string): string {
  return value.replace(/[^A-Za-z0-9_]/g, "_").slice(0, 80) || "unknown";
}

function toValue(value: unknown): protos.google.protobuf.IValue {
  if (value === null || value === undefined) return {nullValue: 0};
  if (typeof value === "string") return {stringValue: value};
  if (typeof value === "number") return {numberValue: value};
  if (typeof value === "boolean") return {boolValue: value};
  if (Array.isArray(value)) return {listValue: {values: value.map(toValue)}};
  const fields: Record<string, protos.google.protobuf.IValue> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) fields[key] = toValue(item);
  return {structValue: {fields}};
}

function toStruct(value: Record<string, unknown>): protos.google.protobuf.IStruct {
  const fields: Record<string, protos.google.protobuf.IValue> = {};
  for (const [key, item] of Object.entries(value)) fields[key] = toValue(item);
  return {fields};
}

function fromStruct(struct?: protos.google.protobuf.IStruct | null): Record<string, unknown> {
  const decode = (value?: protos.google.protobuf.IValue | null): unknown => {
    if (!value) return null;
    if (value.stringValue != null) return value.stringValue;
    if (value.numberValue != null) return value.numberValue;
    if (value.boolValue != null) return value.boolValue;
    if (value.listValue) return (value.listValue.values ?? []).map(decode);
    if (value.structValue) return fromStruct(value.structValue);
    return null;
  };
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(struct?.fields ?? {})) result[key] = decode(value);
  return result;
}

async function enforceRateLimit(uid: string): Promise<void> {
  const reference = db.collection("_mind_aid_rate_limits").doc(uid);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const now = Date.now();
    const startedAt = snapshot.data()?.startedAt instanceof Timestamp ? snapshot.data()!.startedAt.toMillis() : 0;
    const count = Number(snapshot.data()?.count ?? 0);
    if (now - startedAt < RATE_LIMIT_WINDOW_MS && count >= RATE_LIMIT_MAX) {
      throw new HttpsError("resource-exhausted", "Please wait a moment before sending another message.");
    }
    transaction.set(reference, {
      startedAt: Timestamp.fromMillis(now - startedAt >= RATE_LIMIT_WINDOW_MS ? now : startedAt),
      count: now - startedAt >= RATE_LIMIT_WINDOW_MS ? 1 : count + 1,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

async function requireConsentAndRollout(uid: string): Promise<{personalizationEnabled: boolean; conversationId: string}> {
  const [preferences, rollout] = await Promise.all([
    db.collection("mind_aid_preferences").doc(uid).get(),
    db.collection("mind_aid_config").doc("rollout").get(),
  ]);
  const preferenceData = preferences.data() ?? {};
  if (preferenceData.cloudConsent !== true || preferenceData.consentVersion !== CONSENT_VERSION) {
    throw new HttpsError("failed-precondition", "Dialogflow consent is required.");
  }
  const rolloutData = rollout.data() ?? {};
  const pilotUserIds = Array.isArray(rolloutData.pilotUserIds) ? rolloutData.pilotUserIds.map(String) : [];
  const enabled = rolloutData.enabled === true;
  const percent = Math.max(0, Math.min(100, Number(rolloutData.percentage ?? 0)));
  const bucket = parseInt(createHash("sha256").update(uid).digest("hex").slice(0, 8), 16) % 100;
  if (!pilotUserIds.includes(uid) && (!enabled || bucket >= percent)) {
    throw new HttpsError("failed-precondition", "MindAid cloud support is not enabled for this account yet.");
  }
  return {
    personalizationEnabled: preferenceData.personalizationEnabled === true,
    conversationId: String(preferenceData.conversationId ?? ""),
  };
}

async function derivedContext(uid: string): Promise<Record<string, unknown>> {
  const [moods, assessments, user] = await Promise.all([
    db.collection("moods").where("userId", "==", uid).orderBy("createdAt", "desc").limit(7).get(),
    db.collection("assessments").where("userId", "==", uid).orderBy("createdAt", "desc").limit(1).get(),
    db.collection("users").doc(uid).get(),
  ]);
  const levels = moods.docs.map((doc) => Number(doc.data().level)).filter(Number.isFinite);
  const assessment = assessments.docs[0]?.data() ?? {};
  const userData = user.data() ?? {};
  const recentAverage = levels.length ? levels.reduce((sum, item) => sum + item, 0) / levels.length : null;
  let moodTrend = "unknown";
  if (levels.length >= 4) {
    const recent = levels.slice(0, 3).reduce((sum, item) => sum + item, 0) / Math.min(3, levels.length);
    const olderValues = levels.slice(3, 6);
    const older = olderValues.reduce((sum, item) => sum + item, 0) / olderValues.length;
    moodTrend = recent - older >= .6 ? "improving" : recent - older <= -.6 ? "declining" : "steady";
  }
  const concerns = Array.isArray(assessment.mainConcernAreas) ? assessment.mainConcernAreas.map(String).slice(0, 3) : [];
  return {
    moodTrend,
    recentMoodAverage: recentAverage == null ? null : Number(recentAverage.toFixed(1)),
    latestMoodLevel: levels[0] ?? null,
    assessmentLevel: String(assessment.status ?? assessment.overallLevel ?? ""),
    assessmentScore: Number(assessment.overallScore ?? assessment.concernScore ?? 0) || null,
    concernCategories: concerns,
    currentStreak: Number(userData.dayStreak ?? 0),
    lastCheckInAt: moods.docs[0]?.data().createdAt instanceof Timestamp ? moods.docs[0].data().createdAt.toDate().toISOString() : null,
  };
}

function extractDialogflowResponse(result: protos.google.cloud.dialogflow.cx.v3.IDetectIntentResponse): {
  text: string; intent: string; confidence: number; suggestions: string[]; actions: MindAidAction[];
} {
  const query = result.queryResult;
  const texts: string[] = [];
  let payload: Record<string, unknown> = {};
  for (const message of query?.responseMessages ?? []) {
    texts.push(...(message.text?.text ?? []).map(String));
    if (message.payload) payload = {...payload, ...fromStruct(message.payload)};
  }
  const rawActions = Array.isArray(payload.actions) ? payload.actions : [];
  const actions = rawActions.flatMap((item): MindAidAction[] => {
    if (!item || typeof item !== "object") return [];
    const data = item as Record<string, unknown>;
    const type = String(data.type ?? "");
    if (!allowedActions.has(type)) return [];
    const rawPayload = data.payload;
    const payload = rawPayload && typeof rawPayload === "object" && !Array.isArray(rawPayload)
      ? rawPayload as Record<string, unknown>
      : undefined;
    return [{type, label: String(data.label ?? "Open"), payload}];
  });
  return {
    text: texts.join("\n").trim().slice(0, 1200),
    intent: String(query?.match?.intent?.displayName ?? "general_support"),
    confidence: Number(query?.match?.confidence ?? 0),
    suggestions: (Array.isArray(payload.suggestions) ? payload.suggestions : []).map(String).slice(0, 5),
    actions,
  };
}

async function persistTurn(uid: string, requestId: string, conversationId: string, userText: string, response: MindAidResponse, latencyMs: number): Promise<void> {
  const userMessage = db.collection("mind_aid_messages").doc(`${uid}_${requestId}_user`);
  const assistantMessage = db.collection("mind_aid_messages").doc(response.messageId);
  const marker = db.collection("_mind_aid_events").doc(`${uid}_${requestId}`);
  const day = db.collection("mind_aid_analytics_daily").doc(manilaDateKey(new Date()));
  await db.runTransaction(async (transaction) => {
    if ((await transaction.get(marker)).exists) return;
    transaction.create(userMessage, {
      userId: uid, id: userMessage.id, requestId, conversationId, sender: "user", text: userText,
      status: "sent", createdAt: FieldValue.serverTimestamp(),
    });
    transaction.create(assistantMessage, {
      userId: uid, id: assistantMessage.id, requestId, conversationId, sender: "assistant", text: response.text,
      status: response.requiresEscalation ? "urgent" : "sent", safetyLevel: response.safetyLevel,
      primaryIntent: response.intent, requiresEscalation: response.requiresEscalation,
      source: response.source, confidence: response.confidence, fallbackReason: response.fallbackReason,
      effectiveConversationMode: response.effectiveConversationMode,
      ...(response.model ? {model: response.model} : {}),
      actions: response.actions, createdAt: FieldValue.serverTimestamp(),
    });
    transaction.set(day, {
      dateKey: manilaDateKey(new Date()), turnCount: FieldValue.increment(1),
      [`intentCounts.${safeMetricKey(response.intent)}`]: FieldValue.increment(1),
      [`sourceCounts.${safeMetricKey(response.source)}`]: FieldValue.increment(1),
      [`safetyCounts.${safeMetricKey(response.safetyLevel)}`]: FieldValue.increment(1),
      fallbackCount: FieldValue.increment(response.fallbackReason ? 1 : 0),
      latencyTotalMs: FieldValue.increment(latencyMs), updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.create(marker, {userId: uid, requestId, processedAt: FieldValue.serverTimestamp()});
  });
}

async function sendMindAidMessageHandler(request: CallableRequest) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  if (!request.data || typeof request.data !== "object" || Array.isArray(request.data)) {
    throw new HttpsError("invalid-argument", "A valid MindAid message is required.");
  }
  const input = request.data as Record<string, unknown>;
  const requestId = String(input.requestId ?? "").trim();
  const conversationId = String(input.conversationId ?? "").trim();
  const text = String(input.text ?? "").trim();
  const locale = String(input.locale ?? "en").trim().slice(0, 12) || "en";
  const conversationMode = effectiveConversationMode(input.conversationMode);
  if (!REQUEST_ID.test(requestId) || !CONVERSATION_ID.test(conversationId) || !text || text.length > MAX_MESSAGE_LENGTH) {
    throw new HttpsError("invalid-argument", "A valid request, conversation, and message are required.");
  }

  const existing = await db.collection("mind_aid_messages").doc(`${uid}_${requestId}_assistant`).get();
  if (existing.exists) {
    const data = existing.data()!;
    return {
      messageId: existing.id, text: data.text, intent: data.primaryIntent ?? "general_support",
      confidence: data.confidence ?? 0, safetyLevel: data.safetyLevel ?? "safeSupport",
      source: data.source ?? "dialogflow", suggestions: [], actions: data.actions ?? [],
      requiresEscalation: data.requiresEscalation === true, fallbackReason: data.fallbackReason ?? "",
      effectiveConversationMode: conversationMode,
      model: data.model === "gemini-3.8-flash" ? data.model : undefined,
    } satisfies MindAidResponse;
  }

  const access = await requireConsentAndRollout(uid);
  if (access.conversationId !== conversationId) {
    throw new HttpsError("invalid-argument", "The conversation is no longer active.");
  }
  const personalizationEnabled = access.personalizationEnabled;
  // Raw live turns are optional personalization data. The client gate is not
  // sufficient: callers cannot cause this server to use them without consent.
  const recentTurns = eligibleRecentTurns(personalizationEnabled, input.recentTurns);
  await enforceRateLimit(uid);
  const startedAt = Date.now();
  const safetyLevel = classifyMindAidSafety(text);
  const explicitListening = input.explicitListening === true;
  const supportContacts = await loadSupportContacts();
  let response: MindAidResponse;
  if (safetyLevel === "highDistress" || safetyLevel === "crisisOrImmediateRisk") {
    let emergency: {alertId: string; notified: boolean} | null = null;
    if (safetyLevel === "crisisOrImmediateRisk") {
      try {
        emergency = await createOrUpdateMindAidEmergencyAlert({
          userId: uid,
          conversationId,
          triggerMessageId: `${uid}_${requestId}_user`,
        });
      } catch (_) {
        // Keep the user in controlled safety support; never fall through to
        // Gemini and never claim that PACC received an alert.
      }
    }
    const controlled = safetyResponse(safetyLevel, supportContacts, emergency?.notified === true);
    response = {
      messageId: `${uid}_${requestId}_assistant`, text: controlled.text, intent: "crisis_support",
      confidence: 1, safetyLevel, source: "controlled_safety", suggestions: [], actions: controlled.actions,
      requiresEscalation: true, fallbackReason: "safety_intercept",
      effectiveConversationMode: "supportive",
    };
  } else {
    const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "";
    const configuredProvider = aiProvider();
    const rawProvider = String(process.env.MINDAID_AI_PROVIDER ?? "").trim().toLowerCase();
    const providerConfigured = rawProvider === "dialogflow" || rawProvider === "gemini" || rawProvider === "local";
    const functionRevision = String(process.env.K_REVISION ?? "").slice(0, 120);
    logger.info("mindaid_provider_route", {
      projectId, configuredProvider, attemptedProvider: configuredProvider,
      functionRevision: functionRevision || undefined,
    });
    let fallbackReason = providerConfigured ? "" : "provider_not_configured";
    const geminiAttempt = await attemptGemini(projectId, configuredProvider, async () => {
      const gemini = await new GeminiMindAidProvider(projectId).generate({
          message: text, conversationMode, explicitListening, recentTurns,
      });
      if (!isSafeMindAidOutput(gemini.text)) throw new Error("gemini_unsafe_response");
      return gemini;
    });
    if (geminiAttempt.response) {
      logger.info("mindaid_gemini_success", {
        projectId, provider: "gemini", model: GEMINI_MINDAID_MODEL,
        functionRevision: functionRevision || undefined,
      });
      const gemini = geminiAttempt.response;
      response = {
        messageId: `${uid}_${requestId}_assistant`, text: gemini.text.slice(0, 1200), intent: "general_support",
        confidence: 1, safetyLevel, source: "gemini", model: gemini.model, suggestions: [], actions: [],
        requiresEscalation: false, fallbackReason: "", effectiveConversationMode: conversationMode,
      };
    } else if (geminiAttempt.attempted) {
      fallbackReason = geminiAttempt.fallbackReason;
      logger.error("mindaid_gemini_failed", {
        projectId, provider: configuredProvider, model: GEMINI_MINDAID_MODEL,
        errorCode: geminiAttempt.error?.code ?? fallbackReason,
        errorMessage: geminiAttempt.error?.message ?? fallbackReason,
        functionRevision: functionRevision || undefined,
      });
    }
    if (!response!) {
      if (configuredProvider === "local") throw new HttpsError("unavailable", "Local MindAid provider requested.");
    const agentId = process.env.DIALOGFLOW_CX_AGENT_ID ?? "";
    const location = process.env.DIALOGFLOW_CX_LOCATION ?? REGION;
    if (!projectId || !agentId) throw new HttpsError("failed-precondition", "Dialogflow CX is not configured.");
    const sessionId = dialogflowSessionId(uid, conversationId, input.sessionInstanceId, requestId);
    // Load the Dialogflow client only when Mind Aid is invoked. Keeping this
    // SDK out of module initialization prevents Firebase's deployment
    // discovery process from timing out while loading all callable exports.
    const {SessionsClient} = await import("@google-cloud/dialogflow-cx");
    const client = new SessionsClient({apiEndpoint: `${location}-dialogflow.googleapis.com`});
    const session = client.projectLocationAgentSessionPath(projectId, location, agentId, sessionId);
    const asksForWellness = /\b(mood|assessment|score|result|progress|trend)\b/i.test(text);
    const context = personalizationEnabled && asksForWellness
      ? await derivedContext(uid)
      : {};
    const allowedLaunchContexts = new Set(["direct", "home", "mood", "journal", "assessment", "insights", "breathing", "counseling", "appointments"]);
    const requestedLaunchContext = String(input.launchContext ?? "direct");
    const launchContext = allowedLaunchContexts.has(requestedLaunchContext) ? requestedLaunchContext : "direct";
    const [detected] = await client.detectIntent({
      session,
      // CX receives a trusted, server-derived mode event. The original message
      // is intentionally not forwarded as a CX query: the companion policy has
      // already selected its behavioral route, while PACC and safety retain
      // their independent authorities in this Function.
      queryInput: {
        event: {event: dialogflowModeEvent(conversationMode)},
        languageCode: locale.startsWith("fil") ? "en" : "en",
      },
      queryParams: {
        parameters: toStruct({
          ...context,
          launchContext,
          supportContacts,
          conversationMode,
          explicitListening,
          wellnessReferenceAllowed: asksForWellness,
        }),
      },
    });
    const parsed = extractDialogflowResponse(detected);
    if (!isSafeMindAidOutput(parsed.text)) throw new HttpsError("internal", "Dialogflow returned an unusable response.");
    response = {
      messageId: `${uid}_${requestId}_assistant`, text: parsed.text, intent: parsed.intent,
      confidence: parsed.confidence, safetyLevel, source: "dialogflow", suggestions: parsed.suggestions,
      actions: parsed.actions, requiresEscalation: false, fallbackReason,
      effectiveConversationMode: conversationMode,
    };
    }
  }
  await persistTurn(uid, requestId, conversationId, text, response, Date.now() - startedAt);
  return response;
}

export const sendMindAidMessage = onCall({
  region: REGION,
  timeoutSeconds: 15,
  memory: "256MiB",
  enforceAppCheck: true,
}, sendMindAidMessageHandler);
export const sendMindAidMessageDev = onCall({
  region: REGION,
  timeoutSeconds: 15,
  memory: "256MiB",
  enforceAppCheck: false,
}, sendMindAidMessageHandler);

export const aggregateMindAidFeedback = onDocumentWritten(
  {region: REGION, document: "mind_aid_feedback/{feedbackId}", retry: true},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const createdAt = after?.createdAt instanceof Timestamp ? after.createdAt : before?.createdAt;
    const dateKey = manilaDateKey(createdAt instanceof Timestamp ? createdAt.toDate() : new Date());
    const helpfulDelta = Number(after?.helpful === true) - Number(before?.helpful === true);
    const unhelpfulDelta = Number(after?.helpful === false) - Number(before?.helpful === false);
    if (!helpfulDelta && !unhelpfulDelta) return;
    const marker = db.collection("_mind_aid_events").doc(`feedback_${event.id}`);
    const day = db.collection("mind_aid_analytics_daily").doc(dateKey);
    await db.runTransaction(async (transaction) => {
      if ((await transaction.get(marker)).exists) return;
      transaction.set(day, {
        dateKey,
        helpfulCount: FieldValue.increment(helpfulDelta),
        unhelpfulCount: FieldValue.increment(unhelpfulDelta),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.create(marker, {processedAt: FieldValue.serverTimestamp()});
    });
  },
);
