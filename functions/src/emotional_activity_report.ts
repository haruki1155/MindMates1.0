import {Timestamp} from "firebase-admin/firestore";

export const MIN_EMOTIONAL_COHORT_SIZE = 10;

export type EmotionalActivitySourceScope = "all" | "mood" | "assessment";
export type EmotionalActivityStatus = "ready" | "suppressed" | "no_data";
export type ElevationSeverity = "elevated" | "watch" | "improving" | "stable";

export interface EmotionalActivityBucket {
  key: string;
  label: string;
  percentage: number | null;
  suppressed: boolean;
}

export interface EmotionalActivityWeeklyTrend {
  weekKey: string;
  label: string;
  suppressed: boolean;
  activityShare: number | null;
  averageMoodLevel: number | null;
  dominantMoodKey: string | null;
  dominantMoodLabel: string | null;
  strainedShare: number | null;
  valenceBreakdown: EmotionalActivityBucket[];
  moodBreakdown: EmotionalActivityBucket[];
}

export interface EmotionalActivityElevationSignal {
  key: string;
  label: string;
  severity: ElevationSeverity;
  currentWeekLabel: string;
  baselineLabel: string;
  currentPercentage: number;
  baselinePercentage: number;
  deltaPoints: number;
  weekOverWeekDelta: number | null;
  summary: string;
}

export interface EmotionalActivityWeekdayBucket {
  key: string;
  label: string;
  activityShare: number | null;
  strainedShare: number | null;
  dominantMoodLabel: string | null;
  suppressed: boolean;
}

export interface EmotionalActivityMoodEngagement {
  averageMoodLevel: number | null;
  avgCheckInsPerParticipant: number | null;
  repeatParticipantRate: number | null;
  entryMethodBreakdown: EmotionalActivityBucket[];
}

export interface EmotionalActivityReport {
  status: EmotionalActivityStatus;
  suppressed: boolean;
  suppressionThreshold: number;
  suppressionReason: string | null;
  sourceScopeKey: EmotionalActivitySourceScope;
  sourceScopeLabel: string;
  schoolYear: string;
  dateRangeLabel: string;
  participationRate: number | null;
  appUserCohortShare: number | null;
  dominantValenceLabel: string | null;
  hasMixedCategories: boolean;
  moodCheckInShare: number | null;
  assessmentShare: number | null;
  valenceBreakdown: EmotionalActivityBucket[];
  moodBreakdown: EmotionalActivityBucket[];
  assessmentBreakdown: EmotionalActivityBucket[];
  periodTrends: EmotionalActivityBucket[];
  weeklyTrends: EmotionalActivityWeeklyTrend[];
  elevatedMoodSignals: EmotionalActivityElevationSignal[];
  weekdayBreakdown: EmotionalActivityWeekdayBucket[];
  moodEngagement: EmotionalActivityMoodEngagement | null;
  actionableInsights: string[];
  departmentCoverageNote: string;
}

type RecordData = Record<string, unknown>;

type BucketAccumulator = {
  key: string;
  label: string;
  users: Set<string>;
  events: number;
};

type WeekAccumulator = {
  weekKey: string;
  label: string;
  users: Set<string>;
  totalEvents: number;
  moodUsers: Set<string>;
  moodEvents: number;
  moodLevelSum: number;
  valenceMap: Map<string, BucketAccumulator>;
  moodMap: Map<string, BucketAccumulator>;
};

type WeekdayAccumulator = {
  key: string;
  label: string;
  users: Set<string>;
  totalEvents: number;
  moodUsers: Set<string>;
  valenceMap: Map<string, BucketAccumulator>;
  moodMap: Map<string, BucketAccumulator>;
};

const SOURCE_LABELS: Record<EmotionalActivitySourceScope, string> = {
  all: "All approved sources (mood check-ins & assessments)",
  mood: "Mood check-ins only",
  assessment: "Well-being assessments only",
};

const VALENCE_LABELS: Record<"positive" | "neutral" | "strained", string> = {
  positive: "Positive (Levels 4-5)",
  neutral: "Steady / Tired (Level 3)",
  strained: "Strained / Distressed (Levels 1-2)",
};

// Aligned 1-to-1 with LogMoodScreen (_moodChoices in log_mood_screen.dart).
const CANONICAL_MOODS: Record<
  string,
  {key: string; label: string; level: number; valence: "positive" | "neutral" | "strained"}
> = {
  great: {key: "great", label: "Great", level: 5, valence: "positive"},
  excited: {key: "excited", label: "Excited", level: 5, valence: "positive"},
  okay: {key: "okay", label: "Okay", level: 4, valence: "positive"},
  tired: {key: "tired", label: "Tired", level: 3, valence: "neutral"},
  stressed: {key: "stressed", label: "Stressed", level: 2, valence: "strained"},
  sad: {key: "sad", label: "Sad", level: 1, valence: "strained"},
  angry: {key: "angry", label: "Angry", level: 1, valence: "strained"},
};

const STRAINED_OR_DRAINED_KEYS = new Set([
  "strained_combined",
  "stressed",
  "sad",
  "angry",
  "tired",
]);

const POSITIVE_MOOD_KEYS = new Set(["great", "excited", "okay"]);

const ASSESSMENT_BANDS = {
  supported: {key: "supported", label: "Generally Supported"},
  mostly_supported: {key: "mostly_supported", label: "Mostly Supported"},
  needs_attention: {key: "needs_attention", label: "Areas Needing Attention"},
  support_may_help: {key: "support_may_help", label: "Support May Help"},
} as const;

const WEEKDAY_META: ReadonlyArray<{key: string; label: string}> = [
  {key: "1_mon", label: "Mon"},
  {key: "2_tue", label: "Tue"},
  {key: "3_wed", label: "Wed"},
  {key: "4_thu", label: "Thu"},
  {key: "5_fri", label: "Fri"},
  {key: "6_sat", label: "Sat"},
  {key: "7_sun", label: "Sun"},
];

const SHORT_MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function round1(value: number): number {
  return Math.round(value * 10) / 10;
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

function percent(part: number, total: number): number {
  if (total <= 0) return 0;
  return round1((part / total) * 100);
}

function normalizedPopulationRole(user: RecordData): string {
  const raw = text(user.populationRole || user.declaredRole || user.role)
    .toLowerCase()
    .replace(/[\s_-]+/g, "");
  if (raw === "student") return "student";
  if (["faculty", "teaching", "teachingpersonnel"].includes(raw)) return "teaching";
  if (["staff", "nonteaching", "nonteachingpersonnel"].includes(raw)) {
    return "nonTeaching";
  }
  return "unspecified";
}

function dateValue(value: unknown): Date | undefined {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!trimmed) return undefined;
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
      const parsed = new Date(`${trimmed}T00:00:00+08:00`);
      return Number.isNaN(parsed.getTime()) ? undefined : parsed;
    }
    const parsed = new Date(trimmed);
    return Number.isNaN(parsed.getTime()) ? undefined : parsed;
  }
  return undefined;
}

function pad2(value: number): string {
  return String(value).padStart(2, "0");
}

function manilaCalendarParts(instant: Date): {
  year: number;
  month: number;
  day: number;
  isoWeekday: number; // 1 = Mon .. 7 = Sun
  dateKey: string;
} {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(instant);
  const year = Number(parts.find((p) => p.type === "year")?.value ?? "1970");
  const month = Number(parts.find((p) => p.type === "month")?.value ?? "1");
  const day = Number(parts.find((p) => p.type === "day")?.value ?? "1");
  const utcDay = new Date(Date.UTC(year, month - 1, day)).getUTCDay(); // 0=Sun..6=Sat
  const isoWeekday = utcDay === 0 ? 7 : utcDay;
  return {
    year,
    month,
    day,
    isoWeekday,
    dateKey: `${year}-${pad2(month)}-${pad2(day)}`,
  };
}

function manilaMonth(instant: Date): {key: string; label: string} {
  const parts = manilaCalendarParts(instant);
  return {
    key: `${parts.year}-${pad2(parts.month)}`,
    label: `${SHORT_MONTHS[parts.month - 1] ?? ""} ${parts.year}`,
  };
}

function manilaWeek(instant: Date): {
  weekKey: string;
  label: string;
  startUtcMs: number;
} {
  const parts = manilaCalendarParts(instant);
  const monday = new Date(Date.UTC(parts.year, parts.month - 1, parts.day - (parts.isoWeekday - 1)));
  const sunday = new Date(monday.getTime() + 6 * 86400000);
  const mYear = monday.getUTCFullYear();
  const mMonth = monday.getUTCMonth();
  const mDay = monday.getUTCDate();
  const sYear = sunday.getUTCFullYear();
  const sMonth = sunday.getUTCMonth();
  const sDay = sunday.getUTCDate();
  const weekKey = `${mYear}-${pad2(mMonth + 1)}-${pad2(mDay)}`;
  let label: string;
  if (mYear === sYear && mMonth === sMonth) {
    label = `${SHORT_MONTHS[mMonth]} ${mDay}-${sDay}, ${mYear}`;
  } else if (mYear === sYear) {
    label = `${SHORT_MONTHS[mMonth]} ${mDay}-${SHORT_MONTHS[sMonth]} ${sDay}, ${mYear}`;
  } else {
    label = `${SHORT_MONTHS[mMonth]} ${mDay}, ${mYear}-${SHORT_MONTHS[sMonth]} ${sDay}, ${sYear}`;
  }
  return {weekKey, label, startUtcMs: monday.getTime()};
}

function resolveUserDepartmentKeys(
  user: RecordData,
  collegeNameById: ReadonlyMap<string, string>,
): {primaryLabel: string; keys: Set<string>} {
  const collegeId = text(user.collegeId);
  const resolvedCollegeName = collegeId ? text(collegeNameById.get(collegeId)) : "";
  const department = text(user.department);
  const college = text(user.college);
  const primaryLabel = department || college || resolvedCollegeName || "Not specified";
  const keys = new Set<string>();
  for (const candidate of [department, college, resolvedCollegeName, collegeId]) {
    if (candidate) keys.add(candidate.toLocaleLowerCase("en-US"));
  }
  if (keys.size === 0) keys.add("not specified");
  return {primaryLabel, keys};
}

function resolveUserProgramKeys(
  user: RecordData,
  courseNameById: ReadonlyMap<string, string>,
): {primaryLabel: string; keys: Set<string>} {
  const courseId = text(user.courseId);
  const resolvedCourseName = courseId ? text(courseNameById.get(courseId)) : "";
  const course = text(user.course);
  const program = text(user.program);
  const primaryLabel = course || program || resolvedCourseName || "Not specified";
  const keys = new Set<string>();
  for (const candidate of [course, program, resolvedCourseName, courseId]) {
    if (candidate) keys.add(candidate.toLocaleLowerCase("en-US"));
  }
  if (keys.size === 0) keys.add("not specified");
  return {primaryLabel, keys};
}

function canonicalMood(record: RecordData): {
  key: string;
  label: string;
  level: number;
  valenceKey: "positive" | "neutral" | "strained";
} | null {
  if (record.archivedAt != null || record.deletedAt != null) return null;
  const rawLabel = text(record.label).toLocaleLowerCase("en-US");
  const matchedLabel = CANONICAL_MOODS[rawLabel];
  const numericLevel = typeof record.level === "number" ? record.level : Number(record.level);
  const hasValidLevel = Number.isFinite(numericLevel) && numericLevel >= 1 && numericLevel <= 5;
  if (matchedLabel) {
    return {
      key: matchedLabel.key,
      label: matchedLabel.label,
      level: hasValidLevel ? Math.round(numericLevel) : matchedLabel.level,
      valenceKey: matchedLabel.valence,
    };
  }
  if (!hasValidLevel) return null;
  const rounded = Math.round(numericLevel);
  if (rounded >= 5) return {key: "great", label: "Great", level: 5, valenceKey: "positive"};
  if (rounded === 4) return {key: "okay", label: "Okay", level: 4, valenceKey: "positive"};
  if (rounded === 3) return {key: "tired", label: "Tired", level: 3, valenceKey: "neutral"};
  if (rounded === 2) return {key: "stressed", label: "Stressed", level: 2, valenceKey: "strained"};
  return {key: "sad", label: "Sad", level: 1, valenceKey: "strained"};
}

function resolveEntryMethod(record: RecordData): {key: string; label: string} {
  const method = text(record.entryMethod).toLowerCase();
  if (method === "expression_assisted" || record.expressionAssistUsed === true) {
    return {key: "expression_assisted", label: "Expression-assisted"};
  }
  return {key: "manual", label: "Manual check-in"};
}

function mapStatusString(raw: string): keyof typeof ASSESSMENT_BANDS | null {
  const key = raw.toLowerCase().replace(/[\s_-]+/g, "");
  if (["generallysupported", "supported", "thriving", "good", "low"].includes(key)) {
    return "supported";
  }
  if (["mostlysupported", "stable", "moderate", "watchful"].includes(key)) {
    return "mostly_supported";
  }
  if (["someareasneedattention", "somestrain", "needsimprovement", "elevated", "high"].includes(key)) {
    return "needs_attention";
  }
  if (["supportmayhelp", "atrisk", "severe"].includes(key)) {
    return "support_may_help";
  }
  return null;
}

function canonicalAssessmentBand(
  record: RecordData,
): {key: string; label: string; valenceKey: "positive" | "neutral" | "strained"} | null {
  if (
    record.archivedAt != null ||
    record.deletedAt != null ||
    record.privacyOptOut === true ||
    record.reportConsent === false ||
    record.consent === false
  ) {
    return null;
  }
  const verificationStatus = text(record.verificationStatus).toLowerCase();
  const topStatus = text(record.status).toLowerCase();
  if (verificationStatus === "rejected" || topStatus === "draft") {
    return null;
  }

  let mapped: keyof typeof ASSESSMENT_BANDS | null = null;
  const result = record.result;
  if (result && typeof result === "object" && !Array.isArray(result)) {
    const resultObj = result as RecordData;
    if (Array.isArray(resultObj.domainResults)) {
      const emotionalDomain = resultObj.domainResults.find(
        (d) =>
          d &&
          typeof d === "object" &&
          (d as RecordData).domainId === "emotionalWellbeing" &&
          (d as RecordData).isScorable !== false,
      ) as RecordData | undefined;
      if (emotionalDomain) {
        mapped = mapStatusString(text(emotionalDomain.status));
      }
    }
    if (!mapped) {
      mapped = mapStatusString(text(resultObj.profileStatus));
    }
  }
  if (!mapped) {
    mapped = mapStatusString(topStatus);
  }
  if (!mapped) return null;

  const band = ASSESSMENT_BANDS[mapped];
  const valenceKey =
    mapped === "supported"
      ? "positive"
      : mapped === "mostly_supported"
      ? "neutral"
      : "strained";
  return {key: band.key, label: band.label, valenceKey};
}

function addToBucket(
  map: Map<string, BucketAccumulator>,
  key: string,
  label: string,
  userId: string,
): void {
  const current = map.get(key);
  if (current) {
    current.users.add(userId);
    current.events += 1;
    return;
  }
  map.set(key, {key, label, users: new Set([userId]), events: 1});
}

function finalizeBuckets(
  map: Map<string, BucketAccumulator>,
  order: "percentage" | "chronological",
  threshold = MIN_EMOTIONAL_COHORT_SIZE,
): EmotionalActivityBucket[] {
  const nonEmpty = [...map.values()].filter((b) => b.events > 0 && b.users.size > 0);
  if (nonEmpty.length === 0) return [];

  const totalEvents = nonEmpty.reduce((sum, b) => sum + b.events, 0);
  const suppressedKeys = new Set<string>();
  for (const bucket of nonEmpty) {
    if (bucket.users.size < threshold) {
      suppressedKeys.add(bucket.key);
    }
  }
  // Prevent subtraction inference (100% - sum(visible)) when only one cell is < 10.
  if (suppressedKeys.size === 1 && nonEmpty.length >= 2) {
    const unsuppressed = nonEmpty
      .filter((b) => !suppressedKeys.has(b.key))
      .sort((a, b) => a.users.size - b.users.size || a.events - b.events);
    if (unsuppressed.length > 0) {
      suppressedKeys.add(unsuppressed[0].key);
    }
  }

  const mapped = nonEmpty.map((bucket): EmotionalActivityBucket => {
    const isSuppressed = suppressedKeys.has(bucket.key);
    return {
      key: bucket.key,
      label: bucket.label,
      percentage: isSuppressed ? null : percent(bucket.events, totalEvents),
      suppressed: isSuppressed,
    };
  });

  if (order === "chronological") {
    return mapped.sort((a, b) => a.key.localeCompare(b.key));
  }
  return mapped.sort(
    (a, b) =>
      (b.percentage ?? -1) - (a.percentage ?? -1) || a.label.localeCompare(b.label),
  );
}

function getOrCreateWeek(
  map: Map<string, WeekAccumulator>,
  weekKey: string,
  label: string,
): WeekAccumulator {
  const existing = map.get(weekKey);
  if (existing) return existing;
  const created: WeekAccumulator = {
    weekKey,
    label,
    users: new Set<string>(),
    totalEvents: 0,
    moodUsers: new Set<string>(),
    moodEvents: 0,
    moodLevelSum: 0,
    valenceMap: new Map<string, BucketAccumulator>(),
    moodMap: new Map<string, BucketAccumulator>(),
  };
  map.set(weekKey, created);
  return created;
}

function recordWeekMood(
  week: WeekAccumulator,
  uid: string,
  mood: {key: string; label: string; level: number; valenceKey: "positive" | "neutral" | "strained"},
): void {
  week.users.add(uid);
  week.totalEvents += 1;
  week.moodUsers.add(uid);
  week.moodEvents += 1;
  week.moodLevelSum += mood.level;
  addToBucket(week.moodMap, mood.key, mood.label, uid);
  addToBucket(week.valenceMap, mood.valenceKey, VALENCE_LABELS[mood.valenceKey], uid);
}

function recordWeekAssessment(
  week: WeekAccumulator,
  uid: string,
  band: {key: string; label: string; valenceKey: "positive" | "neutral" | "strained"},
): void {
  week.users.add(uid);
  week.totalEvents += 1;
  addToBucket(week.valenceMap, band.valenceKey, VALENCE_LABELS[band.valenceKey], uid);
}

function finalizeSingleWeek(
  week: WeekAccumulator,
  activityShare: number | null,
  forceSuppressed: boolean,
): EmotionalActivityWeeklyTrend {
  if (forceSuppressed || week.users.size < MIN_EMOTIONAL_COHORT_SIZE) {
    return {
      weekKey: week.weekKey,
      label: week.label,
      suppressed: true,
      activityShare: null,
      averageMoodLevel: null,
      dominantMoodKey: null,
      dominantMoodLabel: null,
      strainedShare: null,
      valenceBreakdown: [],
      moodBreakdown: [],
    };
  }
  const valenceBreakdown = finalizeBuckets(week.valenceMap, "percentage");
  const moodBreakdown =
    week.moodUsers.size >= MIN_EMOTIONAL_COHORT_SIZE
      ? finalizeBuckets(week.moodMap, "percentage")
      : [];
  const topMood = moodBreakdown.find((b) => !b.suppressed && b.percentage != null);
  const strainedBucket = valenceBreakdown.find((b) => b.key === "strained");
  const strainedShare =
    strainedBucket == null
      ? valenceBreakdown.some((b) => !b.suppressed && b.percentage != null)
        ? 0
        : null
      : strainedBucket.suppressed
      ? null
      : strainedBucket.percentage;
  const averageMoodLevel =
    week.moodUsers.size >= MIN_EMOTIONAL_COHORT_SIZE && week.moodEvents > 0
      ? round2(week.moodLevelSum / week.moodEvents)
      : null;

  return {
    weekKey: week.weekKey,
    label: week.label,
    suppressed: false,
    activityShare,
    averageMoodLevel,
    dominantMoodKey: topMood?.key ?? null,
    dominantMoodLabel: topMood?.label ?? null,
    strainedShare,
    valenceBreakdown,
    moodBreakdown,
  };
}

function finalizeWeeklyTrends(
  weekMap: Map<string, WeekAccumulator>,
): EmotionalActivityWeeklyTrend[] {
  const activityBuckets = new Map<string, BucketAccumulator>();
  for (const week of weekMap.values()) {
    activityBuckets.set(week.weekKey, {
      key: week.weekKey,
      label: week.label,
      users: week.users,
      events: week.totalEvents,
    });
  }
  const finalizedActivity = finalizeBuckets(activityBuckets, "chronological");
  const shareByKey = new Map(finalizedActivity.map((b) => [b.key, b]));

  return [...weekMap.values()]
    .sort((a, b) => a.weekKey.localeCompare(b.weekKey))
    .map((week) => {
      const shareBucket = shareByKey.get(week.weekKey);
      const isWeekBelowThreshold = week.users.size < MIN_EMOTIONAL_COHORT_SIZE;
      return finalizeSingleWeek(
        week,
        shareBucket && !shareBucket.suppressed ? shareBucket.percentage : null,
        isWeekBelowThreshold,
      );
    });
}

function classifyElevation(
  key: string,
  current: number,
  deltaPoints: number,
): ElevationSeverity {
  if (STRAINED_OR_DRAINED_KEYS.has(key)) {
    if (
      deltaPoints >= 5.0 ||
      (key === "strained_combined" && current >= 35.0 && deltaPoints >= 3.0)
    ) {
      return "elevated";
    }
    if (deltaPoints >= 2.5) return "watch";
    if (deltaPoints <= -5.0) return "improving";
    return "stable";
  }
  if (POSITIVE_MOOD_KEYS.has(key)) {
    if (deltaPoints >= 5.0) return "improving";
    if (deltaPoints <= -5.0) return "watch";
    return "stable";
  }
  return "stable";
}

function formatSignedDelta(delta: number): string {
  const prefix = delta > 0 ? "+" : "";
  return `${prefix}${delta.toFixed(1)} pp`;
}

function buildElevationSignals(
  inRangeWeeks: EmotionalActivityWeeklyTrend[],
  lookbackWeeks: EmotionalActivityWeeklyTrend[],
): EmotionalActivityElevationSignal[] {
  const reportableInRange = inRangeWeeks.filter((w) => !w.suppressed);
  if (reportableInRange.length === 0) return [];

  const latest = reportableInRange[reportableInRange.length - 1];
  const priorPool = [
    ...lookbackWeeks.filter((w) => !w.suppressed && w.weekKey < latest.weekKey),
    ...reportableInRange.slice(0, -1),
  ].sort((a, b) => a.weekKey.localeCompare(b.weekKey));

  const baselineWeeks = priorPool.slice(-4);
  if (baselineWeeks.length === 0) return [];

  const priorWeek = baselineWeeks[baselineWeeks.length - 1];
  const baselineLabel =
    baselineWeeks.length === 1
      ? `Prior week (${priorWeek.label})`
      : `Prior ${baselineWeeks.length}-week baseline`;

  const signals: EmotionalActivityElevationSignal[] = [];

  const pushSignal = (
    key: string,
    label: string,
    currentPct: number,
    baselineValues: number[],
    prevPct: number | null,
  ) => {
    if (baselineValues.length === 0) return;
    const baselinePct = round1(
      baselineValues.reduce((sum, v) => sum + v, 0) / baselineValues.length,
    );
    const deltaPoints = round1(currentPct - baselinePct);
    const weekOverWeekDelta = prevPct != null ? round1(currentPct - prevPct) : null;
    const severity = classifyElevation(key, currentPct, deltaPoints);

    let summary: string;
    if (severity === "elevated") {
      summary = `${label} is elevated at ${currentPct.toFixed(1)}% in ${latest.label} (${formatSignedDelta(deltaPoints)} vs. ${baselineLabel.toLowerCase()} of ${baselinePct.toFixed(1)}%).`;
    } else if (severity === "watch") {
      summary = `${label} shifted to ${currentPct.toFixed(1)}% in ${latest.label} (${formatSignedDelta(deltaPoints)} vs. ${baselineLabel.toLowerCase()} of ${baselinePct.toFixed(1)}%).`;
    } else if (severity === "improving") {
      summary = `${label} improved to ${currentPct.toFixed(1)}% in ${latest.label} (${formatSignedDelta(deltaPoints)} vs. ${baselineLabel.toLowerCase()} of ${baselinePct.toFixed(1)}%).`;
    } else {
      summary = `${label} remained steady at ${currentPct.toFixed(1)}% in ${latest.label} (${formatSignedDelta(deltaPoints)} vs. ${baselineLabel.toLowerCase()}).`;
    }

    signals.push({
      key,
      label,
      severity,
      currentWeekLabel: latest.label,
      baselineLabel,
      currentPercentage: currentPct,
      baselinePercentage: baselinePct,
      deltaPoints,
      weekOverWeekDelta,
      summary,
    });
  };

  // 1. Combined Strained (Stressed + Sad + Angry) signal.
  if (latest.strainedShare != null) {
    const baselineStrained = baselineWeeks
      .map((w) => w.strainedShare)
      .filter((v): v is number => v != null);
    pushSignal(
      "strained_combined",
      "Combined Strained (Stressed/Sad/Angry)",
      latest.strainedShare,
      baselineStrained,
      priorWeek.strainedShare,
    );
  }

  // 2. Per-mood elevation signals aligned to the 7 Log-your-Mood states.
  const moodValue = (week: EmotionalActivityWeeklyTrend, moodKey: string): number | null => {
    if (week.moodBreakdown.length === 0) return null;
    const found = week.moodBreakdown.find((b) => b.key === moodKey);
    if (!found) {
      // Only treat absent mood as 0% when other moods are visible in that week.
      return week.moodBreakdown.some((b) => !b.suppressed && b.percentage != null) ? 0 : null;
    }
    return found.suppressed ? null : found.percentage;
  };

  for (const mood of Object.values(CANONICAL_MOODS)) {
    const currentBucket = latest.moodBreakdown.find((b) => b.key === mood.key);
    if (!currentBucket || currentBucket.suppressed || currentBucket.percentage == null) {
      continue;
    }
    const baselineVals = baselineWeeks
      .map((w) => moodValue(w, mood.key))
      .filter((v): v is number => v != null);
    pushSignal(
      mood.key,
      mood.label,
      currentBucket.percentage,
      baselineVals,
      moodValue(priorWeek, mood.key),
    );
  }

  const severityRank: Record<ElevationSeverity, number> = {
    elevated: 0,
    watch: 1,
    improving: 2,
    stable: 3,
  };

  signals.sort(
    (a, b) =>
      severityRank[a.severity] - severityRank[b.severity] ||
      Math.abs(b.deltaPoints) - Math.abs(a.deltaPoints) ||
      a.label.localeCompare(b.label),
  );

  const notable = signals.filter((s) => s.severity !== "stable");
  if (notable.length > 0) return notable;
  return signals.slice(0, 2);
}

function finalizeWeekdays(
  weekdayMap: Map<string, WeekdayAccumulator>,
): EmotionalActivityWeekdayBucket[] {
  const activityMap = new Map<string, BucketAccumulator>();
  for (const day of weekdayMap.values()) {
    activityMap.set(day.key, {
      key: day.key,
      label: day.label,
      users: day.users,
      events: day.totalEvents,
    });
  }
  const finalizedActivity = finalizeBuckets(activityMap, "chronological");
  const shareByKey = new Map(finalizedActivity.map((b) => [b.key, b]));

  return WEEKDAY_META.filter((meta) => weekdayMap.has(meta.key)).map((meta) => {
    const acc = weekdayMap.get(meta.key)!;
    const shareBucket = shareByKey.get(meta.key);
    const isSuppressed = acc.users.size < MIN_EMOTIONAL_COHORT_SIZE;
    if (isSuppressed) {
      return {
        key: meta.key,
        label: meta.label,
        activityShare: null,
        strainedShare: null,
        dominantMoodLabel: null,
        suppressed: true,
      };
    }

    const valence = finalizeBuckets(acc.valenceMap, "percentage");
    const strainedBucket = valence.find((b) => b.key === "strained");
    const strainedShare =
      strainedBucket == null
        ? valence.some((b) => !b.suppressed && b.percentage != null)
          ? 0
          : null
        : strainedBucket.suppressed
        ? null
        : strainedBucket.percentage;

    const moodBuckets =
      acc.moodUsers.size >= MIN_EMOTIONAL_COHORT_SIZE
        ? finalizeBuckets(acc.moodMap, "percentage")
        : [];
    const topMood = moodBuckets.find((b) => !b.suppressed && b.percentage != null);

    return {
      key: meta.key,
      label: meta.label,
      activityShare:
        shareBucket && !shareBucket.suppressed ? shareBucket.percentage : null,
      strainedShare,
      dominantMoodLabel: topMood?.label ?? null,
      suppressed: false,
    };
  });
}

function buildActionableInsights(input: {
  elevatedSignals: EmotionalActivityElevationSignal[];
  weeklyTrends: EmotionalActivityWeeklyTrend[];
  weekdayBreakdown: EmotionalActivityWeekdayBucket[];
  moodEngagement: EmotionalActivityMoodEngagement | null;
  moodBreakdown: EmotionalActivityBucket[];
  assessmentBreakdown: EmotionalActivityBucket[];
}): string[] {
  const insights: string[] = [];

  const elevated = input.elevatedSignals.filter((s) => s.severity === "elevated");
  const watching = input.elevatedSignals.filter((s) => s.severity === "watch");
  const improving = input.elevatedSignals.filter((s) => s.severity === "improving");

  if (elevated.length > 0) {
    const primary = elevated[0];
    insights.push(
      `${primary.summary} Consider highlighting relevant coping guides in Insights Content or scheduling a targeted PACC wellness reminder.`,
    );
  } else if (watching.length > 0) {
    insights.push(
      `Early shift to monitor: ${watching[0].summary}`,
    );
  } else if (improving.length > 0) {
    insights.push(
      `Positive weekly momentum: ${improving[0].summary}`,
    );
  } else if (input.weeklyTrends.filter((w) => !w.suppressed).length >= 2) {
    insights.push(
      "Weekly mood shares stayed within normal baseline variation with no strained mood elevated above the +5.0 pp alert threshold.",
    );
  }

  const reportableWeekdays = input.weekdayBreakdown.filter(
    (d) => !d.suppressed && d.strainedShare != null,
  );
  if (reportableWeekdays.length > 0) {
    const peakDay = [...reportableWeekdays].sort(
      (a, b) => (b.strainedShare ?? -1) - (a.strainedShare ?? -1),
    )[0];
    if ((peakDay.strainedShare ?? 0) >= 25) {
      insights.push(
        `Strained check-ins peak on ${peakDay.label} (${peakDay.strainedShare!.toFixed(1)}% strained share). Timing wellness prompts or counselor availability notices around ${peakDay.label} may improve support reach.`,
      );
    }
  }

  if (
    input.moodEngagement != null &&
    input.moodEngagement.avgCheckInsPerParticipant != null
  ) {
    const repeatText =
      input.moodEngagement.repeatParticipantRate != null
        ? ` with ${input.moodEngagement.repeatParticipantRate.toFixed(1)}% checking in across multiple days`
        : "";
    const avgScoreText =
      input.moodEngagement.averageMoodLevel != null
        ? ` (average mood score ${input.moodEngagement.averageMoodLevel.toFixed(2)} / 5.00)`
        : "";
    insights.push(
      `Active mood loggers averaged ${input.moodEngagement.avgCheckInsPerParticipant.toFixed(1)} check-ins per participant${repeatText}${avgScoreText}.`,
    );
  }

  const topStrainedAssessment = input.assessmentBreakdown.find(
    (b) =>
      (b.key === "needs_attention" || b.key === "support_may_help") &&
      !b.suppressed &&
      b.percentage != null &&
      b.percentage >= 25,
  );
  const topStrainedMood = input.moodBreakdown.find(
    (b) =>
      (b.key === "stressed" || b.key === "sad" || b.key === "angry") &&
      !b.suppressed &&
      b.percentage != null &&
      b.percentage >= 20,
  );
  if (topStrainedAssessment && topStrainedMood) {
    insights.push(
      `Cross-source alignment: elevated ${topStrainedMood.label} check-ins (${topStrainedMood.percentage!.toFixed(1)}%) coincide with ${topStrainedAssessment.label} assessment patterns (${topStrainedAssessment.percentage!.toFixed(1)}%).`,
    );
  }

  if (insights.length > 0) {
    insights.push(
      "Aggregate wellness indicators reflect self-reported patterns (n >= 10) and are intended for preventive campus planning, not clinical diagnosis.",
    );
  }

  return insights;
}

export function buildEmotionalActivityReport(input: {
  users: Array<{id: string; data: RecordData}>;
  moodEntries: RecordData[];
  moods: RecordData[];
  assessments: RecordData[];
  range: {start: Date; end: Date; label: string};
  schoolYear: string;
  userCategory?: string;
  department?: string;
  program?: string;
  source?: EmotionalActivitySourceScope;
  configuredPopulation?: number | null;
  collegeNameById?: ReadonlyMap<string, string>;
  courseNameById?: ReadonlyMap<string, string>;
}): EmotionalActivityReport {
  const source: EmotionalActivitySourceScope = input.source ?? "all";
  const requestedCategory = input.userCategory ?? "all";
  const requestedDept = (input.department ?? "all").toLocaleLowerCase("en-US");
  const requestedProgram = (input.program ?? "all").toLocaleLowerCase("en-US");
  const collegeNameById = input.collegeNameById ?? new Map<string, string>();
  const courseNameById = input.courseNameById ?? new Map<string, string>();

  const appUsers = input.users.filter(({data}) => {
    const legacyRole = text(data.role).toLowerCase().replace(/[\s_-]+/g, "");
    if (["admin", "superadmin", "counselor", "portalstaff"].includes(legacyRole)) {
      return false;
    }
    const accessRole = text(data.accessRole) || "appUser";
    return accessRole === "appUser" && data.staffAccountStatus == null;
  });

  const scopedUsers = new Map<string, {roleKey: string; primaryDept: string}>();
  for (const {id, data} of appUsers) {
    const roleKey = normalizedPopulationRole(data);
    if (requestedCategory !== "all" && roleKey !== requestedCategory) continue;
    const dept = resolveUserDepartmentKeys(data, collegeNameById);
    if (requestedDept !== "all" && !dept.keys.has(requestedDept)) continue;
    const prog = resolveUserProgramKeys(data, courseNameById);
    if (requestedProgram !== "all" && !prog.keys.has(requestedProgram)) continue;
    scopedUsers.set(id, {roleKey, primaryDept: dept.primaryLabel});
  }

  const participants = new Set<string>();
  const participantCategories = new Set<string>();
  const valenceMap = new Map<string, BucketAccumulator>();
  const moodMap = new Map<string, BucketAccumulator>();
  const assessmentMap = new Map<string, BucketAccumulator>();
  const periodMap = new Map<string, BucketAccumulator>();
  const weekMap = new Map<string, WeekAccumulator>();
  const lookbackWeekMap = new Map<string, WeekAccumulator>();
  const weekdayMap = new Map<string, WeekdayAccumulator>();
  const entryMethodMap = new Map<string, BucketAccumulator>();
  const moodUsers = new Set<string>();
  const moodDaysByUser = new Map<string, Set<string>>();
  const assessmentUsers = new Set<string>();
  let moodEventCount = 0;
  let moodLevelSum = 0;
  let assessmentEventCount = 0;
  let missingDemographicsCount = 0;

  // 4-week lookback window before range.start so weekly elevation baselines work
  // even when viewing a short custom range (e.g. a single week).
  const rangeStartWeek = manilaWeek(input.range.start);
  const lookbackStartMs = rangeStartWeek.startUtcMs - 4 * 7 * 86400000;

  const matchesAcademicYear = (record: RecordData): boolean => {
    const recordYear = text(record.academicYearId);
    return !recordYear || recordYear === input.schoolYear;
  };

  const inRange = (record: RecordData, instant: Date | undefined): boolean => {
    const recordYear = text(record.academicYearId);
    if (recordYear) {
      if (recordYear !== input.schoolYear) return false;
      if (!instant) return true;
      return instant >= input.range.start && instant < input.range.end;
    }
    return Boolean(instant && instant >= input.range.start && instant < input.range.end);
  };

  const inLookback = (record: RecordData, instant: Date | undefined): boolean => {
    if (!instant || !matchesAcademicYear(record)) return false;
    return instant.getTime() >= lookbackStartMs && instant < input.range.start;
  };

  const getOrCreateWeekday = (instant: Date): WeekdayAccumulator => {
    const parts = manilaCalendarParts(instant);
    const meta = WEEKDAY_META[parts.isoWeekday - 1];
    const existing = weekdayMap.get(meta.key);
    if (existing) return existing;
    const created: WeekdayAccumulator = {
      key: meta.key,
      label: meta.label,
      users: new Set<string>(),
      totalEvents: 0,
      moodUsers: new Set<string>(),
      valenceMap: new Map<string, BucketAccumulator>(),
      moodMap: new Map<string, BucketAccumulator>(),
    };
    weekdayMap.set(meta.key, created);
    return created;
  };

  const trackParticipant = (uid: string, monthInfo?: {key: string; label: string}) => {
    const userMeta = scopedUsers.get(uid);
    if (!userMeta) return;
    if (!participants.has(uid) && (userMeta.roleKey === "unspecified" || userMeta.primaryDept === "Not specified")) {
      missingDemographicsCount += 1;
    }
    participants.add(uid);
    participantCategories.add(userMeta.roleKey);
    if (monthInfo) {
      addToBucket(periodMap, monthInfo.key, monthInfo.label, uid);
    }
  };

  if (source === "all" || source === "mood") {
    const seenMoodKeys = new Set<string>();
    for (const entry of [...input.moodEntries, ...input.moods]) {
      const uid = text(entry.userId);
      if (!uid || !scopedUsers.has(uid)) continue;

      const reqId = text(entry.clientRequestId);
      const docId = text(entry.entryId || entry.id);
      const dedupeKey = reqId
        ? `${uid}:req:${reqId}`
        : docId
        ? `${uid}:id:${docId}`
        : null;
      if (dedupeKey) {
        if (seenMoodKeys.has(dedupeKey)) continue;
        seenMoodKeys.add(dedupeKey);
      }

      const instant =
        dateValue(entry.occurredAt) ||
        dateValue(entry.createdAt) ||
        dateValue(entry.dateKey);
      const mood = canonicalMood(entry);
      if (!mood) continue;

      if (inRange(entry, instant)) {
        trackParticipant(uid, instant ? manilaMonth(instant) : undefined);
        moodUsers.add(uid);
        moodEventCount += 1;
        moodLevelSum += mood.level;
        addToBucket(moodMap, mood.key, mood.label, uid);
        addToBucket(valenceMap, mood.valenceKey, VALENCE_LABELS[mood.valenceKey], uid);

        const method = resolveEntryMethod(entry);
        addToBucket(entryMethodMap, method.key, method.label, uid);

        if (instant) {
          const cal = manilaCalendarParts(instant);
          let userDays = moodDaysByUser.get(uid);
          if (!userDays) {
            userDays = new Set<string>();
            moodDaysByUser.set(uid, userDays);
          }
          userDays.add(cal.dateKey);

          const wk = manilaWeek(instant);
          recordWeekMood(getOrCreateWeek(weekMap, wk.weekKey, wk.label), uid, mood);

          const wd = getOrCreateWeekday(instant);
          wd.users.add(uid);
          wd.totalEvents += 1;
          wd.moodUsers.add(uid);
          addToBucket(wd.moodMap, mood.key, mood.label, uid);
          addToBucket(wd.valenceMap, mood.valenceKey, VALENCE_LABELS[mood.valenceKey], uid);
        }
      } else if (inLookback(entry, instant) && instant) {
        const wk = manilaWeek(instant);
        recordWeekMood(getOrCreateWeek(lookbackWeekMap, wk.weekKey, wk.label), uid, mood);
      }
    }
  }

  if (source === "all" || source === "assessment") {
    for (const assessment of input.assessments) {
      const uid = text(assessment.userId);
      if (!uid || !scopedUsers.has(uid)) continue;
      const instant =
        dateValue(assessment.submittedAt) ||
        dateValue(assessment.createdAt) ||
        dateValue(assessment.verifiedAt);
      const band = canonicalAssessmentBand(assessment);
      if (!band) continue;

      if (inRange(assessment, instant)) {
        trackParticipant(uid, instant ? manilaMonth(instant) : undefined);
        assessmentUsers.add(uid);
        assessmentEventCount += 1;
        addToBucket(assessmentMap, band.key, band.label, uid);
        addToBucket(valenceMap, band.valenceKey, VALENCE_LABELS[band.valenceKey], uid);

        if (instant) {
          const wk = manilaWeek(instant);
          recordWeekAssessment(getOrCreateWeek(weekMap, wk.weekKey, wk.label), uid, band);

          const wd = getOrCreateWeekday(instant);
          wd.users.add(uid);
          wd.totalEvents += 1;
          addToBucket(wd.valenceMap, band.valenceKey, VALENCE_LABELS[band.valenceKey], uid);
        }
      } else if (inLookback(assessment, instant) && instant) {
        const wk = manilaWeek(instant);
        recordWeekAssessment(getOrCreateWeek(lookbackWeekMap, wk.weekKey, wk.label), uid, band);
      }
    }
  }

  const departmentCoverageNote =
    missingDemographicsCount > 0 && participants.size >= MIN_EMOTIONAL_COHORT_SIZE
      ? "Some participants have unspecified role or college metadata and appear under Category not specified / Not specified when viewing all."
      : requestedProgram !== "all"
      ? "Filtered strictly to the selected college and program within your access scope."
      : requestedDept === "all"
      ? "Includes all app-user colleges/departments within your access scope."
      : "Filtered to the selected college/department only.";

  if (participants.size === 0) {
    return {
      status: "no_data",
      suppressed: false,
      suppressionThreshold: MIN_EMOTIONAL_COHORT_SIZE,
      suppressionReason: null,
      sourceScopeKey: source,
      sourceScopeLabel: SOURCE_LABELS[source],
      schoolYear: input.schoolYear,
      dateRangeLabel: input.range.label,
      participationRate: null,
      appUserCohortShare: null,
      dominantValenceLabel: null,
      hasMixedCategories: false,
      moodCheckInShare: null,
      assessmentShare: null,
      valenceBreakdown: [],
      moodBreakdown: [],
      assessmentBreakdown: [],
      periodTrends: [],
      weeklyTrends: [],
      elevatedMoodSignals: [],
      weekdayBreakdown: [],
      moodEngagement: null,
      actionableInsights: [],
      departmentCoverageNote,
    };
  }

  if (participants.size < MIN_EMOTIONAL_COHORT_SIZE) {
    return {
      status: "suppressed",
      suppressed: true,
      suppressionThreshold: MIN_EMOTIONAL_COHORT_SIZE,
      suppressionReason:
        "Suppressed to protect privacy: fewer than 10 unique participants matched the active filters.",
      sourceScopeKey: source,
      sourceScopeLabel: SOURCE_LABELS[source],
      schoolYear: input.schoolYear,
      dateRangeLabel: input.range.label,
      participationRate: null,
      appUserCohortShare: null,
      dominantValenceLabel: null,
      hasMixedCategories: false,
      moodCheckInShare: null,
      assessmentShare: null,
      valenceBreakdown: [],
      moodBreakdown: [],
      assessmentBreakdown: [],
      periodTrends: [],
      weeklyTrends: [],
      elevatedMoodSignals: [],
      weekdayBreakdown: [],
      moodEngagement: null,
      actionableInsights: [],
      departmentCoverageNote,
    };
  }

  const valenceBreakdown = finalizeBuckets(valenceMap, "percentage");
  const moodBreakdown =
    moodUsers.size >= MIN_EMOTIONAL_COHORT_SIZE
      ? finalizeBuckets(moodMap, "percentage")
      : [];
  const assessmentBreakdown =
    assessmentUsers.size >= MIN_EMOTIONAL_COHORT_SIZE
      ? finalizeBuckets(assessmentMap, "percentage")
      : [];
  const periodTrends = finalizeBuckets(periodMap, "chronological");
  const weeklyTrends = finalizeWeeklyTrends(weekMap);
  const lookbackTrends = finalizeWeeklyTrends(lookbackWeekMap);
  const elevatedMoodSignals = buildElevationSignals(weeklyTrends, lookbackTrends);
  const weekdayBreakdown = finalizeWeekdays(weekdayMap);

  let moodEngagement: EmotionalActivityMoodEngagement | null = null;
  if (moodUsers.size >= MIN_EMOTIONAL_COHORT_SIZE && moodEventCount > 0) {
    const repeatBuckets = new Map<string, BucketAccumulator>();
    for (const uid of moodUsers) {
      const dayCount = moodDaysByUser.get(uid)?.size ?? 1;
      if (dayCount >= 2) {
        addToBucket(repeatBuckets, "repeat", "Multi-day participants", uid);
      } else {
        addToBucket(repeatBuckets, "single", "Single-day participants", uid);
      }
    }
    const finalizedRepeat = finalizeBuckets(repeatBuckets, "percentage");
    const repeatBucket = finalizedRepeat.find((b) => b.key === "repeat");
    const repeatParticipantRate =
      repeatBucket == null
        ? finalizedRepeat.some((b) => !b.suppressed && b.percentage != null)
          ? 0
          : null
        : repeatBucket.suppressed
        ? null
        : repeatBucket.percentage;

    moodEngagement = {
      averageMoodLevel: round2(moodLevelSum / moodEventCount),
      avgCheckInsPerParticipant: round1(moodEventCount / moodUsers.size),
      repeatParticipantRate,
      entryMethodBreakdown: finalizeBuckets(entryMethodMap, "percentage"),
    };
  }

  const actionableInsights = buildActionableInsights({
    elevatedSignals: elevatedMoodSignals,
    weeklyTrends,
    weekdayBreakdown,
    moodEngagement,
    moodBreakdown,
    assessmentBreakdown,
  });

  const topValence = valenceBreakdown.find((b) => !b.suppressed && b.percentage != null);
  const totalEvents = moodEventCount + assessmentEventCount;
  const canSplitSources =
    source === "all" &&
    moodUsers.size >= MIN_EMOTIONAL_COHORT_SIZE &&
    assessmentUsers.size >= MIN_EMOTIONAL_COHORT_SIZE &&
    totalEvents > 0;

  const populationApplies =
    (requestedCategory === "all" || requestedCategory === "student") &&
    input.configuredPopulation != null &&
    input.configuredPopulation > 0;

  return {
    status: "ready",
    suppressed: false,
    suppressionThreshold: MIN_EMOTIONAL_COHORT_SIZE,
    suppressionReason: null,
    sourceScopeKey: source,
    sourceScopeLabel: SOURCE_LABELS[source],
    schoolYear: input.schoolYear,
    dateRangeLabel: input.range.label,
    participationRate: populationApplies
      ? percent(participants.size, input.configuredPopulation!)
      : null,
    appUserCohortShare:
      scopedUsers.size >= MIN_EMOTIONAL_COHORT_SIZE
        ? percent(participants.size, scopedUsers.size)
        : null,
    dominantValenceLabel: topValence ? topValence.label : null,
    hasMixedCategories: participantCategories.size > 1,
    moodCheckInShare: canSplitSources ? percent(moodEventCount, totalEvents) : null,
    assessmentShare: canSplitSources ? percent(assessmentEventCount, totalEvents) : null,
    valenceBreakdown,
    moodBreakdown,
    assessmentBreakdown,
    periodTrends,
    weeklyTrends,
    elevatedMoodSignals,
    weekdayBreakdown,
    moodEngagement,
    actionableInsights,
    departmentCoverageNote,
  };
}
