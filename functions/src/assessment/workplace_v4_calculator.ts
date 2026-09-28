import {AssessmentValidationError} from "./calculator";
import {
  NON_TEACHING_V4_ALGORITHM_VERSION, NON_TEACHING_V4_CATALOG_HASH, NON_TEACHING_V4_DOMAIN_LABELS, NON_TEACHING_V4_DOMAIN_ORDER, NON_TEACHING_V4_INSTRUMENT_VERSION, NON_TEACHING_V4_ITEMS,
  TEACHING_V4_ALGORITHM_VERSION, TEACHING_V4_CATALOG_HASH, TEACHING_V4_DOMAIN_LABELS, TEACHING_V4_DOMAIN_ORDER, TEACHING_V4_INSTRUMENT_VERSION, TEACHING_V4_ITEMS, WorkplaceV4Direction, WorkplaceV4Item,
} from "./workplace_v4_catalog";

export type WorkplaceV4ResponseCode = "stronglyDisagree" | "disagree" | "agree" | "stronglyAgree";
export type WorkplaceV4Answer = {itemId: string; responseCode?: WorkplaceV4ResponseCode; responseValue?: number; skipped: boolean};
type WorkplaceV4Config = {role: "teaching" | "nonTeaching"; family: string; instrumentVersion: string; algorithmVersion: string; catalogHash: string; items: readonly WorkplaceV4Item[]; domainOrder: readonly string[]; domainLabels: Record<string, string>};

const responseValues: Record<WorkplaceV4ResponseCode, number> = {stronglyDisagree: 1, disagree: 2, agree: 3, stronglyAgree: 4};
const employeeDisclaimer = "This is a 7-day workplace well-being reflection, not a diagnosis and not an evaluation of your job performance. It is meant to support personal reflection and a confidential conversation with a qualified professional if desired.";
const round = (value: number) => Number(value.toFixed(2));
const concern = (value: number, direction: WorkplaceV4Direction) => direction === "protective" ? 100 - ((value - 1) / 3) * 100 : ((value - 1) / 3) * 100;
const statusFor = (value: number) => value <= 25 ? "supported" : value <= 50 ? "mostlySupported" : value <= 75 ? "someStrain" : "supportMayHelp";
const confidenceFor = (percent: number) => percent >= 90 ? "high" : percent >= 70 ? "usableWithCaution" : "limited";
const constructLabel = (value: string) => value.replace(/_/g, " ");

const teachingConfig: WorkplaceV4Config = {role: "teaching", family: "teaching_workplace_reflection", instrumentVersion: TEACHING_V4_INSTRUMENT_VERSION, algorithmVersion: TEACHING_V4_ALGORITHM_VERSION, catalogHash: TEACHING_V4_CATALOG_HASH, items: TEACHING_V4_ITEMS, domainOrder: TEACHING_V4_DOMAIN_ORDER, domainLabels: TEACHING_V4_DOMAIN_LABELS};
const nonTeachingConfig: WorkplaceV4Config = {role: "nonTeaching", family: "non_teaching_workplace_reflection", instrumentVersion: NON_TEACHING_V4_INSTRUMENT_VERSION, algorithmVersion: NON_TEACHING_V4_ALGORITHM_VERSION, catalogHash: NON_TEACHING_V4_CATALOG_HASH, items: NON_TEACHING_V4_ITEMS, domainOrder: NON_TEACHING_V4_DOMAIN_ORDER, domainLabels: NON_TEACHING_V4_DOMAIN_LABELS};

export function validateWorkplaceV4Answers(answers: WorkplaceV4Answer[], config: WorkplaceV4Config): void {
  if (!Array.isArray(answers) || answers.length !== config.items.length) throw new AssessmentValidationError("Workplace V4 requires all 50 item IDs exactly once.");
  const byId = new Map(answers.map((answer) => [answer.itemId, answer]));
  if (byId.size !== config.items.length) throw new AssessmentValidationError("Duplicate Workplace V4 item IDs are not allowed.");
  for (const item of config.items) {
    const answer = byId.get(item.id);
    if (!answer || typeof answer.skipped !== "boolean") throw new AssessmentValidationError("Workplace V4 answers do not match the instrument catalog.");
    if (answer.skipped) {
      if (answer.responseCode !== undefined || answer.responseValue !== undefined) throw new AssessmentValidationError("Skipped Workplace V4 items must not include a response.");
    } else if (!answer.responseCode || responseValues[answer.responseCode] !== answer.responseValue) {
      throw new AssessmentValidationError("Workplace V4 response code and value must match.");
    }
  }
}

function actionFor(config: WorkplaceV4Config, domainId: string): string {
  const teaching = config.role === "teaching";
  const actions: Record<string, string> = teaching ? {
    teachingWorkloadDemands: "Choose one teaching or administrative responsibility to clarify, reprioritize, delegate where appropriate, or schedule more realistically this week.",
    teachingSupport: "Identify one trusted colleague, department contact, or confidential support channel you could approach if needed.",
    teachingEngagementMeaning: "Reconnect with one part of your work that feels meaningful or makes good use of your strengths.", sleepRest: "Choose one small rest or wind-down routine that fits your schedule.", emotionalWellbeing: "Make space for one supportive coping or check-in practice.",
  } : {
    nonTeachingWorkloadDemands: "Choose one work responsibility to clarify, prioritize, or break into a more manageable step.",
    nonTeachingSupport: "Identify one trusted coworker, supervisor where appropriate, or confidential support channel you could approach if needed.",
    nonTeachingEngagementMeaning: "Identify one meaningful contribution or personal strength you want to use more intentionally at work.", sleepRest: "Choose one small rest or wind-down routine that fits your schedule.", emotionalWellbeing: "Make space for one supportive coping or check-in practice.",
  };
  return actions[domainId] ?? "Choose one small supportive step that feels manageable this week.";
}

function insight(item: WorkplaceV4Item, kind: "focus" | "strength", label: string): string {
  const templates: Record<string, Partial<Record<"focus" | "strength", string>>> = {
    deadline_pressure: {focus: "Deadlines may have been creating added pressure this week."}, administrative_load: {focus: "Administrative duties may have been competing with time needed for teaching."}, work_control: {strength: "You reported having some control over how you organized your work."}, speaking_up_safety: {focus: "It may not have felt easy to raise workplace concerns."}, colleague_support: {strength: "You reported being able to rely on colleagues for help."}, teaching_resources: {focus: "Access to the resources needed for teaching may be an area to review."}, work_meaning: {strength: "You reported a supportive sense of meaning in your work."}, role_self_efficacy: {focus: "Confidence in handling current professional challenges may be worth strengthening."}, professional_growth: {focus: "Opportunities for professional learning or growth may feel limited right now."}, interruptions: {focus: "Frequent interruptions may have been making it harder to complete your work."}, task_load: {focus: "Managing several work responsibilities at the same time may be creating strain."}, prioritization: {strength: "You reported being able to prioritize your work responsibilities."}, supervisor_support: {strength: "You reported being able to ask your supervisor for help when needed."}, supervisor_listening: {focus: "Feeling heard when raising work-related concerns may be an area to explore."}, team_cooperation: {strength: "You reported supportive cooperation within your team during demanding periods."}, positive_contribution: {strength: "You reported feeling that your work contributes positively to the university community."}, skill_growth: {focus: "Opportunities to learn or develop useful skills may feel limited right now."}, work_interest: {focus: "Maintaining interest in day-to-day work may be an area worth exploring."},
  };
  return templates[item.constructId]?.[kind] ?? (kind === "focus" ? `${label}: ${constructLabel(item.constructId)} may be an area to explore.` : `${label}: you reported a supportive pattern around ${constructLabel(item.constructId)}.`);
}

function summaryFor(config: WorkplaceV4Config, status: string, focusLabels: string[]): string {
  const focus = focusLabels[0] ?? "one area";
  const second = focusLabels[1] ?? focus;
  if (config.role === "teaching") {
    if (status === "generallySupported") return "Your teaching-related well-being appears generally supported. Over the past 7 days, your responses show supportive patterns across your work demands, professional environment, engagement, rest, and emotional well-being. Continue the routines, relationships, and work practices that are helping.";
    if (status === "mostlySupported") return `Your well-being appears mostly supported, with an area worth exploring. Most areas appear supportive, while ${focus} may deserve some attention. This does not indicate poor teaching performance; it reflects how your recent work experience has been affecting you.`;
    if (status === "someAreasNeedAttention") return `Some areas of your teaching-related well-being may benefit from attention. Your responses suggest strain around ${focus} and ${second}. Consider one manageable change in workload, support, or routine and use confidential support if it would be useful.`;
    if (status === "supportMayHelp") return "Support may be helpful right now. One or more areas show sustained strain in your responses from the past 7 days. Consider speaking confidentially with a qualified university support or counseling professional, particularly if these experiences are affecting your daily functioning.";
    return "More responses are needed for a complete profile. Some domains did not have enough answers for a useful reflection. You may review them later if you feel comfortable.";
  }
  if (status === "generallySupported") return "Your work-related well-being appears generally supported. Your recent responses show supportive patterns across your workload, workplace support, engagement, rest, and emotional well-being. Continue the routines and connections that are working for you.";
  if (status === "mostlySupported") return `Your well-being appears mostly supported, with an area worth exploring. Most areas appear supportive, while ${focus} may deserve some attention. The result reflects your recent experience and is not an evaluation of your job performance.`;
  if (status === "someAreasNeedAttention") return `Some areas of your work-related well-being may benefit from attention. Your responses suggest strain around ${focus} and ${second}. A manageable adjustment, a conversation with someone you trust, or confidential university support may be useful.`;
  if (status === "supportMayHelp") return "Support may be helpful right now. One or more areas show sustained strain over the past 7 days. Consider a confidential check-in with an appropriate university support or counseling professional if these experiences are affecting your day-to-day functioning.";
  return "More responses are needed for a complete profile. Some areas did not have enough responses to form a useful reflection.";
}

function domainSummaryFor(domain: {domainId: string; domainLabel: string; status: string; focusInsight: string | null; strengthInsight: string | null; suggestedAction: string}) {
  const copy: Record<string, string> = {supported: "Responses in this area were generally supportive during the past 7 days.", mostlySupported: "This area was mostly supportive, with one or more patterns worth noticing.", someStrain: "Responses suggest some strain in this area during the past 7 days.", supportMayHelp: "Responses suggest this area may currently be placing meaningful strain on well-being.", insufficientResponses: "There were not enough responses in this area to create a complete reflection."};
  const reflectionPrompt = domain.status === "insufficientResponses" ? `If you choose to revisit ${domain.domainLabel}, what would make the remaining questions easier to answer?` : domain.focusInsight ? `What has been making ${domain.domainLabel.toLowerCase()} feel more difficult during the past 7 days?` : domain.strengthInsight ? `What has been helping ${domain.domainLabel.toLowerCase()} feel supportive during the past 7 days?` : `What is one practical step that could help you maintain ${domain.domainLabel.toLowerCase()} this week?`;
  return {domainId: domain.domainId, domainLabel: domain.domainLabel, status: domain.status, summary: copy[domain.status], focusInsight: domain.focusInsight, strengthInsight: domain.strengthInsight, suggestedAction: domain.suggestedAction, reflectionPrompt};
}

function overallSummaryFor(domains: Array<{domainLabel: string; status: string}>, quality: {answered: number; presented: number; confidence: string}): string {
  const count = (status: string) => domains.filter((domain) => domain.status === status).length;
  const focus = domains.filter((domain) => domain.status === "someStrain" || domain.status === "supportMayHelp").map((domain) => domain.domainLabel).slice(0, 2);
  const strengths = domains.filter((domain) => domain.status === "supported").map((domain) => domain.domainLabel).slice(0, 2);
  return `Across the five areas, ${count("supported")} were supported, ${count("mostlySupported")} were mostly supported, ${count("someStrain")} showed some strain, and ${count("supportMayHelp")} may benefit from support. ${focus.length ? `${focus.join(" and ")} ${focus.length === 1 ? "was" : "were"} the clearest area${focus.length === 1 ? "" : "s"} to explore.` : "No single area stood out as needing additional attention."} ${strengths.length ? `${strengths.join(" and ")} showed supportive patterns.` : ""} You answered ${quality.answered} of ${quality.presented} questions, giving this result ${quality.confidence} response completeness.`;
}

function calculateWorkplaceV4(config: WorkplaceV4Config, answers: WorkplaceV4Answer[]): Record<string, unknown> {
  validateWorkplaceV4Answers(answers, config);
  const byId = new Map(answers.map((answer) => [answer.itemId, answer]));
  const answeredCount = config.items.filter((item) => !byId.get(item.id)!.skipped).length;
  const responseQuality = {answered: answeredCount, presented: config.items.length, skipped: config.items.length - answeredCount, completionPercent: round(answeredCount / config.items.length * 100)};
  const domains = config.domainOrder.map((domainId) => {
    const items = config.items.filter((item) => item.domainId === domainId);
    const answered = items.flatMap((item) => { const answer = byId.get(item.id)!; return answer.skipped ? [] : [{item, concern: concern(answer.responseValue!, item.direction)}]; });
    const isScorable = answered.length >= 7;
    const internalConcern = isScorable ? round(answered.reduce((total, entry) => total + entry.concern, 0) / answered.length) : null;
    const focus = answered.filter((entry) => entry.concern >= 66.67).sort((a, b) => b.concern - a.concern || a.item.displayOrder - b.item.displayOrder)[0];
    const strength = answered.filter((entry) => entry.item.direction === "protective" && entry.concern <= 33.33).sort((a, b) => a.concern - b.concern || a.item.displayOrder - b.item.displayOrder)[0];
    const label = config.domainLabels[domainId];
    return {domainId, domainLabel: label, status: internalConcern === null ? "insufficientResponses" : statusFor(internalConcern), answeredCount: answered.length, presentedCount: items.length, completionPercent: round(answered.length / items.length * 100), isScorable, internalConcern, focusConstructIds: focus ? [focus.item.constructId] : [], strengthConstructIds: strength ? [strength.item.constructId] : [], focusInsight: focus ? insight(focus.item, "focus", label) : null, strengthInsight: strength ? insight(strength.item, "strength", label) : null, suggestedAction: isScorable ? actionFor(config, domainId) : "Answer more items in this area when you feel comfortable."};
  });
  const scorable = domains.filter((domain) => domain.isScorable);
  const profileStatus = domains.some((domain) => !domain.isScorable) ? "insufficientResponses" : scorable.some((domain) => domain.status === "supportMayHelp") ? "supportMayHelp" : scorable.filter((domain) => domain.status === "someStrain").length >= 2 ? "someAreasNeedAttention" : scorable.some((domain) => domain.status === "someStrain" || domain.status === "mostlySupported") ? "mostlySupported" : "generallySupported";
  const focus = domains.filter((domain) => domain.focusInsight && domain.internalConcern !== null).sort((a, b) => b.internalConcern! - a.internalConcern!).slice(0, 3);
  const strengths = domains.filter((domain) => domain.strengthInsight && domain.internalConcern !== null).filter((domain) => !focus.some((focusDomain) => focusDomain.domainId === domain.domainId && focusDomain.focusConstructIds[0] === domain.strengthConstructIds[0])).sort((a, b) => a.internalConcern! - b.internalConcern!).slice(0, 2);
  const profileLabels: Record<string, string> = {generallySupported: "Well-being appears generally supported.", mostlySupported: "Mostly supported, with an area to explore.", someAreasNeedAttention: "Some areas may benefit from attention.", supportMayHelp: "Support may be helpful right now.", insufficientResponses: "More responses are needed for a complete profile."};
  const confidence = confidenceFor(responseQuality.completionPercent);
  const userSummary = summaryFor(config, profileStatus, focus.map((domain) => domain.domainLabel));
  return {schemaVersion: "assessment_record_v4", assessmentKind: "full", instrument: {family: config.family, version: config.instrumentVersion, catalogHash: config.catalogHash, recallPeriodDays: 7, responseScaleId: "agreement_4_no_neutral_v1", algorithmVersion: config.algorithmVersion, referenceSetVersion: "mindmate_wellbeing_refs_v1"}, result: {profileStatus, domainResults: domains.map(({focusInsight, strengthInsight, suggestedAction, domainLabel, ...domain}) => domain), responseQuality: {...responseQuality, confidence}, policyStatus: "provisional_pending_local_validation"}, interpretation: {resultNarrativeVersion: "v4_result_narrative_v1", userSummary, overallResponseSummary: overallSummaryFor(domains, {...responseQuality, confidence}), domainSummaries: domains.map(domainSummaryFor), rationale: focus.length ? [`Areas to explore: ${focus.map((domain) => domain.domainLabel).join(", ")}.`] : ["No focus construct is shown until enough responses are available."], focusInsights: focus.map((domain) => domain.focusInsight), strengthInsights: strengths.map((domain) => domain.strengthInsight), suggestedActions: focus.map((domain) => domain.suggestedAction), followUpGuidance: profileStatus === "supportMayHelp" ? "timelySupport" : profileStatus === "someAreasNeedAttention" ? "considerSupport" : profileStatus === "insufficientResponses" ? "moreResponsesNeeded" : "routine", disclaimer: employeeDisclaimer}, itemSnapshot: config.items.map((item) => ({itemId: item.id, domainId: item.domainId, displayOrder: item.displayOrder, direction: item.direction, constructId: item.constructId, text: item.text})), algorithmVersion: config.algorithmVersion, questionSetVersion: config.instrumentVersion, status: profileLabels[profileStatus], verificationStatus: "verified", calculationAuthority: "server"};
}

export const calculateTeachingV4 = (answers: WorkplaceV4Answer[]) => calculateWorkplaceV4(teachingConfig, answers);
export const calculateNonTeachingV4 = (answers: WorkplaceV4Answer[]) => calculateWorkplaceV4(nonTeachingConfig, answers);
export const validateTeachingV4Answers = (answers: WorkplaceV4Answer[]) => validateWorkplaceV4Answers(answers, teachingConfig);
export const validateNonTeachingV4Answers = (answers: WorkplaceV4Answer[]) => validateWorkplaceV4Answers(answers, nonTeachingConfig);
