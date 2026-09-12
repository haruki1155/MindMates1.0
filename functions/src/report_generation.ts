import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {defaultSchoolYear, listAcademicYears, readPopulationConfig} from "./counseling_population";

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

export interface ReportAnalytics {
  generatedAt: string;
  activeWindowDays: number;
  dateRange: {startDate: string; endDate: string; label: string};
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
}

const roleLabels: Record<string, string> = {
  student: "Students",
  teaching: "Teaching personnel",
  nonTeaching: "Non-teaching personnel",
  unspecified: "Category not specified",
};

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
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) return parsed;
  }
  return undefined;
}

function academicYearRange(schoolYear: string): {start: Date; end: Date} {
  const startYear = Number(schoolYear.slice(0, 4));
  return {
    start: new Date(Date.UTC(startYear, 5, 1)),
    end: new Date(Date.UTC(startYear + 1, 5, 1)),
  };
}

function isActive(user: RecordData, cutoff: Date): boolean {
  const lastActive = dateValue(user.lastActiveAt);
  if (lastActive && lastActive >= cutoff) return true;
  if (!Array.isArray(user.activeDateKeys)) return false;
  return user.activeDateKeys.some((value) => {
    if (typeof value !== "string") return false;
    const date = new Date(`${value}T00:00:00Z`);
    return !Number.isNaN(date.getTime()) && date >= cutoff;
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
      percentage: Math.round((value.count / denominator) * 1000) / 10,
    }))
    .sort((a, b) => b.percentage - a.percentage || a.label.localeCompare(b.label));
}

export function buildReportAnalytics(
  users: Array<{id: string; data: RecordData}>,
  appointments: RecordData[],
  now = new Date(),
  filters: {userCategory?: string; appointmentDepartment?: string; startDate?: string; endDate?: string} = {},
  population = {
    schoolYear: defaultSchoolYear(now),
    departments: [] as string[],
    populations: {} as Record<string, number>,
    configured: false,
    totalPopulation: 0,
    years: [] as Array<{schoolYear: string; startDate: string; endDate: string; status: string}>,
  },
): ReportAnalytics {
  const appUsers = users.filter(({data}) => {
    const legacyRole = text(data.role).toLowerCase();
    const accessRole = text(data.accessRole) ||
      (["admin", "counselor"].includes(legacyRole) ? legacyRole : "appUser");
    return accessRole === "appUser" && data.staffAccountStatus == null;
  });
  const appUserIds = new Set(appUsers.map(({id}) => id));
  const cutoff = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const allCategories = ["student", "teaching", "nonTeaching", "unspecified"]
    .map((key): UserCategoryReport => {
      const categoryUsers = appUsers.filter(
        ({data}) => normalizedPopulationRole(data) === key,
      );
      const categoryActive = categoryUsers.filter(({data}) => isActive(data, cutoff));
      return {
        key,
        label: roleLabels[key],
        populationPercentage: percent(categoryUsers.length, appUsers.length),
        activePercentage: percent(categoryActive.length, categoryUsers.length),
      };
    })
    .filter((item) => item.populationPercentage > 0);

  const requestedUserCategory = filters.userCategory ?? "all";
  const scopedUsers = requestedUserCategory === "all" ? appUsers : appUsers.filter(
    ({data}) => normalizedPopulationRole(data) === requestedUserCategory,
  );
  const scopedActiveUsers = scopedUsers.filter(({data}) => isActive(data, cutoff));
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
  const academicRange = academicYearRange(population.schoolYear);
  const requestedStart = dateValue(filters.startDate);
  const requestedEnd = dateValue(filters.endDate);
  const range = requestedStart && requestedEnd ?
    {start: requestedStart, end: requestedEnd} : academicRange;
  const yearAppointments = eligibleAppointments.filter((appointment) => {
    const appointmentDate = dateValue(appointment.scheduledAt) || dateValue(appointment.createdAt);
    if (requestedStart && requestedEnd) {
      return !!appointmentDate && appointmentDate >= range.start && appointmentDate < range.end;
    }
    if (text(appointment.academicYearId) === population.schoolYear) return true;
    if (text(appointment.academicYearId)) return false;
    return !appointmentDate || (appointmentDate >= range.start && appointmentDate < range.end);
  });
  const userById = new Map(appUsers.map((user) => [user.id, user.data]));
  const appointmentDepartment = (appointment: RecordData): string => {
    const profile = userById.get(text(appointment.userId));
    return text(appointment.department) || text(profile?.department) || "Not specified";
  };
  const departmentGroups = percentageGroups(
    yearAppointments.map(appointmentDepartment),
  );
  const departmentAppointmentRates = departmentGroups.map((item) => ({
    ...item,
    percentage: population.configured && population.populations[item.label] != null ?
      Math.round((yearAppointments.filter((appointment) => appointmentDepartment(appointment) === item.label).length /
        population.populations[item.label]) * 1000) / 10 : 0,
  }));
  const requestedDepartment = (filters.appointmentDepartment ?? "all")
    .toLocaleLowerCase("en-US");
  const selectedDepartment = departmentGroups.find(
    (department) => department.key === requestedDepartment,
  );
  const includedAppointments = requestedDepartment === "all" ?
    yearAppointments : yearAppointments.filter(
      (appointment) => appointmentDepartment(appointment)
        .toLocaleLowerCase("en-US") === requestedDepartment,
    );
  const includedDepartmentRates = requestedDepartment === "all" ?
    departmentAppointmentRates : departmentAppointmentRates.filter(
      (department) => department.key === requestedDepartment,
    );
  const valuesFor = (field: "department" | "course" | "yearLevel"): string[] =>
    includedAppointments.map((appointment) => {
      const profile = userById.get(text(appointment.userId));
      if (field === "department") return appointmentDepartment(appointment);
      return text(appointment[field]) || text(profile?.[field]) || "Not specified";
    });
  const selectedPopulation = requestedDepartment === "all" ?
    population.totalPopulation : population.populations[selectedDepartment?.label ?? ""] ?? 0;
  const studentKeys = new Set(yearAppointments.map((appointment) =>
    text(appointment.studentId) || text(appointment.userId) || text(appointment.fullName),
  ).filter(Boolean));
  const statusCounts: Record<string, number> = {};
  for (const appointment of yearAppointments) {
    const status = text(appointment.status).toLowerCase() || "pending";
    statusCounts[status] = (statusCounts[status] ?? 0) + 1;
  }
  const completed = statusCounts.completed ?? statusCounts.complete ?? 0;
  const scheduled = yearAppointments.filter((appointment) =>
    !["cancelled", "canceled", "no-show", "noshow"].includes(text(appointment.status).toLowerCase()),
  ).length;
  const waitingTimes = yearAppointments.map((appointment) => {
    const created = dateValue(appointment.createdAt);
    const scheduledAt = dateValue(appointment.scheduledAt);
    return created && scheduledAt && scheduledAt >= created ?
      (scheduledAt.getTime() - created.getTime()) / 86400000 : null;
  }).filter((value): value is number => value != null);
  const waitingTimeDays = waitingTimes.length === 0 ? null :
    Math.round(waitingTimes.reduce((sum, value) => sum + value, 0) / waitingTimes.length * 10) / 10;
  const rescheduledAppointments = yearAppointments.filter((appointment) => {
    const status = text(appointment.status).toLowerCase();
    return status === "rescheduled" || status === "schedule_adjustment_needed" ||
      status === "schedule-adjustment-needed";
  }).length;

  return {
    generatedAt: now.toISOString(),
    activeWindowDays: 30,
    dateRange: {
      startDate: range.start.toISOString(),
      endDate: range.end.toISOString(),
      label: requestedStart && requestedEnd ? "Custom date range" : `Academic year ${population.schoolYear}`,
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
      totalAppointments: yearAppointments.length,
      uniqueStudentsServed: studentKeys.size,
      counselingReach: percent(studentKeys.size, population.totalPopulation),
      appointmentRate: percent(yearAppointments.length, population.totalPopulation),
      completionRate: percent(completed, scheduled),
      waitingTimeDays,
      rescheduledAppointments,
      statusCounts,
      departmentScopeKey: requestedDepartment,
      departmentScopeLabel: requestedDepartment === "all" ?
        "All departments" : selectedDepartment?.label ?? "Selected department",
      departmentOptions: departmentGroups.map(({key, label}) => ({key, label})),
      department: includedDepartmentRates,
      course: population.configured ? rateGroups(valuesFor("course"), selectedPopulation) : [],
      yearLevel: population.configured ? rateGroups(valuesFor("yearLevel"), selectedPopulation) : [],
    },
    comparison: null,
    trends: [],
  };
}

async function requireClinicalAccess(uid: string): Promise<void> {
  const snapshot = await db.collection("users").doc(uid).get();
  const legacyRole = text(snapshot.data()?.role).toLowerCase();
  const role = text(snapshot.data()?.accessRole) || legacyRole;
  if (role !== "counselor" && role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Counselor or administrator access is required.",
    );
  }
}

export const getReportAnalytics = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  await requireClinicalAccess(uid);

  const userCategory = text(request.data?.userCategory) || "all";
  if (!["all", "student", "teaching", "nonTeaching", "unspecified"].includes(userCategory)) {
    throw new HttpsError("invalid-argument", "The user category is invalid.");
  }
  const appointmentDepartment = (text(request.data?.appointmentDepartment) || "all")
    .toLocaleLowerCase("en-US");
  if (appointmentDepartment.length > 160) {
    throw new HttpsError("invalid-argument", "The department filter is invalid.");
  }

  const schoolYear = text(request.data?.schoolYear) || defaultSchoolYear();
  if (!/^\d{4}-\d{4}$/.test(schoolYear)) {
    throw new HttpsError("invalid-argument", "Use a school year such as 2026-2027.");
  }

  const startDate = text(request.data?.startDate);
  const endDate = text(request.data?.endDate);
  if ((startDate && !dateValue(startDate)) || (endDate && !dateValue(endDate)) ||
      (startDate && endDate && dateValue(startDate)! >= dateValue(endDate)!)) {
    throw new HttpsError("invalid-argument", "The report date range is invalid.");
  }

  const [usersSnapshot, appointmentsSnapshot, population, years] = await Promise.all([
    db.collection("users").where("accessRole", "==", "appUser").get(),
    db.collection("appointments").get(),
    readPopulationConfig(schoolYear),
    listAcademicYears(),
  ]);
  const populationWithYears = {...population, years};
  const result = buildReportAnalytics(
    usersSnapshot.docs.map((document) => ({
      id: document.id,
      data: document.data() as RecordData,
    })),
    appointmentsSnapshot.docs.map((document) => document.data() as RecordData),
    new Date(),
    {userCategory, appointmentDepartment, startDate: startDate || undefined, endDate: endDate || undefined},
    populationWithYears,
  );
  const previousYear = years
    .filter((year) => year.schoolYear < schoolYear)
    .sort((a, b) => b.schoolYear.localeCompare(a.schoolYear))[0];
  if (previousYear) {
    const previousPopulation = await readPopulationConfig(previousYear.schoolYear);
    const previous = buildReportAnalytics(
      usersSnapshot.docs.map((document) => ({id: document.id, data: document.data() as RecordData})),
      appointmentsSnapshot.docs.map((document) => document.data() as RecordData),
      new Date(),
      {userCategory, appointmentDepartment},
      {...previousPopulation, years: []},
    );
    result.comparison = {
      schoolYear: previousYear.schoolYear,
      totalAppointments: previous.appointments.totalAppointments,
      uniqueStudentsServed: previous.appointments.uniqueStudentsServed,
      counselingReach: previous.appointments.counselingReach,
      completionRate: previous.appointments.completionRate,
    };
  }
  result.trends = (await Promise.all(years.map(async (year) => {
    const yearPopulation = await readPopulationConfig(year.schoolYear);
    const yearReport = buildReportAnalytics(
      usersSnapshot.docs.map((document) => ({id: document.id, data: document.data() as RecordData})),
      appointmentsSnapshot.docs.map((document) => document.data() as RecordData),
      new Date(),
      {userCategory, appointmentDepartment},
      {...yearPopulation, years: []},
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
