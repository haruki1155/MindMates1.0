# Academic Year Management — Implementation Plan

Design: `docs/superpowers/specs/2026-11-16-academic-year-management-design.md`. TDD: write each failing test first and observe it fail before implementing.

1. **Pure academic-year domain** `functions/src/academic_year.ts` + `functions/src/academic_year.test.ts`
   - RED: `schoolYear` format (`YYYY-YYYY`, `end === start + 1`, bounds `2000..2100`); strict calendar `YYYY-MM-DD` validation; `startDate < endDate` and year bounds; overlap detection against existing years; active-year (`status !== "closed"`) uniqueness; cannot close already-closed year.
   - GREEN: `parseAcademicYearInput`, `validateAcademicYearAgainstExisting`, `validateAcademicYearClose`.
2. **Callables & emulator tests** `functions/src/counseling_population.ts` + `functions/src/academic_year_callable.test.ts`
   - RED: authorized admin creates and lists years (`getAcademicYears`, `createAcademicYear`); suspended/unverified admin, counselor, portalStaff, and student rejected (`permission-denied`); invalid/overlapping/duplicate active year rejected; concurrent `createAcademicYear` calls allow at most one active year; `closeAcademicYear` locks period, rejects double-close, records `ACADEMIC_YEAR_CREATED` / `ACADEMIC_YEAR_CLOSED` audits; `saveCounselingPopulation` fails on closed year; `getReportAnalytics` on a closed year preserves historical appointments and population.
   - GREEN: update `counseling_population.ts` with `requireStaff` + `admin` check, Firestore transactions, pure validators, and `writeAudit`.
3. **Model & repository** `lib/features/admin/domain/report_generation_models.dart`, `lib/repositories/admin_portal_repository.dart`, `test/repositories/academic_year_repository_test.dart`
   - RED: `AcademicYearRecord.periodState(...)` classifies current, upcoming, and closed accurately; `fetchAcademicYears`, `createAcademicYear` (with `startDate`/`endDate`), and `closeAcademicYear` pass expected payloads via `_callCallable`.
4. **Dedicated page & navigation** `lib/features/admin/screens/academic_year_management_page.dart`, `admin_portal.dart`, `report_generation_page.dart`
   - RED widget tests:
     - `admin_portal.dart` shows `'Academic Year'` immediately below `'Reports'` for `admin`, and hides it for `counselor` and `portalStaff`.
     - `AcademicYearManagementPage` displays current, upcoming, and closed sections, loading/empty/error-retry states, create form/dialog with validation errors, typed close confirmation, read-only closed periods, and responsive mobile/desktop layout.
     - `ReportGenerationPage` no longer renders `'Add academic year'` or `'Close this year'`, while retaining the Academic Year selector (including closed years) and existing `report_generation_year_test.dart` assertions pass.
5. **Verify**: Functions build + unit + emulator tests (PR #9 + existing report/access suites); `flutter analyze`; `report_generation_year_test.dart` + new PR #9 Flutter tests + admin suite; `git diff --check`.
6. **Independent review** via fresh subagent, fix any Critical/High/Medium findings, re-verify, and commit on `feat/pr9-academic-year-management`.
