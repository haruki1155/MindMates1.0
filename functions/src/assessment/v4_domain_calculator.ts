import {AssessmentValidationError} from "./calculator";
import {STUDENT_V4_INSTRUMENT_VERSION, STUDENT_V4_ITEMS} from "./student_v4_catalog";
import {calculateStudentV4, StudentV4Answer} from "./student_v4_calculator";
import {
  NON_TEACHING_V4_INSTRUMENT_VERSION,
  NON_TEACHING_V4_ITEMS,
  TEACHING_V4_INSTRUMENT_VERSION,
  TEACHING_V4_ITEMS,
} from "./workplace_v4_catalog";
import {calculateNonTeachingV4, calculateTeachingV4, WorkplaceV4Answer} from "./workplace_v4_calculator";

export type V4InstrumentVersion =
  | typeof STUDENT_V4_INSTRUMENT_VERSION
  | typeof TEACHING_V4_INSTRUMENT_VERSION
  | typeof NON_TEACHING_V4_INSTRUMENT_VERSION;
export type V4DomainAnswer = StudentV4Answer | WorkplaceV4Answer;
export type V4DomainCalculation = {
  domainId: string;
  domainLabel: string;
  status: string;
  answeredCount: number;
  presentedCount: number;
  isScorable: boolean;
  summary: string;
  focusInsight: string | null;
  strengthInsight: string | null;
  suggestedAction: string;
  reflectionPrompt: string;
};

type Item = {id: string; domainId: string};
type Config = {items: readonly Item[]; calculate: (answers: V4DomainAnswer[]) => Record<string, unknown>};

function configFor(instrumentVersion: string): Config {
  if (instrumentVersion === STUDENT_V4_INSTRUMENT_VERSION) {
    return {items: STUDENT_V4_ITEMS, calculate: (answers) => calculateStudentV4(answers as StudentV4Answer[])};
  }
  if (instrumentVersion === TEACHING_V4_INSTRUMENT_VERSION) {
    return {items: TEACHING_V4_ITEMS, calculate: (answers) => calculateTeachingV4(answers as WorkplaceV4Answer[])};
  }
  if (instrumentVersion === NON_TEACHING_V4_INSTRUMENT_VERSION) {
    return {items: NON_TEACHING_V4_ITEMS, calculate: (answers) => calculateNonTeachingV4(answers as WorkplaceV4Answer[])};
  }
  throw new AssessmentValidationError("Unsupported V4 assessment instrument.");
}

export function calculateV4Domain(
  instrumentVersion: V4InstrumentVersion,
  domainId: string,
  answers: V4DomainAnswer[],
): V4DomainCalculation {
  const config = configFor(instrumentVersion);
  const domainItems = config.items.filter((item) => item.domainId === domainId);
  if (domainItems.length !== 10 || answers.length !== domainItems.length) {
    throw new AssessmentValidationError("The selected V4 domain requires its exact ten item responses.");
  }
  const expectedIds = new Set(domainItems.map((item) => item.id));
  const byId = new Map(answers.map((answer) => [answer.itemId, answer]));
  if (byId.size !== domainItems.length || [...byId.keys()].some((id) => !expectedIds.has(id))) {
    throw new AssessmentValidationError("V4 domain responses must match the selected domain exactly once.");
  }

  // The established full calculators remain the single source of scoring truth.
  const fullAnswers = config.items.map((item) => byId.get(item.id) ?? {itemId: item.id, skipped: true});
  const calculation = config.calculate(fullAnswers);
  const result = calculation.result as Record<string, unknown>;
  const interpretation = calculation.interpretation as Record<string, unknown>;
  const domainResult = (result.domainResults as Array<Record<string, unknown>>)
    .find((domain) => domain.domainId === domainId);
  const domainSummary = (interpretation.domainSummaries as Array<Record<string, unknown>>)
    .find((domain) => domain.domainId === domainId);
  if (!domainResult || !domainSummary) throw new AssessmentValidationError("The selected V4 domain could not be calculated.");

  return {
    domainId,
    domainLabel: String(domainSummary.domainLabel),
    status: String(domainResult.status),
    answeredCount: Number(domainResult.answeredCount),
    presentedCount: Number(domainResult.presentedCount),
    isScorable: domainResult.isScorable === true,
    summary: String(domainSummary.summary),
    focusInsight: typeof domainSummary.focusInsight === "string" ? domainSummary.focusInsight : null,
    strengthInsight: typeof domainSummary.strengthInsight === "string" ? domainSummary.strengthInsight : null,
    suggestedAction: String(domainSummary.suggestedAction),
    reflectionPrompt: String(domainSummary.reflectionPrompt),
  };
}
