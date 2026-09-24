import {createHash} from "node:crypto";

export type StudentV4Direction = "risk" | "protective";
export type StudentV4DomainId =
  "academic" | "financial" | "socialAdjustment" | "sleepRest" | "emotionalWellbeing";

export type StudentV4Item = {
  id: string;
  domainId: StudentV4DomainId;
  displayOrder: number;
  direction: StudentV4Direction;
  constructId: string;
  text: string;
};

const item = (
  id: string,
  domainId: StudentV4DomainId,
  displayOrder: number,
  direction: StudentV4Direction,
  constructId: string,
  text: string,
): StudentV4Item => ({id, domainId, displayOrder, direction, constructId, text});

/**
 * Immutable Student Well-Being V4 catalog. Do not edit item IDs, ordering,
 * wording, directions, or construct IDs after release; publish a new version.
 */
export const STUDENT_V4_ITEMS: readonly StudentV4Item[] = Object.freeze([
  item("student_v4_academic_01", "academic", 1, "protective", "academic_planning", "I could organize my academic tasks into a workable plan."),
  item("student_v4_academic_02", "academic", 2, "protective", "academic_planning", "I had enough time to complete the academic work I scheduled."),
  item("student_v4_academic_03", "academic", 3, "risk", "academic_workload", "I felt overwhelmed by the amount of academic work expected of me."),
  item("student_v4_academic_04", "academic", 4, "risk", "academic_task_initiation", "I found it difficult to begin academic work I had planned to do."),
  item("student_v4_academic_05", "academic", 5, "risk", "academic_deadlines", "I found it difficult to keep up with academic deadlines."),
  item("student_v4_academic_06", "academic", 6, "protective", "academic_focus", "I could stay focused while doing academic work."),
  item("student_v4_academic_07", "academic", 7, "protective", "academic_help_access", "I knew where to get academic help when I needed it."),
  item("student_v4_academic_08", "academic", 8, "risk", "academic_performance_pressure", "I felt pressure about my academic performance."),
  item("student_v4_academic_09", "academic", 9, "protective", "academic_setback_recovery", "I could regain my focus after an academic setback."),
  item("student_v4_academic_10", "academic", 10, "risk", "academic_learning_motivation", "Academic demands made it hard for me to stay motivated to learn."),
  item("student_v4_financial_01", "financial", 11, "protective", "financial_essential_costs", "I could meet my essential study-related costs."),
  item("student_v4_financial_02", "financial", 12, "protective", "financial_learning_materials", "I had access to the learning materials required for my studies."),
  item("student_v4_financial_03", "financial", 13, "risk", "financial_unexpected_costs", "Unexpected study-related costs were hard for me to manage."),
  item("student_v4_financial_04", "financial", 14, "protective", "financial_support_information", "I knew where to find financial-aid or payment-support information."),
  item("student_v4_financial_05", "financial", 15, "protective", "financial_expense_planning", "I had a workable plan for upcoming education expenses."),
  item("student_v4_financial_06", "financial", 16, "risk", "financial_school_fees", "I worried that I might not be able to pay essential school fees."),
  item("student_v4_financial_07", "financial", 17, "risk", "financial_study_requirements", "I had to delay or miss a study requirement because of cost."),
  item("student_v4_financial_08", "financial", 18, "protective", "financial_budget_tracking", "I could keep track of money set aside for school needs."),
  item("student_v4_financial_09", "financial", 19, "protective", "financial_study_basics", "I could cover the transport, data, food, or other basic costs needed for study."),
  item("student_v4_financial_10", "financial", 20, "risk", "financial_obligations", "I found it hard to manage financial obligations related to school."),
  item("student_v4_social_adjustment_01", "socialAdjustment", 21, "protective", "social_belonging", "I felt that I belonged in the university community."),
  item("student_v4_social_adjustment_02", "socialAdjustment", 22, "protective", "peer_connection", "I had at least one peer at the university I could talk with if I chose to."),
  item("student_v4_social_adjustment_03", "socialAdjustment", 23, "protective", "peer_acceptance", "I felt accepted by peers in my university setting."),
  item("student_v4_social_adjustment_04", "socialAdjustment", 24, "protective", "peer_help", "I was comfortable asking a peer for practical help when I needed it."),
  item("student_v4_social_adjustment_05", "socialAdjustment", 25, "protective", "peer_boundaries", "I could communicate my needs or boundaries with peers."),
  item("student_v4_social_adjustment_06", "socialAdjustment", 26, "risk", "social_avoidance", "I avoided peer interaction because I expected that I would not fit in."),
  item("student_v4_social_adjustment_07", "socialAdjustment", 27, "protective", "peer_connection", "I had opportunities to connect with peers in ways that suited me."),
  item("student_v4_social_adjustment_08", "socialAdjustment", 28, "risk", "social_inclusion", "I felt left out of peer or university activities that I wanted to join."),
  item("student_v4_social_adjustment_09", "socialAdjustment", 29, "protective", "support_access", "I knew a person or university office I could approach for support."),
  item("student_v4_social_adjustment_10", "socialAdjustment", 30, "protective", "social_connections", "I could maintain social connections that mattered to me while studying."),
  item("student_v4_sleep_rest_01", "sleepRest", 31, "protective", "sleep_onset", "I was able to fall asleep in a reasonable amount of time."),
  item("student_v4_sleep_rest_02", "sleepRest", 32, "risk", "sleep_continuity", "I woke during sleep and found it difficult to return to sleep."),
  item("student_v4_sleep_rest_03", "sleepRest", 33, "protective", "sleep_rest", "I got enough sleep to feel rested the next day."),
  item("student_v4_sleep_rest_04", "sleepRest", 34, "protective", "sleep_refreshment", "I woke feeling refreshed."),
  item("student_v4_sleep_rest_05", "sleepRest", 35, "protective", "sleep_routine", "My sleep and wake times were close to the schedule I intended."),
  item("student_v4_sleep_rest_06", "sleepRest", 36, "risk", "daytime_alertness", "I struggled to stay awake during the day because I had not slept enough."),
  item("student_v4_sleep_rest_07", "sleepRest", 37, "risk", "sleep_worry", "Worrying thoughts made it hard for me to fall asleep."),
  item("student_v4_sleep_rest_08", "sleepRest", 38, "protective", "rest_opportunity", "I had enough opportunity to rest when I needed it."),
  item("student_v4_sleep_rest_09", "sleepRest", 39, "protective", "sleep_quality", "I was satisfied with the quality of my sleep."),
  item("student_v4_sleep_rest_10", "sleepRest", 40, "protective", "sleep_wind_down", "I was able to set aside time to wind down before sleep."),
  item("student_v4_emotional_wellbeing_01", "emotionalWellbeing", 41, "protective", "emotional_positivity", "I felt cheerful or in good spirits."),
  item("student_v4_emotional_wellbeing_02", "emotionalWellbeing", 42, "protective", "emotional_calm", "I felt calm and settled."),
  item("student_v4_emotional_wellbeing_03", "emotionalWellbeing", 43, "protective", "emotional_engagement", "I felt interested in my day-to-day activities."),
  item("student_v4_emotional_wellbeing_04", "emotionalWellbeing", 44, "protective", "frustration_coping", "I felt able to handle everyday frustrations."),
  item("student_v4_emotional_wellbeing_05", "emotionalWellbeing", 45, "protective", "emotional_awareness", "I could recognize what I was feeling."),
  item("student_v4_emotional_wellbeing_06", "emotionalWellbeing", 46, "protective", "hope", "I felt hopeful about the near future."),
  item("student_v4_emotional_wellbeing_07", "emotionalWellbeing", 47, "risk", "emotional_exhaustion", "I felt emotionally drained."),
  item("student_v4_emotional_wellbeing_08", "emotionalWellbeing", 48, "risk", "emotional_demands", "I felt overwhelmed by everyday emotional demands."),
  item("student_v4_emotional_wellbeing_09", "emotionalWellbeing", 49, "protective", "emotional_recovery", "I could regain emotional balance after an ordinary setback."),
  item("student_v4_emotional_wellbeing_10", "emotionalWellbeing", 50, "protective", "emotional_satisfaction", "I felt satisfied with my current emotional well-being."),
]);

export const STUDENT_V4_INSTRUMENT_VERSION = "student_wellbeing_v4";
export const STUDENT_V4_ALGORITHM_VERSION = "student_profile_v4";
export const STUDENT_V4_CATALOG_HASH = createHash("sha256")
  .update(JSON.stringify(STUDENT_V4_ITEMS))
  .digest("hex");

export const STUDENT_V4_DOMAIN_ORDER: readonly StudentV4DomainId[] = [
  "academic", "financial", "socialAdjustment", "sleepRest", "emotionalWellbeing",
];

export const STUDENT_V4_DOMAIN_LABELS: Record<StudentV4DomainId, string> = {
  academic: "Academic",
  financial: "Financial",
  socialAdjustment: "Social Adjustment",
  sleepRest: "Sleep and Rest",
  emotionalWellbeing: "Emotional Well-Being",
};
