# Full Well-being Assessment polish implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement approved items 42–46 on the student Full Assessment flow.

**Architecture:** Keep saved assessment data and Cloud Functions unchanged. Add small presentation helpers for summary text and domain art, gate new assessment sessions in the existing entry screen, move response review to its own route, and calculate the app's eligibility date in local school days.

**Tech Stack:** Flutter, Dart, Provider, existing widget and unit tests.

**Spec:** `docs/superpowers/specs/2026-11-13-full-assessment-result-polish-design.md`

## Global Constraints

- Student screens hide response completeness and confidence; counselor and admin records keep answered counts.
- The disclaimer gate appears on both builds, with V4-only claims only on V4, and skips an existing same-user session.
- No Cloud Functions, Firestore, question, scoring, threshold, or quick-assessment flow changes.
- Keep two attempts in seven calendar days. Count the two-day minimum as school days and show the eligible date without a time.
- Do not commit generated lockfiles or desktop platform files. Format touched Dart files only.
- Verify with `flutter analyze`, `flutter test --dart-define=APP_ENV=staging`, staging APK build, and Functions tests.

## Review Focus

- Old saved V4 summaries with the completeness sentence render cleanly in both student views; Task 1 tests this.
- A summary with no matching trailing sentence remains byte-for-byte unchanged; Task 1 tests this.
- Resuming an answering session for the same user bypasses the disclaimer without resetting answers; Task 3 tests this.
- An unknown domain or status still displays a named, expandable area; Task 2 tests this.
- A Friday submission and a weekend rolling-window expiry produce a Monday-or-later midnight date; Task 5 tests this.

---

### Task 1: Student-facing summary cleanup

**Files:** Create `lib/features/student_assessment/services/assessment_summary_text.dart`; modify `lib/features/student_assessment/screens/student_assessment_complete_screen.dart`, `lib/features/profile/screens/mental_health_report_screen.dart`; test in `test/features/student_assessment/assessment_summary_text_test.dart`, `test/features/student_assessment/student_v4_completion_test.dart`, `test/features/profile/profile_screen_test.dart`.

**Interfaces:** Produces `String withoutResponseCompleteness(String summary)` for both student result views. No later task consumes it.

- [ ] Write tests for trailing case-insensitive `You answered … response completeness.` removal, old saved V4 results in both views, unchanged unmatched text, absence of the legacy Response confidence card, and absence of confidence in report metadata.
- [ ] Run targeted tests; expect failures on the old text/card.
- [ ] Implement the pure helper; apply it only to displayed `interpretation['overallResponseSummary']`. Remove the legacy card and metadata confidence. Preserve counselor-facing data.
- [ ] Run the targeted tests; expect PASS.
- [ ] Format touched Dart files and commit as `feat: hide response completeness on student results`.

**Task test command:** `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/assessment_summary_text_test.dart test/features/student_assessment/student_v4_completion_test.dart test/features/profile/profile_screen_test.dart`

### Task 2: Illustrated expandable well-being areas

**Files:** Create `lib/features/student_assessment/widgets/assessment_domain_illustration.dart`; modify `lib/features/student_assessment/screens/student_assessment_complete_screen.dart`; test `test/features/student_assessment/student_v4_completion_test.dart`.

**Interfaces:** Produces a domain illustration widget or pure icon/color selectors consumed by `_V4DomainReflectionCard`. No later task consumes it.

- [ ] Add widget tests for the exact domain-to-icon map and fallback, exact status colors and fallback, 52 px circle/26 px icon, decorative semantics, status label, and expanded detail visibility including unknown domain/status.
- [ ] Run the targeted widget test; expect failures for missing art and tint.
- [ ] Add the illustration, tinted pill, and 3 px expanded-body bar while preserving the tile key and existing detail copy.
- [ ] Run the targeted widget test; expect PASS.
- [ ] Format and commit as `feat: illustrate full assessment areas`.

**Task test command:** `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/student_v4_completion_test.dart`

### Task 3: Disclaimer before a new session

**Files:** Modify `lib/features/student_assessment/screens/student_assessment_screen.dart`; test `test/features/student_assessment/assessment_flow_controller_test.dart` and a new `test/features/student_assessment/student_assessment_intro_test.dart`.

**Interfaces:** Consumes `AssessmentProvider.hasStudentAssessmentStarted`, `ensureStudentAssessmentStarted({String? userId})`, `isV4FullAssessment`, and the authenticated user id. Does not change provider APIs.

- [ ] Add widget tests that fresh entry shows `Before you start` and creates no session; acceptance starts it; V4-only statements are absent on legacy; same-user in-progress entry goes straight to its current question; `Not now` pops when possible and otherwise returns Home.
- [ ] Run intro tests; expect failures because the current screen starts immediately.
- [ ] Implement the first stage with the spec's exact statements, note, and buttons. Check session ownership before bypassing; guard against an unauthenticated start.
- [ ] Run intro and flow-controller tests; expect PASS.
- [ ] Format and commit as `feat: gate new full assessments with disclaimer`.

**Task test command:** `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/student_assessment_intro_test.dart test/features/student_assessment/assessment_flow_controller_test.dart`

### Task 4: Review Responses route

**Files:** Create `lib/features/student_assessment/screens/assessment_saved_responses_screen.dart`; modify `lib/features/student_assessment/screens/student_assessment_complete_screen.dart`; test `test/features/student_assessment/student_v4_completion_test.dart`.

**Interfaces:** New screen accepts the existing `itemSnapshot`, `responses`, and `domainSummaries` lists and hosts `V4AssessmentResponseReview`. It consumes the saved payload already held by `_StudentV4ProfileView`.

- [ ] Update widget tests: no inline Assessment Responses section; `Review Responses` appears above `Book a PACC appointment`; tapping opens `Your responses` with saved answers; Back returns to the result.
- [ ] Run targeted tests; expect failure on the missing button.
- [ ] Build the saved-response screen and push it from the result. Keep appointment wording and Continue behavior.
- [ ] Run targeted tests; expect PASS.
- [ ] Format and commit as `feat: move saved answers behind review button`.

**Task test command:** `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/student_v4_completion_test.dart`

### Task 5: School-day eligibility and limit copy

**Files:** Modify `lib/repositories/assessment_repository.dart`, `lib/features/home/screens/home_screen.dart`, `lib/features/quick_assessment/screens/quick_assessment_category_screen.dart`; test `test/features/student_assessment/student_assessment_calculator_test.dart`, `test/features/home/home_screen_test.dart`, and the existing quick-assessment widget tests or a focused new test.

**Interfaces:** Produces `DateTime addSchoolDays(DateTime from, int days)` and `DateTime nextSchoolDay(DateTime date)` for `FullAssessmentEligibility.fromCompletedDates`. The dialog consumes its `nextEligibleAt` unchanged.

- [ ] Update existing eligibility expectations and add tests for Friday-to-Tuesday minimum interval, weekend rolling expiry to Monday, midnight local eligibility, two-in-seven limit unchanged, and candidate precedence. Add widget assertions for both limit dialogs' school-day copy and date without time.
- [ ] Run targeted tests; expect failures on calendar-day dates and old copy.
- [ ] Implement the two local-date helpers and apply them to the existing minimum/rolling candidates. Update both dialogs to the spec's wording and date-only format.
- [ ] Run targeted tests; expect PASS.
- [ ] Format and commit as `feat: count full assessment wait in school days`.

**Task test command:** `flutter test --dart-define=APP_ENV=staging test/features/student_assessment/student_assessment_calculator_test.dart test/features/home/home_screen_test.dart`

### Task 6: Integration verification and PR notes

**Files:** Tests touched above; PR description only if a PR is prepared.

**Interfaces:** Consumes all previous task outputs.

- [ ] Run `flutter analyze`; expect no errors.
- [ ] Run `flutter test --dart-define=APP_ENV=staging`; expect all tests PASS.
- [ ] Run `flutter build apk --debug --dart-define=APP_ENV=staging`; expect successful APK build.
- [ ] Run Functions tests with the repository's documented command; expect PASS. The Functions source stays untouched.
- [ ] Check `git diff --check`, the final file list, and no generated lock/desktop files. Record in PR notes that the server still uses two calendar days and needs a separate owner-led alignment.

**Task test command:** `flutter test --dart-define=APP_ENV=staging`
