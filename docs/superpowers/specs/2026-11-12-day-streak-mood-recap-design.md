# Item 38: Day streak that means something (aligned to Mood V2)

Status: draft for approval. Revision 2 aligns the design to the Mood V2 build.

- Branch `feat/day-streak-38`, cut from `origin/main` at `0d0b7c9` (2026-11-12).
- Baseline on that commit: `flutter analyze` is clean, and `flutter test --dart-define=APP_ENV=staging` passes 685/685.

## 1. Intent

Panel item 38: "Home > Day streak > Fix counting of streaks." The user wants:
- The streak counts a real well-being action, not opening the app.
- The number is correct.
- A small twist makes the streak worth keeping.

### Decisions made with the user

- **What counts:** one mood check-in per day keeps the streak alive.
- **Twist:** a milestone recap at 7, 14 and 30 days, then every 30 days.
- **Mood V2 stays on.** It is a built feature, and item 38 must align to it and add only what the task needs.
- **"View recap" opens the existing My Mood Journey screen** (`MoodJourneyScreen`) instead of a new recap screen.
- **Look:**
  - The approved Superdesign card states.
  - A larger fire that fills the right side.
  - The fire color shifts per streak day from deep red to royal blue, with a smooth flicker and color transition.

### Mockups

- Card: https://p.superdesign.dev/draft/4b64b37b-8f0d-46e7-a4f9-0aac5e525e28
- Journey revision: added to the same Superdesign project (link in the hand-off message).

### Build used for development and on-device checks

```
--flavor staging --dart-define=APP_ENV=staging
--dart-define=ENABLE_MOOD_V2_PROVIDER_READ=true --dart-define=ENABLE_MOOD_V2_HOME_READ=true
--dart-define=ENABLE_MOOD_V2_PROFILE_READ=true  --dart-define=ENABLE_MOOD_V2_HISTORY_READ=true
--dart-define=ENABLE_MOOD_V2_INSIGHTS_READ=true
```

- These switches only control how the app reads mood data.
- The V2 *writer* (`ENABLE_MOOD_V2`) only saves for server-allowlisted pilot accounts (`MOOD_V2_STAGING_PILOT_UIDS`). Item 38 does not change that, so it must work with either writer.
- Verified on the Infinix X6880 on 2026-11-12: the app starts cleanly with these switches, and My Mood Journey loads.

## 2. How it works today (verified on `0d0b7c9`)

### Two different streaks exist

1. **`users.dayStreak`, the stored counter.**
   - It is updated by `StreakCalculator.calculate` (`lib/repositories/user_repository.dart:45`) on **every** `UserActivityType`, called through `UserRepository.recordActivity`.
   - Home records an `appOpen` every time it loads (`home_screen.dart:183`), and MindAid, assessments, breathing and Secret Chat record activities too.
   - So the counter measures app usage.
   - It is only recalculated on the next activity, so after missed days it keeps showing an old number.
   - It is read by:
     - the Home card (`home_screen.dart:536-545`)
     - Profile "Day Streak" (`profile_screen.dart:352`)
     - weekly reports (`report_repository.dart:384`)
     - client MindAid context (`mind_aid_context_repository.dart:118`)
     - server MindAid (`functions/src/mind_aid.ts:492`)
2. **The Mood V2 "Mood Streak", which is derived.**
   - `MoodAnalytics.streak` (`lib/features/mood/domain/mood_v2_analytics.dart:298`) works over the combined legacy + V2 mood history.
   - It counts consecutive Manila days that have at least one check-in, and it already drops to 0 when the latest check-in is older than yesterday.
   - It is shown on My Mood Journey (`mood_journey_summary.dart`, "Mood Streak" card) and in the V2 Profile rows.

**The bug in the V2 build:** Home's "Day streak" (usage, stale) and Journey's "Mood Streak" (mood-only, correct) show **different numbers** to the same user.

### Saving moods

- The legacy writer (`MoodRepository.saveDailyMood`) updates the stored counter.
- The V2 writer (`_saveMoodV2` → `createMoodEntry` callable) does not, and `UserProvider.markMoodCheckIn` is never called.

### My Mood Journey today

Journey is gated by `MoodProvider.isMoodV2ReadEnabled`. It contains:
- The Mood Streak card (an orange icon and the number).
- A 7-day strip.
- A This Week / This Month toggle.
- A tile with the count of check-ins and mood-active days.
- A "Most logged mood" tile (shows "tied" when tied).
- The date range.
- `MoodV2HistoryPanel`, with per-day details and notes.
- The "Mindful Essentials" and "Mental Health Support" (inSIGHT) cards.

## 3. Goals

1. **One streak definition everywhere: the Mood V2 Mood Streak.** Home, Journey and Profile show the same number, from `MoodAnalytics.streak` over the loaded combined history.
2. **The stored counter becomes mood-only.** It advances only on a mood check-in, on either writer, and its displayed value drops to 0 after a missed day. This keeps reports and MindAid consistent.
3. **Home card states from the approved mockup:**
   - 0/broken
   - active, not checked in today
   - checked in today
   - milestone
4. **The fire** is larger, colored by streak length, and animates smoothly. The same fire appears on Journey's Mood Streak card.
5. **The milestone recap lives on My Mood Journey.** "View recap" opens Journey with a milestone banner and adds three things Journey lacks:
   - the best day
   - a gentle tip
   - the not-a-diagnosis support note

## 4. Non-goals and anti-goals

**Non-goals:**
- No change to Mood V2 flags, defaults, writer, pilot allowlist, Cloud Functions, Firestore rules or indexes.
- No deploy.
- No new Firestore fields.
- No new recap screen.
- No change to `MoodV2HistoryPanel`, `MoodAnalytics.streak` rules, or the This Week / This Month logic.

**Anti-goals:**
- Guilt or shaming copy.
- Diagnostic wording.
- A streak that moves without a mood check-in.
- Removing the analytics trail: other activity types still write `user_activities`.
- Redesigning the colleague's Journey layout beyond the additions listed in §5.4.

## 5. Design

### 5.1 Streak source (single definition)

Add `HomeStreakSource.resolve(...)` (a small pure function, own file) that returns `{int days, bool checkedInToday, List<String> weekDateKeys}`:

**When `MoodProvider.isMoodV2ReadEnabled` and the V2 history for the signed-in user is loaded:**
- `days = MoodAnalytics.streak(history, referenceInstant: now).currentDays`
- `checkedInToday` is true when the history contains today's Manila date key.
- `weekDateKeys` is the set of Manila date keys in the history.

**Otherwise** (readers off, or history still loading):
- `days = StreakCalculator.effectiveStreak(stored dayStreak, lastActivityDateKey, now)`
- `checkedInToday = lastActivityDateKey == today`
- `weekDateKeys = activeDateKeys`

**Used by:**
- the Home card and Home week row
- Profile "Day Streak"

Journey keeps its own existing calculation, which is the same V2 definition.

### 5.2 Stored counter (consumers that cannot read V2 history)

- **`UserRepository.recordActivity`:**
  - Always writes the `user_activities` record.
  - Updates `dayStreak`, `longestStreak`, `lastActivityDateKey`, `activeDateKeys` and `streakUpdatedAt` **only when `type == UserActivityType.moodCheckIn`**.
  - For other types, it writes `lastActiveAt` only.
  - The Home `appOpen` call stays, for analytics only.
- **V2 save path:** after `writer.create(...)` succeeds, Log Mood calls `UserProvider.markMoodCheckIn(userId)` without blocking. A failure is ignored.
- **The legacy writer is unchanged.**
- **New `StreakCalculator.effectiveStreak({storedStreak, lastActivityDateKey, now}) -> int`:** returns the stored value when the last key is today or yesterday, otherwise 0. Used by:
  - the §5.1 fallback
  - `report_repository.dart` `currentStreak`
  - `mind_aid_context_repository.dart`

### 5.3 Home card

| State | Rule | Copy | Action |
|---|---|---|---|
| Not started / broken | `days == 0` | "Log your mood today to start a streak." | "Log mood" → Log Mood |
| Active, not done today | `days > 0 && !checkedInToday` | "Check in today to keep your streak." | "Log mood" |
| Done today | `checkedInToday && !isMilestone(days)` | "Done for today. See you tomorrow!" | Card tap → My Mood Journey |
| Milestone | `checkedInToday && isMilestone(days)` | "Your week in moods is ready" | "View recap ›" → `MoodJourneyScreen(milestoneDays: days)` |

- **Milestone rule:** `isMilestone(d)` is `d == 7 || d == 14 || d == 30 || (d > 30 && d % 30 == 0)`.
- **When Journey is unavailable** (`isMoodV2ReadEnabled` false), the Done and Milestone states route to Log Mood. "View recap" is hidden and replaced by "Milestone reached: {d} days!".
- **Fire** (new `lib/features/home/widgets/streak_flame.dart`, `StreakFlame({required int days, double size})`):
  - The existing `fire_icon.png` is tinted with `ShaderMask`, about 84 px on Home, with a soft radial glow.
  - **Color:**
    - The color stops are
      - day 1 `#C62828`
      - day 7 `#A0237A`
      - day 14 `#7B2FA8`
      - day 21 `#5B3FC4`
      - day 30+ `#4169E1`
    - Between stops the color is linearly interpolated.
    - At 0 days the fire is unlit: `#B8B2A6` at 60% opacity, with no glow and no flicker.
    - Expose `Color streakFlameColor(int days)` for tests.
  - **Motion:**
    - Flicker: scale 1 → 1.04 → 0.98 → 1, rising 1 px, glow 0.30 ↔ 0.45, on a 2.4 s ease-in-out loop anchored at the bottom center.
    - Color changes go through `TweenAnimationBuilder<Color?>` over 600 ms.
    - Both are off when `MediaQuery.disableAnimations` is true.

### 5.4 My Mood Journey additions (V2 screen, minimal edits)

- **`MoodJourneyScreen({..., int? milestoneDays})`:** when it is set, the screen opens on This Week.
- **`MoodJourneySummary` gains `int? milestoneDays`** and three additions. Everything else stays as built.

**1. Milestone banner** (only when `milestoneDays != null`), above the Mood Streak card:
- Gold gradient, like the Home card.
- Text: "🔥 {d}-day streak · Here's your week in moods".

**2. Mood Streak card:**
- `StreakFlame(days: streak.currentDays, size: 44)` replaces the static orange `Icons.local_fire_department_rounded`.
- The card's text and key (`mood-streak-card`) are unchanged.

**3. Below the existing two tiles, This Week only:**
- **"Best day":** the day in the week with the highest single check-in `level`. Ties go to the most recent. Shown as the weekday plus the label, with the line "Notice what made it a good day." Hidden when the week has no check-ins.
- **"A gentle tip"**, first matching rule:
  - Stressed or Angry 2 or more times: suggests 2 minutes of breathing, with a "Try breathing" button that opens the existing breathing screen.
  - Sad 2 or more times: suggests talking to someone, with an "Open MindAid" button.
  - Tired 2 or more times: a rest and sleep tip.
  - Otherwise: "Keep doing what's working."
- **Support note** (always shown with the tip): "This reflects your own check-ins. It is not a diagnosis. If you'd like to talk to someone, PACC is here for you." with a "Book a PACC appointment" button (existing booking route).

**Logic location:** a pure function in the new `lib/features/mood/domain/mood_week_recap.dart`, `MoodWeekRecap.from(List<NormalizedMoodEvent> weekEvents)`, which returns the best day and the tip kind. It is unit-tested. Labels are matched case-insensitively.

### 5.5 Copy fixes

- The Log Mood legacy result text "`N`-day activity streak" becomes "`N`-day mood streak" (`log_mood_screen.dart:1072`).
- The Home card title stays "Day streak". Profile "Day Streak" stays, using the §5.1 value.

## 6. Constraints

- Must merge cleanly with open PR #16 (`feature/mindmate-integration-20261112`, which touches `firestore.rules` and `functions/src/mind_aid.ts`). This design touches neither.
- `mood_journey_screen.dart` and `mood_journey_summary.dart` belong to haruki1155's Mood V2 work. Keep the edits additive and call them out in the PR for their review.
- CI must stay green:
  - `flutter analyze`
  - `flutter test --dart-define=APP_ENV=staging`
  - the staging APK build
  - Functions tests
- Widget tests must cover both reader-on (V2 history injected) and reader-off paths.
- Never commit regenerated `pubspec.lock`, `linux`, `macos` or `windows` files.
- Date keys:
  - V2 uses the Manila calendar.
  - The stored counter uses device-local dates. They are identical for users in the Philippines.
  - The fallback is only used when V2 reading is off.

## 7. Calls made by me (please check)

1. Existing inflated stored numbers are not reset, because that would need a new field, a rules change and a deploy. With V2 reading on, Home no longer shows the stored number anyway.
2. Server MindAid (`functions/src/mind_aid.ts:492`) still reads the raw stored `dayStreak`. This is out of scope because it is a Functions change; it will be noted in the PR as a follow-up.
3. Milestones repeat every 30 days after day 30. The recap banner only appears when Journey is opened from "View recap". The Best day, tip and support note always show on This Week.
4. Journey's existing "Most logged mood" tile and tie wording are kept as built; no duplicate "most common mood" is added.

## 8. Files

**Modified:**
- `lib/repositories/user_repository.dart`: mood-only streak update, `effectiveStreak`.
- New `lib/features/home/domain/home_streak_source.dart`: §5.1.
- `lib/features/home/screens/home_screen.dart`, `lib/features/home/models/home_dashboard_data.dart`, `lib/features/home/widgets/home_dashboard_widgets.dart`: card states, routing.
- New `lib/features/home/widgets/streak_flame.dart`.
- `lib/features/mood/screens/mood_journey_screen.dart`, `lib/features/mood/widgets/mood_journey_summary.dart`: §5.4 additions.
- New `lib/features/mood/domain/mood_week_recap.dart`.
- `lib/features/mood/screens/log_mood_screen.dart`: V2 save → `markMoodCheckIn`; copy fix.
- `lib/features/profile/screens/profile_screen.dart`, `lib/repositories/report_repository.dart`, `lib/repositories/mind_aid_context_repository.dart`: effective or V2 streak.

**Tests:**
- Counting by activity type (`test/providers/user_provider_test.dart`, `test/repositories/...`).
- New `test/features/home/home_streak_source_test.dart`.
- New `test/features/home/streak_card_test.dart`: states, flame colors, reduced motion.
- New `test/features/mood/mood_week_recap_test.dart`.
- Updates to `test/features/mood/mood_journey_test.dart`, `test/features/profile/profile_screen_test.dart` and `test/features/home/home_screen_test.dart` where they pin the old behavior.
