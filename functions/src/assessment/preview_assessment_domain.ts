import {getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {AssessmentValidationError} from "./calculator";
import {AssessmentRole, roleFromPopulation} from "./catalog";
import {
  NON_TEACHING_V4_INSTRUMENT_VERSION,
  TEACHING_V4_INSTRUMENT_VERSION,
} from "./workplace_v4_catalog";
import {STUDENT_V4_INSTRUMENT_VERSION} from "./student_v4_catalog";
import {calculateV4Domain, V4DomainAnswer, V4InstrumentVersion} from "./v4_domain_calculator";

const POLICY_VERSION = "assessment_intervention_v1";
type PreviewDependencies = {loadProfile: (uid: string) => Promise<Record<string, unknown>>};

function requestData(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new HttpsError("invalid-argument", "A valid request object is required.");
  return value as Record<string, unknown>;
}

function uidFrom(request: {auth?: {uid?: string}}): string {
  const uid = request.auth?.uid?.trim();
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  return uid;
}

function parseAnswers(value: unknown): V4DomainAnswer[] {
  if (!Array.isArray(value)) throw new HttpsError("invalid-argument", "Domain responses are required.");
  return value.map((value) => {
    const answer = requestData(value);
    if (typeof answer.itemId !== "string" || answer.itemId.length > 100 || typeof answer.skipped !== "boolean") {
      throw new HttpsError("invalid-argument", "Invalid V4 domain response.");
    }
    if (answer.skipped) {
      if (answer.responseCode !== undefined || answer.responseValue !== undefined) throw new HttpsError("invalid-argument", "Skipped V4 items must not include a response.");
      return {itemId: answer.itemId, skipped: true};
    }
    if (typeof answer.responseCode !== "string" || typeof answer.responseValue !== "number" || !Number.isInteger(answer.responseValue)) {
      throw new HttpsError("invalid-argument", "V4 responses require a code and matching value.");
    }
    return {itemId: answer.itemId, responseCode: answer.responseCode as V4DomainAnswer["responseCode"], responseValue: answer.responseValue, skipped: false};
  });
}

function profileRole(profile: Record<string, unknown>): AssessmentRole {
  const role = roleFromPopulation(profile.populationRole) ?? roleFromPopulation(profile.declaredRole) ?? roleFromPopulation(profile.role);
  if (!role) throw new HttpsError("failed-precondition", "Your profile does not have a valid assessment role.");
  return role;
}

function expectedRole(instrumentVersion: V4InstrumentVersion): AssessmentRole {
  if (instrumentVersion === STUDENT_V4_INSTRUMENT_VERSION) return "student";
  if (instrumentVersion === TEACHING_V4_INSTRUMENT_VERSION) return "teaching";
  return "nonTeaching";
}

export async function previewAssessmentDomainHandler(
  request: CallableRequest,
  dependencies: PreviewDependencies = {loadProfile: async (uid) => (await getFirestore().collection("users").doc(uid).get()).data() ?? {}},
): Promise<Record<string, unknown>> {
  try {
    const uid = uidFrom(request);
    const data = requestData(request.data);
    const instrumentVersion = data.instrumentVersion;
    const domainId = data.domainId;
    if (
      instrumentVersion !== STUDENT_V4_INSTRUMENT_VERSION &&
      instrumentVersion !== TEACHING_V4_INSTRUMENT_VERSION &&
      instrumentVersion !== NON_TEACHING_V4_INSTRUMENT_VERSION
    ) throw new HttpsError("invalid-argument", "Unsupported assessment instrument version.");
    if (typeof domainId !== "string" || domainId.length > 100) throw new HttpsError("invalid-argument", "A valid domain ID is required.");
    if (profileRole(await dependencies.loadProfile(uid)) !== expectedRole(instrumentVersion)) {
      throw new HttpsError("failed-precondition", "This V4 assessment instrument is not available for your profile role.");
    }
    const domain = calculateV4Domain(instrumentVersion, domainId, parseAnswers(data.answers));
    return {...domain, interventionEligible: domain.status === "supportMayHelp", policyVersion: POLICY_VERSION};
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error instanceof AssessmentValidationError) throw new HttpsError("invalid-argument", error.message);
    console.error("assessment_domain_preview_failed", error);
    throw new HttpsError("internal", "The assessment domain could not be previewed.");
  }
}
