# Day Streak aligned to Mood V2 (item 38) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- The Home "Day streak" shows the same mood-check-in streak as My Mood Journey.
- It is shown with four states and a color-shifting animated fire.
- A milestone "View recap" opens My Mood Journey, which gains a banner, a Best day card, a gentle tip and a support note.

**Architecture:**
- **Pure functions decide everything.** A streak resolver (V2 history first, then the stored counter), a flame color function, and a weekly recap builder. They are unit-tested.
- **Widgets only render their results.**
- **The stored `users.dayStreak` counter becomes mood-only and is read through an "effective" value.** That keeps reports and MindAid consistent.
- **Mood V2 code, flags, server and rules are not changed.**

**Tech Stack:** Flutter (Dart), Provider, Material 3, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-12-day-streak-mood-recap-design.md`

## Global Constraints

- **Branch:**
  - Work only on `feat/day-streak-38`.
  - Never push. Never commit `pubspec.lock`, `linux/`, `macos/` or `windows/`; run `git checkout -- pubspec.lock linux macos windows` after every `flutter` command.
- **Out of bounds:**
  - No change to Mood V2 flags or defaults (`lib/features/mood/config/mood_v2_feature_flag.dart`).
  - No change to the V2 writer, Cloud Functions, `firestore.rules`, indexes, or Firestore field names.
- **Test command:**
  - Always pass `--dart-define=APP_ENV=staging`.
  - The V2-enabled focused runs add `--dart-define=ENABLE_MOOD_V2=true --dart-define=ENABLE_MOOD_V2_PROVIDER_READ=true --dart-define=ENABLE_MOOD_V2_HOME_READ=true --dart-define=ENABLE_MOOD_V2_PROFILE_READ=true --dart-define=ENABLE_MOOD_V2_HISTORY_READ=true --dart-define=ENABLE_MOOD_V2_INSIGHTS_READ=true`.
- **Milestones:** `d == 7 || d == 14 || d == 30 || (d > 30 && d % 30 == 0)`.
- **Flame colors:**
  - Stops: day 1 `#C62828`, 7 `#A0237A`, 14 `#7B2FA8`, 21 `#5B3FC4`, 30+ `#4169E1`, linearly interpolated (`Color.lerp`) between stops.
  - Day 0 is `#B8B2A6` at 60% opacity (unlit).
- **Motion:**
  - The flicker is a scale 1 → 1.04 → 0.98 → 1 and a 1 px rise, with glow alpha 0.30 ↔ 0.45, on a 2.4 s ease-in-out loop anchored at the bottom center.
  - Color changes animate over 600 ms.
  - Everything is static when `MediaQuery.disableAnimations` is true, and day 0 never animates.
- **Copy is exact:**
  - "Log your mood today to start a streak."
  - "Check in today to keep your streak."
  - "Done for today. See you tomorrow!"
  - "Your week in moods is ready"
  - "Log mood"
  - "View recap ›"
  - "Milestone reached: {d} days!"
  - "🔥 {d}-day streak · Here's your week in moods"
  - "Best day"
  - "Notice what made it a good day."
  - "A gentle tip"
  - "Try breathing"
  - "Open MindAid"
  - "Book a PACC appointment"
  - "This reflects your own check-ins. It is not a diagnosis. If you'd like to talk to someone, PACC is here for you."
  - "{N}-day mood streak"
  - "{d} day" / "{d} days"
- **Colleague files:** edits to `mood_journey_screen.dart` and `mood_journey_summary.dart` (haruki1155) are additive only; existing keys, texts and tests keep passing.

## Review Focus

1. **Account switch:** V2 history loaded for a different user must never feed Home. Home falls back to the stored counter. (Task 4 test.)
2. **Manila day boundary:** a check-in yesterday and none today shows "Check in today to keep your streak." with the streak intact, not 0. (Task 4 test.)
3. **V2 history still loading** (`v2History == null`) with V2 read on: Home shows the fallback without errors. (Task 4 test.)
4. **Week with no check-ins, or unknown/missing labels** ("Excited", empty): the Best day card is hidden or shows the label it has, and the tip falls back to "Keep doing what's working." (Task 8 test.)
5. **Long streaks** (60, 61): 60 is a milestone and 61 is not; the flame stays royal blue past 30. (Tasks 4 and 5 tests.)

---

### Task 1: Stored counter counts mood check-ins only, plus effective streak

**Files:**
- Modify: `lib/repositories/user_repository.dart` (`StreakCalculator` at lines 45–110; `recordActivity` at lines 182–235)
- Test: `test/providers/user_provider_test.dart` (group `StreakCalculator`)

**Interfaces:**
- Produces:
  - `static bool StreakCalculator.countsTowardStreak(UserActivityType type)`: true only for `moodCheckIn`.
  - `static int StreakCalculator.effectiveStreak({required int storedStreak, required String? lastActivityDateKey, required DateTime now})`: returns `storedStreak` when `lastActivityDateKey` is `dateKey(now)` or the day before (local dates), otherwise 0. A negative `storedStreak` is treated as 0.

- [ ] **Step 1: Write the failing tests** in the `StreakCalculator` group:

```dart
test('only mood check-ins count toward the streak', () {
  for (final type in UserActivityType.values) {
    expect(StreakCalculator.countsTowardStreak(type), type == UserActivityType.moodCheckIn, reason: type.name);
  }
});
test('effective streak keeps today and yesterday, drops older', () {
  final now = DateTime(2026, 11, 12, 9);
  expect(StreakCalculator.effectiveStreak(storedStreak: 4, lastActivityDateKey: '2026-11-12', now: now), 4);
  expect(StreakCalculator.effectiveStreak(storedStreak: 4, lastActivityDateKey: '2026-11-11', now: now), 4);
  expect(StreakCalculator.effectiveStreak(storedStreak: 4, lastActivityDateKey: '2026-11-10', now: now), 0);
  expect(StreakCalculator.effectiveStreak(storedStreak: 4, lastActivityDateKey: null, now: now), 0);
  expect(StreakCalculator.effectiveStreak(storedStreak: 4, lastActivityDateKey: 'bad', now: now), 0);
});
```

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `flutter test --dart-define=APP_ENV=staging test/providers/user_provider_test.dart`
  - Expected: compile FAIL, because `countsTowardStreak` and `effectiveStreak` are not defined.

- [ ] **Step 3: Implement both statics.** Then change `recordActivity`:
  - When `!countsTowardStreak(type)`, the transaction still writes the `user_activities` doc but sets only `{'lastActiveAt': FieldValue.serverTimestamp()}` (merge) on the user.
  - It returns `UserModel.fromJson({...?data, 'id': uid}, id: uid)` with the stored streak fields unchanged.
  - The `moodCheckIn` path is unchanged.

- [ ] **Step 4: Run the tests and confirm they pass.**
  - Same command. Expected: all pass, including the existing 'marks activity and increments local day streak' test.

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/user_repository.dart test/providers/user_provider_test.dart
git commit -m "fix(streak): only mood check-ins advance the stored day streak (38)"
```

### Task 2: Stored-counter readers use the effective streak

**Files:**
- Modify:
  - `lib/repositories/report_repository.dart:384`
  - `lib/repositories/mind_aid_context_repository.dart` (`buildSnapshot` at line 63, field at line 118)
  - `lib/repositories/mental_health_activity_repository.dart:204`
- Test:
  - `test/features/mind_aid/mind_aid_engine_test.dart` (around line 499)
  - `test/repositories/mental_health_activity_repository_test.dart` (around line 49)

**Interfaces:**
- Consumes: `StreakCalculator.effectiveStreak` (Task 1).
- Produces: `MindAidContextRepository.buildSnapshot({..., DateTime? now})`. The new optional `now` defaults to `DateTime.now()`.

- [ ] **Step 1: Update the tests to pin the new rule.**
  - **MindAid test:**
    - Pass `now: DateTime(2026, 7, 4, 12)` and `user: const {'dayStreak': 5, 'lastActivityDateKey': '2026-07-04'}`; keep `expect(snapshot.currentStreak, 5)`.
    - Add a sibling test: `user: const {'dayStreak': 5, 'lastActivityDateKey': '2026-07-01'}` with the same `now` → `expect(snapshot!.currentStreak, 0)`.
  - **Activity summary test:** give the fake user doc `'lastActivityDateKey': '2026-07-07'` so `currentStreak` stays 6. Add one case with `'2026-07-01'` → `currentStreak` 0.

- [ ] **Step 2: Run the tests and confirm the new cases fail.**
  - Run: `flutter test --dart-define=APP_ENV=staging test/features/mind_aid/mind_aid_engine_test.dart test/repositories/mental_health_activity_repository_test.dart test/repositories/report_repository_test.dart`
  - Expected: the two new "drops to 0" cases FAIL (they currently get 5 and 6).

- [ ] **Step 3: Replace each raw `dayStreak` read with `StreakCalculator.effectiveStreak(...)`.**
  - Use the doc's `lastActivityDateKey` and these `now` values:
    - report: `generatedAt`
    - MindAid: the new `now`
    - activity summary: its `date`
  - In MindAid, keep the fallback to `latestReport?.currentStreak` only when the user doc is null.

- [ ] **Step 4: Run the tests and confirm they pass.** Same command. Expected: all pass.

- [ ] **Step 5: Commit**: `git commit -m "fix(streak): reports and MindAid read the effective streak (38)"` (stage the 3 lib and 2 test files).

### Task 3: V2 saves also update the stored counter; copy fix

**Files:**
- Modify: `lib/features/mood/screens/log_mood_screen.dart` (`_saveMoodV2` at line 644; text at line 1072)
- Test: `test/features/mood/log_mood_screen_test.dart`

**Interfaces:**
- Consumes: `UserProvider.markMoodCheckIn(String uid)` (already exists, `lib/providers/user_provider.dart:164`).

- [ ] **Step 1: Write the failing tests.**
  - Using the file's existing V2 save harness (`moodV2Enabled: true` with its fake writer), provide a `UserProvider` whose fake repository records `recordActivity` calls.
  - After a confirmed save, expect exactly one call with `UserActivityType.moodCheckIn` for that user.
  - Second test: when that fake throws, the save still shows its normal success UI.
  - In the existing legacy result test, change the expected text from `'N-day activity streak'` to `'N-day mood streak'`, using the same N as the test.

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `flutter test --dart-define=APP_ENV=staging test/features/mood/log_mood_screen_test.dart`
  - Expected: the three new or changed assertions FAIL.

- [ ] **Step 3: Implement the call and the text change.**
  - After `writer.create(...)` resolves successfully, call `unawaited(_readProviderOrNull<UserProvider>()?.markMoodCheckIn(userId) ?? Future.value())`.
  - It does not block the save and does not change the success UI; `UserProvider.recordActivity` already swallows errors.
  - Change the text to `'$currentStreak-day mood streak'`.

- [ ] **Step 4: Run the tests and confirm they pass.** Same command, then the same file with the V2-enabled defines. Expected: all pass.

- [ ] **Step 5: Commit**: `git commit -m "fix(mood): V2 check-ins advance the stored streak; mood streak copy (38)"`

### Task 4: Home streak resolver (single definition)

**Files:**
- Create: `lib/features/home/domain/home_streak_source.dart`
- Test: `test/features/home/home_streak_source_test.dart`

**Interfaces:**
- Consumes:
  - `MoodAnalytics.streak`, `MoodManilaCalendar`, `MoodHistoryWindow` (`lib/features/mood/domain/mood_v2_analytics.dart`)
  - `StreakCalculator.effectiveStreak` and `StreakCalculator.dateKey` (Task 1)
- Produces:

```dart
enum HomeStreakState { notStarted, activeNotToday, doneToday, milestone }
bool isStreakMilestone(int days);
class HomeStreakSnapshot {
  const HomeStreakSnapshot({required this.days, required this.checkedInToday, required this.activeDateKeys});
  final int days; final bool checkedInToday; final Set<String> activeDateKeys; // 'yyyy-MM-dd'
  HomeStreakState get state; // days==0 → notStarted; !checkedInToday → activeNotToday; milestone(days) → milestone; else doneToday
}
HomeStreakSnapshot resolveHomeStreak({
  MoodHistoryWindow? v2History, // pass only when V2 read is on AND every event.userId == signed-in uid
  required int storedStreak, String? lastActivityDateKey,
  List<String> activeDateKeys = const [], required DateTime now,
});
```

- **V2 branch** (`v2History != null`):
  - `days = MoodAnalytics.streak(v2History, referenceInstant: now).currentDays`
  - `checkedInToday` is true when any unique event's `dateKey` equals `MoodManilaCalendar.dateKeyForInstant(now)`
  - `activeDateKeys` is the set of event `dateKey`s
- **Fallback branch:**
  - `effectiveStreak(...)`
  - `checkedInToday = lastActivityDateKey == StreakCalculator.dateKey(now)`
  - the given keys

- [ ] **Step 1: Write the failing tests.** Build events with `NormalizedMoodEvent(id:, userId: 'u1', level:, dateKey:, occurredAt:, source: MoodEventSource.v2, label:)` and `now = DateTime.utc(2026, 11, 12, 4)` (Manila noon):
  - `'V2 history wins over a stale stored counter'`: events on 11-11 and 11-12, `storedStreak: 9`, key `'2026-11-12'` → `days == 2`, `checkedInToday`, `state == doneToday`.
  - `'yesterday only keeps the streak but asks for today'`: events on 11-10 and 11-11 → `days == 2`, `!checkedInToday`, `state == activeNotToday`.
  - `'missed day breaks the V2 streak'`: event on 11-09 only → `days == 0`, `state == notStarted`.
  - `'null history falls back to the effective stored counter'`: `storedStreak: 3`, key `'2026-11-11'` → `days == 3`, `!checkedInToday`; key `'2026-11-01'` → `days == 0`.
  - `'milestones'`: `isStreakMilestone` is true for 7, 14, 30, 60, 90 and false for 0, 1, 6, 8, 29, 31, 45, 61. Seven consecutive event days ending today → `state == milestone`.
  - `'activeDateKeys come from V2 events'`: they equal the set of event date keys.

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `flutter test --dart-define=APP_ENV=staging test/features/home/home_streak_source_test.dart`
  - Expected: compile FAIL (file missing).

- [ ] **Step 3: Implement `home_streak_source.dart`** per the Interfaces block.

- [ ] **Step 4: Run the tests and confirm they pass.** Same command. Expected: all pass.

- [ ] **Step 5: Commit**: `git commit -m "feat(home): resolve one mood-check-in streak from Mood V2 history (38)"`

### Task 5: Streak flame widget

**Files:**
- Create: `lib/features/home/widgets/streak_flame.dart`
- Test: `test/features/home/streak_flame_test.dart`

**Interfaces:**
- Produces:
  - `Color streakFlameColor(int days)`, with the Global Constraints stops.
  - `class StreakFlame extends StatefulWidget { const StreakFlame({super.key, required this.days, this.size = 84}); }`
    - It renders `HomeDashboardAssetImage(assetName: 'fire_icon.png')` inside a `ShaderMask` (vertical gradient from `streakFlameColor(days)` lightened 15% at the top to the color at the bottom, `BlendMode.srcATop`).
    - Behind it sits a radial glow in that color.
    - The glow, flicker and 600 ms `TweenAnimationBuilder<Color?>` follow the Global Constraints.
    - Root key: `Key('streak-flame')`. The flicker `AnimationController` exists only when `days > 0` and animations are enabled.

- [ ] **Step 1: Write the failing tests.**
  - `streakFlameColor(1) == Color(0xFFC62828)`, `(7) == Color(0xFFA0237A)`, `(14) == Color(0xFF7B2FA8)`, `(21) == Color(0xFF5B3FC4)`, and `(30)`, `(61)` and `(365)` all equal `Color(0xFF4169E1)`.
  - `(0) == Color(0xFFB8B2A6).withValues(alpha: .6)`.
  - `streakFlameColor(4)` equals `Color.lerp(c1, c7, 3/6)`.
  - Widget test 1: under `MediaQuery(data: MediaQueryData(disableAnimations: true))`, after `pump()` no ticker is active: `expect(tester.binding.transientCallbackCount, 0)`. Widget test 2: with animations on and `days: 5`, `transientCallbackCount > 0`.
  - Widget test: `days: 0` with animations on → `transientCallbackCount == 0`.

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `flutter test --dart-define=APP_ENV=staging test/features/home/streak_flame_test.dart`
  - Expected: compile FAIL.

- [ ] **Step 3: Implement the widget.** Dispose the controller. Stop and restart the controller in `didUpdateWidget` when `days` crosses 0 or `disableAnimations` changes.

- [ ] **Step 4: Run the tests and confirm they pass.** Same command. Expected: all pass.

- [ ] **Step 5: Commit**: `git commit -m "feat(home): color-shifting animated streak flame (38)"`

### Task 6: Home streak card states and routing

**Files:**
- Modify:
  - `lib/features/home/models/home_dashboard_data.dart` (`HomeStreakData` at lines 320–338)
  - `lib/features/home/widgets/home_dashboard_widgets.dart` (`HomeStreakCard` at lines 697–808)
  - `lib/features/home/screens/home_screen.dart` (card at lines 323–326; data at lines 486–552)
- Test:
  - Create `test/features/home/home_streak_card_test.dart`
  - Modify `test/features/home/home_screen_test.dart` (test 'home dashboard overlays profile, streak, moods, and report')

**Interfaces:**
- Consumes: `resolveHomeStreak`, `HomeStreakState`, `HomeStreakSnapshot` (Task 4); `StreakFlame` (Task 5).
- Produces:
  - `HomeStreakData` gains `final HomeStreakState state` (default `HomeStreakState.notStarted`) and `final bool canViewRecap` (default `false`). Existing fields are kept.
  - `HomeStreakCard({required HomeStreakData? data, required VoidCallback onTap, VoidCallback? onViewRecap})`.
  - `String homeStreakDescription(HomeStreakState state, {required int days, required bool canViewRecap})` returns the exact copy from the spec table. A milestone without recap returns "Milestone reached: {d} days!".

- [ ] **Step 1: Write the failing card tests** (pump `HomeStreakCard` alone in `MaterialApp`, with animations disabled):
  - notStarted, 0 days: shows "Log your mood today to start a streak." and "Log mood". Tapping "Log mood" calls `onTap`.
  - activeNotToday, 4 days: shows "4", "days", "Check in today to keep your streak." and "Log mood".
  - doneToday, 1 day: shows "1", "day" (not "days") and "Done for today. See you tomorrow!". No "Log mood".
  - milestone, 7 days, `canViewRecap: true`: shows "Your week in moods is ready" and "View recap ›". Tapping it calls `onViewRecap` and not `onTap`.
  - milestone, 7 days, `canViewRecap: false`: shows "Milestone reached: 7 days!" and no "View recap ›".
  - Each state renders `find.byKey(const Key('streak-flame'))`.
  - At width 360, there is no overflow (`tester.takeException()` is null).

- [ ] **Step 2: Update the Home screen test.**
  - Give the user `lastActivityDateKey: StreakCalculator.dateKey(DateTime.now())` and `dayStreak: 5`. Assert "Day streak", "5" and "Done for today. See you tomorrow!".
  - Add a case with `lastActivityDateKey: '2000-01-01'` → "Log your mood today to start a streak.".

- [ ] **Step 3: Run the tests and confirm they fail.**
  - Run: `flutter test --dart-define=APP_ENV=staging test/features/home/home_streak_card_test.dart test/features/home/home_screen_test.dart`
  - Expected: the new assertions FAIL.

- [ ] **Step 4: Implement the card.**
  - The card keeps its gradient, border and title. The right column holds `StreakFlame(days:)`, replacing the static 46 px fire.
  - "{d}" uses the existing 36/w900 style. The unit is "day"/"days".
  - Pill buttons use teal `Color(0xFF2F7D6D)` with white text for "Log mood", and a white surface with dark text for "View recap ›".

- [ ] **Step 5: Implement the Home wiring.**
  - **History:** `v2 = MoodV2FeatureFlag.homeRead && moodProvider.isMoodV2ReadEnabled && history != null && history.events.every((e) => e.userId == user.id) ? history : null`.
  - **Streak:** `resolveHomeStreak(v2History: v2, storedStreak: user.dayStreak, lastActivityDateKey: user.lastActivityDateKey, activeDateKeys: user.activeDateKeys, now: widget._nowProvider())`.
  - **Week row:** the week row's `activityDates` come from `snapshot.activeDateKeys` through the existing `_dateFromActivityKey`, keeping the existing mood fallback when empty.
  - **Recap:** `canViewRecap = MoodV2FeatureFlag.historyRead && moodProvider.isMoodV2ReadEnabled`.
  - **Navigation:**
    - `onTap` opens My Mood Journey (`MaterialPageRoute(builder: (_) => const MoodJourneyScreen())`) when the state is doneToday or milestone and `canViewRecap`; otherwise `_openLogMood`.
    - `onViewRecap` pushes `MoodJourneyScreen(milestoneDays: snapshot.days)`.

- [ ] **Step 6: Run the tests and confirm they pass.**
  - Same command, then with the V2-enabled defines on `test/features/home/home_screen_test.dart`.
  - Expected: all pass.

- [ ] **Step 7: Commit**: `git commit -m "feat(home): day streak card states, flame and recap entry (38)"`

### Task 7: Profile "Day Streak" uses the same value

**Files:**
- Modify: `lib/features/profile/screens/profile_screen.dart:350-355`
- Test: `test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes: `StreakCalculator.effectiveStreak` (Task 1); the existing `moodV2Analytics` parameter.

- [ ] **Step 1: Write the failing test.**
  - Pump the profile screen with a user (`dayStreak: 5`, `lastActivityDateKey: '2000-01-01'`) and V2 analytics null → the 'Day Streak' value is "0".
  - Pump with `lastActivityDateKey` set to today → "5".
  - Use the file's existing screen harness. The view-data tests at lines 43 and 707 stay unchanged.

- [ ] **Step 2: Run the test and confirm it fails.**
  - Run: `flutter test --dart-define=APP_ENV=staging test/features/profile/profile_screen_test.dart`
  - Expected: the "0" case FAILS.

- [ ] **Step 3: Implement the value.** The value becomes `moodV2Analytics?.streak.currentDays ?? StreakCalculator.effectiveStreak(storedStreak: effectiveUser.dayStreak, lastActivityDateKey: effectiveUser.lastActivityDateKey, now: DateTime.now())`.

- [ ] **Step 4: Run the test and confirm it passes.** Same command. Expected: all pass.

- [ ] **Step 5: Commit**: `git commit -m "fix(profile): day streak shows the effective mood streak (38)"`

### Task 8: My Mood Journey recap additions

**Files:**
- Create: `lib/features/mood/domain/mood_week_recap.dart`
- Modify:
  - `lib/features/mood/widgets/mood_journey_summary.dart`
  - `lib/features/mood/screens/mood_journey_screen.dart`
- Test:
  - Create `test/features/mood/mood_week_recap_test.dart`
  - Modify `test/features/mood/mood_journey_test.dart`

**Interfaces:**
- Consumes: `StreakFlame` (Task 5); `NormalizedMoodEvent`, `MoodJourneyPeriod`, `includesMoodJourneyDate` (existing).
- Produces:

```dart
enum MoodTipKind { breathing, talk, rest, keepGoing }
class MoodWeekRecap {
  const MoodWeekRecap({required this.bestDay, required this.tip});
  final NormalizedMoodEvent? bestDay; // highest level; ties → latest occurredAt; null when no events
  final MoodTipKind tip; // stressed|angry ≥2 → breathing; sad ≥2 → talk; tired ≥2 → rest; else keepGoing (first match, case-insensitive trimmed labels)
  static MoodWeekRecap from(List<NormalizedMoodEvent> weekEvents);
}
```

- `MoodJourneyScreen({super.key, this.nowProvider, this.milestoneDays})` (`int?`). It passes `milestoneDays` to `MoodJourneySummary`, which gains `final int? milestoneDays`.

- [ ] **Step 1: Write the failing recap tests.**
  - Empty list: `bestDay == null`, `tip == keepGoing`.
  - [Okay(4) Mon, Great(5) Fri, Great(5) Sat]: bestDay is the Sat event.
  - Two 'Stressed' + one 'Angry': breathing. One 'stressed ' + one 'ANGRY': breathing (2 total, trimmed, case-insensitive).
  - Two 'Sad': talk. Two 'Tired': rest.
  - Two 'Sad' + two 'Stressed': breathing (first rule wins).
  - Labels `null`, '' and 'Excited' only: keepGoing.

- [ ] **Step 2: Write the failing Journey widget tests** (in `mood_journey_test.dart`, using its `_JourneyAuth`/`_PeriodMood` fakes, `now = DateTime.utc(2026, 11, 12)`):
  - `MoodJourneyScreen(milestoneDays: 7)` shows "🔥 7-day streak · Here's your week in moods". Without `milestoneDays` the banner is absent.
  - The Mood Streak card contains `Key('streak-flame')`. The existing card test (white, yellow border, 'Mood Streak') still passes.
  - This Week with a week Great event: shows "Best day", "Notice what made it a good day.", "A gentle tip", "Book a PACC appointment" and the exact support note.
  - With two Stressed events: shows "Try breathing". Tapping it pushes `RouteNames.mindfulBreathing` (register a stub route in the test `MaterialApp`).
  - Switching to This Month hides "Best day" and "A gentle tip".

- [ ] **Step 3: Run the tests and confirm they fail.**
  - Run: `flutter test --dart-define=APP_ENV=staging test/features/mood/mood_week_recap_test.dart test/features/mood/mood_journey_test.dart`
  - Expected: the new tests FAIL.

- [ ] **Step 4: Implement the recap builder and the additions.**
  - **Builder:** implement `MoodWeekRecap.from`.
  - **Summary:**
    - Insert the banner (gold gradient `#FFD75C`→`#FFC414`, radius 16, 15/w800) above `mood-streak-card` when `milestoneDays != null`.
    - Replace the static `Icons.local_fire_department_rounded` with `StreakFlame(days: streak.currentDays, size: 44)`.
    - After the date-range text, when `period == MoodJourneyPeriod.week`, add three cards built from `MoodWeekRecap.from(filtered)`:
      - **Best day:** hidden when `bestDay == null`. Shows the full weekday name and the label.
      - **A gentle tip:**
        - Fixed tip text per kind:
          - breathing: "Stress showed up a few times this week. A 2-minute breathing session can help you reset."
          - talk: "Some days felt low this week. Talking to someone can help."
          - rest: "You felt tired on a few days. Try an earlier night or a short rest today."
          - keepGoing: "Keep doing what's working."
        - Buttons: "Try breathing" opens `RouteNames.mindfulBreathing`; "Open MindAid" opens `RouteNames.mindAid`.
      - **Support note:** "Book a PACC appointment" pushes `PaccCounselingScreen(startBooking: true)` (`lib/features/counseling/screens/pacc_counseling_screen.dart`).
  - **Screen:** when `milestoneDays != null`, initialise `_period = MoodJourneyPeriod.week`.

- [ ] **Step 5: Run the tests and confirm they pass.**
  - Same command, then with the V2-enabled defines on `test/features/mood` (excluding `mood_v2_repository_test.dart`, which requires disabled defaults).
  - Expected: all pass.

- [ ] **Step 6: Commit**: `git commit -m "feat(mood): milestone recap on My Mood Journey (38)"`

### Task 9: Full verification and on-device check

- [ ] **Step 1: Run analyze and the full suite.**
  - Run: `flutter analyze` → "No issues found!".
  - Run: `flutter test --dart-define=APP_ENV=staging` → "All tests passed!" (baseline 685, plus the new tests).
- [ ] **Step 2: Run the V2-enabled focused suite.**
  - Run with the six V2 defines on `test/features/home test/features/mood test/providers/mood_provider_test.dart test/features/insights/insight_mood_v2_metrics_test.dart`, excluding `test/features/mood/mood_v2_repository_test.dart`.
  - Expected: all pass.
- [ ] **Step 3: Check the Functions suite is untouched.**
  - Run: `npm test --prefix functions`. Expected: pass (no functions files changed).
- [ ] **Step 4: Clean the working tree.**
  - Run: `git checkout -- pubspec.lock linux macos windows`, then `git status --short`. Expected: empty.
- [ ] **Step 5: Install on the device** (Infinix `13195704C5003842`) with `--flavor staging` and the six V2 defines.
  - Check that the Home card number matches the Log Mood "Mood streak · N days" line and Journey's "Mood Streak".
  - Check the fire color and flicker, and that the card opens Journey after today's check-in.
- [ ] **Step 6: Note follow-ups for the PR description.** Do not create the PR. Two follow-ups:
  - Server MindAid still reads the raw `dayStreak` (`functions/src/mind_aid.ts:492`).
  - The Journey edits need review from haruki1155.
