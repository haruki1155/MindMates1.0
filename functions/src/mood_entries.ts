import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {defineString} from "firebase-functions/params";

if (!getApps().length) initializeApp();

const db = getFirestore();
const moodEntries = db.collection("moodEntries");
const REQUEST_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EXPRESSION_MODEL_VERSION = "justinshenk_fer_tflite_v1";
// This deployment parameter is intentionally empty by default. Only a
// staging deployer may set it, and callable clients cannot override it.
const moodV2StagingPilotUids = defineString("MOOD_V2_STAGING_PILOT_UIDS", {default: ""});
const ALLOWED_FIELDS = new Set([
  "level",
  "label",
  "note",
  "entryMethod",
  "expressionAssistUsed",
  "expressionSuggestionAccepted",
  "expressionModelVersion",
  "clientRequestId",
]);

type MoodEntryInput = {
  level: number;
  label: string;
  note: string;
  entryMethod: "manual" | "expression_assisted";
  expressionAssistUsed: boolean;
  expressionSuggestionAccepted: boolean;
  expressionModelVersion: string | null;
  clientRequestId: string;
};

export type MoodV2RolloutGate = {
  projectId: string;
  pilotUserIds: ReadonlySet<string>;
};

function currentProjectId(): string {
  return (process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "").trim();
}

export function moodV2RolloutGate(): MoodV2RolloutGate {
  return {
    projectId: currentProjectId(),
    pilotUserIds: new Set(
      moodV2StagingPilotUids.value().split(",").map((value) => value.trim()).filter(Boolean),
    ),
  };
}

export function requireMoodV2StagingPilot(uid: string, gate: MoodV2RolloutGate = moodV2RolloutGate()): void {
  if (gate.projectId !== "mindmate-staging" || !gate.pilotUserIds.has(uid)) {
    throw new HttpsError("permission-denied", "Mood V2 is not enabled for this account.");
  }
}

function requireUid(request: {auth?: {uid?: string}}): string {
  const uid = request.auth?.uid?.trim();
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  return uid;
}

function objectData(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "A valid mood entry is required.");
  }
  return value as Record<string, unknown>;
}

function boundedText(value: unknown, max: number, label: string): string {
  if (value == null) return "";
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${label} must be text.`);
  }
  const text = value.trim();
  if (text.length > max) {
    throw new HttpsError("invalid-argument", `${label} is too long.`);
  }
  return text;
}

/** Parses only client-controlled canonical inputs; timestamps and user IDs are
 * deliberately absent so they cannot affect the trusted event contract. */
export function parseMoodEntryInput(raw: unknown): MoodEntryInput {
  const data = objectData(raw);
  for (const key of Object.keys(data)) {
    if (!ALLOWED_FIELDS.has(key)) {
      throw new HttpsError("invalid-argument", "Unsupported mood entry field.");
    }
  }
  if (typeof data.level !== "number" || !Number.isInteger(data.level) || data.level < 1 || data.level > 5) {
    throw new HttpsError("invalid-argument", "Mood level must be an integer from 1 to 5.");
  }
  if (typeof data.clientRequestId !== "string" || !REQUEST_ID_PATTERN.test(data.clientRequestId)) {
    throw new HttpsError("invalid-argument", "A valid request ID is required.");
  }
  const entryMethod = data.entryMethod ?? "manual";
  if (entryMethod !== "manual" && entryMethod !== "expression_assisted") {
    throw new HttpsError("invalid-argument", "Unsupported mood entry method.");
  }
  const expressionAssistUsed = data.expressionAssistUsed ?? false;
  const expressionSuggestionAccepted = data.expressionSuggestionAccepted ?? false;
  if (typeof expressionAssistUsed !== "boolean" || typeof expressionSuggestionAccepted !== "boolean") {
    throw new HttpsError("invalid-argument", "Expression metadata must be boolean.");
  }
  const expressionModelVersion = data.expressionModelVersion == null ? null : data.expressionModelVersion;
  if (expressionModelVersion != null && expressionModelVersion !== EXPRESSION_MODEL_VERSION) {
    throw new HttpsError("invalid-argument", "Unsupported expression model version.");
  }
  if (entryMethod === "manual" &&
      (expressionAssistUsed || expressionSuggestionAccepted || expressionModelVersion != null)) {
    throw new HttpsError("invalid-argument", "Manual mood entries cannot include expression metadata.");
  }
  if (entryMethod === "expression_assisted" && !expressionAssistUsed) {
    throw new HttpsError("invalid-argument", "Expression-assisted entries require expression metadata.");
  }
  return {
    level: data.level,
    label: boundedText(data.label, 40, "Mood label"),
    note: boundedText(data.note, 300, "Mood note"),
    entryMethod,
    expressionAssistUsed,
    expressionSuggestionAccepted,
    expressionModelVersion,
    clientRequestId: data.clientRequestId,
  };
}

export function manilaDateKey(instant: Date): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(instant);
  const part = (type: string) => parts.find((item) => item.type === type)?.value;
  return `${part("year")}-${part("month")}-${part("day")}`;
}

export function moodEntryDocumentId(uid: string, clientRequestId: string): string {
  return `mood_v2_${uid}_${clientRequestId}`;
}

export function canonicalMoodEntryPayload(input: MoodEntryInput): Record<string, unknown> {
  return {
    level: input.level,
    label: input.label,
    note: input.note,
    entryMethod: input.entryMethod,
    expressionAssistUsed: input.expressionAssistUsed,
    expressionSuggestionAccepted: input.expressionSuggestionAccepted,
    expressionModelVersion: input.expressionModelVersion,
    clientRequestId: input.clientRequestId,
  };
}

function matchingCanonicalPayload(existing: FirebaseFirestore.DocumentData, input: MoodEntryInput): boolean {
  const expected = canonicalMoodEntryPayload(input);
  return Object.entries(expected).every(([key, value]) => (existing[key] ?? null) === value);
}

async function requireEligibleAppUser(uid: string): Promise<void> {
  const profile = await db.collection("users").doc(uid).get();
  const data = profile.data();
  const role = String(data?.populationRole ?? data?.declaredRole ?? data?.role ?? "");
  const accountStatus = data?.accountStatus == null ? "active" : String(data.accountStatus);
  if (!profile.exists || data?.accessRole !== "appUser" || data?.staffAccountStatus != null ||
      !["student", "teaching", "nonTeaching"].includes(role) || accountStatus !== "active") {
    throw new HttpsError("failed-precondition", "An active app-user profile is required.");
  }
}

function response(document: FirebaseFirestore.DocumentSnapshot): Record<string, unknown> {
  const data = document.data() ?? {};
  const occurredAt = data.occurredAt instanceof Timestamp ? data.occurredAt.toDate().toISOString() : null;
  return {
    entryId: document.id,
    userId: data.userId,
    level: data.level,
    label: data.label,
    note: data.note,
    entryMethod: data.entryMethod,
    expressionAssistUsed: data.expressionAssistUsed,
    expressionSuggestionAccepted: data.expressionSuggestionAccepted,
    expressionModelVersion: data.expressionModelVersion ?? null,
    clientRequestId: data.clientRequestId,
    dateKey: data.dateKey,
    timezone: data.timezone,
    occurredAt,
    calculationAuthority: "server",
  };
}

/**
 * Persists a previously validated entry. `trustedInstant` exists for emulator
 * tests only; callers of the public callable always use Timestamp.now().
 */
export async function createMoodEntryForUser(
  uid: string,
  input: MoodEntryInput,
  trustedInstant: Timestamp = Timestamp.now(),
  gate: MoodV2RolloutGate = moodV2RolloutGate(),
): Promise<Record<string, unknown>> {
  await requireEligibleAppUser(uid);
  requireMoodV2StagingPilot(uid, gate);
  const entryRef = moodEntries.doc(moodEntryDocumentId(uid, input.clientRequestId));
  // One trusted instant is retained on first creation. Retries never recompute
  // the timestamp or Manila day, even if they arrive after midnight.
  const dateKey = manilaDateKey(trustedInstant.toDate());

  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(entryRef);
    if (existing.exists) {
      if (!matchingCanonicalPayload(existing.data() ?? {}, input)) {
        throw new HttpsError("already-exists", "This request ID was already used for a different mood entry.");
      }
      return;
    }
    transaction.create(entryRef, {
      userId: uid,
      ...canonicalMoodEntryPayload(input),
      dateKey,
      timezone: "Asia/Manila",
      occurredAt: trustedInstant,
      createdAt: FieldValue.serverTimestamp(),
      calculationAuthority: "server",
      verificationStatus: "verified",
    });
  });
  return response(await entryRef.get());
}

export async function createMoodEntryHandler(request: CallableRequest): Promise<Record<string, unknown>> {
  const uid = requireUid(request);
  return createMoodEntryForUser(uid, parseMoodEntryInput(request.data));
}

export const createMoodEntry = onCall({enforceAppCheck: true}, createMoodEntryHandler);
export const createMoodEntryDev = onCall({enforceAppCheck: false}, createMoodEntryHandler);
