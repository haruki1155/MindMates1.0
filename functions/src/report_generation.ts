import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requireClinical} from "./access";
import {defaultSchoolYear, listAcademicYears, readPopulationConfig} from "./counseling_population";
import {
  buildEmotionalActivityReport,
  EmotionalActivityReport,
  EmotionalActivitySourceScope,
} from "./emotional_activity_report";

if (!getApps().length) initializeApp();

const db = getFirestore();

type RecordData = Record<string, unknown>;

export interface PercentageItem {
  key: string;
  label: string;
  percentage: number;
}

export interface FilterOption {
  key: string;
  label: string;
}

export interface UserCategoryReport {
  key: string;
  label: string;
  populationPercentage: number;
  activePercentage: number;
}

export interface AppliedReportFilters {
  schoolYear: string;
  periodLabel: string;
  startDate: string;
  endDate: string;
  userCategory: string;
  userCategoryLabel: string;
  collegeKey: string;
  collegeLabel: string;
  programKey: string;
  programLabel: string;
  emotionalSource: EmotionalActivitySourceScope;
  emotionalSourceLabel: string;
  collegeOptions: FilterOption[];
  programOptions: FilterOption[];
  programOptionsByCollege: Record<string, FilterOption[]>;
}

export interface ReportAnalytics {
  generatedAt: string;
  activeWindowDays: number;
  dateRange: {startDate: string; endDate: string; label: string};
  filters: AppliedReportFilters;
  population: {
    schoolYear: string;
    departments: string[];
    populations: Record<string, number>;
    configured: boolean;
    totalPopulation: number;
    years: Array<{schoolYear: string; startDate: string; endDate: string; status: string}>;
  };
  users: {
    scopeKey: string;
    scopeLabel: string;
    overallActivePercentage: number;
    categoryOptions: FilterOption[];
    categories: UserCategoryReport[];
  };
  appointments: {
    totalAppointments: number;
    uniqueStudentsServed: number;
    counselingReach: number;
    appointmentRate: number;
    completionRate: number;
    statusCounts: Record<string, number>;
    departmentScopeKey: string;
    departmentScopeLabel: string;
    departmentOptions: FilterOption[];
    department: PercentageItem[];
    course: PercentageItem[];
    yearLevel: PercentageItem[];
    waitingTimeDays: number | null;
    rescheduledAppointments: number;
  };
  comparison: {
    schoolYear: string;
    totalAppointments: number;
    uniqueStudentsServed: number;
    counselingReach: number;
    completionRate: number;
  } | null;
  trends: Array<{
    schoolYear: string;
    totalAppointments: number;
    uniqueStudentsServed: number;
    counselingReach: number;
    completedAppointments: number;
  }>;
  emotionalActivity: EmotionalActivityReport & {
    departmentOptions: FilterOption[];
  };
}

const roleLabels: Record<string, string> = {
  student: "Students",
  teaching: "Teaching personnel",
  nonTeaching: "Non-teaching personnel",
  unspecified: "Category not specified",
};

const ALLOWED_PERIOD_LABELS = new Set([
  "Whole academic year",
  "1st semester",
  "2nd semester",
  "Custom date range",
]);

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizedPopulationRole(user: RecordData): string {
  const raw = text(user.populationRole || user.declaredRole || user.role)
    .toLowerCase().replace(/[\s_-]+/g, "");
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
    if (!Number.isNaN(parsed.getTime())) return parsed;
  }
  return undefined;
}

function exclusiveEndDateValue(value: unknown): Date | undefined {
  const parsed = dateValue(value);
  if (!parsed) return undefined;
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value.trim())) {
    return new Date(parsed.getTime() + 86400000);
  }
  return parsed;
}

function academicYearRange(
  schoolYear: string,
  startDateText?: string,
  endDateText?: string,
): {start: Date; end: Date} {
  if (
    startDateText &&
    endDateText &&
    /^\d{4}-\d{2}-\d{2}$/.test(startDateText) &&
    /^\d{4}-\d{2}-\d{2}$/.test(endDateText)
  ) {
    const start = new Date(`${startDateText}T00:00:00+08:00`);
    const endInclusive = new Date(`${endDateText}T00:00:00+08:00`);
    if (!Number.isNaN(start.getTime()) && !Number.isNaN(endInclusive.getTime())) {
      return {
        start,
        end: new Date(endInclusive.getTime() + 86400000),
      };
    }
  }
  const startYear = Number(schoolYear.slice(0, 4));
  return {
    start: new Date(`${startYear}-06-01T00:00:00+08:00`),
    end: new Date(`${startYear + 1}-06-01T00:00:00+08:00`),
  };
}

function isActiveInWindow(
  user: RecordData,
  range: {start: Date; end: Date},
): boolean {
  const inBounds = (instant: Date | undefined): boolean =>
    Boolean(instant && instant >= range.start && instant < range.end);
  if (inBounds(dateValue(user.lastActiveAt))) return true;
  if (!Array.isArray(user.activeDateKeys)) return false;
  return user.activeDateKeys.some((value) => {
    if (typeof value !== "string") return false;
    const trimmed = value.trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return false;
    const date = new Date(`${trimmed}T00:00:00+08:00`);
    return !Number.isNaN(date.getTime()) && inBounds(date);
  });
}

function percent(part: number, total: number): number {
  if (total <= 0) return 0;
  return Math.round((part / total) * 1000) / 10;
}

function percentageGroups(values: string[]): PercentageItem[] {
  if (values.length === 0) return [];
  const counts = new Map<string, {label: string; count: number}>();
  for (const raw of values) {
    const label = raw || "Not specified";
    const key = label.toLocaleLowerCase("en-US");
    const current = counts.get(key);
    counts.set(key, {label: current?.label ?? label, count: (current?.count ?? 0) + 1});
  }
  return [...counts.entries()]
    .map(([key, value]) => ({
      key,
      label: value.label,
      percentage: percent(value.count, values.length),
    }))
    .sort((a, b) => b.percentage - a.percentage || a.label.localeCompare(b.label));
}

function rateGroups(values: string[], denominator: number): PercentageItem[] {
  const counts = new Map<string, {label: string; count: number}>();
  for (const raw of values) {
    const label = raw || "Not specified";
    const key = label.toLocaleLowerCase("en-US");
    const current = counts.get(key);
    counts.set(key, {label: current?.label ?? label, count: (current?.count ?? 0) + 1});
  }
  return [...counts.entries()]
    .map(([key, value]) => ({
      key,
      label: value.label,
      percentage: denominator > 0 ? Math.round((value.count / denominator) * 1000) / 10 : 0,
    }))
    .sort((a, b) => b.percentage - a.percentage || a.label.localeCompare(b.label));
}

function userCollegeInfo(
  data: RecordData,
  collegeNameById: ReadonlyMap<string, string>,
): {label: string; keys: Set<string>} {
  const collegeId = text(data.collegeId);
  const resolved = collegeId ? text(collegeNameById.get(collegeId)) : "";
  const department = text(data.department);
  const college = text(data.college);
  const label = department || college || resolved || "Not specified";
  const keys = new Set<string>();
  for (const cand of [department, college, resolved, collegeId]) {
    if (cand) keys.add(cand.toLocaleLowerCase("en-US"));
  }
  if (keys.size === 0) keys.add("not specified");
  return {label, keys};
}

function userProgramInfo(
  data: RecordData,
  courseNameById: ReadonlyMap<string, string>,
): {label: string; keys: Set<string>} {
  const courseId = text(data.courseId);
  const resolved = courseId ? text(courseNameById.get(courseId)) : "";
  const course = text(data.course);
  const program = text(data.program);
  const label = course || program || resolved || "Not specified";
  const keys = new Set<string>();
  for (const cand of [course, program, resolved, courseId]) {
    if (cand) keys.add(cand.toLocaleLowerCase("en-US"));
  }
  if (keys.size === 0) keys.add("not specified");
  return {label, keys};
}

export function buildReportAnalytics(
  users: Array<{id: string; data: RecordData}>,
  appointments: RecordData[],
  now = new Date(),
  filters: {
    userCategory?: string;
    appointmentDepartment?: string;
    program?: string;
    periodLabel?: string;
    startDate?: string;
    endDate?: string;
    emotionalSource?: EmotionalActivitySourceScope;
  } = {},
  population: {
    schoolYear: string;
    startDate?: string;
    endDate?: string;
    departments: string[];
    populations: Record<string, number>;
    configured: boolean;
    totalPopulation: number;
    years: Array<{schoolYear: string; startDate: string; endDate: string; status: string}>;
  } = {
    schoolYear: defaultSchoolYear(now),
    departments: [] as string[],
    populations: {} as Record<string, number>,
    configured: false,
    totalPopulation: 0,
    years: [] as Array<{schoolYear: string; startDate: string; endDate: string; status: string}>,
  },
  emotionalInput: {
    moodEntries?: RecordData[];
    moods?: RecordData[];
    assessments?: RecordData[];
    collegeNameById?: ReadonlyMap<string, string>;
    courseNameById?: ReadonlyMap<string, string>;
    emotionalDepartmentOptions?: FilterOption[];
    programOptionsByCollege?: Record<string, FilterOption[]>;
  } = {},
): ReportAnalytics {
  const collegeNameById = emotionalInput.collegeNameById ?? new Map<string, string>();
  const courseNameById = emotionalInput.courseNameById ?? new Map<string, string>();
  const requestedUserCategory = filters.userCategory ?? "all";
  const requestedDepartment = (filters.appointmentDepartment ?? "all")
    .toLocaleLowerCase("en-US");
  const requestedProgram = (filters.program ?? "all")
    .toLocaleLowerCase("en-US");
  const emotionalSource: EmotionalActivitySourceScope = filters.emotionalSource ?? "all";

  const appUsers = users.filter(({data}) => {
    const legacyRole = text(data.role).toLowerCase();
    const accessRole = text(data.accessRole) ||
      (["admin", "counselor"].includes(legacyRole) ? legacyRole : "appUser");
    return accessRole === "appUser" && data.staffAccountStatus == null;
  });
  const appUserIds = new Set(appUsers.map(({id}) => id));
  const userById = new Map(appUsers.map((user) => [user.id, user.data]));

  const academicRange = academicYearRange(
    population.schoolYear,
    population.startDate,
    population.endDate,
  );
  const requestedStart = dateValue(filters.startDate);
  const requestedEnd = exclusiveEndDateValue(filters.endDate);
  const hasExplicitRange = Boolean(requestedStart && requestedEnd);
  const range = hasExplicitRange ?
    {start: requestedStart!, end: requestedEnd!} : academicRange;
  const resolvedPeriodLabel = text(filters.periodLabel) ||
    (hasExplicitRange ? "Custom date range" : `Academic year ${population.schoolYear}`);

  const matchesUserCollegeAndProgram = (data: RecordData): boolean => {
    if (requestedDepartment !== "all") {
      const col = userCollegeInfo(data, collegeNameById);
      if (!col.keys.has(requestedDepartment)) return false;
    }
    if (requestedProgram !== "all") {
      const prog = userProgramInfo(data, courseNameById);
      if (!prog.keys.has(requestedProgram)) return false;
    }
    return true;
  };

  const baseUsersForCategory = appUsers.filter(({data}) =>
    matchesUserCollegeAndProgram(data),
  );
  const activeWindowDays = Math.max(
    1,
    Math.round((range.end.getTime() - range.start.getTime()) / 86400000),
  );
  const allCategories = ["student", "teaching", "nonTeaching", "unspecified"]
    .map((key): UserCategoryReport => {
      const categoryUsers = baseUsersForCategory.filter(
        ({data}) => normalizedPopulationRole(data) === key,
      );
      const categoryActive = categoryUsers.filter(({data}) =>
        isActiveInWindow(data, range),
      );
      return {
        key,
        label: roleLabels[key],
        populationPercentage: percent(categoryUsers.length, baseUsersForCategory.length),
        activePercentage: percent(categoryActive.length, categoryUsers.length),
      };
    })
    .filter((item) => item.populationPercentage > 0);

  const scopedUsers = requestedUserCategory === "all" ? baseUsersForCategory : baseUsersForCategory.filter(
    ({data}) => normalizedPopulationRole(data) === requestedUserCategory,
  );
  const scopedActiveUsers = scopedUsers.filter(({data}) =>
    isActiveInWindow(data, range),
  );
  const selectedCategory = allCategories.find(
    (category) => category.key === requestedUserCategory,
  );
  const categories = requestedUserCategory === "all" ? allCategories : selectedCategory ? [{
    ...selectedCategory,
    populationPercentage: scopedUsers.length > 0 ? 100 : 0,
  }] : [];

  // Imported office walk-ins have no app user ID. They are explicitly marked
  // by the secured import callable and are included in appointment reports.
  const eligibleAppointments = appointments.filter((appointment) =>
    appointment.source === "walk_in_import" || appUserIds.has(text(appointment.userId)),
  );
  const appointmentCategory = (appointment: RecordData): string => {
    const explicit = normalizedPopulationRole(appointment);
    if (explicit !== "unspecified") return explicit;
    const profile = userById.get(text(appointment.userId));
    if (profile) return normalizedPopulationRole(profile);
    if (appointment.source === "walk_in_import") return "student";
    return "unspecified";
  };

  const categoryAndYearAppointments = eligibleAppointments.filter((appointment) => {
    if (requestedUserCategory !== "all" && appointmentCategory(appointment) !== requestedUserCategory) {
      return false;
    }
    const recordYear = text(appointment.academicYearId);
    const appointmentDate =
      dateValue(appointment.scheduledAt) ||
      dateValue(appointment.createdAt) ||
      dateValue(appointment.importedAt);
    if (recordYear) {
      if (recordYear !== population.schoolYear) return false;
      if (!hasExplicitRange) return true;
      return Boolean(appointmentDate && appointmentDate >= range.start && appointmentDate < range.end);
    }
    return Boolean(appointmentDate && appointmentDate >= range.start && appointmentDate < range.end);
  });

  const appointmentDepartment = (appointment: RecordData): {label: string; keys: Set<string>} => {
    const profile = userById.get(text(appointment.userId));
    const directDept = text(appointment.department) || text(appointment.college);
    const directId = text(appointment.collegeId);
    const resolvedId = directId ? text(collegeNameById.get(directId)) : "";
    const profileInfo = profile ? userCollegeInfo(profile, collegeNameById) : null;
    const label = directDept || resolvedId || profileInfo?.label || "Not specified";
    const keys = new Set<string>(profileInfo?.keys ?? []);
    for (const cand of [directDept, resolvedId, directId]) {
      if (cand) keys.add(cand.toLocaleLowerCase("en-US"));
    }
    if (keys.size === 0) keys.add("not specified");
    return {label, keys};
  };

  const appointmentProgram = (appointment: RecordData): {label: string; keys: Set<string>} => {
    const profile = userById.get(text(appointment.userId));
    const directCourse = text(appointment.course) || text(appointment.program);
    const directCourseId = text(appointment.courseId);
    const resolved = directCourseId ? text(courseNameById.get(directCourseId)) : "";
    const profileInfo = profile ? userProgramInfo(profile, courseNameById) : null;
    const label = directCourse || resolved || profileInfo?.label || "Not specified";
    const keys = new Set<string>(profileInfo?.keys ?? []);
    for (const cand of [directCourse, resolved, directCourseId]) {
      if (cand) keys.add(cand.toLocaleLowerCase("en-US"));
    }
    if (keys.size === 0) keys.add("not specified");
    return {label, keys};
  };

  const departmentGroups = percentageGroups(
    categoryAndYearAppointments.map((a) => appointmentDepartment(a).label),
  );
  const departmentAppointmentRates = departmentGroups.map((item) => ({
    ...item,
    percentage: population.configured && population.populations[item.label] != null ?
      Math.round((categoryAndYearAppointments.filter((a) => appointmentDepartment(a).label === item.label).length /
        population.populations[item.label]) * 1000) / 10 : 0,
  }));
  const selectedDepartment = departmentGroups.find(
    (department) => department.key === requestedDepartment,
  );
  const includedAppointments = categoryAndYearAppointments.filter((appointment) => {
    if (requestedDepartment !== "all" && !appointmentDepartment(appointment).keys.has(requestedDepartment)) {
      return false;
    }
    if (requestedProgram !== "all" && !appointmentProgram(appointment).keys.has(requestedProgram)) {
      return false;
    }
    return true;
  });
  const includedDepartmentRates = requestedDepartment === "all" ?
    departmentAppointmentRates : departmentAppointmentRates.filter(
      (department) => department.key === requestedDepartment,
    );
  const valuesFor = (field: "department" | "course" | "yearLevel"): string[] =>
    includedAppointments.map((appointment) => {
      if (field === "department") return appointmentDepartment(appointment).label;
      if (field === "course") return appointmentProgram(appointment).label;
      const profile = userById.get(text(appointment.userId));
      return text(appointment[field]) || text(profile?.[field]) || "Not specified";
    });
  const matchedPopulationKey = Object.keys(population.populations).find(
    (name) => name.toLocaleLowerCase("en-US") === requestedDepartment,
  );
  const selectedPopulation = !population.configured
    ? 0
    : requestedDepartment === "all"
    ? population.totalPopulation
    : matchedPopulationKey != null
    ? population.populations[matchedPopulationKey] ?? 0
    : population.populations[selectedDepartment?.label ?? ""] ?? 0;

  const studentKeys = new Set(includedAppointments.map((appointment) =>
    text(appointment.studentId) || text(appointment.userId) || text(appointment.fullName),
  ).filter(Boolean));
  const statusCounts: Record<string, number> = {};
  for (const appointment of includedAppointments) {
    const status = text(appointment.status).toLowerCase() || "pending";
    statusCounts[status] = (statusCounts[status] ?? 0) + 1;
  }
  const completed = statusCounts.completed ?? statusCounts.complete ?? 0;
  const scheduled = includedAppointments.filter((appointment) =>
    !["cancelled", "canceled", "no-show", "noshow"].includes(text(appointment.status).toLowerCase()),
  ).length;
  const waitingTimes = includedAppointments.map((appointment) => {
    const created = dateValue(appointment.createdAt);
    const scheduledAt = dateValue(appointment.scheduledAt);
    return created && scheduledAt && scheduledAt >= created ?
      (scheduledAt.getTime() - created.getTime()) / 86400000 : null;
  }).filter((value): value is number => value != null);
  const waitingTimeDays = waitingTimes.length === 0 ? null :
    Math.round(waitingTimes.reduce((sum, value) => sum + value, 0) / waitingTimes.length * 10) / 10;
  const rescheduledAppointments = includedAppointments.filter((appointment) => {
    const status = text(appointment.status).toLowerCase();
    return status === "rescheduled" || status === "schedule_adjustment_needed" ||
      status === "schedule-adjustment-needed";
  }).length;

  const emotionalPopulation = !population.configured
    ? null
    : selectedPopulation > 0
    ? selectedPopulation
    : null;

  const fallbackDepartmentOptions: FilterOption[] = (
    emotionalInput.emotionalDepartmentOptions ??
    population.departments.map((label) => ({
      key: label.toLocaleLowerCase("en-US"),
      label,
    }))
  ).slice();

  const programOptionsByCollege: Record<string, FilterOption[]> =
    emotionalInput.programOptionsByCollege ?? {};
  const currentProgramOptions: FilterOption[] =
    requestedDepartment === "all"
      ? [...new Map(
          Object.values(programOptionsByCollege).flat().map((opt) => [opt.key, opt]),
        ).values()].sort((a, b) => a.label.localeCompare(b.label))
      : programOptionsByCollege[requestedDepartment] ?? [];

  const emotionalActivity = {
    ...buildEmotionalActivityReport({
      users,
      moodEntries: emotionalInput.moodEntries ?? [],
      moods: emotionalInput.moods ?? [],
      assessments: emotionalInput.assessments ?? [],
      range: {
        ...range,
        label: resolvedPeriodLabel,
      },
      schoolYear: population.schoolYear,
      userCategory: requestedUserCategory,
      department: requestedDepartment,
      program: requestedProgram,
      source: emotionalSource,
      configuredPopulation: emotionalPopulation,
      collegeNameById,
      courseNameById,
    }),
    departmentOptions: fallbackDepartmentOptions,
  };

  const requestedDeptOption = fallbackDepartmentOptions.find(
    (option) => option.key === requestedDepartment,
  );
  const resolvedCollegeLabel = [...collegeNameById.entries()]
    .find(
      ([id, name]) =>
        id.toLocaleLowerCase("en-US") === requestedDepartment ||
        name.toLocaleLowerCase("en-US") === requestedDepartment,
    )?.[1];
  const resolvedCollegeDisplay = requestedDepartment === "all"
    ? "All colleges & departments"
    : selectedDepartment?.label ??
      requestedDeptOption?.label ??
      resolvedCollegeLabel ??
      "Selected college";

  const requestedProgramOption =
    currentProgramOptions.find((o) => o.key === requestedProgram) ??
    Object.values(programOptionsByCollege)
      .flat()
      .find((o) => o.key === requestedProgram);
  const resolvedCourseLabel = [...courseNameById.entries()]
    .find(
      ([id, name]) =>
        id.toLocaleLowerCase("en-US") === requestedProgram ||
        name.toLocaleLowerCase("en-US") === requestedProgram,
    )?.[1];
  const resolvedProgramDisplay = requestedProgram === "all"
    ? "All programs"
    : requestedProgramOption?.label ?? resolvedCourseLabel ?? requestedProgram;

  return {
    generatedAt: now.toISOString(),
    activeWindowDays,
    dateRange: {
      startDate: range.start.toISOString(),
      endDate: range.end.toISOString(),
      label: resolvedPeriodLabel,
    },
    filters: {
      schoolYear: population.schoolYear,
      periodLabel: resolvedPeriodLabel,
      startDate: range.start.toISOString(),
      endDate: range.end.toISOString(),
      userCategory: requestedUserCategory,
      userCategoryLabel:
        requestedUserCategory === "all"
          ? "All categories"
          : roleLabels[requestedUserCategory] ?? "Category",
      collegeKey: requestedDepartment,
      collegeLabel: resolvedCollegeDisplay,
      programKey: requestedProgram,
      programLabel: resolvedProgramDisplay,
      emotionalSource,
      emotionalSourceLabel: emotionalActivity.sourceScopeLabel,
      collegeOptions: fallbackDepartmentOptions,
      programOptions: currentProgramOptions,
      programOptionsByCollege,
    },
    population,
    users: {
      scopeKey: requestedUserCategory,
      scopeLabel: requestedUserCategory === "all" ?
        "Whole app-user population" : roleLabels[requestedUserCategory] ?? "Category",
      overallActivePercentage: percent(scopedActiveUsers.length, scopedUsers.length),
      categoryOptions: allCategories.map(({key, label}) => ({key, label})),
      categories,
    },
    appointments: {
      totalAppointments: includedAppointments.length,
      uniqueStudentsServed: studentKeys.size,
      counselingReach: percent(studentKeys.size, selectedPopulation),
      appointmentRate: percent(includedAppointments.length, selectedPopulation),
      completionRate: percent(completed, scheduled),
      waitingTimeDays,
      rescheduledAppointments,
      statusCounts,
      departmentScopeKey: requestedDepartment,
      departmentScopeLabel: requestedDepartment === "all" ?
        "All departments" :
        selectedDepartment?.label ??
        requestedDeptOption?.label ??
        resolvedCollegeLabel ??
        "Selected department",
      departmentOptions: departmentGroups.map(({key, label}) => ({key, label})),
      department: includedDepartmentRates,
      course: population.configured ? rateGroups(valuesFor("course"), selectedPopulation) : [],
      yearLevel: population.configured ? rateGroups(valuesFor("yearLevel"), selectedPopulation) : [],
    },
    comparison: null,
    trends: [],
    emotionalActivity,
  };
}

export const getReportAnalytics = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  const actor = await requireClinical(uid);

  const userCategory = text(request.data?.userCategory) || "all";
  if (!["all", "student", "teaching", "nonTeaching", "unspecified"].includes(userCategory)) {
    throw new HttpsError("invalid-argument", "The user category is invalid.");
  }
  const appointmentDepartment = (text(request.data?.appointmentDepartment) || "all")
    .toLocaleLowerCase("en-US");
  if (appointmentDepartment.length > 160) {
    throw new HttpsError("invalid-argument", "The department filter is invalid.");
  }

  const program = (text(request.data?.program) || "all")
    .toLocaleLowerCase("en-US");
  if (program.length > 160) {
    throw new HttpsError("invalid-argument", "The program filter is invalid.");
  }

  const periodLabel = text(request.data?.periodLabel);
  if (periodLabel && !ALLOWED_PERIOD_LABELS.has(periodLabel)) {
    throw new HttpsError("invalid-argument", "The reporting period label is invalid.");
  }

  const emotionalSourceRaw = text(request.data?.emotionalSource) || "all";
  if (!["all", "mood", "assessment"].includes(emotionalSourceRaw)) {
    throw new HttpsError("invalid-argument", "The emotional activity source is invalid.");
  }
  const emotionalSource = emotionalSourceRaw as EmotionalActivitySourceScope;

  const schoolYear = text(request.data?.schoolYear) || defaultSchoolYear();
  if (!/^\d{4}-\d{4}$/.test(schoolYear)) {
    throw new HttpsError("invalid-argument", "Use a school year such as 2026-2027.");
  }

  const startDate = text(request.data?.startDate);
  const endDate = text(request.data?.endDate);
  const parsedStart = startDate ? dateValue(startDate) : undefined;
  const parsedEnd = endDate ? exclusiveEndDateValue(endDate) : undefined;
  if ((startDate && !parsedStart) || (endDate && !parsedEnd) ||
      (parsedStart && parsedEnd && parsedStart >= parsedEnd)) {
    throw new HttpsError("invalid-argument", "The report date range is invalid.");
  }

  const [
    usersSnapshot,
    appointmentsSnapshot,
    population,
    years,
    moodEntriesSnapshot,
    moodsSnapshot,
    assessmentsSnapshot,
    collegesSnapshot,
    coursesSnapshot,
  ] = await Promise.all([
    db.collection("users").where("accessRole", "==", "appUser").get(),
    db.collection("appointments").get(),
    readPopulationConfig(schoolYear),
    listAcademicYears({includeVoided: false}),
    db.collection("moodEntries").get(),
    db.collection("moods").get(),
    db.collection("assessments").get(),
    db.collection("colleges").get(),
    db.collection("courses").get(),
  ]);
  if (population.status === "voided") {
    throw new HttpsError("failed-precondition", "Voided academic years cannot be used in reporting.");
  }
  if (population.status === "planned") {
    throw new HttpsError("failed-precondition", "Planned academic years cannot generate official reports.");
  }
  if (population.exists && population.status === "unknown") {
    throw new HttpsError("failed-precondition", "Academic year has an unrecognized status and cannot generate official reports.");
  }

  const collegeNameById = new Map<string, string>();
  const collegeCodeById = new Map<string, string>();
  const institutionCollegeNames = new Set<string>(population.departments);
  for (const doc of collegesSnapshot.docs) {
    const data = doc.data();
    const name = text(data.name);
    const code = text(data.code);
    if (name) {
      collegeNameById.set(doc.id, name);
      if (data.active !== false) institutionCollegeNames.add(name);
    }
    if (code) collegeCodeById.set(doc.id, code);
  }

  const assignedCollegeIds = Array.isArray(actor.assignedCollegeIds)
    ? actor.assignedCollegeIds.filter((id): id is string => typeof id === "string" && id.trim().length > 0)
    : [];
  const restrictByCollege = actor.accessRole === "counselor";
  if (restrictByCollege && assignedCollegeIds.length === 0) {
    throw new HttpsError(
      "permission-denied",
      "Your counselor account does not have any assigned colleges.",
    );
  }
  const allowedCollegeKeys = new Set<string>();
  if (restrictByCollege) {
    for (const id of assignedCollegeIds) {
      allowedCollegeKeys.add(id.toLocaleLowerCase("en-US"));
      const cname = collegeNameById.get(id);
      if (cname) allowedCollegeKeys.add(cname.toLocaleLowerCase("en-US"));
      const ccode = collegeCodeById.get(id);
      if (ccode) allowedCollegeKeys.add(ccode.toLocaleLowerCase("en-US"));
    }
    if (appointmentDepartment !== "all" && !allowedCollegeKeys.has(appointmentDepartment)) {
      throw new HttpsError(
        "permission-denied",
        "You are not authorized to access reports outside your assigned colleges.",
      );
    }
  }

  const courseNameById = new Map<string, string>();
  const courseCollegeKeysByProgram = new Map<string, Set<string>>();
  const programsByCollegeMap = new Map<string, Map<string, string>>();

  const addProgramToCollege = (collegeLabel: string, progLabel: string, keys: string[] = []) => {
    if (!collegeLabel || !progLabel) return;
    const cKey = collegeLabel.toLocaleLowerCase("en-US");
    const pKey = progLabel.toLocaleLowerCase("en-US");
    let progMap = programsByCollegeMap.get(cKey);
    if (!progMap) {
      progMap = new Map<string, string>();
      programsByCollegeMap.set(cKey, progMap);
    }
    if (!progMap.has(pKey)) progMap.set(pKey, progLabel);

    for (const k of [pKey, ...keys.map((x) => x.toLocaleLowerCase("en-US")).filter(Boolean)]) {
      let colSet = courseCollegeKeysByProgram.get(k);
      if (!colSet) {
        colSet = new Set<string>();
        courseCollegeKeysByProgram.set(k, colSet);
      }
      colSet.add(cKey);
      const colId = [...collegeNameById.entries()].find(([, n]) => n.toLocaleLowerCase("en-US") === cKey)?.[0];
      if (colId) colSet.add(colId.toLocaleLowerCase("en-US"));
    }
  };

  for (const doc of coursesSnapshot.docs) {
    const data = doc.data();
    if (data.active === false) continue;
    const cname = text(data.name);
    const ccode = text(data.code);
    const collegeId = text(data.collegeId);
    if (cname) courseNameById.set(doc.id, cname);
    const collegeLabel = collegeNameById.get(collegeId) || collegeId;
    if (collegeLabel && cname) {
      addProgramToCollege(collegeLabel, cname, [doc.id, ccode]);
    }
  }

  const allUsers = usersSnapshot.docs.map((document) => ({
    id: document.id,
    data: document.data() as RecordData,
  }));
  const userMatchesAllowedColleges = (data: RecordData): boolean => {
    if (!restrictByCollege) return true;
    const col = userCollegeInfo(data, collegeNameById);
    return [...col.keys].some((k) => allowedCollegeKeys.has(k));
  };

  const scopedUsers = restrictByCollege
    ? allUsers.filter(({data}) => userMatchesAllowedColleges(data))
    : allUsers;
  const userById = new Map(allUsers.map((u) => [u.id, u.data]));
  const allAppointments = appointmentsSnapshot.docs.map((document) => document.data() as RecordData);
  const scopedAppointments = restrictByCollege
    ? allAppointments.filter((appointment) => {
        const apptDept = (
          text(appointment.department) ||
          text(appointment.college) ||
          text(appointment.collegeId)
        ).toLocaleLowerCase("en-US");
        if (apptDept && allowedCollegeKeys.has(apptDept)) return true;
        const owner = userById.get(text(appointment.userId));
        return owner ? userMatchesAllowedColleges(owner) : false;
      })
    : allAppointments;

  // Enrich college -> programs map from authorized user/appointment records (fallback when catalog is sparse).
  for (const {data} of scopedUsers) {
    const colLabel = userCollegeInfo(data, collegeNameById).label;
    const progLabel = userProgramInfo(data, courseNameById).label;
    if (colLabel !== "Not specified" && progLabel !== "Not specified") {
      addProgramToCollege(colLabel, progLabel);
    }
  }
  for (const appt of scopedAppointments) {
    const colLabel = text(appt.department) || text(appt.college);
    const progLabel = text(appt.course) || text(appt.program);
    if (colLabel && progLabel) {
      addProgramToCollege(colLabel, progLabel);
    }
  }

  // Enforce authorized & valid college -> program combinations.
  if (program !== "all" && program !== "not specified") {
    const knownCollegesForProgram = courseCollegeKeysByProgram.get(program);
    if (restrictByCollege) {
      if (knownCollegesForProgram && ![...knownCollegesForProgram].some((k) => allowedCollegeKeys.has(k))) {
        throw new HttpsError(
          "permission-denied",
          "You are not authorized to access reports outside your assigned colleges.",
        );
      }
      if (!knownCollegesForProgram) {
        throw new HttpsError(
          "permission-denied",
          "You are not authorized to access reports outside your assigned colleges.",
        );
      }
    }
    if (appointmentDepartment !== "all") {
      const allowedPrograms = programsByCollegeMap.get(appointmentDepartment);
      if (knownCollegesForProgram && !knownCollegesForProgram.has(appointmentDepartment)) {
        throw new HttpsError(
          "invalid-argument",
          "The selected program does not belong to the selected college.",
        );
      }
      if (allowedPrograms && allowedPrograms.size > 0 && !allowedPrograms.has(program)) {
        throw new HttpsError(
          "invalid-argument",
          "The selected program does not belong to the selected college.",
        );
      }
    }
  }

  const emotionalDepartmentOptions: FilterOption[] = [...institutionCollegeNames]
    .filter((label) => !restrictByCollege || allowedCollegeKeys.has(label.toLocaleLowerCase("en-US")))
    .sort((a, b) => a.localeCompare(b))
    .map((label) => ({key: label.toLocaleLowerCase("en-US"), label}));

  const programOptionsByCollege: Record<string, FilterOption[]> = {};
  for (const [colKey, progMap] of programsByCollegeMap.entries()) {
    if (restrictByCollege && !allowedCollegeKeys.has(colKey)) continue;
    programOptionsByCollege[colKey] = [...progMap.entries()]
      .map(([key, label]) => ({key, label}))
      .sort((a, b) => a.label.localeCompare(b.label));
  }

  const populationWithYears = {...population, years};
  const moodEntries = moodEntriesSnapshot.docs.map((document) => document.data() as RecordData);
  const moods = moodsSnapshot.docs.map((document) => document.data() as RecordData);
  const assessments = assessmentsSnapshot.docs.map((document) => document.data() as RecordData);

  const hasReportableStatus =
    population.status === "current" || population.status === "closed";
  const result = buildReportAnalytics(
    hasReportableStatus ? scopedUsers : [],
    hasReportableStatus ? scopedAppointments : [],
    new Date(),
    {
      userCategory,
      appointmentDepartment,
      program,
      periodLabel: periodLabel || undefined,
      startDate: startDate || undefined,
      endDate: endDate || undefined,
      emotionalSource,
    },
    populationWithYears,
    {
      moodEntries: hasReportableStatus ? moodEntries : [],
      moods: hasReportableStatus ? moods : [],
      assessments: hasReportableStatus ? assessments : [],
      collegeNameById,
      courseNameById,
      emotionalDepartmentOptions,
      programOptionsByCollege,
    },
  );
  const reportableYears = years.filter(
    (year) => year.status === "current" || year.status === "closed",
  );
  const previousYear = reportableYears
    .filter((year) => year.schoolYear < schoolYear)
    .sort((a, b) => b.schoolYear.localeCompare(a.schoolYear))[0];
  if (previousYear) {
    const previousPopulation = await readPopulationConfig(previousYear.schoolYear);
    const previous = buildReportAnalytics(
      scopedUsers,
      scopedAppointments,
      new Date(),
      {userCategory, appointmentDepartment, program, emotionalSource},
      {...previousPopulation, years: []},
      {collegeNameById, courseNameById},
    );
    result.comparison = {
      schoolYear: previousYear.schoolYear,
      totalAppointments: previous.appointments.totalAppointments,
      uniqueStudentsServed: previous.appointments.uniqueStudentsServed,
      counselingReach: previous.appointments.counselingReach,
      completionRate: previous.appointments.completionRate,
    };
  }
  result.trends = (await Promise.all(reportableYears.map(async (year) => {
    const yearPopulation = await readPopulationConfig(year.schoolYear);
    const yearReport = buildReportAnalytics(
      scopedUsers,
      scopedAppointments,
      new Date(),
      {userCategory, appointmentDepartment, program, emotionalSource},
      {...yearPopulation, years: []},
      {collegeNameById, courseNameById},
    );
    return {
      schoolYear: year.schoolYear,
      totalAppointments: yearReport.appointments.totalAppointments,
      uniqueStudentsServed: yearReport.appointments.uniqueStudentsServed,
      counselingReach: yearReport.appointments.counselingReach,
      completedAppointments: yearReport.appointments.statusCounts.completed ?? 0,
    };
  }))).sort((a, b) => a.schoolYear.localeCompare(b.schoolYear));
  return {report: result};
});
