import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";

import {requireUid} from "./access";
import {
  isValidIsoDate,
  parseSchoolYear,
  parseStoredAcademicYearStatus,
} from "./academic_year";

if (!getApps().length) initializeApp();

const db = getFirestore();

export type StudentSemesterSource = "configured" | "reportGrouping";

export type StudentSemesterRange = {
  id: string;
  label: string;
  startDateKey: string;
  endExclusiveDateKey: string;
  source: StudentSemesterSource;
};

export type StudentAcademicYearCalendar = {
  schoolYear: string;
  startDateKey: string;
  endExclusiveDateKey: string;
  status: "current" | "closed" | "planned";
  semesterRanges: StudentSemesterRange[];
};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function formatUtcIsoDate(date: Date): string {
  const year = date.getUTCFullYear().toString().padStart(4, "0");
  const month = (date.getUTCMonth() + 1).toString().padStart(2, "0");
  const day = date.getUTCDate().toString().padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function addDaysToIsoDate(isoDate: string, days: number): string {
  const year = Number(isoDate.slice(0, 4));
  const month = Number(isoDate.slice(5, 7));
  const day = Number(isoDate.slice(8, 10));
  return formatUtcIsoDate(new Date(Date.UTC(year, month - 1, day + days)));
}

function addMonthsToIsoDate(isoDate: string, months: number): string {
  const year = Number(isoDate.slice(0, 4));
  const month = Number(isoDate.slice(5, 7));
  const day = Number(isoDate.slice(8, 10));
  return formatUtcIsoDate(new Date(Date.UTC(year, month - 1 + months, day)));
}

function parseConfiguredSemesterRanges(
  raw: unknown,
  yearStartDateKey: string,
  yearEndExclusiveDateKey: string,
): StudentSemesterRange[] | null {
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const parsed: StudentSemesterRange[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (!item || typeof item !== "object" || Array.isArray(item)) return null;
    const rec = item as Record<string, unknown>;
    const id = text(rec.id) || `semester_${i + 1}`;
    const label = text(rec.label) || `Semester ${i + 1}`;
    const startDateKey = text(rec.startDateKey) || text(rec.startDate);
    let endExclusiveDateKey = text(rec.endExclusiveDateKey);
    if (!endExclusiveDateKey) {
      const endInclusive = text(rec.endDate);
      if (isValidIsoDate(endInclusive)) {
        endExclusiveDateKey = addDaysToIsoDate(endInclusive, 1);
      }
    }
    if (
      !isValidIsoDate(startDateKey) ||
      !isValidIsoDate(endExclusiveDateKey) ||
      startDateKey >= endExclusiveDateKey ||
      startDateKey < yearStartDateKey ||
      endExclusiveDateKey > yearEndExclusiveDateKey
    ) {
      return null;
    }
    parsed.push({
      id,
      label,
      startDateKey,
      endExclusiveDateKey,
      source: "configured",
    });
  }
  return parsed;
}

function deriveReportGroupingSemesters(
  startDateKey: string,
  endExclusiveDateKey: string,
): StudentSemesterRange[] {
  const midDateKey = addMonthsToIsoDate(startDateKey, 6);
  if (
    !isValidIsoDate(midDateKey) ||
    midDateKey <= startDateKey ||
    midDateKey >= endExclusiveDateKey
  ) {
    return [];
  }
  return [
    {
      id: "semester_1",
      label: "Semester 1 (report grouping)",
      startDateKey,
      endExclusiveDateKey: midDateKey,
      source: "reportGrouping",
    },
    {
      id: "semester_2",
      label: "Semester 2 (report grouping)",
      startDateKey: midDateKey,
      endExclusiveDateKey,
      source: "reportGrouping",
    },
  ];
}

/**
 * Pure fail-closed builder that converts raw `counseling_population` documents
 * into non-sensitive student academic calendar metadata.
 */
export function buildStudentAcademicCalendarYears(
  docs: ReadonlyArray<{id: string; data: Record<string, unknown>}>,
): StudentAcademicYearCalendar[] {
  const result: StudentAcademicYearCalendar[] = [];
  for (const doc of docs) {
    const rawYear = text(doc.data.schoolYear) || doc.id;
    let schoolYear: string;
    try {
      schoolYear = parseSchoolYear(rawYear).schoolYear;
    } catch {
      continue;
    }

    const status = parseStoredAcademicYearStatus(doc.data.status);
    if (status === "voided" || status === "unknown") {
      continue;
    }

    const startDate = text(doc.data.startDate);
    const endDate = text(doc.data.endDate);
    if (
      !isValidIsoDate(startDate) ||
      !isValidIsoDate(endDate) ||
      startDate >= endDate
    ) {
      continue;
    }

    const startDateKey = startDate;
    const endExclusiveDateKey = addDaysToIsoDate(endDate, 1);
    const rawSemesters = doc.data.semesterRanges ?? doc.data.semesters;
    const hasConfiguredSemestersField =
      rawSemesters !== undefined &&
      rawSemesters !== null &&
      (!Array.isArray(rawSemesters) || rawSemesters.length > 0);
    const configuredSemesters = hasConfiguredSemestersField
      ? parseConfiguredSemesterRanges(
        rawSemesters,
        startDateKey,
        endExclusiveDateKey,
      )
      : null;
    const semesterRanges = hasConfiguredSemestersField
      ? (configuredSemesters ?? [])
      : deriveReportGroupingSemesters(startDateKey, endExclusiveDateKey);

    result.push({
      schoolYear,
      startDateKey,
      endExclusiveDateKey,
      status,
      semesterRanges,
    });
  }

  return result.sort((a, b) => b.schoolYear.localeCompare(a.schoolYear));
}

async function requireActiveAppUser(uid: string): Promise<void> {
  const [authUser, profileSnap] = await Promise.all([
    getAuth()
      .getUser(uid)
      .catch(() => null),
    db.collection("users").doc(uid).get(),
  ]);

  if (!authUser || authUser.disabled || !authUser.emailVerified) {
    throw new HttpsError(
      "permission-denied",
      "An active, verified account is required.",
    );
  }

  const data = profileSnap.data();
  const role = text(data?.populationRole || data?.declaredRole || data?.role);
  const accountStatus =
      data?.accountStatus == null ? "active" : text(data.accountStatus);
  if (
    !profileSnap.exists ||
    data?.accessRole !== "appUser" ||
    data?.staffAccountStatus != null ||
    !["student", "teaching", "nonTeaching"].includes(role) ||
    accountStatus !== "active"
  ) {
    throw new HttpsError(
      "permission-denied",
      "An active app-user profile is required.",
    );
  }
}

export async function getStudentAcademicCalendarHandler(
  request: CallableRequest,
): Promise<{years: StudentAcademicYearCalendar[]}> {
  const uid = requireUid(request);
  await requireActiveAppUser(uid);
  const snapshot = await db.collection("counseling_population").get();
  const years = buildStudentAcademicCalendarYears(
    snapshot.docs.map((doc) => ({id: doc.id, data: doc.data()})),
  );
  return {years};
}

export const getStudentAcademicCalendar = onCall(
  {enforceAppCheck: true},
  getStudentAcademicCalendarHandler,
);

export const getStudentAcademicCalendarDev = onCall(
  {enforceAppCheck: false},
  getStudentAcademicCalendarHandler,
);
