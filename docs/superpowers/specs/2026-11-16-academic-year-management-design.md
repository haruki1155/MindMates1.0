# Academic Year Management — Design

**Date:** 2026-11-16 · **Requirement:** evaluator #4 (PR 9) · **Base:** `origin/main` `c1943f6`

## Findings
- `functions/src/counseling_population.ts` already provides `getAcademicYears`, `createAcademicYear`, `closeAcademicYear`, `getCounselingPopulation`, and `saveCounselingPopulation` over `counseling_population/{schoolYear}` (`schoolYear`, `startDate`, `endDate`, `status: "current" | "closed"`, `populations`).
- Existing gaps in `counseling_population.ts`:
  - Uses a local `requireAdmin` that only reads `users/{uid}` without checking Auth enabled/verified status or `accountStatus` (`requireStaff`).
  - `createAcademicYear` does not run in a transaction, does not check for an existing active (`status !== "closed"`) year, does not check date overlaps, does not check `endYear === startYear + 1` or real calendar dates (`2026-02-31` passes `Date.parse`), and writes no audit log.
  - `closeAcademicYear` and `saveCounselingPopulation` do not run in a transaction and allow re-closing an already closed year without auditing.
- `ReportGenerationPage` currently embeds `"Add academic year"` in `_AdminReportControls` and `"Close this year"` in `_PopulationSetup`, while `admin_portal.dart` has no dedicated Academic Year navigation destination.
- `report_generation.ts` already reads both `"current"` and `"closed"` years via `listAcademicYears()` and `readPopulationConfig()`, and matches appointments by `academicYearId` without altering historical records.

## Decisions
1. **Preserve existing status schema:** Firestore documents keep `status: "current" | "closed"` (no new stored status value). Uniqueness of active (`status !== "closed"`) years is enforced atomically in Firestore transactions.
2. **Display classification (`Current` / `Upcoming` / `Closed`):**
   - `status === "closed"` -> **Closed** (locked, read-only, selectable in Reports).
   - `status !== "closed"` and `today < startDate` -> **Upcoming** (scheduled active period not yet started).
   - `status !== "closed"` and `today >= startDate` -> **Current** (active period).
3. **Navigation placement:** `AdminPortalPage.academicYear` (`'Academic Year'`) sits immediately below `AdminPortalPage.reports` in the `Insights` section of `admin_portal.dart`, visible only to `AccessRole.admin`.
4. **Separation of concerns:** Academic year creation and closing move from `ReportGenerationPage` to `AcademicYearManagementPage`. `ReportGenerationPage` retains the Academic Year dropdown (including closed years) and department population setup (`Population locked` when closed).
5. **Server authorization & auditing:** All academic-year callables require `requireStaff(uid)` + `accessRole === "admin"`, and record `ACADEMIC_YEAR_CREATED` / `ACADEMIC_YEAR_CLOSED` via `writeAudit` inside the same transaction.
6. **Historical integrity:** Existing `academicYearId` values on appointments/walk-in imports and closed-year population configs are never modified.

## Deploy
Deploy `getAcademicYears`, `createAcademicYear`, `closeAcademicYear`, `getCounselingPopulation`, and `saveCounselingPopulation` together with the web app. No Firestore rules change, index, or data migration is required.
