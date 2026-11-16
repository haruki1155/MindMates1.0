// Pure domain rules for Academic Year management (evaluator requirement #4).
// Keeps the existing counseling_population/{schoolYear} status schema
// ("current" | "closed") while enforcing bounds, calendar dates, overlaps,
// and active-year uniqueness.

export type AcademicYearErrorCode =
  | "invalid-argument"
  | "already-exists"
  | "failed-precondition"
  | "not-found";

export class AcademicYearError extends Error {
  constructor(public readonly code: AcademicYearErrorCode, message: string) {
    super(message);
    this.name = "AcademicYearError";
  }
}

export type AcademicYearStatus = "current" | "closed";
export type AcademicYearPeriodState = "current" | "upcoming" | "closed";

export type AcademicYearSummary = {
  schoolYear: string;
  startDate: string;
  endDate: string;
  status: AcademicYearStatus;
};

const YEAR_PATTERN = /^(\d{4})-(\d{4})$/;
const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const MIN_START_YEAR = 2000;
const MAX_START_YEAR = 2100;

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/** Validates a YYYY-MM-DD calendar date without JS Date overflow (e.g. Feb 31). */
export function isValidIsoDate(value: string): boolean {
  const match = DATE_PATTERN.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  const probe = new Date(Date.UTC(year, month - 1, day));
  return probe.getUTCFullYear() === year &&
    probe.getUTCMonth() === month - 1 &&
    probe.getUTCDate() === day;
}

export function parseSchoolYear(value: unknown): {schoolYear: string; startYear: number; endYear: number} {
  const schoolYear = text(value);
  const match = YEAR_PATTERN.exec(schoolYear);
  if (!match) {
    throw new AcademicYearError("invalid-argument", "Use a school year such as 2027-2028.");
  }
  const startYear = Number(match[1]);
  const endYear = Number(match[2]);
  if (startYear < MIN_START_YEAR || startYear > MAX_START_YEAR || endYear !== startYear + 1) {
    throw new AcademicYearError(
      "invalid-argument",
      "School year must span two consecutive years between 2000 and 2101 (e.g. 2027-2028).",
    );
  }
  return {schoolYear, startYear, endYear};
}

export function parseAcademicYearInput(input: {
  schoolYear?: unknown;
  startDate?: unknown;
  endDate?: unknown;
}): {schoolYear: string; startDate: string; endDate: string} {
  const {schoolYear, startYear, endYear} = parseSchoolYear(input.schoolYear);
  const startDate = text(input.startDate) || `${startYear}-06-01`;
  const endDate = text(input.endDate) || `${endYear}-05-31`;
  if (!isValidIsoDate(startDate) || !isValidIsoDate(endDate)) {
    throw new AcademicYearError("invalid-argument", "Enter valid start and end calendar dates (YYYY-MM-DD).");
  }
  if (startDate >= endDate) {
    throw new AcademicYearError("invalid-argument", "Start date must be before end date.");
  }
  if (startDate < `${startYear}-01-01` || endDate > `${endYear}-12-31`) {
    throw new AcademicYearError(
      "invalid-argument",
      `Academic year dates must stay within ${startYear}-01-01 to ${endYear}-12-31.`,
    );
  }
  return {schoolYear, startDate, endDate};
}

export function validateAcademicYearAgainstExisting(
  candidate: {schoolYear: string; startDate: string; endDate: string},
  existing: readonly AcademicYearSummary[],
): void {
  if (existing.some((item) => item.schoolYear === candidate.schoolYear)) {
    throw new AcademicYearError("already-exists", "That academic year already exists.");
  }
  const active = existing.find((item) => item.status !== "closed");
  if (active) {
    throw new AcademicYearError(
      "failed-precondition",
      `Close active academic year ${active.schoolYear} before creating a new academic year.`,
    );
  }
  const overlapping = existing.find(
    (item) => candidate.startDate <= item.endDate && candidate.endDate >= item.startDate,
  );
  if (overlapping) {
    throw new AcademicYearError(
      "failed-precondition",
      `The selected dates overlap with existing academic year ${overlapping.schoolYear} (${overlapping.startDate} to ${overlapping.endDate}).`,
    );
  }
}

export function validateAcademicYearClose(existing: {status?: unknown} | null): void {
  if (!existing) {
    throw new AcademicYearError("not-found", "Academic year not found.");
  }
  if (existing.status === "closed") {
    throw new AcademicYearError("failed-precondition", "This academic year is already closed.");
  }
}

export function academicYearPeriodState(
  record: {startDate: string; status: AcademicYearStatus},
  todayIsoDate: string,
): AcademicYearPeriodState {
  if (record.status === "closed") return "closed";
  if (record.startDate && todayIsoDate < record.startDate) return "upcoming";
  return "current";
}
