# Optional Transcript / Remarks — Implementation Plan

Design: `docs/superpowers/specs/2026-11-16-case-remarks-design.md`. Stacked on `feat/pr7-student-case-history`. TDD: each test is run and seen failing before the code it covers.

1. **Pure domain** `functions/src/case_remarks.ts` + `case_remarks.test.ts`
   - RED: blank/omitted/null text is valid (→ `""`), CRLF normalized, trimmed, >10,000 chars and control characters rejected; `expectedRevision` validation; entitlement (college and assigned counselors allowed; super-admin, other admin, other-college counselor, staff target refused); save plan (first save → revision 1, stale revision → `aborted`, identical text → unchanged); view projection.
2. **Callables** `functions/src/case_remarks_callable.ts` (exported from `index.ts`) + emulator test `case_remarks_callable.test.ts`
   - RED: blank save valid; authorized counselor saves and reloads; versions kept newest first with author; stale update conflicts with no write; wrong-college, unassigned, super-admin, other admin, portal staff, student, suspended and unverified accounts refused with no write and no audit; unknown appointment refused like out-of-scope; view and update audited without the note text; remarks never appear in `getStudentCaseHistory` or `appointment_queue`.
3. **Rules** `case_remarks_rules.test.ts`: direct client read/write of `case_remarks/current` and `versions/*` denied for student, portal staff, assigned counselor, other counselor and admin.
4. **Flutter model + repository** `lib/models/case_remarks_model.dart`, `fetchCaseRemarks` / `saveCaseRemarks`.
5. **Editor widget** `case_remarks_editor.dart` + tests: optional label, blank save, reload shows saved text, save error keeps the draft, conflict keeps the draft and offers Reload, refused state, account switch shows no stale text, narrow and wide layouts without overflow.
6. **History page**: counselor-only per-case toggle that lazily loads the editor; hidden for the super-admin. Widget tests.
7. **Verify**: Functions build + new unit/emulator/rules suites + PR 7 case-history suites; `flutter analyze`; admin/models/repositories tests; `git diff --check`.
8. **Independent review** (fresh subagent), fix Critical/High/Medium, re-verify, report.
