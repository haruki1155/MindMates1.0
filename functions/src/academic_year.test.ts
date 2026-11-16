import assert from "node:assert/strict";
import {test} from "node:test";

import {
  AcademicYearError,
  academicYearPeriodState,
  parseAcademicYearInput,
  validateAcademicYearAgainstExisting,
  validateAcademicYearClose,
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

test("validateAcademicYearClose rejects missing or already-closed years", () => {
  rejects(() => validateAcademicYearClose(null), "not-found");
  rejects(() => validateAcademicYearClose({status: "closed"}), "failed-precondition");
  validateAcademicYearClose({status: "current"});
});

test("academicYearPeriodState distinguishes current, upcoming and closed", () => {
  assert.equal(academicYearPeriodState({startDate: "2025-06-01", status: "closed"}, "2026-11-16"), "closed");
  assert.equal(academicYearPeriodState({startDate: "2026-06-01", status: "current"}, "2026-11-16"), "current");
  assert.equal(academicYearPeriodState({startDate: "2027-06-01", status: "current"}, "2026-11-16"), "upcoming");
});
