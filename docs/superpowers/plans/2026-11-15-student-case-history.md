# Student Case History — Implementation Plan

Design: `docs/superpowers/specs/2026-11-15-student-case-history-design.md`. TDD: each test is run and seen failing before the code it covers.

1. **Pure domain** `functions/src/student_case_history.ts` + `student_case_history.test.ts`
   - RED: entitlement table (super-admin, college counselor, unverified college, other college, assigned case, other admin, staff target); sort newest first with `createdAt` fallback and timestamp-less records last, ID tie-break; cursor round-trip, strict "after" paging across pages with no repeats/gaps, invalid cursor rejected; page-size bounds; entry projection excludes contact details and clinical fields; `userId` mismatch never included.
   - GREEN: `decideCaseHistoryAccess`, `sortCaseHistory`, `pageCaseHistory`, `encodeCursor`/`decodeCursor`, `caseHistoryEntry`.
2. **Callable** `functions/src/student_case_history_callable.ts` (exported from `index.ts`) + emulator test `student_case_history_callable.test.ts` (creates its own verified Auth users)
   - RED: counselor for the student's verified college sees all appointments for that `userId` (current + archived) newest first; duplicate-name student excluded; unauthorized counselor, other admin, portal staff, student refused with no audit; assigned-case counselor allowed; super-admin allowed; pagination over the real query; first page audited as `COUNSELING_HISTORY_VIEWED` (actor-scoped), later pages not; clinical notes never returned.
   - GREEN: callable; add `COUNSELING_HISTORY_VIEWED` to `ACTOR_SCOPED_AUDIT_ACTIONS`.
3. **Flutter model + repository** `lib/models/student_case_history_model.dart`, `AdminPortalRepository.fetchStudentCaseHistory`
   - RED: parsing (missing timestamps, archived), repository passes `studentId`/`cursor`/`pageSize` to `getStudentCaseHistory`.
4. **Page** `lib/features/admin/screens/student_case_history_page.dart`
   - RED widget tests: grouped newest-first entries with status/archived/counselor; load more appends; empty; error + retry; permission-denied message; back navigation; narrow width without overflow.
5. **Entry points**: "Case history" on My Cases cards and appointment cards (clinical roles only). Widget tests for both.
6. **Verify**: Functions build + new unit/emulator suites + appointment/rules/access emulator regressions (temp emulator ports), `flutter analyze`, admin/models/repositories tests, `git diff --check`.
7. **Independent review** (fresh subagent), fix Critical/High/Medium, re-verify, report.
