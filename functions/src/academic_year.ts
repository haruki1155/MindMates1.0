// Pure domain rules for Academic Year management (lifecycle states:
// planned, current [Active], closed, voided; plus unknown fail-closed).
// Authoritative dates follow Asia/Manila (UTC+8).

export type AcademicYearErrorCode =
  | "invalid-argument"
  | "already-exists"
  | "failed-precondition"
  | "aborted"
  | "not-found";

export class AcademicYearError extends Error {
  constructor(public readonly code: AcademicYearErrorCode, message: string) {
    super(message);
    this.name = "AcademicYearError";
  }
}

export type AcademicYearStatus = "planned" | "current" | "closed" | "voided" | "unknown";
export type AcademicYearPeriodState = "planned" | "current" | "upcoming" | "closed" | "voided" | "unknown";

export type AcademicYearSummary = {
  schoolYear: string;
  startDate: string;
  endDate: string;
  status: AcademicYearStatus;
  revision?: number;
  voidReason?: string | null;
};

const YEAR_PATTERN = /^(\d{4})-(\d{4})$/;
const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const MIN_START_YEAR = 2000;
const MAX_START_YEAR = 2100;
export const MAX_PLANNING_AHEAD_YEARS = 1;
export const MIN_VOID_REASON_LENGTH = 10;
export const MAX_VOID_REASON_LENGTH = 500;

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/** Authoritative calendar date (YYYY-MM-DD) in Asia/Manila (UTC+8). */
export function manilaTodayIso(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

/** Academic start year (June-May cycle) for an Asia/Manila calendar date. */
export function manilaCurrentSchoolStartYear(todayManila = manilaTodayIso()): number {
  const year = Number(todayManila.slice(0, 4));
  const month = Number(todayManila.slice(5, 7));
  return month >= 6 ? year : year - 1;
}

/** Parses stored Firestore status fail-closed; never coerces unknown to current. */
export function parseStoredAcademicYearStatus(value: unknown): AcademicYearStatus {
  if (value === "planned" || value === "current" || value === "closed" || value === "voided") {
    return value;
  }
  return "unknown";
}

export function revisionOfAcademicYear(data: {revision?: unknown} | null | undefined): number {
  const rev = data?.revision;
  return typeof rev === "number" && Number.isSafeInteger(rev) && rev >= 0 ? rev : 0;
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

/** Legacy compatibility validator retained for direct unit tests. */
export function validateAcademicYearAgainstExisting(
  candidate: {schoolYear: string; startDate: string; endDate: string},
  existing: readonly AcademicYearSummary[],
): void {
  if (existing.some((item) => item.schoolYear === candidate.schoolYear && item.status !== "voided")) {
    throw new AcademicYearError("already-exists", "That academic year already exists.");
  }
  const active = existing.find((item) => item.status === "current");
  if (active) {
    throw new AcademicYearError(
      "failed-precondition",
      `Close active academic year ${active.schoolYear} before creating a new academic year.`,
    );
  }
  const overlapping = existing.find(
    (item) => item.status !== "voided" && candidate.startDate <= item.endDate && candidate.endDate >= item.startDate,
  );
  if (overlapping) {
    throw new AcademicYearError(
      "failed-precondition",
      `The selected dates overlap with existing academic year ${overlapping.schoolYear} (${overlapping.startDate} to ${overlapping.endDate}).`,
    );
  }
}

export type CreateAcademicYearDecision = {
  kind: "create" | "reinstate";
  initialStatus: "planned" | "current";
  nextRevision: number;
  previousVoidRevision: number | null;
};

/**
 * Full server validation & initial-state decision for creating or reinstating
 * a voided academic year using Asia/Manila boundaries.
 */
export function decideAcademicYearCreate(input: {
  candidate: {schoolYear: string; startDate: string; endDate: string};
  existing: readonly AcademicYearSummary[];
  todayManila: string;
  extendedLifecycleEnabled: boolean;
  maxPlanningAheadYears?: number;
}): CreateAcademicYearDecision {
  const {candidate, existing, todayManila, extendedLifecycleEnabled} = input;
  const maxAhead = input.maxPlanningAheadYears ?? MAX_PLANNING_AHEAD_YEARS;
  const {startYear} = parseSchoolYear(candidate.schoolYear);
  const currentStartYear = manilaCurrentSchoolStartYear(todayManila);
  if (startYear > currentStartYear + maxAhead) {
    throw new AcademicYearError(
      "failed-precondition",
      `Academic years cannot be created more than ${maxAhead} year ahead of ${currentStartYear}-${currentStartYear + 1} (${todayManila} Asia/Manila).`,
    );
  }
  if (candidate.endDate < todayManila) {
    throw new AcademicYearError(
      "invalid-argument",
      `Cannot create an open academic year whose end date (${candidate.endDate}) has already passed (${todayManila} Asia/Manila).`,
    );
  }

  const sameYear = existing.find((item) => item.schoolYear === candidate.schoolYear);
  if (sameYear && sameYear.status !== "voided") {
    throw new AcademicYearError("already-exists", "That academic year already exists.");
  }

  const overlapping = existing.find(
    (item) => item.status !== "voided" && candidate.startDate <= item.endDate && candidate.endDate >= item.startDate,
  );
  if (overlapping) {
    throw new AcademicYearError(
      "failed-precondition",
      `The selected dates overlap with existing academic year ${overlapping.schoolYear} (${overlapping.startDate} to ${overlapping.endDate}).`,
    );
  }

  const isFutureStart = todayManila < candidate.startDate;
  if (isFutureStart) {
    if (!extendedLifecycleEnabled) {
      throw new AcademicYearError(
        "failed-precondition",
        "Creating planned future academic years is disabled until updated report analytics are deployed.",
      );
    }
    const existingPlanned = existing.find((item) => item.status === "planned");
    if (existingPlanned) {
      throw new AcademicYearError(
        "failed-precondition",
        `Planned academic year ${existingPlanned.schoolYear} already exists. Activate or void it before planning another.`,
      );
    }
    const prevVoidRev = sameYear ? revisionOfAcademicYear(sameYear) : null;
    return {
      kind: sameYear ? "reinstate" : "create",
      initialStatus: "planned",
      nextRevision: prevVoidRev == null ? 1 : prevVoidRev + 1,
      previousVoidRevision: prevVoidRev,
    };
  }

  const active = existing.find((item) => item.status === "current");
  if (active) {
    throw new AcademicYearError(
      "failed-precondition",
      `Close active academic year ${active.schoolYear} before activating ${candidate.schoolYear}.`,
    );
  }
  const prevVoidRev = sameYear ? revisionOfAcademicYear(sameYear) : null;
  return {
    kind: sameYear ? "reinstate" : "create",
    initialStatus: "current",
    nextRevision: prevVoidRev == null ? 1 : prevVoidRev + 1,
    previousVoidRevision: prevVoidRev,
  };
}

export function validateAcademicYearActivation(input: {
  target: AcademicYearSummary | null;
  existing: readonly AcademicYearSummary[];
  todayManila: string;
  expectedRevision?: number;
}): {nextRevision: number} {
  const {target, existing, todayManila, expectedRevision} = input;
  if (!target) {
    throw new AcademicYearError("not-found", "Academic year not found.");
  }
  if (target.status === "current") {
    throw new AcademicYearError("failed-precondition", "This academic year is already active.");
  }
  if (target.status !== "planned") {
    throw new AcademicYearError(
      "failed-precondition",
      `Only planned academic years can be activated (current state: ${target.status}).`,
    );
  }
  const currentRevision = revisionOfAcademicYear(target);
  if (expectedRevision !== undefined) {
    if (!Number.isSafeInteger(expectedRevision) || expectedRevision !== currentRevision) {
      throw new AcademicYearError("aborted", "This academic year changed concurrently. Reload and try again.");
    }
  }
  const otherActive = existing.find((item) => item.schoolYear !== target.schoolYear && item.status === "current");
  if (otherActive) {
    throw new AcademicYearError(
      "failed-precondition",
      `Close active academic year ${otherActive.schoolYear} before activating ${target.schoolYear}.`,
    );
  }
  if (todayManila < target.startDate) {
    throw new AcademicYearError(
      "failed-precondition",
      `Cannot activate ${target.schoolYear} before its start date (${target.startDate} Asia/Manila).`,
    );
  }
  if (todayManila > target.endDate) {
    throw new AcademicYearError(
      "failed-precondition",
      `Cannot activate ${target.schoolYear} after its end date (${target.endDate} Asia/Manila).`,
    );
  }
  return {nextRevision: currentRevision + 1};
}

export function validateAcademicYearClose(
  existing: {status?: unknown; revision?: unknown} | null,
  expectedRevision?: number,
): {nextRevision: number} {
  if (!existing) {
    throw new AcademicYearError("not-found", "Academic year not found.");
  }
  const status = parseStoredAcademicYearStatus(existing.status);
  if (status === "closed") {
    throw new AcademicYearError("failed-precondition", "This academic year is already closed.");
  }
  if (status === "voided") {
    throw new AcademicYearError("failed-precondition", "Voided academic years cannot be closed.");
  }
  if (status === "unknown") {
    throw new AcademicYearError("failed-precondition", "Academic year has an unrecognized status and cannot be closed.");
  }
  const currentRevision = revisionOfAcademicYear(existing);
  if (expectedRevision !== undefined) {
    if (!Number.isSafeInteger(expectedRevision) || expectedRevision !== currentRevision) {
      throw new AcademicYearError("aborted", "This academic year changed concurrently. Reload and try again.");
    }
  }
  return {nextRevision: currentRevision + 1};
}

export function validateAcademicYearVoid(input: {
  target: (AcademicYearSummary & {populations?: unknown}) | null;
  confirmation: unknown;
  reason: unknown;
  expectedRevision?: unknown;
  appointmentRefCount: number;
  walkInImportRefCount: number;
  reportRefCount: number;
}): {reason: string; nextRevision: number} {
  const {target} = input;
  if (!target) {
    throw new AcademicYearError("not-found", "Academic year not found.");
  }
  if (target.status === "voided") {
    throw new AcademicYearError("failed-precondition", "This academic year has already been voided.");
  }
  if (target.status === "closed") {
    throw new AcademicYearError("failed-precondition", "Closed academic years are immutable historical records and cannot be voided.");
  }
  const expectedConfirmation = `VOID ${target.schoolYear}`;
  if (text(input.confirmation) !== expectedConfirmation) {
    throw new AcademicYearError("invalid-argument", `Type "${expectedConfirmation}" to confirm voiding.`);
  }
  const reason = text(input.reason);
  if (reason.length < MIN_VOID_REASON_LENGTH || reason.length > MAX_VOID_REASON_LENGTH) {
    throw new AcademicYearError(
      "invalid-argument",
      `Enter a written reason (${MIN_VOID_REASON_LENGTH}-${MAX_VOID_REASON_LENGTH} characters).`,
    );
  }
  const currentRevision = revisionOfAcademicYear(target);
  if (typeof input.expectedRevision !== "number" ||
      !Number.isSafeInteger(input.expectedRevision) ||
      input.expectedRevision !== currentRevision) {
    throw new AcademicYearError("aborted", "This academic year changed concurrently. Reload and verify its state.");
  }
  const pops = target.populations;
  if (pops && typeof pops === "object" && !Array.isArray(pops)) {
    const hasConfigured = Object.values(pops as Record<string, unknown>)
      .some((v) => typeof v === "number" && v > 0);
    if (hasConfigured || Object.keys(pops as Record<string, unknown>).length > 0) {
      throw new AcademicYearError(
        "failed-precondition",
        "Cannot void an academic year that has saved counseling population figures.",
      );
    }
  }
  if (input.appointmentRefCount > 0 || input.walkInImportRefCount > 0 || input.reportRefCount > 0) {
    throw new AcademicYearError(
      "failed-precondition",
      "Cannot void an academic year referenced by appointments, walk-in imports, or reports.",
    );
  }
  return {reason, nextRevision: currentRevision + 1};
}

export function academicYearPeriodState(
  record: {startDate: string; endDate?: string; status: AcademicYearStatus | string},
  todayIsoDate: string,
): AcademicYearPeriodState {
  const status = parseStoredAcademicYearStatus(record.status);
  if (status === "voided") return "voided";
  if (status === "closed") return "closed";
  if (status === "planned") return "planned";
  if (status === "unknown") return "unknown";
  if (record.startDate && todayIsoDate < record.startDate) return "upcoming";
  return "current";
}
