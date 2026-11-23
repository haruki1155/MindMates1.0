# My Mood Journey V3 Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended with reviewers) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Journey 7-day strip / period selector with a usable month calendar and reliable selected-week / monthly mood recaps, optionally filtered by academic year / semester, without rewriting Mood V2.

**Architecture:** Extend existing date-key analytics and bounded `MoodCombinedHistoryRepository.fetch` for a separately owned calendar window, leaving the existing recent `v2History` and streak path unchanged. Compose a Flutter-native 7-column calendar with existing `HomePalette`, mood glyphs and history day detail; expose restricted academic calendar metadata via a safe read-only source rather than changing admin access.

**Tech Stack:** Existing Flutter/Dart 3.12, Provider, Firebase Firestore/Auth/Functions, Node 22 / TypeScript 6, existing `flutter_test` and `node --test`, Firebase emulator. **No new packages unless a verified missing capability demands one.**

**Spec:** `docs/superpowers/specs/2026-11-23-mood-journey-v3-calendar-design.md`

## Global Constraints

- Start from freshly fetched `main`; repo audit at plan drafting was `fc028e009762c1d1f54c46449785e89d15114f6f`. Check ongoing PRs first; #77 and #78 were draft as of 2026-11-23.
- Branch `feat/mood-journey-v3-calendar` in an isolated worktree. Do not modify PR #77/#78 branches or unrelated systems.
- Existing `MoodV2FeatureFlag`, account isolation, both mood sources, multiple same-day check-ins, current log writer, PACC support and Home navigation remain unchanged.
- `Asia/Manila` date keys and Monday-first week boundaries, as defined by `MoodManilaCalendar`; bounds are start inclusive/end exclusive. No host timezone-dependent date arithmetic.
- Use existing `HomePalette`, `HomeDecor`, `HomeMetrics`, `HomeMotion`, `MoodGlyph`/`MoodGlyphPainter`; no calendar dependency unless standard widgets are inadequate.
- Keep authenticated student's personal notes private and lazily fetched. Never mix one account's records into another.
- Do not weaken admin-only `getAcademicYears`, Firestore rules or App Check. No unreviewed deployment, merge or `main` commit.
- TDD every behavior: RED failing test → GREEN minimal code → refactor → focused test → commit. Verify complete suites before PR.

## Review Focus (regressions that must be tested)

1. Visible month begins/ends midweek: select a week crossing months; no missing check-ins from adjacent grid days (Tasks 1, 2, 3).
2. Very active student with more events than one page: calendar query drains bounded cursors or displays explicitly partial results (Task 2).
3. Student switches accounts while older day notes/history are still fetching: neither old mood nor old notes can appear (Task 2).
4. Academic year boundary and semester midpoint: counts are clipped to exact configured ranges and dates are never claimed to be official unless stored (Tasks 1, 5).
5. Narrow 320dp screen at 1.8x text: no overflow, all dates can be selected and announced accessibly (Task 3).

---

## Dependency map and intended files

| Responsibility | Existing/new file | Kind |
|---|---|---|
| Dates and recap summary | `lib/features/mood/domain/mood_journey_period.dart` | modify; keep existing helpers compatible |
| Date/recap pure unit tests | `test/features/mood/mood_journey_period_test.dart` | modify |
| Owner-bound date-window reader + note lookup | `lib/providers/mood_provider.dart` | modify minimally |
| Bounded history repository / tests | `lib/repositories/mood_combined_history_repository.dart`, `test/providers/mood_provider_test.dart` | reuse; extend only if tests require |
| Calendar widget | `lib/features/mood/widgets/mood_journey_calendar.dart` | create |
| Calendar widget tests | `test/features/mood/mood_journey_calendar_test.dart` | create |
| Screen selection and composition | `lib/features/mood/screens/mood_journey_screen.dart` | modify |
| Summary and selected-day details | `lib/features/mood/widgets/mood_journey_summary.dart`, `lib/features/mood/widgets/mood_v2_history_panel.dart` | modify surgically |
| Screen / screenshot regression | `test/features/mood/mood_journey_test.dart`, `test/features/mood/mood_visual_acceptance_test.dart` | modify |
| Academic metadata callable | `functions/src/student_academic_calendar.ts` | create only if no safe existing API |
| Callable export / routing | `functions/src/index.ts`, `lib/services/firebase/firebase_callable_router.dart` | modify if callable needed |
| Student callable repository | `lib/repositories/student_academic_calendar_repository.dart` | create only if needed |
| Backend and repository tests | `functions/src/student_academic_calendar.test.ts`, `test/repositories/student_academic_calendar_repository_test.dart` | create if endpoint needed |

Adjust exact names only if fresh code audit finds an established equivalent; record the change in the implementation log rather than creating duplicates.

### Task 0: Worktree, baseline and UI checkpoints

**Files:** existing repo, no product changes.

- [ ] **Step 1:** `git fetch origin main`, `git status --short`, `git worktree list`, inspect overlapping open PRs and confirm the tracked baseline (`git rev-parse origin/main`). If a local managed worktree already exists, reuse it. Follow `superpowers:using-git-worktrees` including `.worktrees` ignore check.
- [ ] **Step 2:** Create/reuse isolated branch `feat/mood-journey-v3-calendar` based on current `origin/main`. Use the repo's current Flutter/Node SDK; do not alter production/staging configuration.
- [ ] **Step 3:** Read all listed files and `functions/src/access.ts`, `functions/src/counseling_population.ts`, `functions/src/report_generation.ts`, `test/features/mood/mood_journey_test.dart` in full. Map all callers of the old `period` parameter and existing note loader; verify whether an existing student-safe calendar API already exists.
- [ ] **Step 4:** Run baseline `flutter test --dart-define=APP_ENV=staging test/features/mood/` and `flutter analyze`; if invoking from Windows PowerShell use `flutter.bat`. Run `npm --prefix functions run build`. Record baseline failures without masking them.
- [ ] **Step 5:** Document three final screen states before coding: month with entries, no-entry month, month read error/partial; include 320px/390px visual checks and MoodGlyph consistency. No separate high-fidelity graphic dependency is required; code is the source of visual truth.

### Task 1: Pure calendar range and recap semantics

**Files:** `lib/features/mood/domain/mood_journey_period.dart`, `test/features/mood/mood_journey_period_test.dart`.

**Interfaces (suggested; adapt in one place if an existing helper is better):**
- `MoodWeekRange moodWeekContainingDate(DateTime calendarDate)` — keys as Manila calendar dates, independent of instant interpretation; use the existing `MoodManilaCalendar.weekContaining` carefully (it expects an instant).
- `MoodWeekRange moodVisibleMonthRange(DateTime displayedMonth)` — Monday of first grid row through Monday after last Sunday, with `startDateKey` and `endExclusiveDateKey`.
- `MoodJourneyRangeSummary summarizeMoodRange(MoodHistoryWindow window, String startInclusiveDateKey, String endExclusiveDateKey)` — immutable counts, active days, label frequencies, top labels including ties, `isPartial`; `MoodJourneyRangeSummary` can be defined beside the helpers to avoid another file.
- `MoodWeekRange intersectMoodRanges(MoodWeekRange a, MoodWeekRange b)` — helper only if needed to implement academic clipping; empty intersection represented explicitly.

- [ ] **Step 1 (RED):** Tests for Monday-first display range on November 2026; Feb 2028 leap year; Sunday and Monday around Manila midnight; 2 events on same day count as 2 check-ins/1 active day; duplicate `stableIdentity` counts once; tied top moods remain tied; `partial` retained; labels absent do not become a fake mood; week clipping at academic boundary.
- [ ] **Step 2:** Run `flutter test test/features/mood/mood_journey_period_test.dart --dart-define=APP_ENV=staging` and confirm new tests fail for missing behavior, not compilation/setup errors.
- [ ] **Step 3 (GREEN):** Implement only tested pure functions; reuse `MoodManilaCalendar.dateForKey`, `dateKeyForDate`, `MoodHistoryWindow.uniqueEvents` and `MoodWeekRange.includes`. Do not change `MoodAnalytics.streak`.
- [ ] **Step 4:** Re-run focused tests; review how range and selected week math intersects at month/term edges.
- [ ] **Step 5:** Commit `feat(mood): add calendar date range and recap helpers`.

### Task 2: Bounded calendar history read, pagination and owner note safety

**Files:** `lib/providers/mood_provider.dart`, `test/providers/mood_provider_test.dart`, optional focused repository tests, `lib/repositories/mood_combined_history_repository.dart` only if needed.

**Interfaces (suggested):**
- `Future<void> loadMoodCalendarRange(String userId, {required String startDateKey, required String endExclusiveDateKey})`.
- `MoodHistoryWindow? get moodCalendarHistory; bool get isLoadingMoodCalendarRange; String? get moodCalendarRangeError; String? get loadedMoodCalendarStartKey; String? get loadedMoodCalendarEndExclusiveKey;`
- Calendar range state does NOT replace `v2History` or `v2Analytics`; `clearMoodV2History()`/`bindAuthenticatedUser()` clear both stores and invalidate both request generations.

- [ ] **Step 1 (RED):** Tests prove reader requests `forManilaDateRange` for visible grid and returns only owner events, follows cursor pages for a busy month, keeps partial status on failures and permits explicit retry, does not replace recent history/streak, discards stale month A result if month B requested, discards stale previous-account response, and loads older-day notes only for current owner.
- [ ] **Step 2:** Run `flutter test --dart-define=APP_ENV=staging test/providers/mood_provider_test.dart`; verify expected RED.
- [ ] **Step 3 (GREEN):** Extend provider with one window state plus separate request generation. Use `MoodCombinedHistoryRepository.fetch(MoodCombinedHistoryRequest.forManilaDateRange(...))`; follow bounded pagination until complete; cap only if necessary and label `partial`, never falsely complete. On navigation/midnight avoid overlapping older requests overwriting later ones. Preserve source failures as retryable.
- [ ] **Step 4:** Update existing `loadMoodV2DayNotes` **only if necessary** to find the date's owner-matched events in either recent history or current calendar history; preserve `_requireCurrentUser` checks and lazy note fetch. Do not fetch private notes on month-grid render.
- [ ] **Step 5:** Re-run provider/repository tests. Commit `feat(mood): add owner-safe calendar range history reads`.

### Task 3: Flo-inspired, MindMate-native calendar UI

**Files:** create `lib/features/mood/widgets/mood_journey_calendar.dart`, `test/features/mood/mood_journey_calendar_test.dart`; compose initially through tests before screen wiring.

**Suggested widget inputs:** `displayedMonth` (UTC midnight calendar date), `selectedDateKey`, `todayDateKey`, `MoodHistoryWindow? history`, `isLoading`, callbacks `onMonthChanged(DateTime)`, `onDaySelected(String)`, `onTodayPressed()`; no global state or Firestore access inside widget.

- [ ] **Step 1 (RED):** Tests render November 2026 as Monday-first with correct date placement; navigate October/December, Today shortcut, select a date with 1 or 3 entries, preserve selected vs today styling, see calendar loading/error/unknown state, and announce date + check-in count via semantics. Verify no overflow at widths `[320, 360, 390, 430]` and text scale `1.8`.
- [ ] **Step 2:** Run `flutter test --dart-define=APP_ENV=staging test/features/mood/mood_journey_calendar_test.dart`; verify expected RED.
- [ ] **Step 3 (GREEN):** Implement a 7-column non-scrolling Material grid with only visible month rows, using `HomePalette`, `HomeDecor`, `HomeMotion` and `MoodGlyph` utilities. Latest mood is a compact glyph/marker and multiple entries a `+N` count. Avoid a calendar dependency, gradients and oversized cards. Distinguish today's date, selected date, dates outside month and unavailable future days.
- [ ] **Step 4:** Verify widget tests, check keyboard/semantics and screen text scaling manually or with widget tests. Commit `feat(mood): add accessible journey month calendar`.

### Task 4: Compose My Mood Journey, selected-day detail and recaps

**Files:** `lib/features/mood/screens/mood_journey_screen.dart`, `lib/features/mood/widgets/mood_journey_summary.dart`, `lib/features/mood/widgets/mood_v2_history_panel.dart`, `test/features/mood/mood_journey_test.dart`, `test/features/mood/mood_visual_acceptance_test.dart`.

**Interfaces:** Screen owns `_displayedMonth`, `_selectedDateKey`; derive `selectedMoodWeekRange` and displayed-month range from Task 1, using the calendar window from Task 2. The existing summary widget can be refactored to show week/month subcards; do not create a parallel analytics pipeline. The history panel may accept optional start/end keys to filter to the selected day; preserve existing `period` behavior for other consumers/tests until migrated.

- [ ] **Step 1 (RED):** Replace old seven-day strip and Week/Month toggle expectations with calendar navigation tests: tapping a past date shows only its expanded detail, changes the weekly summary to its Monday–Sunday, handles cross-month week and tied label counts, keeps month overview separate, respects user switch, preserves mental health route and support note, does not turn selected historic date into a backdated logger.
- [ ] **Step 2:** Run focused `mood_journey_test.dart` and visual acceptance tests and verify RED.
- [ ] **Step 3 (GREEN):** Reorder UI: AppBar → intro → compact academic filter (Task 5) → calendar → selected-day detail → selected-week summary + existing gentle recap → month at a glance → compact streak and support. Keep scrolling in one `ListView`; no nested calendar scrolling. Preserve `nowProvider` test seam and midnight refresh; calendar re-entry refreshes the visible range after a new mood entry.
- [ ] **Step 4:** Refactor old summary code to share Task 1 aggregate, keep semantics and existing `mood-streak-card` behavior where compatibility tests expect it; update tests purposefully rather than deleting security coverage.
- [ ] **Step 5:** Run all mood widget tests and visual acceptance; commit `feat(mood): connect calendar and weekly monthly journey insights`.

### Task 5: Student-safe Academic Year / Semester calendar filter

**Files:** Prefer existing safe student-facing read if freshly discovered. Otherwise `functions/src/student_academic_calendar.ts` (new), `functions/src/index.ts`, `functions/src/student_academic_calendar.test.ts`, `lib/repositories/student_academic_calendar_repository.dart` (new), `test/repositories/student_academic_calendar_repository_test.dart` (new), `lib/features/mood/screens/mood_journey_screen.dart`, and `lib/services/firebase/firebase_callable_router.dart` only if alias routing is required.

**Contract (if new callable is necessary):** `getStudentAcademicCalendar` returns `years: [{schoolYear, startDateKey, endExclusiveDateKey, status, semesterRanges: [{id, label, startDateKey, endExclusiveDateKey, source}]}]` for configured non-voided years. Return only dates/IDs/status and term source (`configured` vs `reportGrouping`); no populations or student records. Verify all fields against the real schema before coding. Client always intersects selected week/month range with chosen academic range. A school year with invalid/missing dates is not selectable.

- [ ] **Step 1 (RED):** Callable/emulator tests: active authenticated student can read only permitted date metadata; unauthenticated/unverified/unauthorized caller denied using repository's existing role policy; no `populations`, `departments`, audit data, staff details or student IDs returned; malformed/voided year omitted; semester midpoint and end-exclusive boundaries match existing report grouping; an explicit `source: reportGrouping` is not represented as an official university term.
- [ ] **Step 2:** Run the new Functions test using Node 22 + repo's `functions/package.json` patterns; verify RED. Do not broaden `getAcademicYears` privileges.
- [ ] **Step 3 (GREEN):** Implement minimal callable and exports, correct App Check policy + matching staging alias if routing requires it; expose a small Flutter repository with `FirebaseFunctionsRouting.routedCallable`. No admin mutation, new Firestore index, schema migration, or new collection.
- [ ] **Step 4 (RED):** Flutter repository/screen tests for selected academic year and semester clipping, no-year availability, old configured year selection, missing term dates, stale owner response, and clear error handling.
- [ ] **Step 5 (GREEN):** Wire two compact filter controls to selection state. Default to configured current academic year if available; use `All year` when no reliable term. If only six-month report grouping is available, label it `Semester 1/2 (report grouping)` or explicitly show `Approximate dates` near selection. Do not claim those are official semester schedules.
- [ ] **Step 6:** Run Functions test suite and relevant Flutter tests; commit `feat(mood): filter journey by published academic calendar`.

### Task 6: End-to-end acceptance, review and PR handoff

**Files:** focused test adjustments only; no extra feature work.

- [ ] **Step 1:** Execute `flutter test --dart-define=APP_ENV=staging test/features/mood/`, `flutter test --dart-define=APP_ENV=staging test/providers/mood_provider_test.dart`, new repository tests and `flutter analyze`; use Windows `flutter.bat` when appropriate. Record counts and skip reasons.
- [ ] **Step 2:** Execute full `flutter test --dart-define=APP_ENV=staging` and `flutter analyze` from repository root; if tests exceed local resources, report exact blockers and do not claim all green.
- [ ] **Step 3:** Run `npm --prefix functions run build` and `npm --prefix functions test` with required Firebase emulators, separately verifying new callable auth and status; report exact pass/fail counts. Review `mood-v2-emulator-validation.yml` and `android-verify.yml` for CI parity.
- [ ] **Step 4:** Perform visual acceptance on 320/390/430 logical-width devices, 1.0/1.8 text scale, empty/partial/loaded/error cases, mixed moods with multiple check-ins, calendar month controls and midnight boundaries; capture artifact screenshots where project test harness supports it.
- [ ] **Step 5:** Fresh independent review for security, correctness, over-engineering and API backward-compatibility (`superpowers:requesting-code-review`, `engineering-suite-ponytail/ponytail-review`). Address findings only in scope and re-verify.
- [ ] **Step 6:** `git status --short`, `git diff --check`, `git diff --stat origin/main...HEAD`, inspect every changed file; no accidental secrets, lockfile drift, no unrelated changes. Commit only verified changes and prepare an isolated draft PR with exact verification results and any blockers. Do not merge or deploy without separate authorization.

## Execution note

The most efficient order for a single agent is Task 0 → 1 → 2 → 3 → 4 → 5 → 6, with compact commits and one independent review gate after Task 2 and Task 5 if reviewers are available. Keep the entire feature in one worktree. A deployment is not required for the implementation or local emulator verification; staging/production activation is a separate user-approved gate.
