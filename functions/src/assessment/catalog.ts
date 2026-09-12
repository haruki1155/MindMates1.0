export type AssessmentDirection = "risk" | "protective";
export type AssessmentRole = "student" | "teaching" | "nonTeaching";

export type AssessmentQuestion = {
  id: string;
  text: string;
  section: string;
  domain: string;
  direction: AssessmentDirection;
  conditional?: boolean;
  isFunctionalImpactItem?: boolean;
  functionalImpactCategory?: string;
  priorityContribution?: number;
};

export type QuickOption = {
  id: string;
  value: number;
};

export type QuickQuestion = {
  id: string;
  area: string;
  direction: AssessmentDirection;
  options: QuickOption[];
};

const q = (
  id: string,
  text: string,
  section: string,
  domain: string,
  direction: AssessmentDirection,
  conditional = false,
): AssessmentQuestion => ({id, text, section, domain, direction, conditional});

const commonSleep: AssessmentQuestion[] = [
  q("common_sleep_1", "I get enough sleep each night.", "sleepRest", "Sleep and Rest", "protective"),
  q("common_sleep_2", "I wake up feeling refreshed.", "sleepRest", "Sleep and Rest", "protective"),
  q("common_sleep_3", "I have difficulty falling asleep.", "sleepRest", "Sleep and Rest", "risk"),
  q("common_sleep_4", "I feel tired during the day.", "sleepRest", "Sleep and Rest", "risk"),
  q("common_sleep_5", "Stress affects my sleep.", "sleepRest", "Sleep and Rest", "risk"),
  q("common_sleep_6", "I maintain a healthy sleep schedule.", "sleepRest", "Sleep and Rest", "protective"),
  q("common_sleep_7", "Lack of sleep affects my concentration.", "sleepRest", "Sleep and Rest", "risk"),
  q("common_sleep_8", "Poor sleep negatively affects my mood.", "sleepRest", "Sleep and Rest", "risk"),
  q("common_sleep_9", "I prioritize rest.", "sleepRest", "Sleep and Rest", "protective"),
  q("common_sleep_10", "I feel physically rested.", "sleepRest", "Sleep and Rest", "protective"),
];

const commonEmotional: AssessmentQuestion[] = [
  q("common_emotional_1", "I feel emotionally balanced.", "emotionalWellBeing", "Emotional Well-Being", "protective"),
  q("common_emotional_2", "I can manage stress effectively.", "emotionalWellBeing", "Emotional Well-Being", "protective"),
  q("common_emotional_3", "I feel hopeful about my future.", "emotionalWellBeing", "Emotional Well-Being", "protective"),
  q("common_emotional_4", "I feel confident handling challenges.", "emotionalWellBeing", "Emotional Well-Being", "protective"),
  q("common_emotional_5", "I feel supported by others.", "emotionalWellBeing", "Emotional Well-Being", "protective"),
  q("common_emotional_6", "I feel emotionally exhausted.", "emotionalWellBeing", "Emotional Well-Being", "risk"),
  q("common_emotional_7", "I feel overwhelmed by responsibilities.", "emotionalWellBeing", "Emotional Well-Being", "risk"),
  q("common_emotional_8", "I worry excessively about problems.", "emotionalWellBeing", "Emotional Well-Being", "risk"),
  q("common_emotional_9", "I can recover from setbacks.", "emotionalWellBeing", "Emotional Well-Being", "protective"),
  q("common_emotional_10", "I am satisfied with my overall well-being.", "emotionalWellBeing", "Emotional Well-Being", "protective"),
];

// Student question IDs predate the shared teaching/non-teaching catalog and
// are part of the v1 mobile/web submission contract. Keep the common wording
// and scoring direction while preserving those role-specific IDs.
const studentSleep = commonSleep.map((question, index) => ({
  ...question,
  id: `sleep_${index + 1}`,
}));

const studentEmotional = commonEmotional.map((question, index) => ({
  ...question,
  id: `emotional_${index + 1}`,
}));

const studentCatalog: AssessmentQuestion[] = [
  ...[
    "I feel overwhelmed by academic requirements.", "I worry about my grades.",
    "I struggle to meet deadlines.", "I feel pressured to perform well academically.",
    "I experience stress before examinations.", "I have difficulty concentrating during classes.",
    "I lose motivation because of academic demands.", "I feel mentally exhausted after classes.",
    "Academic tasks affect my sleep.", "I feel discouraged when I receive low grades.",
  ].map((text, i) => q(`academic_core_${i + 1}`, text, "academicCore", "Academic Stress", "risk")),
  ...[
    "I experience headaches during academic pressure.", "I have difficulty managing multiple requirements.",
    "Academic stress affects my confidence.", "I worry about disappointing my family.",
    "I feel anxious about graduation.", "Academic stress affects my social life.",
    "I skip meals because of schoolwork.", "I find it difficult to relax.",
    "I constantly think about unfinished requirements.", "Academic concerns affect my emotional well-being.",
  ].map((text, i) => q(`academic_deeper_${i + 1}`, text, "academicDeeper", "Academic Stress", "risk", true)),
  ...[
    "Financial concerns affect my studies.", "I worry about tuition or school expenses.",
    "Financial stress affects my concentration.", "I worry about future educational costs.",
    "Financial concerns affect my emotional well-being.", "Unexpected school expenses cause me stress.",
    "Financial limitations prevent me from joining school activities.",
    "I worry about paying for my basic educational needs.",
    "I have difficulty managing my school-related budget.",
    "Financial pressure makes me consider delaying my studies.",
  ].map((text, i) => q(`financial_${i + 1}`, text, "financialConcern", "Financial Well-Being", "risk")),
  ...[
    "I feel supported by my classmates.", "I find it easy to build friendships.",
    "I feel comfortable seeking help.", "I feel connected to the university community.",
    "Social relationships positively affect my well-being.",
    "I have someone at the university I can talk to when needed.",
    "I feel accepted by people in my university community.",
    "I participate in group or community activities.",
    "I can communicate comfortably with my peers.",
    "My university connections help me feel less isolated.",
  ].map((text, i) => q(`social_${i + 1}`, text, "socialAdjustment", "Social Adjustment", "protective")),
  ...studentSleep,
  ...studentEmotional,
];
const student = studentCatalog.filter((question) => !question.conditional);

const facultyCatalog: AssessmentQuestion[] = [
  q("faculty_workplace_core_1", "My workload is manageable.", "workplaceStressCore", "Workplace Stress", "protective"),
  q("faculty_workplace_core_2", "Teaching responsibilities cause me stress.", "workplaceStressCore", "Workplace Stress", "risk"),
  q("faculty_workplace_core_3", "Administrative tasks increase my stress level.", "workplaceStressCore", "Workplace Stress", "risk"),
  q("faculty_workplace_core_4", "I feel pressured by deadlines.", "workplaceStressCore", "Workplace Stress", "risk"),
  q("faculty_workplace_core_5", "I experience stress from multiple responsibilities.", "workplaceStressCore", "Workplace Stress", "risk"),
  q("faculty_workplace_core_6", "I maintain work-life balance.", "workplaceStressCore", "Workplace Stress", "protective"),
  q("faculty_workplace_core_7", "Work affects my personal life.", "workplaceStressCore", "Workplace Stress", "risk"),
  q("faculty_workplace_core_8", "I feel mentally exhausted after work.", "workplaceStressCore", "Workplace Stress", "risk"),
  q("faculty_workplace_core_9", "Workplace concerns affect my sleep.", "workplaceStressCore", "Workplace Stress", "risk"),
  q("faculty_workplace_core_10", "I feel valued in my workplace.", "workplaceStressCore", "Workplace Stress", "protective"),
  ...[
    "I worry about unfinished tasks outside work hours.", "Work responsibilities affect my family time.",
    "I experience burnout from teaching responsibilities.", "I feel emotionally drained after work.",
    "Work-related concerns affect my health.", "I feel overwhelmed by administrative duties.",
    "I struggle to manage workload demands.", "Work pressure affects my motivation.",
    "Workplace stress affects my relationships.", "I find it difficult to relax after work.",
  ].map((text, i) => q(`faculty_workplace_deeper_${i + 1}`, text, "workplaceStressDeeper", "Workplace Stress", "risk", true)),
  ...[
    "I receive support from my department.", "I can communicate concerns with colleagues.",
    "I feel respected in the workplace.", "I receive recognition for my efforts.",
    "I feel supported by university policies.",
    "My department leadership listens to workplace concerns.",
    "My colleagues offer help when my workload is difficult.",
    "I have access to the resources I need to teach effectively.",
    "I receive constructive feedback about my work.",
    "I know where to seek support for workplace concerns.",
  ].map((text, i) => q(`faculty_support_${i + 1}`, text, "professionalSupport", "Professional Support", "protective")),
  ...[
    "I can manage stress effectively.", "I feel emotionally balanced.",
    "I remain motivated in my profession.", "I am satisfied with my work environment.",
    "I feel confident handling workplace challenges.",
    "I have enough energy to carry out my teaching duties.",
    "I can disconnect from work during my personal time.",
    "I feel a sense of purpose in my professional role.",
    "I recover well after a stressful workday.",
    "My work routine supports my overall health.",
  ].map((text, i) => q(`faculty_wellbeing_${i + 1}`, text, "professionalWellBeing", "Professional Well-Being", "protective")),
  ...commonSleep,
  ...commonEmotional,
];
const faculty = facultyCatalog.filter((question) => !question.conditional);

const staffCatalog: AssessmentQuestion[] = [
  q("staff_responsibility_core_1", "My workload is manageable.", "workplaceResponsibilityCore", "Workplace Responsibilities", "protective"),
  ...[
    "I feel overwhelmed by work responsibilities.", "Deadlines cause me stress.",
    "Workplace demands affect my well-being.", "I feel pressured to complete tasks quickly.",
    "Work affects my personal life.", "I feel physically exhausted after work.",
    "I feel mentally exhausted after work.", "Workplace concerns affect my sleep.",
    "I worry about work-related issues.",
  ].map((text, i) => q(`staff_responsibility_core_${i + 2}`, text, "workplaceResponsibilityCore", "Workplace Responsibilities", "risk")),
  ...[
    "I experience difficulty concentrating at work.", "Work responsibilities affect my mood.",
    "I struggle to manage multiple tasks.", "Work pressure affects my confidence.",
    "I find it difficult to relax after work.", "Workplace stress affects my health.",
    "Work demands affect my relationships.", "I feel emotionally drained.",
    "I experience frustration because of workload.", "Workplace concerns affect my overall well-being.",
  ].map((text, i) => q(`staff_responsibility_deeper_${i + 1}`, text, "workplaceResponsibilityDeeper", "Workplace Responsibilities", "risk", true)),
  ...[
    "I receive support from supervisors.", "I receive support from coworkers.",
    "I can communicate workplace concerns openly.", "I feel valued in my workplace.",
    "I feel respected by colleagues.", "My supervisor listens to workplace concerns.",
    "My team cooperates when the workload is difficult.",
    "I have access to the resources and training I need.",
    "I receive constructive feedback about my work.",
    "I know where to seek support for workplace concerns.",
  ].map((text, i) => q(`staff_support_${i + 1}`, text, "workplaceSupport", "Workplace Support", "protective")),
  ...[
    "I can manage stress effectively.", "I feel emotionally balanced.",
    "I am satisfied with my work environment.", "I feel motivated at work.",
    "I feel confident handling challenges.", "I have enough energy to carry out my work duties.",
    "I can disconnect from work during my personal time.",
    "I feel a sense of purpose in my workplace role.",
    "I recover well after a stressful workday.",
    "My work routine supports my overall health.",
  ].map((text, i) => q(`staff_wellbeing_${i + 1}`, text, "workplaceWellBeing", "Workplace Well-Being", "protective")),
  ...commonSleep,
  ...commonEmotional,
];
const staff = staffCatalog.filter((question) => !question.conditional);

export const QUESTIONS_BY_ROLE: Record<AssessmentRole, AssessmentQuestion[]> = {
  student,
  teaching: faculty,
  nonTeaching: staff,
};

export const QUICK_QUESTIONS: QuickQuestion[] = [
  {id: "calm_relaxed", area: "Emotional calm", direction: "protective", options: [
    {id: "all_time", value: 5}, {id: "most_time", value: 4}, {id: "more_than_half", value: 3}, {id: "less_than_half", value: 2}, {id: "at_no_time", value: 1},
  ]},
  {id: "overwhelmed", area: "Stress load", direction: "risk", options: [
    {id: "never", value: 1}, {id: "rarely", value: 2}, {id: "sometimes", value: 3}, {id: "fairly_often", value: 4}, {id: "very_often", value: 5},
  ]},
  {id: "connected", area: "Social connection", direction: "protective", options: [
    {id: "very_connected", value: 5}, {id: "somewhat_connected", value: 4}, {id: "neutral", value: 3}, {id: "somewhat_disconnected", value: 2}, {id: "very_disconnected", value: 1},
  ]},
  {id: "little_interest", area: "Motivation and interest", direction: "risk", options: [
    {id: "not_at_all", value: 1}, {id: "several_days", value: 2}, {id: "more_than_half", value: 3}, {id: "nearly_every_day", value: 4},
  ]},
  {id: "stress_affecting_life", area: "Daily coping", direction: "risk", options: [
    {id: "never", value: 1}, {id: "rarely", value: 2}, {id: "sometimes", value: 3}, {id: "often", value: 4}, {id: "always", value: 5},
  ]},
];

// No documented validation source was found. These are internal experimental
// product rules retained for compatibility and requiring professional review.
export const ALGORITHM_VERSION = "internal_wellness_policy_v2";
export const FULL_QUESTION_SET_VERSION = "experimental_role_based_v3";
export const QUICK_QUESTION_SET_VERSION = "quick_v2";
export const POLICY_SOURCE = "internally_defined_product_rule";
export const POLICY_VALIDATION_STATUS = "requires_professional_review";
export const MIN_DOMAIN_ANSWERS = 3;
export const MIN_DOMAIN_COMPLETION = 0.70;
export const SCORE_BOUNDARIES = {low: 20, watchful: 40, moderate: 60, elevated: 80} as const;
export const QUICK_BOUNDARIES = {moderate: 30, high: 55, veryHigh: 75} as const;
export const RESPONSE_COMPLETION = {usable: 70, high: 90} as const;
export const INDICATOR_BOUNDARIES = {elevated: 75, protectiveMaximum: 25, focus: 40} as const;
export const CONDITIONAL_RULE = {always: 1, oftenOrAlways: 2, average: 50} as const;
export const PRIORITY_RULES = {
  prompt: {highDomains: 1, elevatedDomains: 2, functionalImpacts: 3},
  followUp: {elevatedDomains: 1, moderateDomains: 2, functionalImpacts: 2},
  monitor: {moderateDomains: 1, functionalImpacts: 1},
} as const;
export const FUNCTIONAL_IMPACT_QUESTION_IDS = new Set([
  "academic_core_6", "academic_core_7", "academic_core_9", "academic_deeper_6", "academic_deeper_7", "financial_3",
  "sleep_1", "sleep_3", "sleep_4", "sleep_5", "sleep_6", "sleep_7", "sleep_8", "sleep_9", "sleep_10",
  "faculty_workplace_core_7", "faculty_workplace_core_9", "faculty_workplace_deeper_2", "faculty_workplace_deeper_5", "faculty_workplace_deeper_8", "faculty_workplace_deeper_9",
  "staff_responsibility_core_6", "staff_responsibility_core_9", "staff_responsibility_deeper_6", "staff_responsibility_deeper_7",
  "common_sleep_1", "common_sleep_3", "common_sleep_4", "common_sleep_5", "common_sleep_6", "common_sleep_7", "common_sleep_8", "common_sleep_9", "common_sleep_10",
]);

export const ROLE_LABELS: Record<AssessmentRole, string> = {
  student: "Student",
  teaching: "Teaching Personnel",
  nonTeaching: "Non-Teaching Personnel",
};

export const ROLE_DOMAINS: Record<AssessmentRole, {label: string; sections: string[]; weight: number}[]> = {
  student: [
    {label: "Academic Stress", sections: ["academicCore"], weight: .20},
    {label: "Financial Well-Being", sections: ["financialConcern"], weight: .20},
    {label: "Social Adjustment", sections: ["socialAdjustment"], weight: .20},
    {label: "Sleep and Rest", sections: ["sleepRest"], weight: .20},
    {label: "Emotional Well-Being", sections: ["emotionalWellBeing"], weight: .20},
  ],
  teaching: [
    {label: "Workplace Stress", sections: ["workplaceStressCore"], weight: .20},
    {label: "Professional Support", sections: ["professionalSupport"], weight: .20},
    {label: "Professional Well-Being", sections: ["professionalWellBeing"], weight: .20},
    {label: "Sleep and Rest", sections: ["sleepRest"], weight: .20},
    {label: "Emotional Well-Being", sections: ["emotionalWellBeing"], weight: .20},
  ],
  nonTeaching: [
    {label: "Workplace Responsibilities", sections: ["workplaceResponsibilityCore"], weight: .20},
    {label: "Workplace Support", sections: ["workplaceSupport"], weight: .20},
    {label: "Workplace Well-Being", sections: ["workplaceWellBeing"], weight: .20},
    {label: "Sleep and Rest", sections: ["sleepRest"], weight: .20},
    {label: "Emotional Well-Being", sections: ["emotionalWellBeing"], weight: .20},
  ],
};

export function roleFromPopulation(value: unknown): AssessmentRole | null {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (normalized === "student") return "student";
  if (["teaching", "faculty", "teaching personnel"].includes(normalized)) return "teaching";
  if (["nonteaching", "non-teaching", "staff", "non-teaching personnel"].includes(normalized)) return "nonTeaching";
  return null;
}
