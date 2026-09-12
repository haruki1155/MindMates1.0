import {createHash} from "node:crypto";

import type {protos} from "@google-cloud/dialogflow-cx";
import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";

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
  source: "dialogflow" | "controlled_safety";
  suggestions: string[];
  actions: MindAidAction[];
  requiresEscalation: boolean;
  fallbackReason: string;
}

const crisisPhrases = [
  "kill myself", "end my life", "end it all", "take my life",
  "no reason to live", "cant go on", "cannot go on", "want to disappear",
  "unalive myself", "suicide", "self harm", "hurt myself", "cut myself",
  "i want to die", "do not want to live", "ayoko nang mabuhay",
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
  return value.toLowerCase().replace(/[^a-z0-9\s]/g, " ").replace(/\s+/g, " ").trim();
}

export function classifyMindAidSafety(text: string): SafetyLevel {
  const value = normalize(text);
  if (!value) return "needsClarification";
  if (crisisPhrases.some((phrase) => value.includes(phrase)) || /(^|\s)kms(\s|$)/.test(value)) return "crisisOrImmediateRisk";
  if (highDistressPhrases.some((phrase) => value.includes(phrase))) return "highDistress";
  return "safeSupport";
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
}

async function loadSupportContacts(): Promise<SupportContacts> {
  const data = (await db.collection("mind_aid_config").doc("support_contacts").get()).data() ?? {};
  const phone = (value: unknown): string => {
    const text = String(value ?? "").trim();
    return /^[+0-9() -]{7,24}$/.test(text) ? text : "";
  };
  return {
    paccName: String(data.paccName ?? "PACC").trim().slice(0, 80) || "PACC",
    paccPhone: phone(data.paccPhone),
    campusSecurityPhone: phone(data.campusSecurityPhone),
    emergencyLabel: String(data.emergencyLabel ?? "local emergency services").trim().slice(0, 80) || "local emergency services",
    emergencyPhone: phone(data.emergencyPhone),
  };
}

function safetyResponse(level: SafetyLevel, contacts: SupportContacts): {text: string; actions: MindAidAction[]} {
  const verified = [
    contacts.paccPhone ? `${contacts.paccName}: ${contacts.paccPhone}` : "",
    contacts.campusSecurityPhone ? `Campus security: ${contacts.campusSecurityPhone}` : "",
    contacts.emergencyPhone ? `${contacts.emergencyLabel}: ${contacts.emergencyPhone}` : "",
  ].filter(Boolean);
  const contactLine = verified.length ? `\n\nVerified contacts: ${verified.join(" • ")}` : "";
  if (level === "crisisOrImmediateRisk") {
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
    } satisfies MindAidResponse;
  }

  const access = await requireConsentAndRollout(uid);
  if (access.conversationId !== conversationId) {
    throw new HttpsError("invalid-argument", "The conversation is no longer active.");
  }
  const personalizationEnabled = access.personalizationEnabled;
  await enforceRateLimit(uid);
  const startedAt = Date.now();
  const safetyLevel = classifyMindAidSafety(text);
  const supportContacts = await loadSupportContacts();
  let response: MindAidResponse;
  if (safetyLevel === "highDistress" || safetyLevel === "crisisOrImmediateRisk") {
    const controlled = safetyResponse(safetyLevel, supportContacts);
    response = {
      messageId: `${uid}_${requestId}_assistant`, text: controlled.text, intent: "crisis_support",
      confidence: 1, safetyLevel, source: "controlled_safety", suggestions: [], actions: controlled.actions,
      requiresEscalation: true, fallbackReason: "safety_intercept",
    };
  } else {
    const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "";
    const agentId = process.env.DIALOGFLOW_CX_AGENT_ID ?? "";
    const location = process.env.DIALOGFLOW_CX_LOCATION ?? REGION;
    if (!projectId || !agentId) throw new HttpsError("failed-precondition", "Dialogflow CX is not configured.");
    const sessionId = createHash("sha256").update(`${uid}:${conversationId}`).digest("hex").slice(0, 36);
    // Load the Dialogflow client only when Mind Aid is invoked. Keeping this
    // SDK out of module initialization prevents Firebase's deployment
    // discovery process from timing out while loading all callable exports.
    const {SessionsClient} = await import("@google-cloud/dialogflow-cx");
    const client = new SessionsClient({apiEndpoint: `${location}-dialogflow.googleapis.com`});
    const session = client.projectLocationAgentSessionPath(projectId, location, agentId, sessionId);
    const context = personalizationEnabled ? await derivedContext(uid) : {};
    const allowedLaunchContexts = new Set(["direct", "home", "mood", "journal", "assessment", "insights", "breathing", "counseling", "appointments"]);
    const requestedLaunchContext = String(input.launchContext ?? "direct");
    const launchContext = allowedLaunchContexts.has(requestedLaunchContext) ? requestedLaunchContext : "direct";
    const [detected] = await client.detectIntent({
      session,
      queryInput: {text: {text}, languageCode: locale.startsWith("fil") ? "en" : "en"},
      queryParams: {parameters: toStruct({...context, launchContext, supportContacts})},
    });
    const parsed = extractDialogflowResponse(detected);
    if (!isSafeMindAidOutput(parsed.text)) throw new HttpsError("internal", "Dialogflow returned an unusable response.");
    response = {
      messageId: `${uid}_${requestId}_assistant`, text: parsed.text, intent: parsed.intent,
      confidence: parsed.confidence, safetyLevel, source: "dialogflow", suggestions: parsed.suggestions,
      actions: parsed.actions, requiresEscalation: false, fallbackReason: "",
    };
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
