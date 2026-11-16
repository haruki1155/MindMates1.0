import {Timestamp} from "firebase-admin/firestore";

export const MIN_EMOTIONAL_COHORT_SIZE = 10;

export type EmotionalActivitySourceScope = "all" | "mood" | "assessment";
export type EmotionalActivityStatus = "ready" | "suppressed" | "no_data";

export interface EmotionalActivityBucket {
  key: string;
  label: string;
  percentage: number | null;
  suppressed: boolean;
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
  departmentCoverageNote: string;
}

type RecordData = Record<string, unknown>;

type BucketAccumulator = {
  key: string;
  label: string;
  users: Set<string>;
  events: number;
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

const CANONICAL_MOODS: Record<
  string,
  {key: string; label: string; valence: "positive" | "neutral" | "strained"}
> = {
  great: {key: "great", label: "Great", valence: "positive"},
  excited: {key: "excited", label: "Excited", valence: "positive"},
  okay: {key: "okay", label: "Okay", valence: "positive"},
  tired: {key: "tired", label: "Tired", valence: "neutral"},
  stressed: {key: "stressed", label: "Stressed", valence: "strained"},
  sad: {key: "sad", label: "Sad", valence: "strained"},
  angry: {key: "angry", label: "Angry", valence: "strained"},
};

const ASSESSMENT_BANDS = {
  supported: {key: "supported", label: "Generally Supported"},
  mostly_supported: {key: "mostly_supported", label: "Mostly Supported"},
  needs_attention: {key: "needs_attention", label: "Areas Needing Attention"},
  support_may_help: {key: "support_may_help", label: "Support May Help"},
} as const;

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function percent(part: number, total: number): number {
  if (total <= 0) return 0;
  return Math.round((part / total) * 1000) / 10;
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

function manilaMonth(instant: Date): {key: string; label: string} {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "short",
  }).formatToParts(instant);
  const year = parts.find((p) => p.type === "year")?.value ?? "0000";
  const monthName = parts.find((p) => p.type === "month")?.value ?? "";
  const monthNum = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
  })
    .format(instant)
    .slice(0, 7);
  return {key: monthNum, label: `${monthName} ${year}`};
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

function canonicalMood(record: RecordData): {
  key: string;
  label: string;
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
      valenceKey: matchedLabel.valence,
    };
  }
  if (!hasValidLevel) return null;
  const rounded = Math.round(numericLevel);
  if (rounded >= 5) return {key: "great", label: "Great", valenceKey: "positive"};
  if (rounded === 4) return {key: "okay", label: "Okay", valenceKey: "positive"};
  if (rounded === 3) return {key: "tired", label: "Tired", valenceKey: "neutral"};
  if (rounded === 2) return {key: "stressed", label: "Stressed", valenceKey: "strained"};
  return {key: "sad", label: "Sad", valenceKey: "strained"};
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

export function buildEmotionalActivityReport(input: {
  users: Array<{id: string; data: RecordData}>;
  moodEntries: RecordData[];
  moods: RecordData[];
  assessments: RecordData[];
  range: {start: Date; end: Date; label: string};
  schoolYear: string;
  userCategory?: string;
  department?: string;
  source?: EmotionalActivitySourceScope;
  configuredPopulation?: number | null;
  collegeNameById?: ReadonlyMap<string, string>;
}): EmotionalActivityReport {
  const source: EmotionalActivitySourceScope = input.source ?? "all";
  const requestedCategory = input.userCategory ?? "all";
  const requestedDept = (input.department ?? "all").toLocaleLowerCase("en-US");
  const collegeNameById = input.collegeNameById ?? new Map<string, string>();

  const appUsers = input.users.filter(({data}) => {
    const legacyRole = text(data.role).toLowerCase();
    const accessRole =
      text(data.accessRole) ||
      (["admin", "counselor"].includes(legacyRole) ? legacyRole : "appUser");
    return accessRole === "appUser" && data.staffAccountStatus == null;
  });

  const scopedUsers = new Map<string, {roleKey: string; primaryDept: string}>();
  for (const {id, data} of appUsers) {
    const roleKey = normalizedPopulationRole(data);
    if (requestedCategory !== "all" && roleKey !== requestedCategory) continue;
    const dept = resolveUserDepartmentKeys(data, collegeNameById);
    if (requestedDept !== "all" && !dept.keys.has(requestedDept)) continue;
    scopedUsers.set(id, {roleKey, primaryDept: dept.primaryLabel});
  }

  const participants = new Set<string>();
  const participantCategories = new Set<string>();
  const valenceMap = new Map<string, BucketAccumulator>();
  const moodMap = new Map<string, BucketAccumulator>();
  const assessmentMap = new Map<string, BucketAccumulator>();
  const periodMap = new Map<string, BucketAccumulator>();
  const moodUsers = new Set<string>();
  const assessmentUsers = new Set<string>();
  let moodEventCount = 0;
  let assessmentEventCount = 0;
  let missingDemographicsCount = 0;

  const inRange = (record: RecordData, instant: Date | undefined): boolean => {
    const recordYear = text(record.academicYearId);
    if (recordYear) {
      if (recordYear !== input.schoolYear) return false;
      if (!instant) return true;
      return instant >= input.range.start && instant < input.range.end;
    }
    return Boolean(instant && instant >= input.range.start && instant < input.range.end);
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
    for (const entry of [...input.moodEntries, ...input.moods]) {
      const uid = text(entry.userId);
      if (!uid || !scopedUsers.has(uid)) continue;
      const instant =
        dateValue(entry.occurredAt) ||
        dateValue(entry.createdAt) ||
        dateValue(entry.dateKey);
      if (!inRange(entry, instant)) continue;
      const mood = canonicalMood(entry);
      if (!mood) continue;
      trackParticipant(uid, instant ? manilaMonth(instant) : undefined);
      moodUsers.add(uid);
      moodEventCount += 1;
      addToBucket(moodMap, mood.key, mood.label, uid);
      addToBucket(valenceMap, mood.valenceKey, VALENCE_LABELS[mood.valenceKey], uid);
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
      if (!inRange(assessment, instant)) continue;
      const band = canonicalAssessmentBand(assessment);
      if (!band) continue;
      trackParticipant(uid, instant ? manilaMonth(instant) : undefined);
      assessmentUsers.add(uid);
      assessmentEventCount += 1;
      addToBucket(assessmentMap, band.key, band.label, uid);
      addToBucket(valenceMap, band.valenceKey, VALENCE_LABELS[band.valenceKey], uid);
    }
  }

  const departmentCoverageNote =
    missingDemographicsCount > 0 && participants.size >= MIN_EMOTIONAL_COHORT_SIZE
      ? "Some participants have unspecified role or college metadata and appear under Category not specified / Not specified when viewing all."
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
      departmentCoverageNote,
    };
  }

  const valenceBreakdown = finalizeBuckets(valenceMap, "percentage");
  const moodBreakdown = finalizeBuckets(moodMap, "percentage");
  const assessmentBreakdown = finalizeBuckets(assessmentMap, "percentage");
  const periodTrends = finalizeBuckets(periodMap, "chronological");

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
    departmentCoverageNote,
  };
}
