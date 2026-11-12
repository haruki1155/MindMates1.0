# Item 38: Day streak that means something (mood check-in streak + milestone recap)

Status: draft for approval. Branch `feat/day-streak-38`, cut from `origin/main` at `0d0b7c9` (2026-11-12). Baseline on that commit: `flutter analyze` clean; `flutter test --dart-define=APP_ENV=staging` 685/685 pass.

## 1. Intent

Panel item 38: "Home > Day streak > Fix counting of streaks."

Today the streak is a usage counter. It goes up whenever the user opens the app, sends a MindAid message, or reacts in Secret Chat. So it tells neither the user nor PACC anything.

The user wants three things:
- The streak counts a real well-being action, not app opens.
- The number is correct.
- There is a small twist that makes keeping the streak worthwhile.

Decisions made with the user:
- **What counts:** one mood check-in per day keeps the streak alive (option A).
- **Twist:** a milestone mood recap at 7, 14 and 30 days, then every 30 days (option 1).
- **Build approach:** fix the existing counter in the app. No Cloud Functions or Firestore rules change, and no deploy (approach A).
- **Look:**
  - The approved Superdesign card states.
  - The fire grows to fill the right side of the card.
  - The fire color shifts per streak day from deep red to royal blue, with a smooth flicker and color transition.
- **Mockups:**
  - Card: https://p.superdesign.dev/draft/4b64b37b-8f0d-46e7-a4f9-0aac5e525e28
  - Recap: https://p.superdesign.dev/draft/0c61ceea-3420-4dc7-99b4-1ed62c0dfd4f

## 2. How it works today (verified on `0d0b7c9`)

- `StreakCalculator.calculate` (`lib/repositories/user_repository.dart:45`) is correct for a single trigger:
  - Same day: no change.
  - Next day: +1.
  - Any gap: reset to 1.
- It is called from two places:
  1. `UserRepository.recordActivity`, for **every** `UserActivityType`.
  2. The legacy daily mood transaction in `MoodRepository.saveDailyMood` (`lib/repositories/mood_repository.dart:104`).
- **Trigger bug:** Home calls `recordActivity(userId, UserActivityType.appOpen)` on every load (`lib/features/home/screens/home_screen.dart:183`). MindAid, quick/full assessments, breathing and Secret Chat (post, comment, interaction) also call it.
- **Display bug:** `dayStreak` is only recalculated on the next activity. A user who stopped 5 days ago still sees the old number on:
  - Home (`home_screen.dart:536-545`)
  - Profile (`profile_screen.dart:352`)
  - The weekly report (`report_repository.dart:384`)
  - MindAid context (`mind_aid_context_repository.dart:118`)
- **Gap from the latest `main` (#12 and #15):** when `ENABLE_MOOD_V2=true`, Log Mood saves via `_saveMoodV2` through the Cloud Function. That path never updates the streak, and `UserProvider.markMoodCheckIn` exists but is never called. The default build has V2 off, so the legacy path (which does update the streak) is live today.
- The Home card already opens Log Mood when tapped.
- Profile's extra "Mood streak" rows only appear behind the V2 profile flag.

## 3. Goals

1. Only a saved mood check-in advances the streak. This holds on both save paths, legacy and V2.
2. Every screen shows the effective streak: if the last check-in was before yesterday, the streak shown is 0.
3. The Home card has four states, per the mockup:
   - 0/broken
   - Active, not checked in today
   - Checked in today
   - Milestone reached
4. The fire is larger, tinted by streak length, and animates smoothly.
5. A Milestone mood recap screen, built from the user's own last 7 check-ins, with a gentle tip and a not-a-diagnosis note.

## 4. Non-goals and anti-goals

**Non-goals:**
- No Cloud Functions, Firestore rules or index changes, and no deploy.
- No new Firestore fields.
- No change to Mood V2 analytics or the V2 Profile rows (colleague-owned, behind flags).
- Not moving the counter to the server; that's a possible future item.

**Anti-goals (a failure even if the code works):**
- Guilt or shaming copy when a streak breaks.
- Any diagnostic wording in the recap.
- The streak advancing without a mood check-in.
- Breaking the analytics trail: other activity types must still write their `user_activities` records.

## 5. Design

### 5.1 Counting

- `UserRepository.recordActivity` keeps writing the `user_activities` record for every type.
- It updates the streak fields (`dayStreak`, `longestStreak`, `lastActivityDateKey`, `activeDateKeys`, `streakUpdatedAt`) **only when `type == UserActivityType.moodCheckIn`**. Other types write `lastActiveAt` only.
- The Home app-open call stays, for analytics. It no longer moves the streak.
- On the V2 save path, after a successful `writer.create(...)`, Log Mood calls `UserProvider.markMoodCheckIn(userId)` without blocking the save. If that call fails, the save still succeeds.
- The legacy `saveDailyMood` transaction is unchanged; it already counts correctly.

### 5.2 Effective streak (shown value)

- Add `StreakCalculator.effectiveStreak({required int storedStreak, required String? lastActivityDateKey, required DateTime now}) -> int`:
  - Returns `storedStreak` when the last key is today or yesterday (local date).
  - Otherwise returns 0.
- Use it for:
  - The Home card
  - Profile "Day Streak"
  - The weekly report `currentStreak`
  - The client MindAid context
- Add `StreakCalculator.checkedInToday(lastActivityDateKey, now) -> bool` for the card state.

### 5.3 Home card

State rules (`days` is the effective streak):

| State | Rule | Copy | Action |
|---|---|---|---|
| Not started / broken | `days == 0` | "Log your mood today to start a streak." | "Log mood" |
| Active, not done today | `days > 0 && !checkedInToday` | "Check in today to keep your streak." | "Log mood" |
| Done today | `checkedInToday && !milestone` | "Done for today. See you tomorrow!" | none |
| Milestone | `checkedInToday && isMilestone(days)` | "Your week in moods is ready" | "View recap ›" |

- `isMilestone(d)`: `d == 7 || d == 14 || d == 30 || (d > 30 && d % 30 == 0)`.
- The week row (M–S dots) keeps using `activeDateKeys`. From now on those keys only come from mood check-ins.
- **Fire:**
  - The existing `fire_icon.png` at about 84 px fills the right column, with a soft radial glow in the same color.
  - The tint is applied with `ShaderMask`/`ColorFiltered`.
- **Fire color:** a hue from day 1 at deep red `#C62828` to day 30+ at royal blue `#4169E1`, interpolated through crimson, magenta (`#A0237A` around day 7), violet (`#7B2FA8` around day 14) and indigo (`#5B3FC4` around day 21). It never passes through green or yellow. At 0 days the fire is unlit: grey `#B8B2A6` at 60% opacity, with no glow and no flicker.
- **Motion:**
  - The flicker is a scale 1 → 1.04 → 0.98 → 1, rising 1 px, with glow opacity between 0.30 and 0.45. It runs on a 2.4 s ease-in-out loop, anchored at the bottom center.
  - Color changes animate over 600 ms.
  - Both turn off when `MediaQuery.disableAnimations` is true.

### 5.4 Milestone mood recap screen

- **Opens from** "View recap". The new route receives the streak length.
- **Data:** the last 7 entries from the legacy `MoodProvider.moods`, which Home already loads (`fetchRecentMoods`, limit 14). No new queries.
- **Pure builder:** `MoodRecap.fromMoods(List<MoodModel>, {required int streakDays}) -> MoodRecap`, in its own file so it can be unit-tested.
- **Most common mood:** the label with the highest count. A tie goes to the most recent of the tied labels. Shown as "Okay · 4 of 7 days".
- **Best day:** the highest `level`, with ties going to the most recent. Shown as the weekday plus the label.
- **Tip, first rule that matches:**
  - Stressed or Angry 2 or more times: suggests 2 minutes of breathing, with a "Try breathing" button that opens the existing breathing screen.
  - Sad 2 or more times: suggests talking to someone, pointing to MindAid or PACC.
  - Tired 2 or more times: a rest and sleep tip.
  - Otherwise: "Keep doing what's working."
- **Always shown:** the note "This recap reflects your own check-ins. It is not a diagnosis. If you'd like to talk to someone, PACC is here for you.", "Book a PACC appointment" (the existing booking route), and "Keep my streak going" (back to Home).
- **Layout:** as in the approved recap mockup. Section titles are 16/w800, values 20/w900, body 13/w600 and captions 12.

### 5.5 Copy fixes

- Log Mood's result: "`N`-day activity streak" becomes "`N`-day mood streak" (`log_mood_screen.dart:1072`).
- Profile's "Day Streak" label stays the same and uses the effective value.

## 6. Constraints

- Must merge cleanly with open PR #16 (`feature/mindmate-integration-20261112`). It touches `firestore.rules` and `functions/src/mind_aid.ts`; this design touches neither.
- Stale PR #3 touches the Home files, but it is 190 commits behind `main` and is ignored.
- CI runs analyze, `flutter test --dart-define=APP_ENV=staging`, the staging APK build and Functions tests. All must stay green.
- Never commit regenerated `pubspec.lock`, `linux`, `macos` or `windows` files.

## 7. Calls made by me (check these)

1. **Existing inflated numbers are not reset.** That would need a new field, a rules change and a deploy. Because app opens stop counting, an inflated streak drops to 0 within 2 days unless the user really checks in daily.
2. The server-side MindAid (`functions/src/mind_aid.ts:492`) still reads the raw stored `dayStreak`. Fixing it is a Functions change, so it's out of scope; I'll note it in the PR.
3. The recap only uses legacy mood entries. If V2 reading is turned on later, the builder accepts the same fields (`level`, `label`, `createdAt`), so V2 can feed it with a small adapter.
4. Milestones repeat every 30 days after day 30.
5. The recap appears only on the milestone day, after that day's check-in. It is not stored or re-openable later, which keeps the scope small.

## 8. Files

- `lib/repositories/user_repository.dart`: streak update limited to `moodCheckIn`; `effectiveStreak`; `checkedInToday`.
- `lib/features/home/screens/home_screen.dart`: card data from the effective streak and state; "View recap" route.
- `lib/features/home/models/home_dashboard_data.dart`: `HomeStreakData` gains a state and a milestone flag.
- `lib/features/home/widgets/home_dashboard_widgets.dart`: `HomeStreakCard` states and layout.
- New `lib/features/home/widgets/streak_flame.dart`: tinted, animated fire and the color function.
- New `lib/features/mood/domain/mood_recap.dart`: the pure recap builder.
- New `lib/features/mood/screens/mood_recap_screen.dart`, plus a route registration.
- `lib/features/mood/screens/log_mood_screen.dart`: V2 path calls `markMoodCheckIn`; copy fix.
- `lib/features/profile/screens/profile_screen.dart`, `lib/repositories/report_repository.dart`, `lib/repositories/mind_aid_context_repository.dart`: use the effective streak.
- Tests:
  - `test/providers/user_provider_test.dart` and `test/repositories/...`: counting by type.
  - New `test/features/mood/mood_recap_test.dart`.
  - New `test/features/home/streak_card_test.dart`: states, flame color stops, reduced motion.
  - Update `test/features/profile/profile_screen_test.dart` and `test/features/home/home_screen_test.dart` where they pin the old behavior.
