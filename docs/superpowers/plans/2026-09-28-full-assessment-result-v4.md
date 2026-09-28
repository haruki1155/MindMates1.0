# Full Assessment Result V4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Present a complete, transparent, server-authoritative V4 Full Assessment Result for Student, Teaching, and Non-Teaching users.

**Architecture:** Existing V4 calculators add deterministic explanation fields without changing scores or persistence. Flutter renders only the callable payload; a scoring-free widget joins immutable `itemSnapshot` and `responses` for historical review.

**Tech Stack:** Firebase Functions TypeScript, Flutter/Dart, Flutter widget tests, Node built-in test runner.

**Spec:** `docs/superpowers/specs/2026-09-28-full-assessment-result-v4-design.md`

## Global Constraints

- Preserve V4 normalization, thresholds, profile precedence, focus/strength selection, completion rules, question sets, and server-authoritative persistence.
- Preserve Student `studentSummary`; UI resolves `userSummary ?? studentSummary`.
- Add exactly five role-ordered `interpretation.domainSummaries` entries.
- Never rescore in Flutter or rebuild historical questions from a live catalog.
- Never show internal concern, response value, direction, catalog hash, numeric overall scores, clinical labels, or validation claims.
- Do not modify Appointment, Mental Health Summary, ReportRepository, counselor workflow, authentication, or production deployment.
- Keep edits limited to named files; avoid unrelated formatter or refactor churn.

## Review Focus

- Historical result text must come from saved `itemSnapshot.text`, even after a catalog changes — Task 3 test.
- Skipped answers must render **Not answered**, without a raw value — Task 3 test.
- Missing optional V4 fields must render safe fallback content — Task 2 test.
- Student records with only `studentSummary` must remain readable — Task 2 test.
- Employee roles must retain their labels and non-performance disclaimer — Tasks 1 and 2 tests.

---

### Task 1: Phase 1 — Server interpretation contract

**Files:**
- Modify: `functions/src/assessment/student_v4_calculator.ts`
- Modify: `functions/src/assessment/workplace_v4_calculator.ts`
- Modify: `functions/src/assessment/student_v4_calculator.test.ts`
- Modify: `functions/src/assessment/workplace_v4_calculator.test.ts

**Interfaces:**
- Consumes: current `profileStatus`, `domainResults`, focus/strength selections, and `responseQuality`.
- Produces: `instrument.referenceSetVersion`, `interpretation.userSummary`, `interpretation.overallResponseSummary`, and five `interpretation.domainSummaries` for Flutter.

- [ ] **Step 1: Write failing Student contract tests**
  Assert `referenceSetVersion === 'mindmate_wellbeing_refs_v1'`, retained `studentSummary`, a non-empty `userSummary` and `overallResponseSummary`, and five ordered domain summaries. Every entry must have all seven contract keys: `domainId`, `domainLabel`, `status`, `summary`, `focusInsight`, `strengthInsight`, and `suggestedAction`; optional insight/action values may be null. Equal input must deep-equal the generated interpretation.

- [ ] **Step 2: Build Functions, then run the Student test red**
  Run: `npm.cmd --prefix functions run build`
  Expected: TypeScript build succeeds and refreshes `functions/lib`.
  Run: `node --test functions/lib/assessment/student_v4_calculator.test.js`
  Expected: FAIL because the metadata and new interpretation fields do not yet exist.

- [ ] **Step 3: Implement deterministic Student builders**
  Add pure helpers in `student_v4_calculator.ts` that derive five summaries from existing domain detail and generate an overall five-domain pattern with completeness. Preserve all score and compatibility fields; set `userSummary` without deleting or changing `studentSummary`.

- [ ] **Step 4: Build Functions, then run the Student test green**
  Run: `npm.cmd --prefix functions run build`
  Expected: TypeScript build succeeds and refreshes `functions/lib`.
  Run: `node --test functions/lib/assessment/student_v4_calculator.test.js`
  Expected: PASS.

- [ ] **Step 5: Write failing workplace contract tests**
  For Teaching and Non-Teaching, assert the same seven-key contract and determinism. Assert the complete ordered five-label sets: Teaching uses Teaching Workload & Role Demands, Collegial & Organizational Support, Professional Engagement & Meaning, Sleep & Rest, Emotional Well-Being; Non-Teaching uses Workload & Role Demands, Supervisor, Team & Organizational Support, Work Engagement & Meaning, Sleep & Rest, Emotional Well-Being. Assert employee summaries retain non-performance wording.

- [ ] **Step 6: Build Functions, then run workplace tests red**
  Run: `npm.cmd --prefix functions run build`
  Expected: TypeScript build succeeds and refreshes `functions/lib`.
  Run: `node --test functions/lib/assessment/workplace_v4_calculator.test.js`
  Expected: FAIL because workplace reference metadata and the new interpretation fields do not yet exist.

- [ ] **Step 7: Implement deterministic workplace builders**
  In `workplace_v4_calculator.ts`, produce the same fields using `WorkplaceV4Config.domainOrder`, `domainLabels`, and existing insight/action templates. Do not alter profile logic or use Student copy.

- [ ] **Step 8: Verify focused Functions work**
  Run: `npm.cmd --prefix functions run build`
  Expected: TypeScript build succeeds and refreshes `functions/lib`.
  Run: `node --test functions/lib/assessment/student_v4_calculator.test.js functions/lib/assessment/workplace_v4_calculator.test.js`
  Expected: PASS.

- [ ] **Step 9: Commit Phase 1**
  Run: `git add functions/src/assessment/student_v4_calculator.ts functions/src/assessment/workplace_v4_calculator.ts functions/src/assessment/student_v4_calculator.test.ts functions/src/assessment/workplace_v4_calculator.test.ts; git commit -m "feat: add V4 assessment result explanations"`

### Task 2: Phase 2 — Full Assessment Result UI

**Files:**
- Modify: `lib/features/student_assessment/screens/student_assessment_complete_screen.dart`
- Modify: `test/features/student_assessment/student_v4_completion_test.dart`

**Interfaces:**
- Consumes: Task 1 payload fields plus existing `instrument`, `result`, `interpretation`, `populationRole`, and timestamps.
- Produces: these explicit sections: 1 Header, 2 Overall Status, 3 Assessment Summary, 4 Overall Response Pattern, 5 Well-Being Areas, 6 Strengths, 7 Areas to Explore, 8 Suggested Next Steps, 10 Response Completeness, and 13 Non-Clinical Disclaimer. Task 3 supplies section 9; Task 4 supplies sections 11 and 12.

- [ ] **Step 1: Write failing result-screen tests**
  Extend callable fixtures for all three roles. Assert **Your Full Well-Being Assessment Result**, overall status, assessment summary, overall response summary, five domain summaries, strengths, focus, next steps, completeness, and disclaimer. Add Student legacy (`studentSummary` only) and malformed optional-field fixtures. Methodology and references are intentionally tested in Task 4.

- [ ] **Step 2: Run the UI test red**
  Run: `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/student_v4_completion_test.dart`
  Expected: FAIL because the shallow profile view lacks the complete hierarchy.

- [ ] **Step 3: Implement the server-payload renderer**
  Replace the V4 profile layout in `student_assessment_complete_screen.dart` with the required ordered sections. Render stored date, role-aware label, past-seven-days copy, `userSummary ?? studentSummary`, `overallResponseSummary`, and saved domain summaries. Use safe adapters/fallback copy only; do not calculate or display forbidden values.

- [ ] **Step 4: Implement Response Completeness and Non-Clinical Disclaimer**
  Render the saved response-quality fields with high/usable/limited copy and clear skipped-response handling. Render the saved disclaimer with a non-clinical fallback; employee roles must include the job-performance/fitness-for-work limitation. Do not add methodology or references in this phase.

- [ ] **Step 5: Run the UI test green**
  Run: `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/student_v4_completion_test.dart`
  Expected: PASS for all role, legacy, fallback, completeness, disclaimer, and lifecycle cases.

- [ ] **Step 6: Commit Phase 2**
  Run: `git add lib/features/student_assessment/screens/student_assessment_complete_screen.dart test/features/student_assessment/student_v4_completion_test.dart; git commit -m "feat: present complete V4 assessment results"`

### Task 3: Phase 3 — Historical 50-question response review

**Files:**
- Create: `lib/features/student_assessment/widgets/v4_assessment_response_review.dart`
- Create: `test/features/student_assessment/v4_assessment_response_review_test.dart`
- Modify: `lib/features/student_assessment/screens/student_assessment_complete_screen.dart`
- Modify: `test/features/student_assessment/student_v4_completion_test.dart`

**Interfaces:**
- Consumes: saved snapshot maps (`itemId`, `domainId`, `displayOrder`, `text`), saved response maps (`itemId`, `responseCode`, `skipped`), and stored `domainSummaries` order.
- Produces: `V4AssessmentResponseReview` with five accessible expansion groups and no scoring dependency.

- [ ] **Step 1: Write failing review-widget tests**
  Use deliberately reordered 50-item snapshots and matching response maps. Assert five groups, 10 items per group, saved display order/text, readable answer labels, skipped **Not answered**, and collapsed/expanded behavior. Include a historical text differing from a hypothetical live item. Add explicit regressions for a missing saved response, unknown `responseCode`, missing `itemSnapshot.text`, and very long saved question text on a narrow phone. Required safe behavior: missing response renders **Not answered** or **Response unavailable**; unknown response code renders **Response unavailable**; missing saved question text renders **Question unavailable**; long question text wraps with no overflow. These cases must not trigger a live-catalog lookup, rescoring, or result replacement.

- [ ] **Step 2: Run the review test red**
  Run: `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/v4_assessment_response_review_test.dart`
  Expected: FAIL because the widget does not exist.

- [ ] **Step 3: Implement `V4AssessmentResponseReview`**
  Create `V4AssessmentResponseReview({required List<Map<String, dynamic>> itemSnapshot, required List<Map<String, dynamic>> responses, required List<Map<String, dynamic>> domainSummaries})`. Join only by `itemId`, order by saved `displayOrder`, group by saved `domainId`, and map the four response codes or skipped state to the required labels. Missing response uses **Not answered** or **Response unavailable**; an unknown response code uses **Response unavailable**; missing saved text uses **Question unavailable**. Use wrapping accessible `ExpansionTile`s; do not import a calculator or question catalog, rescore, or replace the result view.

- [ ] **Step 4: Mount response review in the result screen**
  Place **Assessment Responses** before Response Completeness and pass only payload snapshots, payload responses, and saved domain summaries. Render a safe empty state when a historical payload is invalid without replacing the saved result.

- [ ] **Step 5: Verify review and completion tests**
  Run: `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/v4_assessment_response_review_test.dart test/features/student_assessment/student_v4_completion_test.dart`
  Expected: PASS; no catalog lookup, raw value, or direction is shown.

- [ ] **Step 6: Commit Phase 3**
  Run: `git add lib/features/student_assessment/widgets/v4_assessment_response_review.dart lib/features/student_assessment/screens/student_assessment_complete_screen.dart test/features/student_assessment/v4_assessment_response_review_test.dart test/features/student_assessment/student_v4_completion_test.dart; git commit -m "feat: add V4 historical response review"`

### Task 4: Phase 4 — Methodology and References transparency

**Files:**
- Modify: `lib/features/student_assessment/screens/student_assessment_complete_screen.dart`
- Modify: `test/features/student_assessment/student_v4_completion_test.dart`

**Interfaces:**
- Consumes: Task 1 metadata and Task 2 sections.
- Produces: narrow-phone accessible, semantically labeled expandable transparency content without a new backend service.

- [ ] **Step 1: Add failing accessibility/content assertions**
  Assert **How This Result Was Created** and **References & Resources** expose readable semantic state, expand on a narrow surface, include all required copy, and do not expose technical secrets or clinical-validation claims.

- [ ] **Step 2: Run the completion test red**
  Run: `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/student_v4_completion_test.dart`
  Expected: FAIL until transparency content and accessibility match the contract.

- [ ] **Step 3: Implement accessible methodology and references widgets**
  Add the two expandable sections after Response Completeness and before the final disclaimer. Methodology exposes 50 questions, five domains, seven-day recall, four-point agreement scale, server-authoritative deterministic calculation, instrument/algorithm versions, `assessment_record_v4`, and no generative-AI determination. References show the Hefferon/Boniwell citation and custom/non-validated MindMate disclosure. Use wrapping `ExpansionTile` content and omit submission/catalog hashes and raw response metadata.

- [ ] **Step 4: Run the completion test green and commit**
  Run: `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/student_v4_completion_test.dart`
  Expected: PASS.
  Run: `git add lib/features/student_assessment/screens/student_assessment_complete_screen.dart test/features/student_assessment/student_v4_completion_test.dart; git commit -m "feat: disclose V4 result methodology"`

### Task 5: Phase 5 — Server and Flutter regression coverage

**Files:**
- Modify: `functions/src/assessment/student_v4_calculator.test.ts`
- Modify: `functions/src/assessment/workplace_v4_calculator.test.ts`
- Modify: `test/features/student_assessment/workplace_v4_assessment_test.dart`
- Modify only if needed: `test/features/student_assessment/student_assessment_calculator_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4 contracts.
- Produces: regression evidence that accepted V4 scoring/routing and the new result contract remain deterministic.

- [ ] **Step 1: Add profile-status regression cases**
  Cover `generallySupported`, `mostlySupported`, `someAreasNeedAttention`, `supportMayHelp`, and insufficient responses for Student and workplace roles. Assert unchanged status, deterministic interpretation, five summaries, and absence of diagnosis, `At Risk`, or `/100` language.

- [ ] **Step 2: Add workplace payload/routing fixtures**
  Extend `workplace_v4_assessment_test.dart` to preserve accepted 50-item staging routing and exact Teaching/Non-Teaching labels without adding scoring logic to Flutter.

- [ ] **Step 3: Run focused regression suites**
  Run: `npm.cmd --prefix functions run build`
  Expected: TypeScript build succeeds and refreshes `functions/lib`.
  Run: `node --test functions/lib/assessment/student_v4_calculator.test.js functions/lib/assessment/workplace_v4_calculator.test.js`
  Expected: PASS.
  Run: `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/student_assessment_calculator_test.dart test/features/student_assessment/student_v4_completion_test.dart test/features/student_assessment/workplace_v4_assessment_test.dart test/features/student_assessment/v4_assessment_response_review_test.dart`
  Expected: PASS.

- [ ] **Step 4: Commit Phase 5**
  Run: `git add functions/src/assessment/student_v4_calculator.test.ts functions/src/assessment/workplace_v4_calculator.test.ts test/features/student_assessment/student_assessment_calculator_test.dart test/features/student_assessment/student_v4_completion_test.dart test/features/student_assessment/workplace_v4_assessment_test.dart test/features/student_assessment/v4_assessment_response_review_test.dart; git commit -m "test: cover V4 full assessment results"`

### Task 6: Phase 6 — Analyzer, build, and manual staging verification

**Files:**
- Modify: none unless a verification failure proves a focused in-scope defect.
- Verify: `build/app/outputs/flutter-apk/app-staging-debug.apk`

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: staging-only evidence for the complete result experience.

- [ ] **Step 1: Run static and build checks**
  Run: `npm.cmd --prefix functions run build`
  Expected: PASS.
  Run: `flutter analyze`
  Expected: PASS with no new assessment diagnostics.

- [ ] **Step 2: Build staging APK**
  Run: `flutter clean; flutter pub get; flutter build apk --debug --flavor staging --dart-define=APP_ENV=staging`
  Expected: `build/app/outputs/flutter-apk/app-staging-debug.apk` is produced for staging.

- [ ] **Step 3: Manually verify each staging role**
  For Student, Teaching, and Non-Teaching, complete 50 answers and verify callable success, stored role/instrument, ordered result sections, five summaries, response-review expansion/answers, completeness, methodology, references, disclaimer, and no numeric or clinical score. Do not deploy production.

- [ ] **Step 4: Record only intentional in-scope fixes**
  If verification identifies an in-scope defect, first add its regression test, then make the smallest fix, rerun affected checks, and commit. Otherwise make no code-only verification commit.

## Plan self-review

- Tasks 1–4 cover every result-contract, UI, historical-review, and transparency requirement; Task 5 covers determinism/regression; Task 6 covers analyzer, builds, and three-role staging verification.
- Task 1 produces the exact fields consumed by Task 2; Task 2 passes immutable payload maps to Task 3; Task 3 contains no scoring or catalog dependency.
- Each review-focus risk has an assigned test task.
- The plan excludes migrations, extra backend services, unrelated features, and production deployment.
