# Mood V2 Default Staging Presentation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A plain `flutter build apk --debug --flavor staging --dart-define=APP_ENV=staging` shows the complete Mood V2 presentation, while ordinary accounts keep saving through the legacy writer and the protected V2 writer stays disabled everywhere.

**Architecture:** One flag (`MoodV2FeatureFlag.enabled`) currently selects both the V2 layout and the V2 writer. It splits into `presentation` (defaults to staging), `enabled` (the writer, stays false), and five read flags (default to staging). Every `widget.moodV2Enabled` site in Log Mood is reclassified as layout or persistence, and the saved-mood confirmation becomes source-neutral so a legacy entry can render in the V2 design without fabricating a V2 event.

**Tech Stack:** Flutter (Dart), compile-time `bool.fromEnvironment` constants, Provider, Firebase (unchanged).

**Spec:** `docs/superpowers/specs/2026-11-14-mood-v2-default-presentation-design.md`

## Global Constraints

- **The protected V2 writer stays `false` in every environment**, including staging. No task enables it.
- **No changes to** `firestore.rules`, `functions/`, App Check, or the pilot allowlist.
- **Production and development defaults are unchanged** — all six flags remain `false` outside staging.
- Explicit `--dart-define` overrides keep working in both directions, for every flag.
- `bool.fromEnvironment` needs a **const** `defaultValue`; `AppEnvironmentConfig.isStaging` is a getter and cannot be used. `isStagingBuild` must be a `const`.
- **Never fabricate a `MoodV2Event`** from a legacy entry, and **never call `MoodProvider.recordConfirmedMoodV2Entry`** after a legacy save — it injects a `v2`-source event into combined history, reaching the home card and streak.
- **No second daily entry** is offered when the writer is off; the legacy writer allows one check-in per day.
- Account isolation is preserved: existing ownership guards (`_ownedV2History`, `_requireCurrentUser`) are untouched.
- Do not restore the duplicate Home buttons removed by PR #18.
- Commit trailer: `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. No push, merge, deploy or APK install without the user's approval.

## Review Focus

1. **The ordinary case — no mood logged today, writer off.** The blank form must still render and save via the legacy writer; this is the most common path and the easiest to break while reworking the branches. Pinned in Task 2.
2. **Account switch with a confirmation on screen.** A confirmation built from one account's legacy entry must not survive into the next account's session. Pinned in Task 3.
3. **A legacy save that fails** (offline, permission). The error and retry must surface inside the V2 layout, not vanish with the legacy-only branches. Pinned in Task 2.
4. **The day rolling over while the screen is open.** With the writer off, the overnight reset at `log_mood_screen.dart:759` must still clear today's state. Pinned in Task 2.
5. **A pilot account in staging that already has real V2 entries.** Its history must merge legacy and V2 rather than showing one source, since the writer being off does not mean V2 rows are absent. Pinned in Task 4.

---

## File Structure

**Config**
- Modify `lib/core/config/app_environment.dart` — add `isStagingBuild`.
- Modify `lib/features/mood/config/mood_v2_feature_flag.dart` — add `presentation`, repoint read defaults, clarify `enabled`.

**Screen**
- Modify `lib/features/mood/screens/log_mood_screen.dart` — the split, the classification, the source-neutral confirmation.

**Readers**
- Modify `lib/features/home/screens/home_screen.dart`, `lib/features/profile/screens/profile_screen.dart`, `lib/features/profile/screens/mental_health_insights_screen.dart` — injection seams where tests need both states; the caption at `mental_health_insights_screen.dart:918`.
- Modify `lib/repositories/mood_v2_repository.dart` — defensive guard on `create` only.

**CI**
- Modify `.github/workflows/android-verify.yml:35` and `.github/workflows/mood-v2-emulator-validation.yml:115`; add one staging-defaults job.

**Tests**
- `test/features/mood/mood_v2_feature_flag_test.dart` (create), `test/features/mood/log_mood_screen_test.dart`, `test/features/home/home_screen_test.dart`, `test/providers/mood_provider_test.dart`.

**Commands** — `flutter test <paths>`, `flutter analyze`, and the staging build in Task 6. Baseline on this branch: `test/features/mood test/features/home test/providers/mood_provider_test.dart` = **175 pass, 3 skipped, 1 pre-existing failure** (`home_screen_test.dart` asserts `'Teaching Work Well-Being Reflection'` where the app now says `'Teaching Assessment'` — already failing on `main`, not this work's to fix).

---

### Task 1: Environment constant and the flag split

**Files:**
- Modify: `lib/core/config/app_environment.dart`
- Modify: `lib/features/mood/config/mood_v2_feature_flag.dart`
- Test: `test/features/mood/mood_v2_feature_flag_test.dart` (create)

**Interfaces — Produces:**
```dart
// app_environment.dart
static const isStagingBuild = _name == 'staging';   // _name is already const

// mood_v2_feature_flag.dart
static const presentation = bool.fromEnvironment(
    'ENABLE_MOOD_V2_PRESENTATION', defaultValue: AppEnvironmentConfig.isStagingBuild);
static const enabled = bool.fromEnvironment('ENABLE_MOOD_V2', defaultValue: false); // WRITER ONLY
static const providerRead /* homeRead, profileRead, historyRead, insightsRead */ =
    bool.fromEnvironment('ENABLE_MOOD_V2_PROVIDER_READ',
        defaultValue: AppEnvironmentConfig.isStagingBuild);
```
`actionLabel` is unchanged, including its `writerEnabled = enabled` default.

- [ ] **Step 1: Write the failing test.** Compile-time constants cannot be varied at runtime, so assert the *relationships*, which hold in both configurations and are proven by the two CI jobs in Task 5:
```dart
test('presentation and readers follow the staging build, writer never does', () {
  expect(MoodV2FeatureFlag.presentation, AppEnvironmentConfig.isStagingBuild);
  for (final read in [MoodV2FeatureFlag.providerRead, MoodV2FeatureFlag.homeRead,
                      MoodV2FeatureFlag.profileRead, MoodV2FeatureFlag.historyRead,
                      MoodV2FeatureFlag.insightsRead]) {
    expect(read, AppEnvironmentConfig.isStagingBuild);
  }
  expect(MoodV2FeatureFlag.enabled, isFalse);
});
test('isStagingBuild agrees with the resolved environment', () {
  expect(AppEnvironmentConfig.isStagingBuild,
      AppEnvironmentConfig.current == AppEnvironment.staging);
});
```
- [ ] **Step 2: Run to verify it fails** — `flutter test test/features/mood/mood_v2_feature_flag_test.dart`. Expected: FAIL, `presentation` undefined.
- [ ] **Step 3: Implement** the constant and the flag changes above. Update `enabled`'s doc comment to state it governs the protected **writer** only and does not affect presentation.
- [ ] **Step 4: Run to verify it passes**, and again with `--dart-define=APP_ENV=staging` — both must pass. Also run `--dart-define=APP_ENV=staging --dart-define=ENABLE_MOOD_V2_PRESENTATION=false` and confirm the first test fails, proving overrides still win (then discard that run).
- [ ] **Step 5: Commit** `feat(mood): add staging-aware presentation and reader defaults`

---

### Task 2: Split presentation from the writer in Log Mood

**Files:**
- Modify: `lib/features/mood/screens/log_mood_screen.dart`
- Test: `test/features/mood/log_mood_screen_test.dart`

**Interfaces:**
- Consumes: Task 1's `MoodV2FeatureFlag.presentation` and `enabled`.
- Produces: the screen takes two injectable inputs — `presentation` (default `MoodV2FeatureFlag.presentation`) and `writerEnabled` (default `MoodV2FeatureFlag.enabled`) — replacing the single `moodV2Enabled`. Task 3 builds on the same two.

**The classification.** Every current `widget.moodV2Enabled` site, already audited:

| Lines | What it governs | Becomes |
|---|---|---|
| 69 (`_offerMoodReflection`), 236 (`v2:`), 311, 320, 330, 350, 367, 375, 392, 413, 417, 429, 438, 442 | layout, styling, compact variants, reflection prompt, history placement, button label | `presentation` |
| 206 (bottom bar), 238 (`showingResult:`), 271 (confirmation render) | whether the save bar and the result are shown | `presentation` **and** the source-neutral "confirmation shown" state from Task 3 |
| 289, 295, 304 (legacy loading / error / today's result) | the legacy today's-mood states | shown when the **writer is off** — invert from `!moodV2Enabled` to `!writerEnabled` |
| 510 (`_loadTodayMood` V2 branch) | which load runs | `writerEnabled`; with the writer off the legacy load must run |
| 552 (`_saveMoodV2` branch) | the writer | `writerEnabled` |
| 759 (overnight reset skip) | keeping a V2 draft overnight | `writerEnabled` |

- [ ] **Step 1: Write the failing tests** (all with `presentation: true, writerEnabled: false` unless stated):
  - **the ordinary path**: no mood today → the V2 form renders, choosing a mood and saving calls the **legacy** provider save, and `_saveMoodV2` is never reached
  - a **failing** legacy save surfaces its error inside the V2 layout and the retry works
  - the **overnight reset** still clears today's state when the day rolls over
  - no "log another" affordance is offered anywhere
  - with `writerEnabled: true` the V2 save path is still chosen (existing behaviour preserved)
  - with `presentation: false` the legacy layout renders exactly as today
- [ ] **Step 2: Run to verify they fail** — `flutter test test/features/mood/log_mood_screen_test.dart`
- [ ] **Step 3: Implement** the two inputs and apply the classification table. No site may read the writer flag for a visual decision, and none may read `presentation` for a persistence decision.
- [ ] **Step 4: Run to verify they pass**, plus `flutter test test/features/mood` and `flutter analyze lib/features/mood test/features/mood`
- [ ] **Step 5: Commit** `feat(mood): separate Mood V2 presentation from the protected writer`

---

### Task 3: Source-neutral confirmation and today's legacy entry

**Files:**
- Modify: `lib/features/mood/screens/log_mood_screen.dart`
- Test: `test/features/mood/log_mood_screen_test.dart`

**Interfaces:**
- Consumes: Task 2's `presentation` / `writerEnabled`.
- Produces: `_MoodSaved` takes a source-neutral view (label, timestamp, optional note) instead of requiring a `MoodV2Event`; a single "confirmation shown" state drives lines 206, 238 and 271 regardless of which writer produced it.

- [ ] **Step 1: Write the failing tests** (`presentation: true, writerEnabled: false`):
  - a student who **already logged today** sees the V2 confirmation showing that legacy entry's label and time — not a blank form, and not the old V1 card
  - after a successful legacy save the same V2 confirmation appears, with the saved label
  - `recordConfirmedMoodV2Entry` is **never** called on the legacy path (assert on a fake provider)
  - no `MoodV2Event` is constructed from a legacy entry (assert the provider receives no v2 event; combined history gains no `v2`-source row)
  - the confirmation offers **no** "log another" action
  - after the legacy save, today's mood, the streak and insights **refresh** through the existing legacy provider path
  - **account switch**: with a confirmation on screen, switching to another account clears it rather than showing the previous account's mood
  - with `writerEnabled: true` the V2 confirmation still renders from a real `MoodV2Event`
- [ ] **Step 2: Run to verify they fail**
- [ ] **Step 3: Implement.** Make `_loadTodayMood` run the legacy load when the writer is off, and feed its result into the same confirmation state the V2 path uses. Keep the legacy retry-on-error reachable inside the V2 layout.
- [ ] **Step 4: Run to verify they pass**, plus `flutter test test/features/mood test/providers/mood_provider_test.dart`
- [ ] **Step 5: Commit** `feat(mood): show today's legacy entry in the V2 confirmation`

---

### Task 4: Reader surfaces and repository couplings

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart`, `lib/features/profile/screens/profile_screen.dart`, `lib/features/profile/screens/mental_health_insights_screen.dart`
- Modify: `lib/repositories/mood_v2_repository.dart`
- Test: `test/features/home/home_screen_test.dart`, `test/providers/mood_provider_test.dart`

**Interfaces:**
- Consumes: Task 1's read flags.
- Produces: injection seams on the read surfaces whose tests need both states (flag parameters defaulting to the constants).

- [ ] **Step 1: Write the failing tests**
  - with the read flags on and **no V2 entries**, the home card still shows the legacy today's mood (the fallback at `home_screen.dart:263-274` must hold)
  - combined history for a **legacy-only** account lists its legacy entries, and the streak is computed from them
  - combined history for an account with **both** legacy and V2 rows merges them in date order without duplication
  - history events belonging to another uid are rejected (`_ownedV2History` behaviour preserved)
  - profile and insights render their V2 presentation with the flags on and legacy-only data
- [ ] **Step 2: Run to verify they fail**
- [ ] **Step 3: Implement.** Add flag parameters only where a test needs both states. Repoint the caption at `mental_health_insights_screen.dart:918` from `enabled` to `presentation`. Add a defensive guard so the legacy save path cannot reach `MoodV2Repository.create`'s bare `StateError`. **Leave `MoodV2Repository.fetchHistory` gated on the writer flag** — repointing it to a read flag would return V2-only history and recreate the empty-Journey failure.
- [ ] **Step 4: Run to verify they pass**, plus `flutter test test/features/home test/features/profile test/providers` and `flutter analyze` on the touched paths
- [ ] **Step 5: Commit** `feat(mood): keep V2 read surfaces working with legacy-only data`

---

### Task 5: CI — separate the two configurations

**Files:**
- Modify: `.github/workflows/android-verify.yml` (line 35), `.github/workflows/mood-v2-emulator-validation.yml` (line 115)

- [ ] **Step 1: Pin the existing runs to a neutral environment** so no existing test's behaviour shifts: remove `--dart-define=APP_ENV=staging` from the suite-wide `flutter test` invocations (or set it explicitly to `development`), leaving every other argument unchanged.
- [ ] **Step 2: Add one job** that runs `flutter test test/features/mood test/features/home test/features/profile test/providers --dart-define=APP_ENV=staging`, so the staging defaults are proven on every push.
- [ ] **Step 3: Verify** both invocations locally — the neutral set and the staging set must each be green (allowing the one pre-existing `home_screen_test.dart` failure noted above).
- [ ] **Step 4: Commit** `ci(mood): cover default and staging flag configurations separately`

---

### Task 6: Verification and the staging APK

**Files:** none (verification only), plus any fix a failure demands.

- [ ] **Step 1: Run the full regression** — `flutter test` (neutral) and the staging-scoped set, recording real numbers. Compare against the baseline: 175 pass / 3 skipped / 1 pre-existing failure on the mood+home+provider scope.
- [ ] **Step 2: `flutter analyze`** — must be clean.
- [ ] **Step 3: Build the staging APK with no Mood V2 flags** — `flutter build apk --debug --flavor staging --dart-define=APP_ENV=staging`. Record the exact output path and the source commit.
- [ ] **Step 4: Confirm the writer is still disabled** — grep the built config path and assert `MoodV2FeatureFlag.enabled` has no staging default; state plainly that the APK cannot be inspected for the constant directly, so this rests on the Task 1 test plus the absence of any staging default on `enabled`.
- [ ] **Step 5: Report** changed files, test results, remaining limitations, and confirmation that the protected writer is disabled. **Do not install or push.**

---

## Acceptance criteria

- A staging APK built with no Mood V2 flags shows the V2 Log Mood design, Journey, home card, profile statistics and insights.
- An ordinary (non-pilot) account can log a mood, see the V2 confirmation, and find it on the home card and in history afterwards.
- A student who already logged today sees that entry in the V2 confirmation, with no second-save affordance.
- `MoodV2FeatureFlag.enabled` is `false` in every environment, and no code path reaches `_saveMoodV2` when it is false.
- No `v2`-source event appears in combined history as a result of a legacy save.
- Production and development builds behave exactly as before this change.
- `flutter analyze` is clean; both CI configurations are green apart from the documented pre-existing failure.

## Rollback

Every change is additive or a default change; there is no data migration and no deployed component.

- **Full rollback:** `git revert` the task commits in reverse order, or abandon the branch — nothing is merged or deployed by this plan.
- **Partial rollback without reverting code:** build with `--dart-define=ENABLE_MOOD_V2_PRESENTATION=false --dart-define=ENABLE_MOOD_V2_PROVIDER_READ=false --dart-define=ENABLE_MOOD_V2_HOME_READ=false --dart-define=ENABLE_MOOD_V2_PROFILE_READ=false --dart-define=ENABLE_MOOD_V2_HISTORY_READ=false --dart-define=ENABLE_MOOD_V2_INSIGHTS_READ=false`, which restores the pre-change experience in staging without touching the tree.
- **Server-side:** nothing to roll back — no rules, functions, or allowlist are modified.
