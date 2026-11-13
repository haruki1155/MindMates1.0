# Items 40–41: Home dashboard polish (short design)

Status: approved by the user on 2026-11-12. Branch `feat/home-polish-40-41`, cut from `feat/day-streak-38` (PR #17, not merged yet). Mockup: https://p.superdesign.dev/draft/6543bf7f-c3b5-42d6-bcac-dbd74fe2545d

## Intent

These are panel items. The aim is a cleaner Home with no duplicate mood buttons:

- **40:** Remove the "View today's mood" button and add the button below the greeting instead.
- **Extra (user):** Remove the separate "Log a mood" button, because it is already in the Day streak card, and recolor the streak card's button to match its gold background.
- **41:** Remove the "X" on the "Start Assessment" card.

## Today (on `feat/day-streak-38`)

- `home_screen.dart:360-372` contains a full-width yellow `HomeWideButton` under the Announcement section.
  - Its label comes from `MoodV2FeatureFlag.actionLabel`: "Log a mood" (V2 on), "View today's mood" (V2 off, already checked in) or "Log your mood".
  - It always opens Log Mood.
- `HomeWelcomeCard` (`home_dashboard_widgets.dart:348`) shows "Welcome, {name}!", then "How are you feeling today?", then a "Today's mood: X" chip when a mood exists today.
- `HomeAssessmentBanner` (`home_dashboard_widgets.dart:275`) has a close button (`HomePlainIconButton`, `x.png`, tooltip 'Dismiss').
  - The button sets `_isAssessmentBannerDismissed` (`home_screen.dart:132, 402, 702`).
- The streak card's "Log mood" pill is teal `#2F7D6D` with white text (`home_dashboard_widgets.dart`, `HomeStreakCard`).

## Approaches

- **A (chosen):** the button under the greeting is **"View today's mood"**.
  - It is shown only after today's check-in and opens My Mood Journey.
  - It falls back to Log Mood when Journey is unavailable, that is when Mood V2 reading is off.
  - The streak card stays the only place to log.
- **B:** "Log a mood" under the greeting. This was rejected because it repeats the streak card's button, which is the duplication being removed.
- **C:** something else. Not chosen.

## Design

1. **Remove the wide mood button.** Delete the `HomeWideButton` block (and its `SizedBox` gap) from Home. The `HomeWideButton` class stays in the widgets file, untouched.
2. **Add "View today's mood" to the welcome card.**
   - `HomeWelcomeCard` gains `VoidCallback? onViewTodaysMood`.
   - When `todayMoodLabel` is non-empty and the callback is set, a full-width outlined pill button appears **"View today’s mood"** below the "Today's mood" chip:
     - white `HomePalette.surface` background
     - 1 px `HomePalette.sun` border
     - text 13/w800 `HomePalette.text`
     - trailing chevron
     - height 44
     - key `Key('home-view-todays-mood')`
   - It is hidden when there is no mood today.
   - Home passes a callback that opens `MoodJourneyScreen()` when `MoodV2FeatureFlag.historyRead && moodProvider.isMoodV2ReadEnabled`, and otherwise `_openLogMood`. This is the same `canViewRecap` condition as item 38.
3. **Recolor the streak button.** The streak card's "Log mood" pill uses `HomePalette.surface` with `HomePalette.text`, the same as "View recap ›". No teal remains in the card.
4. **Remove the assessment card's X.**
   - Remove `onClose` and the close button from `HomeAssessmentBanner`.
   - In Home, remove `_isAssessmentBannerDismissed`, `_dismissAssessmentBanner` and the condition.
   - The card's other rules and contents stay the same.

## Non-goals

- No change to the greeting text, streak logic, Announcement, appointments, services or other sections.
- No Mood V2, backend or rules changes.

## Constraints

- PR #17 must merge first. This branch's PR targets `main` after that.
- Tests run with `--dart-define=APP_ENV=staging`, plus the six Mood V2 defines for the V2 runs.
- Never commit regenerated `pubspec.lock`, `linux`, `macos` or `windows` files, and only format the files this change touches.

## Tests

- **Home "Log your mood" test** (`home_screen_test.dart:365`): change it to tap the streak card's "Log mood" pill, and assert there is no `HomeWideButton`.
- **Banner-dismiss test** (`:440`): replace it with "the assessment card has no Dismiss button" and assert the card is still shown.
- **Dashboard-asset test** (`:568`): drop `x.png` and `+.png` from the expected assets. Those images belonged to the removed X and the removed wide button.
- **New Home tests:**
  - "View today's mood" is absent before a check-in.
  - After a check-in (fake mood repository returns today's mood), it is present below the greeting and opens Log Mood when V2 reading is off.
- **Streak card test:** the "Log mood" pill uses the surface color, not teal.
