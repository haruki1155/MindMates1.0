import {createHash, randomUUID} from "node:crypto";
import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {
  AssessmentRole,
  roleFromPopulation,
} from "./catalog";
import {
  calculateFull,
  calculateQuick,
  FullAnswer,
  QuickAnswer,
  validateFullAnswers,
  validateQuickAnswers,
} from "./calculator";
import {
  calculateStudentV4,
  StudentV4Answer,
  validateStudentV4Answers,
} from "./student_v4_calculator";
import {STUDENT_V4_INSTRUMENT_VERSION} from "./student_v4_catalog";
import {toHttpsError} from "./errors";
import {quickProfileRoleDecision, submissionHashesMatch} from "./submission_policy";

if (!getApps().length) initializeApp();

const db = getFirestore();
const assessments = db.collection("assessments");
const limits = db.collection("assessment_limits");
const MAX_SUBMISSION_ID_LENGTH = 100;

function uidFrom(request: {auth?: {uid?: string}}): string {
  const uid = request.auth?.uid?.trim();
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  return uid;
}

function submissionIdFrom(value: unknown): string {
  if (typeof value !== "string" || value.length < 8 || value.length > MAX_SUBMISSION_ID_LENGTH || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new HttpsError("invalid-argument", "A valid submission ID is required.");
  }
  return value;
}

function objectData(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new HttpsError("invalid-argument", "A valid request object is required.");
  return value as Record<string, unknown>;
}

function responsePayload(document: FirebaseFirestore.DocumentSnapshot): Record<string, unknown> {
  const data = document.data() ?? {};
  return {assessmentId: document.id, ...data};
}

function hashSubmission(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function assessmentRequestSummary(
  functionName: string,
  correlationId: string,
  submissionId: string,
  answers: FullAnswer[],
  role?: AssessmentRole,
): void {
  const ids = answers.map((answer) => answer.questionId);
  console.info("assessment_submission_received", {
    functionName,
    correlationId,
    submissionId,
    role: role ?? "unknown",
    answerCount: answers.length,
    firstQuestionId: ids[0] ?? "",
    lastQuestionId: ids[ids.length - 1] ?? "",
  });
}

function parseQuickAnswers(value: unknown): QuickAnswer[] {
  if (!Array.isArray(value) || value.length > 20) throw new HttpsError("invalid-argument", "Quick responses are required and must be within the payload limit.");
  return value.map((item) => {
    const data = objectData(item);
    if (typeof data.questionId !== "string" || data.questionId.length > 100 || typeof data.optionId !== "string" || data.optionId.length > 100 || typeof data.value !== "number" || !Number.isFinite(data.value)) {
      throw new HttpsError("invalid-argument", "Invalid quick response.");
    }
    return {questionId: data.questionId, optionId: data.optionId, value: data.value};
  });
}

function parseFullAnswers(value: unknown): FullAnswer[] {
  if (!Array.isArray(value) || value.length > 60) throw new HttpsError("invalid-argument", "Full assessment answers are required and must be within the payload limit.");
  return value.map((item) => {
    const data = objectData(item);
    if (typeof data.questionId !== "string" || data.questionId.length > 100 || typeof data.answer !== "string" || data.answer.length > 30 || typeof data.isSkipped !== "boolean") {
      throw new HttpsError("invalid-argument", "Invalid full-assessment answer.");
    }
    return {questionId: data.questionId, answer: data.answer, isSkipped: data.isSkipped};
  });
}

function parseStudentV4Answers(value: unknown): StudentV4Answer[] {
  if (!Array.isArray(value) || value.length !== 50) throw new HttpsError("invalid-argument", "Student V4 requires 50 responses.");
  return value.map((item) => {
    const data = objectData(item);
    if (typeof data.itemId !== "string" || data.itemId.length > 100 || typeof data.skipped !== "boolean") {
      throw new HttpsError("invalid-argument", "Invalid Student V4 response.");
    }
    if (data.skipped) return {itemId: data.itemId, skipped: true};
    if (typeof data.responseCode !== "string" || typeof data.responseValue !== "number" || !Number.isInteger(data.responseValue)) {
      throw new HttpsError("invalid-argument", "Student V4 responses require a code and matching value.");
    }
    return {
      itemId: data.itemId,
      responseCode: data.responseCode as StudentV4Answer["responseCode"],
      responseValue: data.responseValue,
      skipped: false,
    };
  });
}

function profileRole(value: Record<string, unknown>): AssessmentRole {
  const role = roleFromPopulation(value.populationRole) ?? roleFromPopulation(value.declaredRole) ?? roleFromPopulation(value.role);
  if (!role) throw new HttpsError("failed-precondition", "Your profile does not have a valid assessment role.");
  return role;
}

function fullDocumentId(uid: string, submissionId: string): string {
  return `full_${uid}_${submissionId}`;
}

function legacyRole(role: AssessmentRole): string {
  if (role === "teaching") return "faculty";
  if (role === "nonTeaching") return "staff";
  return "student";
}

async function submitQuickAssessmentHandler(request: CallableRequest) {
  const correlationId = randomUUID();
  const uid = uidFrom(request);
  const data = objectData(request.data);
  const submissionId = submissionIdFrom(data.submissionId);
  const role = roleFromPopulation(data.role);
  if (!role) throw new HttpsError("invalid-argument", "A valid assessment role is required.");
  if (typeof data.name !== "string" || data.name.trim().length < 1 || data.name.trim().length > 100) throw new HttpsError("invalid-argument", "A valid name is required.");
  const answers = parseQuickAnswers(data.responses);
  try {
    validateQuickAnswers(answers);
    const result = calculateQuick(role, data.name, answers);
    const documentId = `quick_${uid}`;
    const ref = assessments.doc(documentId);
    const submissionHash = hashSubmission({role, answers});
    const payload = {
      userId: uid,
      type: "quick",
      role: role,
      populationRole: role,
      ...result,
      responses: result.responses,
      calculationAuthority: "server",
      verificationStatus: "verified",
      algorithmVersion: result.algorithmVersion,
      questionSetVersion: result.questionSetVersion,
      serverAlgorithmVersion: result.algorithmVersion,
      serverQuestionSetVersion: result.questionSetVersion,
      submissionId,
      submissionHash,
      createdAt: FieldValue.serverTimestamp(),
      submittedAt: FieldValue.serverTimestamp(),
      verifiedAt: FieldValue.serverTimestamp(),
    };
    await db.runTransaction(async (transaction) => {
      const profileRef = db.collection("users").doc(uid);
      const profile = await transaction.get(profileRef);
      const current = await transaction.get(ref);
      if (!profile.exists) {
        throw new HttpsError("failed-precondition", "Complete your user profile before submitting an assessment.");
      }
      const roleDecision = quickProfileRoleDecision(profile.data() ?? {}, role);
      if (roleDecision === "mismatch") {
        throw new HttpsError("failed-precondition", "The selected assessment role does not match your profile.");
      }
      if (current.exists && !submissionHashesMatch(current.data()?.submissionHash, submissionHash)) {
        throw new HttpsError("already-exists", "A different quick assessment is already stored for this account.");
      }
      if (!current.exists) transaction.create(ref, payload);
      transaction.set(profileRef, {
        ...(roleDecision === "backfill" ? {
          role: legacyRole(role),
          populationRole: role,
          declaredRole: role,
        } : {}),
        quickAssessmentCompleted: true,
        quickAssessmentCompletedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
    return {...responsePayload(await ref.get()), correlationId};
  } catch (error) {
    console.error("quick_assessment_failed", {correlationId, uid, error});
    return toHttpsError(error);
  }
}

export const submitQuickAssessment = onCall({enforceAppCheck: true}, submitQuickAssessmentHandler);
export const submitQuickAssessmentDev = onCall({enforceAppCheck: false}, submitQuickAssessmentHandler);

async function submitFullAssessmentHandler(request: CallableRequest) {
  const correlationId = randomUUID();
  const uid = uidFrom(request);
  const data = objectData(request.data);
  const submissionId = submissionIdFrom(data.submissionId);
  const requestedInstrument = data.instrumentVersion?.toString().trim() ?? "";
  const isStudentV4 = requestedInstrument === STUDENT_V4_INSTRUMENT_VERSION;
  if (requestedInstrument && !isStudentV4) throw new HttpsError("invalid-argument", "Unsupported assessment instrument version.");
  const v4Answers = isStudentV4 ? parseStudentV4Answers(data.answers) : null;
  const legacyAnswers = isStudentV4 ? null : parseFullAnswers(data.answers);
  const answers = v4Answers ?? legacyAnswers!;
  if (isStudentV4) {
    console.info("assessment_submission_received", {
      functionName: "submitFullAssessment",
      correlationId,
      submissionId,
      instrumentVersion: requestedInstrument,
      answerCount: answers.length,
    });
  } else {
    assessmentRequestSummary("submitFullAssessment", correlationId, submissionId, legacyAnswers!);
  }
  const ref = assessments.doc(fullDocumentId(uid, submissionId));
  const existing = await ref.get();
  if (existing.exists) return responsePayload(existing);
  const profile = await db.collection("users").doc(uid).get();
  const role = profileRole(profile.data() ?? {});
  if (isStudentV4) {
    if (role !== "student") throw new HttpsError("failed-precondition", "Student Well-Being V4 is available only to student profiles.");
  } else {
    assessmentRequestSummary("submitFullAssessment", correlationId, submissionId, legacyAnswers!, role);
  }
  try {
    if (isStudentV4) validateStudentV4Answers(v4Answers!);
    else validateFullAnswers(role, legacyAnswers!);
    const result = isStudentV4 ? calculateStudentV4(v4Answers!) : calculateFull(role, legacyAnswers!);
    const limitRef = limits.doc(uid);
    const now = Date.now();
    const windowStart = now - 7 * 24 * 60 * 60 * 1000;
    const minimumInterval = 2 * 24 * 60 * 60 * 1000;
    const payload = {
      userId: uid,
      type: role === "student" ? "student" : role === "teaching" ? "teaching personnel" : "non-teaching personnel",
      role: role,
      populationRole: role,
      ...result,
      responses: answers.map((answer) => ({...answer})),
      calculationAuthority: "server",
      verificationStatus: "verified",
      algorithmVersion: result.algorithmVersion,
      questionSetVersion: result.questionSetVersion,
      serverAlgorithmVersion: result.algorithmVersion,
      serverQuestionSetVersion: result.questionSetVersion,
      submissionId,
      submissionHash: hashSubmission({role, instrumentVersion: requestedInstrument || undefined, answers}),
      createdAt: FieldValue.serverTimestamp(),
      submittedAt: FieldValue.serverTimestamp(),
      verifiedAt: FieldValue.serverTimestamp(),
    };
    await db.runTransaction(async (transaction) => {
      const limitSnapshot = await transaction.get(limitRef);
      const duplicate = await transaction.get(ref);
      if (duplicate.exists) return;
      const timestamps = Array.isArray(limitSnapshot.data()?.completedAt)
        ? (limitSnapshot.data()?.completedAt as unknown[]).map((value) => value instanceof Timestamp ? value.toMillis() : Number(value)).filter((value) => Number.isFinite(value) && value > windowStart)
        : [];
      const latest = timestamps.length ? Math.max(...timestamps) : 0;
      if (latest && now < latest + minimumInterval) throw new HttpsError("resource-exhausted", "The full assessment must be spaced at least two days apart.");
      if (timestamps.length >= 2) throw new HttpsError("resource-exhausted", "Only two full assessments are allowed in a rolling seven-day period.");
      transaction.create(ref, payload);
      transaction.set(limitRef, {userId: uid, completedAt: [...timestamps, now], updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    });
    return {...responsePayload(await ref.get()), correlationId};
  } catch (error) {
    console.error("full_assessment_failed", {correlationId, uid, error});
    return toHttpsError(error);
  }
}

export const submitFullAssessment = onCall({enforceAppCheck: true}, submitFullAssessmentHandler);
export const submitFullAssessmentDev = onCall({enforceAppCheck: false}, submitFullAssessmentHandler);
