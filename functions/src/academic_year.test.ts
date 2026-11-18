import assert from "node:assert/strict";
import {test} from "node:test";

import {
  AcademicYearError,
  academicYearPeriodState,
  decideAcademicYearCreate,
  manilaCurrentSchoolStartYear,
  manilaTodayIso,
  parseAcademicYearInput,
  parseStoredAcademicYearStatus,
  validateAcademicYearActivation,
  validateAcademicYearAgainstExisting,
  validateAcademicYearClose,
  validateAcademicYearVoid,
} from "./academic_year";

function rejects(fn: () => unknown, code: string) {
  assert.throws(fn, (e: unknown) => e instanceof AcademicYearError && e.code === code);
}

test("parseAcademicYearInput accepts valid consecutive school years and defaults dates", () => {
  assert.deepEqual(parseAcademicYearInput({schoolYear: "2026-2027"}), {
    schoolYear: "2026-2027",
    startDate: "2026-06-01",
    endDate: "2027-05-31",
  });
  assert.deepEqual(parseAcademicYearInput({
    schoolYear: "2026-2027",
    startDate: "2026-08-15",
    endDate: "2027-06-10",
  }), {
    schoolYear: "2026-2027",
    startDate: "2026-08-15",
    endDate: "2027-06-10",
  });
});

test("parseAcademicYearInput rejects invalid school years, non-consecutive bounds and impossible calendar dates", () => {
  for (const badYear of ["", "2026", "2026-2026", "2026-2028", "1999-2000", "2101-2102", "abcd-efgh"]) {
    rejects(() => parseAcademicYearInput({schoolYear: badYear}), "invalid-argument");
  }
  for (const badRange of [
    {schoolYear: "2026-2027", startDate: "2026-02-31", endDate: "2027-05-31"},
    {schoolYear: "2026-2027", startDate: "2027-06-01", endDate: "2027-05-31"},
    {schoolYear: "2026-2027", startDate: "2026-06-01", endDate: "2026-06-01"},
    {schoolYear: "2026-2027", startDate: "2025-12-31", endDate: "2027-05-31"},
    {schoolYear: "2026-2027", startDate: "2026-06-01", endDate: "2028-01-01"},
    {schoolYear: "2026-2027", startDate: "2026/06/01", endDate: "2027-05-31"},
  ]) {
    rejects(() => parseAcademicYearInput(badRange), "invalid-argument");
  }
});

test("validateAcademicYearAgainstExisting rejects duplicates, active-year duplicates and date overlaps", () => {
  const closedPrev = {schoolYear: "2025-2026", startDate: "2025-06-01", endDate: "2026-05-31", status: "closed" as const};
  const current = {schoolYear: "2026-2027", startDate: "2026-06-01", endDate: "2027-05-31", status: "current" as const};

  // Duplicate ID
  rejects(
    () => validateAcademicYearAgainstExisting(
      {schoolYear: "2025-2026", startDate: "2025-06-01", endDate: "2026-05-31"},
      [closedPrev],
    ),
    "already-exists",
  );

  // Active-year uniqueness
  rejects(
    () => validateAcademicYearAgainstExisting(
      {schoolYear: "2027-2028", startDate: "2027-06-01", endDate: "2028-05-31"},
      [closedPrev, current],
    ),
    "failed-precondition",
  );

  // Overlap with a closed year (e.g. boundary day 2026-05-31)
  rejects(
    () => validateAcademicYearAgainstExisting(
      {schoolYear: "2026-2027", startDate: "2026-05-31", endDate: "2027-05-30"},
      [closedPrev],
    ),
    "failed-precondition",
  );

  // Valid non-overlapping year after all existing years are closed
  validateAcademicYearAgainstExisting(
    {schoolYear: "2026-2027", startDate: "2026-06-01", endDate: "2027-05-31"},
    [closedPrev],
  );
});

test("validateAcademicYearClose enforces end-date Manila boundary, confirmation, revision, and current status", () => {
  const currentTarget = {
    schoolYear: "2026-2027",
    startDate: "2026-06-01",
    endDate: "2027-05-31",
    status: "current",
    revision: 2,
  };
  const baseValid = {
    target: currentTarget,
    todayManila: "2027-06-01",
    confirmation: "CLOSE 2026-2027",
    expectedRevision: 2,
  };

  rejects(() => validateAcademicYearClose({...baseValid, target: null}), "not-found");
  rejects(() => validateAcademicYearClose({...baseValid, target: {...currentTarget, status: "closed"}}), "failed-precondition");
  rejects(() => validateAcademicYearClose({...baseValid, target: {...currentTarget, status: "planned"}}), "failed-precondition");
  rejects(() => validateAcademicYearClose({...baseValid, target: {...currentTarget, status: "voided"}}), "failed-precondition");
  rejects(() => validateAcademicYearClose({...baseValid, target: {...currentTarget, status: "unknown"}}), "failed-precondition");
  rejects(() => validateAcademicYearClose({...baseValid, target: {...currentTarget, status: "legacy_corrupted"}}), "failed-precondition");

  // Cannot close before or on the approved end date (Manila UTC+8).
  rejects(() => validateAcademicYearClose({...baseValid, todayManila: "2026-11-17"}), "failed-precondition");
  rejects(() => validateAcademicYearClose({...baseValid, todayManila: "2027-05-31"}), "failed-precondition");

  // Confirmation & revision checks.
  rejects(() => validateAcademicYearClose({...baseValid, confirmation: "close 2026-2027"}), "invalid-argument");
  rejects(() => validateAcademicYearClose({...baseValid, confirmation: ""}), "invalid-argument");
  rejects(() => validateAcademicYearClose({...baseValid, expectedRevision: "2"}), "invalid-argument");
  rejects(() => validateAcademicYearClose({...baseValid, expectedRevision: -1}), "invalid-argument");
  rejects(() => validateAcademicYearClose({...baseValid, expectedRevision: 1.5}), "invalid-argument");
  rejects(() => validateAcademicYearClose({...baseValid, expectedRevision: 1}), "aborted");
  rejects(() => validateAcademicYearClose({...baseValid, expectedRevision: undefined}), "aborted");

  const ok = validateAcademicYearClose(baseValid);
  assert.equal(ok.nextRevision, 3);
});

test("academicYearPeriodState distinguishes planned, current, upcoming, closed, voided and unknown", () => {
  assert.equal(academicYearPeriodState({startDate: "2025-06-01", endDate: "2026-05-31", status: "closed"}, "2026-11-16"), "closed");
  assert.equal(academicYearPeriodState({startDate: "2026-06-01", endDate: "2027-05-31", status: "current"}, "2026-11-16"), "current");
  assert.equal(academicYearPeriodState({startDate: "2027-06-01", endDate: "2028-05-31", status: "current"}, "2026-11-16"), "upcoming");
  assert.equal(academicYearPeriodState({startDate: "2027-06-01", endDate: "2028-05-31", status: "planned"}, "2026-11-16"), "planned");
  assert.equal(academicYearPeriodState({startDate: "2028-06-01", endDate: "2029-05-31", status: "voided"}, "2026-11-16"), "voided");
  assert.equal(academicYearPeriodState({startDate: "2026-06-01", endDate: "2027-05-31", status: "unknown"}, "2026-11-16"), "unknown");
});

test("manilaTodayIso and manilaCurrentSchoolStartYear respect UTC+8 boundaries", () => {
  // 2026-05-31 23:59 Manila = 2026-05-31 15:59Z
  assert.equal(manilaTodayIso(new Date("2026-05-31T15:59:00Z")), "2026-05-31");
  assert.equal(manilaCurrentSchoolStartYear("2026-05-31"), 2025);
  // 2026-06-01 00:01 Manila = 2026-05-31 16:01Z (same UTC day May 31, new Manila June 1)
  assert.equal(manilaTodayIso(new Date("2026-05-31T16:01:00Z")), "2026-06-01");
  assert.equal(manilaCurrentSchoolStartYear("2026-06-01"), 2026);
});

test("parseStoredAcademicYearStatus never coerces unknown status to current", () => {
  assert.equal(parseStoredAcademicYearStatus("current"), "current");
  assert.equal(parseStoredAcademicYearStatus("planned"), "planned");
  assert.equal(parseStoredAcademicYearStatus("closed"), "closed");
  assert.equal(parseStoredAcademicYearStatus("voided"), "voided");
  for (const bad of [null, undefined, "", "active", "draft", "archived", 42]) {
    assert.equal(parseStoredAcademicYearStatus(bad), "unknown");
  }
});

test("decideAcademicYearCreate enforces planning horizon, Manila bounds, planned status, and void reuse", () => {
  const today = "2026-11-17";
  const current26 = {schoolYear: "2026-2027", startDate: "2026-06-01", endDate: "2027-05-31", status: "current" as const, revision: 1};

  // Distant future (> +1 school year) is rejected even when no active year exists.
  rejects(
    () => decideAcademicYearCreate({
      candidate: {schoolYear: "2028-2029", startDate: "2028-06-01", endDate: "2029-05-31"},
      existing: [],
      todayManila: today,
      extendedLifecycleEnabled: true,
    }),
    "failed-precondition",
  );

  // Already-ended period cannot be created as open.
  rejects(
    () => decideAcademicYearCreate({
      candidate: {schoolYear: "2025-2026", startDate: "2025-06-01", endDate: "2026-05-31"},
      existing: [],
      todayManila: today,
      extendedLifecycleEnabled: true,
    }),
    "invalid-argument",
  );

  // Preparing next year (2027-2028) creates status "planned" — never "current" prematurely.
  const plannedDecision = decideAcademicYearCreate({
    candidate: {schoolYear: "2027-2028", startDate: "2027-06-01", endDate: "2028-05-31"},
    existing: [current26],
    todayManila: today,
    extendedLifecycleEnabled: true,
  });
  assert.equal(plannedDecision.kind, "create");
  assert.equal(plannedDecision.initialStatus, "planned");

  // Second planned year is rejected.
  const planned27 = {schoolYear: "2027-2028", startDate: "2027-06-01", endDate: "2028-05-31", status: "planned" as const, revision: 1};
  rejects(
    () => decideAcademicYearCreate({
      candidate: {schoolYear: "2027-2028", startDate: "2027-06-01", endDate: "2028-05-31"},
      existing: [current26, planned27],
      todayManila: today,
      extendedLifecycleEnabled: true,
    }),
    "already-exists",
  );

  // Compat mode (extendedLifecycleEnabled = false) refuses writing new "planned" status.
  rejects(
    () => decideAcademicYearCreate({
      candidate: {schoolYear: "2027-2028", startDate: "2027-06-01", endDate: "2028-05-31"},
      existing: [current26],
      todayManila: today,
      extendedLifecycleEnabled: false,
    }),
    "failed-precondition",
  );

  // Reinstatement of previously voided 2028-2029 succeeds when date reaches 2028 and ignores old voided range.
  const voided28 = {schoolYear: "2028-2029", startDate: "2028-06-01", endDate: "2029-05-31", status: "voided" as const, revision: 2};
  const reinstateDecision = decideAcademicYearCreate({
    candidate: {schoolYear: "2028-2029", startDate: "2028-06-01", endDate: "2029-05-31"},
    existing: [voided28],
    todayManila: "2028-06-02",
    extendedLifecycleEnabled: true,
  });
  assert.equal(reinstateDecision.kind, "reinstate");
  assert.equal(reinstateDecision.initialStatus, "current");
  assert.equal(reinstateDecision.nextRevision, 3);
});

test("validateAcademicYearActivation enforces start date, single active year, and state", () => {
  const current26 = {schoolYear: "2026-2027", startDate: "2026-06-01", endDate: "2027-05-31", status: "current" as const, revision: 1};
  const planned27 = {schoolYear: "2027-2028", startDate: "2027-06-01", endDate: "2028-05-31", status: "planned" as const, revision: 1};

  rejects(() => validateAcademicYearActivation({target: null, existing: [], todayManila: "2027-06-01"}), "not-found");
  // Cannot activate while 2026-2027 is still open.
  rejects(() => validateAcademicYearActivation({target: planned27, existing: [current26, planned27], todayManila: "2027-06-01"}), "failed-precondition");
  // Cannot activate before startDate.
  rejects(() => validateAcademicYearActivation({target: planned27, existing: [{...current26, status: "closed"}, planned27], todayManila: "2027-05-31"}), "failed-precondition");
  // Cannot activate after endDate.
  rejects(() => validateAcademicYearActivation({target: planned27, existing: [{...current26, status: "closed"}, planned27], todayManila: "2028-06-01"}), "failed-precondition");
  // Cannot activate closed or voided years.
  rejects(() => validateAcademicYearActivation({target: {...planned27, status: "closed"}, existing: [], todayManila: "2027-06-01"}), "failed-precondition");
  rejects(() => validateAcademicYearActivation({target: {...planned27, status: "voided"}, existing: [], todayManila: "2027-06-01"}), "failed-precondition");
  // Succeeds when previous year is closed and Manila date is inside period.
  const ok = validateAcademicYearActivation({
    target: planned27,
    existing: [{...current26, status: "closed"}, planned27],
    todayManila: "2027-06-01",
    expectedRevision: 1,
  });
  assert.equal(ok.nextRevision, 2);
});

test("validateAcademicYearVoid enforces confirmation, reason, revision, empty population, and zero refs", () => {
  const baseTarget = {
    schoolYear: "2028-2029",
    startDate: "2028-06-01",
    endDate: "2029-05-31",
    status: "current" as const,
    revision: 0,
    populations: {},
  };
  const validInput = {
    target: baseTarget,
    confirmation: "VOID 2028-2029",
    reason: "Erroneous premature future academic year.",
    expectedRevision: 0,
    appointmentRefCount: 0,
    walkInImportRefCount: 0,
    reportRefCount: 0,
  };

  rejects(() => validateAcademicYearVoid({...validInput, target: null}), "not-found");
  rejects(() => validateAcademicYearVoid({...validInput, target: {...baseTarget, status: "closed"}}), "failed-precondition");
  rejects(() => validateAcademicYearVoid({...validInput, target: {...baseTarget, status: "voided"}}), "failed-precondition");
  rejects(() => validateAcademicYearVoid({...validInput, target: {...baseTarget, status: "unknown"}}), "failed-precondition");
  rejects(() => validateAcademicYearVoid({...validInput, confirmation: "void 2028-2029"}), "invalid-argument");
  rejects(() => validateAcademicYearVoid({...validInput, reason: "too short"}), "invalid-argument");
  rejects(() => validateAcademicYearVoid({...validInput, expectedRevision: "0"}), "invalid-argument");
  rejects(() => validateAcademicYearVoid({...validInput, expectedRevision: -1}), "invalid-argument");
  rejects(() => validateAcademicYearVoid({...validInput, expectedRevision: 2}), "aborted");
  rejects(() => validateAcademicYearVoid({...validInput, target: {...baseTarget, populations: {CITE: 10}}}), "failed-precondition");
  rejects(() => validateAcademicYearVoid({...validInput, appointmentRefCount: 1}), "failed-precondition");
  rejects(() => validateAcademicYearVoid({...validInput, walkInImportRefCount: 1}), "failed-precondition");
  rejects(() => validateAcademicYearVoid({...validInput, reportRefCount: 1}), "failed-precondition");

  const ok = validateAcademicYearVoid(validInput);
  assert.equal(ok.nextRevision, 1);
});
