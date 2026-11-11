# MindMate Mood V2 Mockup-Parity UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recreate the approved MindMate Mood V2 Home, Mood Log, Mood Saved, and Mood Journey mockups as accessible, responsive Flutter UI while preserving all current Mood V2 and legacy behavior.

**Architecture:** Make scoped presentation changes to the existing Home/Mood screens and widgets. Keep the existing V2 provider, repositories, backend, route contracts, feature flags, and current Home bottom navigation. Prefer the app's established palette/components and one state owner per screen rather than introducing a parallel UI framework.

**Tech Stack:** Existing MindMate Flutter/Dart; existing provider/state management; existing golden/green theme and mood assets; existing phosphor icon dependency if installed; standard Flutter widgets/animations/tests.

**Spec:** `docs/superpowers/specs/2026-11-12-mood-v2-visual-parity-design.md` (owner-approved). Visual references: `docs/design/mindmate-mood-v2-approved-board.png` and `docs/design/mindmate-mood-v2-save-success.png`.

## Agent Handoff — copy/paste instruction

You are implementing **ONLY the approved Mood V2 STUDENT UI visual parity** in the owner's existing local MindMate 1.0 Flutter repository. **First inspect** the active local branch, HEAD, status, tracked/untracked changes, current screens, test suites, theme, mood mappings, save callback/idempotency, routes, and the two visual references. The owner expects nearly identical UI hierarchy/colors/proportions and working interactions—not a generic redesign, image pasted into the app, or a broad refactor. Treat the design spec and reference images as the visual contract. Preserve the original yellow Home `+ Log a mood` button and remove the additional Home Mood Check-ins card. Move that information to a small banner on the Mood Log screen. Modernize the seven-mood selector, safe-area Save CTA, save-success state, and Journey timeline/7-day strip; keep multiple intentional same-day mood entries. Use the existing theme and optional installed phosphor icons. **Do not change backend, Firestore, feature flags/defaults, deployment config, other features, or unrelated uncommitted files. Do not push/merge/deploy.** Follow this plan task by task with red/green tests, scoped commits only when an independently complete diff can be staged, then run all checks and deliver device screenshots for owner review. If a commit requires unrelated pre-existing hunks, stop and request approval; never silently include them or stash/reset them. If the mockup asset is missing, ask the owner for the supplied images before implementing visuals.

## Global Constraints

- Work on the user's **existing worktree** to avoid consuming disk space with another Flutter worktree. Verify `fix/mood-v2-primary-experience` and the HEAD; a moved HEAD is not automatically an error, but document differences and stop on suspicious/conflicting state.
- Report `git status --short`, `git diff --name-only`, and `git diff --cached --name-only` at start. No `git reset --hard`, force checkout, clean, stash, broad `git add -A`, unrelated staging, push, merge, tag, Firebase deployment or new staging writes.
- Pre-existing uncommitted Functions, `.env.example`, inSIGHT screen, rollout docs, and any other user edits are **untouchable** unless later authorized. Read-only inspection for route integration is allowed.
- The new design is **not** authorization to change authentication/privacy, `moodEntries`, `moods`, streak calculation, note limits, server timestamps, or callable write flow.
- Preserve feature-flag default **off** and any existing `APP_ENV=staging` enabled flags; no new feature flag unless explicitly approved.
- Do not use any fake dates or counters from the mockup. Use existing trusted per-user provider, Manila date/time conversion, and clear empty/partial states.
- Use existing icon and theme packages; avoid `pubspec.yaml` edits unless owner approves; use native `AnimatedContainer`, `AnimatedScale`, `AnimatedSwitcher` only if appropriate and respect reduced motion.
- No new Journal/appointment/research dashboard/term analytics/student diagnosis. Mindful Essentials stays an honest placeholder; Mental Health Support routes to existing inSIGHT (do not modify inSIGHT itself).
- The only allowed new files are small UI widgets/tests that keep existing files focused; do not rewrite app-wide architecture.

## Review Focus

1. **Multiple intentional same-day logs:** 3 saves create 3 history entries, 1 mood-active day, same existing Mood streak; tested end-to-end from form through Journey.
2. **Account changes mid-request:** prior user's note, selection, loading outcome, confirmation, and timeline never appear to the next user.
3. **Save succeeds but history reload fails:** confirmation persists; retry refresh never submits the mood again.
4. **Narrow viewport + text scale + keyboard:** 7 choices, week strip and actions remain usable, no overflow/hidden Save.
5. **Legacy/default-disabled:** original Home and writer behavior remains valid when V2 feature flag is off; no retroactive semantic changes to general Day streak.

## File Map — confirm local source first

| Responsibility | Expected file | Work |
| --- | --- | --- |
| Home position and one CTA | `lib/features/home/screens/home_screen.dart` | Modify only V2 Home card integration; retain existing yellow CTA |
| Home card widget | `lib/features/home/widgets/home_dashboard_widgets.dart` | Remove/orphan-free cleanup of obsolete `HomeMoodV2SummaryCard` if unused; keep others |
| Mood form and saved confirmation | `lib/features/mood/screens/log_mood_screen.dart` | Re-compose presentation around existing behavior |
| Dense history presentation | `lib/features/mood/widgets/mood_v2_history_panel.dart` | Remove it from Mood Log composition; reuse/reshape only for Journey if suitable |
| Journey screen | `lib/features/mood/screens/mood_journey_screen.dart` | Re-compose to reference |
| Journey summary | `lib/features/mood/widgets/mood_journey_summary.dart` | Compact week strip/streak/period summary |
| Feature gate label helper | `lib/features/mood/config/mood_v2_feature_flag.dart` | Read only unless unavoidable and separately justified; never change flag values/defaults |
| Existing provider and V2 analytics | `lib/providers/mood_provider.dart`, `lib/features/mood/domain/mood_v2_analytics.dart` | Read only in UI-polish scope |
| Home widgets | `test/features/home/home_screen_test.dart` | Add/update tests |
| Mood Logger | `test/features/mood/log_mood_screen_test.dart` | Add/update tests |
| Journey | `test/features/mood/mood_journey_test.dart` | Add/update tests |
| History | `test/features/mood/mood_v2_history_panel_test.dart` | Adjust tests only where UI contract changes |
| Existing app navigation | `lib/routes/route_names.dart`, `lib/routes/app_pages.dart` or local route equivalent | Read-only audit; use established routes |

If a path/function differs in the local branch, report the real one and update the plan before touching code; **do not invent an API to satisfy this file map**.

---

### Task 0: Establish a safe visual and functional baseline

**Files:** No app modifications. Read the two design images and the spec; inspect paths in File Map; identify existing theme tokens, logger call path, summary shape, V2 gate, Home button, route to Journey and inSIGHT, and local test names.

**Interfaces:** No new interface. Produce a 1-page audit with current branch/HEAD, worktree exclusions, source paths, theme source, existing onTap navigation, and potential visual parity risks.

- [ ] **Step 1:** Read `AGENTS.md`, source files, design spec, and both PNGs. Record source function/widget names; verify that selected mood values and note/camera semantics are already wired.
- [ ] **Step 2:** `git status --short`, `git branch --show-current`, `git rev-parse HEAD`, `git diff --name-only`, `git diff --cached --name-only`. Record all unrelated/overlapping work; stop if safe isolation is impossible.
- [ ] **Step 3:** Run targeted baseline tests (Home, Log Mood, Journey) with current local V2 staging configuration; record result, no repair outside scope.
- [ ] **Step 4:** Capture existing device screenshots or Flutter screenshots for before/after comparison; no credential/data export.

**Gate:** Owner-approved spec/assets and baseline audit available; no code changed.

### Task 1: Home — exact existing mood entry CTA, no duplicate card

**Files:** Modify `home_screen.dart` and if safe `home_dashboard_widgets.dart`; test `home_screen_test.dart`.

**Interfaces:** Consume the existing Home `Log a mood` action and current navigation. Produce exactly one visible Home mood-logging CTA when V2 enabled, while preserving general `Day streak` and all other Home sections.

- [ ] **Step 1 — RED:** Add widget test `v2_home_keeps_one_existing_log_button_and_no_mood_checkins_card`; assert exactly one Home `Log a mood` CTA, absence of `Mood check-ins` card, general `Day streak` present, tap opens existing logger, five-tab navigation unchanged. Run test; observe failure before code.
- [ ] **Step 2 — GREEN:** Remove duplicate V2 summary card insertion and any now-unused dedicated Home widget only if no other usage. Keep the original yellow CTA location and style, Announcement/appointments/general streak untouched.
- [ ] **Step 3:** Re-run focused Home tests in enabled and default-disabled staging configurations; inspect one updated Home screenshot against left mockup.
- [ ] **Step 4:** Stage only exact Home hunks/test; `git diff --cached --check` and inspect `git diff --cached`. If diff includes unapproved hunks, do not commit; ask for boundary. Otherwise local checkpoint commit `style(mood): restore single home logging entry`.

### Task 2: Mood Log — compact check-in summary and expressive picker

**Files:** Modify `log_mood_screen.dart`; optionally create a small local pure presentation widget in `lib/features/mood/widgets/`; tests `log_mood_screen_test.dart`.

**Interfaces:** Consume **existing** current-user `todayCount`, `moodStreak`, selection, draft note and camera state via actual provider types (identify in Task 0). Produce the visually compact authenticated summary banner and selected/unselected mood card states; do not change persistence interfaces.

- [ ] **Step 1 — RED:** Add tests `v2_log_shows_own_today_count_and_mood_streak`, `v2_log_shows_all_seven_original_mood_labels`, `v2_log_selection_enables_save_without_changing_value_mapping`, `v2_log_note_camera_and_validation_remain_usable`. Test counts (0 and 4), labels, selection semantics, and save state; run and see relevant failures.
- [ ] **Step 2 — GREEN:** Apply existing palette to natural header, slim pale-sage summary (`N check-ins today`, `Mood streak · N days`), concise reassurance, prompt, 2-column six-choice grid + compact Excited row; selected gold/sage outline and check affordance. No giant card descriptions. Ensure narrow and large text layouts scroll sensibly.
- [ ] **Step 3:** Retain existing <=300-character optional note, optional camera behavior, permission/privacy notice, writer and duplicate-save gating. Make the Save button gold, conspicuous, and safe-area aware, without covering keyboard or assistive controls.
- [ ] **Step 4:** Remove dense full-history/raw analytics card **from Mood Log screen composition**, not from repository/provider; Journey owns personal history. Implement 160–220 ms selection feedback, honoring disabled animations.
- [ ] **Step 5:** Run enabled widget tests and default-disabled compatibility tests; inspect screenshot against center mockup at ~390 dp. Stage inspected hunks only; checkpoint commit if isolated.

### Task 3: Mood Saved — light, trustworthy confirmation with repeat action

**Files:** Modify existing `log_mood_screen.dart` confirmation builder (or extract small presentation-only widget); test `log_mood_screen_test.dart` and journey navigation test if needed.

**Interfaces:** Consume existing save-confirmation record (mood label, timestamp, new-entry reset callback, Journey navigation, Home navigation). Preserve current idempotent request lifecycle; do not add writes.

- [ ] **Step 1 — RED:** Add `save_confirmation_shows_mood_and_manila_time`, `save_success_has_log_another_and_journey_actions`, `history_refresh_failure_does_not_erase_success_or_resubmit`, `log_another_creates_new_intent_even_same_mood`. Run focused suite to observe failure for new UI assertions.
- [ ] **Step 2 — GREEN:** Replace oversized technical success text/history dump with the approved compact ivory status card: green check, chosen mood glyph/label, short acknowledgement, display-friendly Manila timestamp, pale-sage hint, gold `Log another mood`, sage-outline `View My Mood Journey`, tertiary `Return Home`, concise non-diagnosis footer.
- [ ] **Step 3:** Verify that repeating a mood begins a *new* intentional write; retries retain the old request ID; history retries do not trigger submission; account switch discards old confirmation/draft.
- [ ] **Step 4:** Run tests and compare screenshot with save-success reference. Commit only isolated presentation/test hunks after `git diff --cached --check`.

### Task 4: Mood Journey — compact personal weekly experience

**Files:** Modify `mood_journey_screen.dart`, `mood_journey_summary.dart`; reuse/reshape `mood_v2_history_panel.dart` only if it remains the appropriate owner; test `mood_journey_test.dart`, history tests.

**Interfaces:** Consume the existing owner-scoped historical event list, Manila-day streak and period counts; produce a nonwrapping last-seven-day strip, Week/Month local presentation choice, tie-aware most-logged mood summary, and owner-only timeline.

- [ ] **Step 1 — RED:** Add tests `journey_seven_days_single_horizontal_strip`, `journey_same_day_entries_distinct_and_one_streak_day`, `journey_week_month_switch_changes_displayed_period`, `journey_tie_does_not_invent_dominant_mood`, `journey_partial_history_is_marked`, `journey_owner_switch_clears_private_notes`, `journey_support_routes_to_existing_insight`.
- [ ] **Step 2 — GREEN:** Implement reference hierarchy: compact header/title, *mood*-specific streak card with sage/leaf differentiation, seven-day horizontal scroller (>=48 dp targets and no wrap on narrow widths), pill Week/Month toggle, two concise personal insight tiles, grouped timeline with short mood names/Manila time, expandable existing owner notes.
- [ ] **Step 3:** Keep each same-day history record separate, latest first, even if display times match. Use honest empty and partial-history states. No research charts or term filters in app.
- [ ] **Step 4:** Place Mindful Essentials as non-interactive honest placeholder without fake navigation; route Mental Health Support using **existing inSIGHT** route. Keep appointment absent from this screen.
- [ ] **Step 5:** Run Journey/history/insight-navigation tests, inspect screenshot against right mockup, test narrow widths and large text. Stage only the approved files, inspect diff, local checkpoint if isolated.

### Task 5: Integrated behavior and visual/device acceptance

**Files:** Existing focused tests only; no production/backend source outside UI scope. Capture four device screenshots for owner inspection.

**Interfaces:** No new feature API. Report proof that code and screenshots match spec, with evidence from exact commands and manual testing.

- [ ] **Step 1 — RED:** Add an integrated widget/route harness using the existing fake repository/provider: perform 3 intentional same-day saves (including repeated mood), navigate to Journey, assert 3 records displayed and only 1 active streak day; test no cross-account note leakage after switch. Make it fail on previous missing coverage.
- [ ] **Step 2 — GREEN:** Make only the minimal UI/navigation or test-harness changes needed; do not modify live backend contracts.
- [ ] **Step 3:** Run `dart.bat analyze` for touched Dart paths, `flutter.bat analyze --no-pub`, enabled V2 focused suites, default-disabled Home/Log/Insights regressions, and `flutter.bat test --no-pub --dart-define=APP_ENV=staging --reporter compact`. For enabled focused runs, use exact existing local defines: `--dart-define=APP_ENV=staging --dart-define=ENABLE_MOOD_V2=true --dart-define=ENABLE_MOOD_V2_PROVIDER_READ=true --dart-define=ENABLE_MOOD_V2_HOME_READ=true --dart-define=ENABLE_MOOD_V2_PROFILE_READ=true --dart-define=ENABLE_MOOD_V2_HISTORY_READ=true --dart-define=ENABLE_MOOD_V2_INSIGHTS_READ=true`; no feature flags committed/changed.
- [ ] **Step 4:** Build a **staging debug APK only if owner authorizes build/installation** (do not deploy backend). Capture physical-device Home, Mood Log, Mood Saved, Journey screenshots; compare against both references. Check 320/360/390/430 dp, keyboard open, TalkBack, large text, camera permission, animation disabled, back navigation and owner switching.
- [ ] **Step 5:** Run `git diff --check`, inspect `git status --short` and `git diff --cached --name-only`; report all non-UI dirty files unchanged. If cleanly scoped and permitted, local checkpoint commit; no push/merge/deploy.

## Final handoff / evidence required

Report: active branch and HEAD before/after; exact changed paths and checkpoint commit(s) if created; screenshot comparison notes for four states; enabled/default-disabled/full-suite counts and analyzer results; integrated 3-save test result; device accessibility/navigation/camera results; remaining gaps; preserved unrelated dirty files. Do not claim "pixel-identical" or "fully accepted" without actual screenshot comparison and physical-device tests. Explicitly state that generated reference text/data are illustrative while live UI is data-driven.

## Self-review mapping

- Home single button: Task 1.
- Mood Log compact summary, seven choices, optional note/camera, gold save CTA: Task 2.
- Save success design, repeated independent check-ins, errors: Task 3.
- Journey seven-day strip, Week/Month, timeline, placeholders/routes, partial data: Task 4.
- End-to-end multi-entry, privacy, responsive/accessibility/device, feature-flag regression: Task 5.

**Execution preference:** follow the existing worktree with native/task-by-task execution and focused scoped commits, because prior worktree storage and overlapping uncommitted client changes make another worktree and automated wide staging unsafe. Independent code review is welcome after the last task but is not an invitation to modify unrelated files.
