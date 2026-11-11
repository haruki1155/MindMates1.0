# Mood V2 Correctness and Clarity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct latest mood and personal notes, make date filters functional, and deliver compact, accessible white-and-yellow Mood V2 screens.

**Architecture:** Preserve existing repositories, provider, protected writer, and Flutter widgets. Use a shared Journey period state, keep private notes in owner-scoped detail state, and retain the existing analytics projection without notes. Confirmed writes update an account-scoped latest-event overlay so failed refreshes cannot undo a successful save.

**Tech Stack:** Flutter/Dart, Provider, Firebase Auth/Firestore/Functions, existing flutter_test and repository fakes; no new packages.

**Spec:** `docs/superpowers/specs/2026-11-12-mood-v2-correctness-and-clarity-design.md` (proposed; review before execution).

## Global Constraints
- No new dependencies, framework, schema migration, deletion, production change, or backend authorization bypass.
- Preserve feature-flag defaults, the protected callable, App Check, server eligibility, request UUID/idempotency, midnight retry, account isolation, and existing legacy behavior when V2 is disabled.
- Keep Mood streak distinct from activity streak. Do not log notes or credentials. Preserve unrelated `pubspec.lock` changes.
- Use existing `HomePalette.sun` (#FFC414), white surfaces and dark ink.
- No deployment is included. Never disable staging student saving or App Check as test cleanup.

## Review Focus
- Confirmed save followed by stale/failed history refresh must keep the latest mood; failed save must not update it (Task 1).
- Logout/account switch during a private note fetch must never reveal another student's notes (Task 2).
- Manila midnight, Monday/month boundaries and incomplete pages must produce honest period results (Task 3).
- Repeated selections, Skip, existing note drafts and retries must not create prompt loops, lose text or duplicate writes (Task 4).
- Many entries, long notes, large text, keyboard and narrow/landscape screens must remain readable and operable (Tasks 3–5).

---

## File map and current evidence
- `lib/providers/mood_provider.dart`: legacy `todayMood` is separate from V2 history; add latest-confirmed and private-detail state here.
- `lib/features/home/screens/home_screen.dart`: currently derives Today's mood from legacy `todayMood`.
- `lib/features/mood/screens/log_mood_screen.dart`: confirmed V2 write refreshes history; owns note draft, selection and expression action.
- `lib/repositories/mood_combined_history_repository.dart`: normalization deliberately omits notes; retain this default boundary, add an owner-only detail read.
- `lib/features/mood/screens/mood_journey_screen.dart`: owns history loading; will own period selection.
- `lib/features/mood/widgets/mood_journey_summary.dart`: period currently local to summary; uses green styling.
- `lib/features/mood/widgets/mood_v2_history_panel.dart`: currently renders full dates and all days/entries; will group collapsed days and load personal details.
- Existing tests: `test/providers/mood_provider_test.dart`, `test/features/home/home_screen_test.dart`, and the Mood test files named below.
- No Functions, Rules or index changes are expected. If evidence shows a required backend change, stop and update this plan before widening scope.

### Task 1: Latest confirmed mood on Home and reload

**Files:** Modify `lib/providers/mood_provider.dart`, `lib/features/home/screens/home_screen.dart`, `lib/features/mood/screens/log_mood_screen.dart`; test `test/providers/mood_provider_test.dart`, `test/features/home/home_screen_test.dart`, `test/features/mood/log_mood_screen_test.dart`.

**Interfaces:** Add `void recordConfirmedMoodV2Entry(MoodV2Event entry)` and `NormalizedMoodEvent? latestMoodForToday({DateTime? now})` to MoodProvider. Keep legacy `todayMood` semantics unchanged. Consume server-confirmed `MoodV2Event` from the existing writer; produce owner/date-checked latest entry for enabled Home.

- [ ] **Step 1:** Add tests `latest V2 mood survives stale refresh`, `failed save retains latest confirmed mood`, `today selects newest persisted event after reload`, and `account switch and Manila midnight clear current display`. Assert two different same-day saves show the second label on Home; disabled V2 retains legacy behavior. Include equal-time deterministic identity ordering.
- [ ] **Step 2:** Run `flutter.bat test --dart-define=APP_ENV=staging test/providers/mood_provider_test.dart test/features/home/home_screen_test.dart test/features/mood/log_mood_screen_test.dart --reporter expanded`; verify the new assertions fail for the identified display path.
- [ ] **Step 3:** Implement the interfaces using existing sorted events plus a confirmed-entry overlay scoped to current auth and Manila date. Call recordConfirmedMoodV2Entry immediately after write confirmation, before dependent reads. Use the getter only on V2-enabled Home, gated by the existing Home reader flag; retain legacy fallback when no eligible V2 event exists. Clear overlay on auth changes and exclude prior-day events. Ensure existing Home V2 loading covers app reentry.
- [ ] **Step 4:** Repeat Step 2; require all assertions pass, including delayed completion after account switch and existing midnight/idempotency tests.
- [ ] **Step 5:** Stage only these reviewed paths and commit `fix(mood): display latest confirmed student mood`.

### Task 2: Private saved notes on expanded days

**Files:** Modify `lib/repositories/mood_combined_history_repository.dart`, `lib/providers/mood_provider.dart`, `lib/features/mood/widgets/mood_v2_history_panel.dart`, `lib/features/mood/screens/mood_journey_screen.dart`; test `test/features/mood/mood_combined_history_repository_test.dart`, `test/providers/mood_provider_test.dart`, `test/features/mood/mood_v2_history_panel_test.dart`.

**Interfaces:** Add repository `Future<Map<String, String?>> fetchOwnerNotes({required String userId, required List<NormalizedMoodEvent> events})`, keyed by source-qualified stableIdentity. Add provider `Future<void> loadMoodV2DayNotes(String userId, String dateKey)`, `Map<String, String?> get v2PersonalNotes`, `Set<String> get v2NoteLoadingDays`, and `Set<String> get v2NoteErrorDays`. Add optional panel inputs with those types and `ValueChanged<String>? onExpandDay`.

- [ ] **Step 1:** Add tests `expanded owner day shows persisted note after reload`, `blank note uses placeholder`, `failed detail read offers retry instead of false no-note placeholder`, `account switch discards pending notes`, and `analytics events still omit private notes`. Assert legacy/V2 identical document IDs remain distinct, existing analytics request behavior stays unchanged, and foreign-user event requests reject.
- [ ] **Step 2:** Run `flutter.bat test --dart-define=APP_ENV=staging test/features/mood/mood_combined_history_repository_test.dart test/providers/mood_provider_test.dart test/features/mood/mood_v2_history_panel_test.dart --reporter expanded`; confirm new tests fail.
- [ ] **Step 3:** Implement bounded owner-only detail reads of the already-loaded event documents using existing collection constants and Firebase identity. Recheck identity after asynchronous reads and verify every document owner before returning data. Read sequential chunks of at most 20 documents, never unbounded fan-out; preserve null for missing/empty notes and report fetch failures distinctly. Provider stores private notes separately from v2History/v2Analytics, uses auth/request generation guards, and clears on account changes. Panel renders loading/error/retry states before deciding a note is absent. Never log note text.
- [ ] **Step 4:** Repeat Step 2; require passing privacy and reload assertions. Confirm no note is added to summary, reports or MindAid projections.
- [ ] **Step 5:** Commit reviewed files as `fix(mood): load owner notes for journey details`.

### Task 3: Shared periods and compact expandable days

**Files:** Modify `lib/features/mood/screens/mood_journey_screen.dart`, `lib/features/mood/widgets/mood_journey_summary.dart`, `lib/features/mood/widgets/mood_v2_history_panel.dart`; create `lib/features/mood/domain/mood_journey_period.dart`; test `test/features/mood/mood_journey_test.dart`, `test/features/mood/mood_v2_history_panel_test.dart`; create `test/features/mood/mood_journey_period_test.dart`.

**Interfaces:** Add `enum MoodJourneyPeriod { week, month }` and `bool includesMoodJourneyDate(String dateKey, MoodJourneyPeriod period, DateTime now)` using MoodManilaCalendar. Summary receives `MoodJourneyPeriod period` and `ValueChanged<MoodJourneyPeriod> onPeriodChanged`; screen owns selection. Panel receives optional `MoodJourneyPeriod? period` and `DateTime? referenceInstant`; defaults preserve other consumers. Use the existing complete history for streak calculation and apply period to summaries/list only. Use Task 2 detail callback on expansion.

- [ ] **Step 1:** Add tests `week and month change summary and check-in dates together`, `empty selected period explains no check-ins`, `Manila Monday and month boundary`, and `partial period keeps Load more available`. Assert count/date-range labels, selected semantics and no off-period entries; never auto-fetch all history. Add `collapsed day hides entries and full date`, `expanded day shows weekday then full date and check-ins`, and `many same-day entries remain one collapsed row`. Full-date accessibility label must exist while collapsed.
- [ ] **Step 2:** Run `flutter.bat test --dart-define=APP_ENV=staging test/features/mood/mood_journey_period_test.dart test/features/mood/mood_journey_test.dart test/features/mood/mood_v2_history_panel_test.dart --reporter expanded`; confirm new tests fail.
- [ ] **Step 3:** Implement shared period filtering and a Flutter ExpansionTile per date keyed by owner/date; keep stable ordering, pagination/retry controls outside the filtered list, and explicit partial-coverage messaging. Day header is weekday, check-in count and chevron; expanded full localized date is secondary above time/mood/note details. Use existing glyphs plus mood-specific accents. If a new period has no loaded matching entries, explain partial coverage and retain Load more rather than claiming no records exist.
- [ ] **Step 4:** Repeat Step 2. Verify Monday/month-boundary fixtures and pagination revealing additional days without duplicates or losing already-loaded personal notes.
- [ ] **Step 5:** Commit as `fix(mood): filter journey and collapse daily check-ins`.

### Task 4: Optional reflection prompt

**Files:** Modify `lib/features/mood/screens/log_mood_screen.dart`; test `test/features/mood/log_mood_screen_test.dart`.

**Interfaces:** Add private `Future<void> _offerMoodReflection()` in screen state; reuse the existing TextEditingController and add a disposed FocusNode for its note field. Existing selection/save signatures remain unchanged.

- [ ] **Step 1:** Add widget tests `first mood selection offers optional reflection`, `Skip retains selection and note`, `Add note focuses existing field`, `changing selection does not repeat prompt before save`, `confirmed save resets prompt eligibility`, and `account change dismisses old prompt safely`. Assert exact spec copy, no automatic write and successful saving with no note. Keyboard/back dismissal equals Skip; save failure/retry retains prompt state and request identity.
- [ ] **Step 2:** Run `flutter.bat test --dart-define=APP_ENV=staging test/features/mood/log_mood_screen_test.dart --reporter expanded`; verify failures are on the new prompt expectations.
- [ ] **Step 3:** Implement a V2-only Flutter dialog with `Skip` and `Add note`, shown once per unsaved entry after explicit manual selection or explicit acceptance of an expression suggestion. Focus/scroll to the existing field on Add note. Never show from build, inferred expression alone, or a reloaded historical entry. Retain drafts and retry UUID; guard mounted/session state after dialog completion.
- [ ] **Step 4:** Repeat Step 2 including existing midnight and expression acceptance tests; require pass at 1.8x text with keyboard open.
- [ ] **Step 5:** Commit as `feat(mood): invite optional reflection after selection`.

### Task 5: Yellow visual clarity and final validation

**Files:** Modify `lib/features/mood/screens/log_mood_screen.dart`, `lib/features/mood/widgets/mood_journey_summary.dart`, `lib/features/mood/widgets/mood_v2_history_panel.dart`; test `test/features/mood/mood_visual_acceptance_test.dart`, `test/features/mood/mood_journey_test.dart`, `test/features/mood/log_mood_screen_test.dart`.

**Interfaces:** Preserve public widget behavior established in Tasks 1–4. Reuse HomePalette and existing mood glyph/palette mappings; only extract a small shared style helper if these edited widgets otherwise duplicate the same decoration.

- [ ] **Step 1:** Add assertions for white Journey/Streak surfaces, #FFC414 yellow borders/glow, dark text, selected period semantics, visible chevron/button semantics and yellow Check Expression styling. Add overflow/interaction cases at 320px and 390px portrait, 844x390 landscape and 1.8x text, long notes, many entries and keyboard. Assert all primary actions remain reachable by scrolling with at least 48px tap targets.
- [ ] **Step 2:** Run `flutter.bat test --dart-define=APP_ENV=staging test/features/mood/mood_visual_acceptance_test.dart test/features/mood/mood_journey_test.dart test/features/mood/log_mood_screen_test.dart --reporter expanded`; confirm new visual/semantic assertions fail before styling.
- [ ] **Step 3:** Apply consistent 16px outer padding, flexible rows/wrapping, white cards with restrained static yellow shadow/border, prominent streak count and warm icon, and filled yellow Check Expression action with camera icon. Replace green controls/highlights in the requested Mood surfaces; retain varied mood colors as secondary indicators. Use dark text for contrast and clear pressed/disabled states.
- [ ] **Step 4:** Repeat Step 2, then run enabled focused tests with `--dart-define=APP_ENV=staging --dart-define=ENABLE_MOOD_V2=true --dart-define=ENABLE_MOOD_V2_PROVIDER_READ=true --dart-define=ENABLE_MOOD_V2_HOME_READ=true --dart-define=ENABLE_MOOD_V2_PROFILE_READ=true --dart-define=ENABLE_MOOD_V2_HISTORY_READ=true --dart-define=ENABLE_MOOD_V2_INSIGHTS_READ=true`. Include `test/features/mood` except `mood_v2_repository_test.dart` (its assertions require disabled defaults), plus provider/Home/Insights tests. Run that repository test separately with only APP_ENV=staging. Run `flutter.bat analyze --no-pub`, `git diff --check`, and full `flutter.bat test --no-pub --dart-define=APP_ENV=staging --reporter expanded` once for final regression coverage. Require exit 0; do not change flags/assertions to conceal failures.
- [ ] **Step 5:** Commit reviewed files as `style(mood): unify yellow journey and reflection actions`. Report actual counts and remaining limitations; do not claim live acceptance from automated tests.

## Staging APK handoff after plan approval and execution
- Preserve unrelated dirty files and record final commit/dirty state. Confirm whether to rebuild/reinstall for this iteration before the device side effect; this plan alone is not an instruction to deploy.
- For an authorized install, use the established staging debug flavor with APP_ENV=staging, ENABLE_STAGING_APP_CHECK=true, all six enabled Mood V2 flags listed above, and the existing ignored App Check define file. Do not print its value or unredacted Gradle dart-defines; capture/redact build output. Do not change server configuration or register new tokens as part of this task.
- Verify build exit, APK hash, `adb install -r` success and launch without clearing app data. Leave the same enabled configuration in place after testing.
- User manual acceptance: save two different moods with distinctive optional notes; return Home and confirm newest; reopen app and expand each day's entries to confirm notes; switch periods; verify day collapse, prompt Skip/Add note, Journey navigation, streak, expression button and narrow/landscape layout. Real saves require the user's chosen staging account and approval; never delete records as cleanup.

## Self-review
All user requirements map to Tasks 1–5. Proposed behavior choices are explicit in the companion design. Private notes remain separate from analytics; owner/generation checks cover asynchronous account changes. Default-disabled tests are separated from enabled runs. Backend, deployment and installed-runtime success remain separate from local validation. No implementation has been performed by creating this plan.
