import {
  STUDENT_V4_ALGORITHM_VERSION,
  STUDENT_V4_CATALOG_HASH,
  STUDENT_V4_DOMAIN_LABELS,
  STUDENT_V4_DOMAIN_ORDER,
  STUDENT_V4_INSTRUMENT_VERSION,
  STUDENT_V4_ITEMS,
  StudentV4Direction,
  StudentV4DomainId,
  StudentV4Item,
} from "./student_v4_catalog";
import {AssessmentValidationError} from "./calculator";

export type StudentV4ResponseCode = "stronglyDisagree" | "disagree" | "agree" | "stronglyAgree";
export type StudentV4Answer = {
  itemId: string;
  responseCode?: StudentV4ResponseCode;
  responseValue?: number;
  skipped: boolean;
};

const RESPONSE_VALUES: Record<StudentV4ResponseCode, number> = {
  stronglyDisagree: 1,
  disagree: 2,
  agree: 3,
  stronglyAgree: 4,
};
const DOMAIN_STATUS = {
  supported: "supported",
  mostlySupported: "mostlySupported",
  someStrain: "someStrain",
  supportMayHelp: "supportMayHelp",
  insufficientResponses: "insufficientResponses",
} as const;
const DISCLAMER = "This is a 7-day reflection profile, not a diagnosis. It is meant to support reflection and a conversation with a qualified professional if desired.";

function round(value: number): number {
  return Number(value.toFixed(2));
}

function concern(value: number, direction: StudentV4Direction): number {
  const normalized = ((value - 1) / 3) * 100;
  return direction === "protective" ? 100 - normalized : normalized;
}

function statusFor(value: number): keyof typeof DOMAIN_STATUS {
  if (value <= 25) return "supported";
  if (value <= 50) return "mostlySupported";
  if (value <= 75) return "someStrain";
  return "supportMayHelp";
}

function confidenceFor(completionPercent: number): "high" | "usableWithCaution" | "limited" {
  if (completionPercent >= 90) return "high";
  if (completionPercent >= 70) return "usableWithCaution";
  return "limited";
}

function constructLabel(constructId: string): string {
  return constructId.replace(/_/g, " ");
}

function focusTemplate(item: StudentV4Item): string {
  return `${STUDENT_V4_DOMAIN_LABELS[item.domainId]}: explore ${constructLabel(item.constructId)}.`;
}

function strengthTemplate(item: StudentV4Item): string {
  return `${STUDENT_V4_DOMAIN_LABELS[item.domainId]}: supportive patterns around ${constructLabel(item.constructId)}.`;
}

function actionFor(domain: StudentV4DomainId): string {
  const actions: Record<StudentV4DomainId, string> = {
    academic: "Choose one manageable planning or academic-support step for this week.",
    financial: "Review one practical university or trusted financial-support option if useful.",
    socialAdjustment: "Consider one connection or support option that feels comfortable.",
    sleepRest: "Choose one small rest or wind-down routine that fits your schedule.",
    emotionalWellbeing: "Make space for one supportive coping or check-in practice.",
  };
  return actions[domain];
}

export function validateStudentV4Answers(answers: StudentV4Answer[]): void {
  if (!Array.isArray(answers) || answers.length !== STUDENT_V4_ITEMS.length) {
    throw new AssessmentValidationError("Student V4 requires all 50 item IDs exactly once.");
  }
  const byId = new Map(answers.map((answer) => [answer.itemId, answer]));
  if (byId.size !== STUDENT_V4_ITEMS.length) {
    throw new AssessmentValidationError("Duplicate Student V4 item IDs are not allowed.");
  }
  for (const item of STUDENT_V4_ITEMS) {
    const answer = byId.get(item.id);
    if (!answer || typeof answer.skipped !== "boolean") {
      throw new AssessmentValidationError("Student V4 answers do not match the instrument catalog.");
    }
    if (answer.skipped) {
      if (answer.responseCode !== undefined || answer.responseValue !== undefined) {
        throw new AssessmentValidationError("Skipped Student V4 items must not include a response.");
      }
      continue;
    }
    if (!answer.responseCode || RESPONSE_VALUES[answer.responseCode] !== answer.responseValue) {
      throw new AssessmentValidationError("Student V4 response code and value must match.");
    }
  }
}

export function calculateStudentV4(answers: StudentV4Answer[]): Record<string, unknown> {
  validateStudentV4Answers(answers);
  const byId = new Map(answers.map((answer) => [answer.itemId, answer]));
  const answeredItems = STUDENT_V4_ITEMS.filter((item) => !byId.get(item.id)!.skipped);
  const responseQuality = {
    answered: answeredItems.length,
    presented: STUDENT_V4_ITEMS.length,
    skipped: STUDENT_V4_ITEMS.length - answeredItems.length,
    completionPercent: round((answeredItems.length / STUDENT_V4_ITEMS.length) * 100),
  };
  const confidence = confidenceFor(responseQuality.completionPercent);
  const domainResults = STUDENT_V4_DOMAIN_ORDER.map((domainId) => {
    const items = STUDENT_V4_ITEMS.filter((item) => item.domainId === domainId);
    const answered = items.flatMap((item) => {
      const answer = byId.get(item.id)!;
      return answer.skipped ? [] : [{item, concern: concern(answer.responseValue!, item.direction)}];
    });
    const isScorable = answered.length >= 7;
    const internalConcern = isScorable
      ? round(answered.reduce((total, item) => total + item.concern, 0) / answered.length)
      : null;
    const status = internalConcern === null ? DOMAIN_STATUS.insufficientResponses : DOMAIN_STATUS[statusFor(internalConcern)];
    const focus = answered.filter((entry) => entry.concern >= 66.67);
    const strengths = answered.filter((entry) => entry.item.direction === "protective" && entry.concern <= 33.33);
    const topFocus = focus.sort((a, b) => b.concern - a.concern || a.item.displayOrder - b.item.displayOrder)[0];
    const topStrength = strengths.sort((a, b) => a.concern - b.concern || a.item.displayOrder - b.item.displayOrder)[0];
    return {
      domainId,
      domainLabel: STUDENT_V4_DOMAIN_LABELS[domainId],
      status,
      answeredCount: answered.length,
      presentedCount: items.length,
      completionPercent: round((answered.length / items.length) * 100),
      isScorable,
      internalConcern,
      focusConstructIds: topFocus ? [topFocus.item.constructId] : [],
      strengthConstructIds: topStrength ? [topStrength.item.constructId] : [],
      focusInsight: topFocus ? focusTemplate(topFocus.item) : null,
      strengthInsight: topStrength ? strengthTemplate(topStrength.item) : null,
      suggestedAction: isScorable ? actionFor(domainId) : "Answer more items in this area when you feel comfortable.",
    };
  });
  const unscorable = domainResults.some((domain) => !domain.isScorable);
  const scorable = domainResults.filter((domain) => domain.isScorable);
  const supportMayHelp = scorable.filter((domain) => domain.status === DOMAIN_STATUS.supportMayHelp).length;
  const someStrain = scorable.filter((domain) => domain.status === DOMAIN_STATUS.someStrain).length;
  const mostlySupported = scorable.filter((domain) => domain.status === DOMAIN_STATUS.mostlySupported).length;
  const profileStatus = unscorable ? "insufficientResponses" : supportMayHelp > 0 ? "supportMayHelp" : someStrain >= 2 ? "someAreasNeedAttention" : someStrain === 1 || mostlySupported > 0 ? "mostlySupported" : "generallySupported";
  const focus = domainResults
    .filter((domain) => domain.focusInsight !== null && domain.internalConcern !== null)
    .sort((a, b) => b.internalConcern! - a.internalConcern! || STUDENT_V4_DOMAIN_ORDER.indexOf(a.domainId) - STUDENT_V4_DOMAIN_ORDER.indexOf(b.domainId))
    .slice(0, 3);
  const strengths = domainResults
    .filter((domain) => domain.strengthInsight !== null && domain.internalConcern !== null)
    .filter((domain) => !focus.some((focusDomain) => focusDomain.domainId === domain.domainId && focusDomain.focusConstructIds[0] === domain.strengthConstructIds[0]))
    .sort((a, b) => a.internalConcern! - b.internalConcern! || STUDENT_V4_DOMAIN_ORDER.indexOf(a.domainId) - STUDENT_V4_DOMAIN_ORDER.indexOf(b.domainId))
    .slice(0, 2);
  const profileLabels: Record<string, string> = {
    generallySupported: "Well-being appears generally supported.",
    mostlySupported: "Mostly supported, with an area to explore.",
    someAreasNeedAttention: "Some areas may benefit from attention.",
    supportMayHelp: "Support may be helpful right now.",
    insufficientResponses: "More responses are needed for a complete profile.",
  };
  const focusLabels = focus.map((domain) => domain.domainLabel);
  const strengthLabels = strengths.map((domain) => domain.domainLabel);
  const summary = `${profileLabels[profileStatus]} This is a snapshot of the past 7 days based on the areas you answered.`;
  return {
    schemaVersion: "assessment_record_v4",
    assessmentKind: "full",
    instrument: {
      family: "student_wellbeing_reflection",
      version: STUDENT_V4_INSTRUMENT_VERSION,
      catalogHash: STUDENT_V4_CATALOG_HASH,
      recallPeriodDays: 7,
      responseScaleId: "agreement_4_no_neutral_v1",
      algorithmVersion: STUDENT_V4_ALGORITHM_VERSION,
    },
    result: {
      profileStatus,
      domainResults: domainResults.map((domain) => ({
        domainId: domain.domainId,
        status: domain.status,
        answeredCount: domain.answeredCount,
        presentedCount: domain.presentedCount,
        completionPercent: domain.completionPercent,
        isScorable: domain.isScorable,
        internalConcern: domain.internalConcern,
        focusConstructIds: domain.focusConstructIds,
        strengthConstructIds: domain.strengthConstructIds,
      })),
      responseQuality: {...responseQuality, confidence},
      policyStatus: "provisional_pending_local_validation",
    },
    interpretation: {
      studentSummary: summary,
      rationale: focusLabels.length
        ? [`Added attention: ${focusLabels.join(", ")}.`, ...(strengthLabels.length ? [`Supportive patterns: ${strengthLabels.join(", ")}.`] : [])]
        : ["No focus construct is shown until enough responses are available."],
      focusInsights: focus.map((domain) => domain.focusInsight),
      strengthInsights: strengths.map((domain) => domain.strengthInsight),
      suggestedActions: focus.map((domain) => domain.suggestedAction),
      followUpGuidance: profileStatus === "supportMayHelp" ? "timelySupport" : profileStatus === "someAreasNeedAttention" ? "considerSupport" : profileStatus === "insufficientResponses" ? "moreResponsesNeeded" : "routine",
      disclaimer: DISCLAMER,
    },
    itemSnapshot: STUDENT_V4_ITEMS.map((item) => ({
      itemId: item.id,
      domainId: item.domainId,
      displayOrder: item.displayOrder,
      direction: item.direction,
      constructId: item.constructId,
      text: item.text,
    })),
    algorithmVersion: STUDENT_V4_ALGORITHM_VERSION,
    questionSetVersion: STUDENT_V4_INSTRUMENT_VERSION,
    status: profileLabels[profileStatus],
    verificationStatus: "verified",
    calculationAuthority: "server",
  };
}
