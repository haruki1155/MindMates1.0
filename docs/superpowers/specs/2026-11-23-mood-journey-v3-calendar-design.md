# My Mood Journey V3 — Calendar and Insights Design

**Status:** Product direction approved 2026-11-23; implementation pending.<br>
**Repository checked:** `haruki1155/MindMates1.0`, `main` at `fc028e009762c1d1f54c46449785e89d15114f6f` (recheck before execution).<br>
**Owner-facing goal:** Make each student's existing MindMate mood history easier to understand week by week, month by month, and by academic period, with a Flo-inspired calendar interaction but MindMate visual identity.

## 1. Scope and guardrails

**In:** month calendar, marked mood-active days, date selection, selected-day history and private notes, weekly mood distribution / most logged mood, brief monthly summary, existing streak and helpful recap, selected academic-year and semester filters based on existing configured dates.

**Out:** mood logging changes, symptom or cycle tracking, predictions, diagnosis, counselor dashboards, student comparisons, ML, new Firestore mood schema, rewriting `MoodProvider` or the admin academic-year management interface, broad refactors, notifications.

**Non-negotiable:** Mood V2's multiple same-day check-ins, legacy compatibility, account separation, UTC+8 calendar boundaries, feature flags, note authorization, and existing Home / Log Mood navigation remain intact. This screen is owner-only. Never treat missing data as a negative mood or a day with a mood. Never make a medical inference.

## 2. Source-of-truth audit

Already present in main:
- `lib/features/mood/screens/mood_journey_screen.dart`: `MoodJourneyScreen`, authenticated owner gate, screen lifecycle, `MoodJourneySummary`, `MoodV2HistoryPanel`, `MoodWeekRecapCards`.
- `lib/features/mood/widgets/mood_journey_summary.dart`: streak, check-in totals, most logged mood, 7-day strip and This Week/This Month segmented button.
- `lib/features/mood/widgets/mood_v2_history_panel.dart`: owner-only expandable day cards, notes, pagination, loading/error and privacy behavior.
- `lib/features/mood/domain/mood_v2_analytics.dart`: `MoodManilaCalendar`, `MoodHistoryWindow.uniqueEvents`, event IDs/labels, `MoodWeekRange`.
- `lib/features/mood/domain/mood_journey_period.dart`: present week/month helpers; adjust for arbitrary selected dates while preserving any external callers.
- `lib/features/mood/domain/mood_week_recap.dart` and `mood_week_recap_cards.dart`: gentle tip and recap logic; reuse.
- `lib/repositories/mood_combined_history_repository.dart`: `MoodCombinedHistoryRequest.forManilaDateRange` and `MoodCombinedHistoryPage` with source-aware cursor pagination.
- `lib/providers/mood_provider.dart`: owner-bound V2 read, recent paginated history, note loading, stale-request invalidation, feature gating. Existing initial history request is a **page** (100 per source), not necessarily all history.
- `lib/features/home/widgets/home_dashboard_widgets.dart`: `HomePalette`, `HomeMetrics`, `HomeDecor`, `HomeMotion`.
- `lib/features/mood/widgets/mood_glyph.dart`: established mood glyphs.
- `functions/src/counseling_population.ts`: `getAcademicYears` is **admin-only**; does not provide a student-facing academic calendar. `counseling_population/{schoolYear}` has school year, start/end dates, lifecycle status and populations.
- `lib/features/admin/screens/report_generation_page.dart`: current report convention for 1st/2nd semester is a six-month split from configured academic-year start (fallback June/December); **not separately confirmed academic term dates**.
- `lib/services/firebase/firebase_callable_router.dart`: environment routing for certain App Check-protected callable aliases.

## 3. UI design — actual intended layout

**Screen hierarchy, vertical scroll:**

```
┌──────────────────────────────────────────┐
│ ‹  My Mood Journey                       │  AppBar, existing navigation
│ Notice patterns in your check-ins.       │
│                                          │
│ Academic year: 2026–2027        [change] │  Optional compact filter row
│ Semester: All year              [change] │  No giant filtering form
│                                          │
│ ┌──────────────────────────────────────┐ │
│ │ ‹        November 2026        › Today│ │
│ │ Mon Tue Wed Thu Fri Sat Sun          │ │
│ │                  1                   │ │
│ │  2   3   4   5   6   7   8           │ │
│ │  9  10  11  12  13  14  15           │ │  Calendar markers show latest mood
│ │ 16  17 [18] 19  20  21  22           │ │  + count of other check-ins on day
│ │ 23  24  25  26  27  28  29           │ │
│ │ 30                                   │ │
│ │ [Selected day] [Today] [Logged mood]│ │
│ └──────────────────────────────────────┘ │
│                                          │
│ Nov 18 · Your check-ins                  │
│ [Stressed at 10:00] [Calm at 16:00]      │  Reuse private day details / notes
│                                          │
│ Week of Nov 16–22                        │
│ 6 check-ins · 4 mood-active days         │
│ Most logged: Stressed (3 of 6)           │
│ [Stressed ███] [Calm ██] [Okay █]       │  Text labels + proportions
│ [Existing gentle recap / tip]           │
│                                          │
│ November at a glance                     │
│ [Top logged moods] [Active days]         │
│                                          │
│ [Mood streak] [Mental health support]   │  Existing actions preserved
└──────────────────────────────────────────┘
```

This is a hierarchy specification, **not a literal new visual theme**. Follow current UI structure and text styles. Flo is used only as an interaction reference (month browsing + selected day), not for color, branding, screenshots, or predictions.

**Visual tokens:** Use `HomePalette.background` (`#F7F1DF`), `HomePalette.surface` (`#FFFEFA`), `HomePalette.sun` (`#FFC414`), `HomePalette.text` (`#17120A`), `HomePalette.muted`, `HomeDecor.card` and existing mood glyph colors. White/warm cards, 16 px standard padding, 12–16 px vertical rhythm, 16–20 px radii, touch-first layout. Don't add decorative gradients, photo assets, extra libraries, or arbitrary new mood colors. Existing `MoodGlyph` identity is authoritative; a selected day has a visible gold/yellow outline, today has a distinct text/outline indicator; logged state should not rely on color alone.

**Calendar:** custom Flutter-native 7-column grid, Monday-first (matching `MoodManilaCalendar.weekContaining`), 4–6 rows according to month, no nested scroll. Header month/year, previous/next arrows, Today shortcut; proper previous/next disabled/grey when outside available permitted periods if restricted. Show day number and latest recorded glyph/marker; on multiple entries show compact `+N` badge, with accessible description including precise count. Tapping any non-future date selects it and updates day detail and weekly insight; do not allow backdated mood logging merely by tapping. Calendar selection persists when scrolling, and switching month picks a valid date in the new month (today for current month, otherwise first day), not a stale off-screen day. Tapping trailing adjacent-month dates may navigate to that month. Do not use color as the only signal.

**Accessibility and responsive rules:** test on logical device widths 320, 360, 390 and 430 with text scaling 1.0 and 1.8; avoid overflow, maintain as large a touch area as the seven-column layout permits (40+ logical px at 320), support semantic date labels (`Wednesday, Nov 18, 2 check-ins, selected`), distinct selected/today markers, reasonable color contrast, reduced-motion support via `HomeMotion`. Use `Key` values for stable widget tests and screenshots. Prefer plain `GridView` or `Table` and current `Theme` widgets over a third-party calendar library; `CalendarDatePicker` does not easily support this per-day glyph/count treatment.

**Empty/loading/errors:** initial shimmer not required; spinner or lightweight skeleton is enough. Unknown/not-yet-loaded days must not be displayed as definitely empty; disable or indicate loading until the visible date-range query completes. Partial pagination shows `Based on loaded entries` and a Retry/Load more action; don't show an unqualified dominant mood. A loaded empty day displays `No mood check-ins on this date.`; no entries in week/month has its own friendly copy. On a failed month query preserve the last valid result only if clearly identified as belonging to its original month, never misrepresent it as the requested month.

## 4. Summary semantics

Calendar uses **the recorded check-ins**. Count deduplicated `MoodHistoryWindow.uniqueEvents` by event `stableIdentity`; group by `dateKey` and normalized nonempty label; leave unknown labels as `Unlabeled` only if necessary for complete totals, without inventing a mood.

**Selected week:** Monday 00:00 to next Monday 00:00 (Manila date keys), including weeks that cross calendar months and academic term boundaries. When an academic year/semester filter is active, compute the intersection with that academic range. Display check-in count, distinct mood-active days, most logged mood(s) with count and percentage of all labeled check-ins (if labels incomplete, clarify the denominator), 2–4 compact labeled distribution bars. Ties must name all tied top moods; if all missing, show no dominant mood. Existing `MoodWeekRecap` uses only the same selected, complete period; do not claim the best day if not enough data.

**Displayed month:** summary by current displayed month, independently from the selected week's aggregation and clipped to academic filter. Display top recorded mood(s), active days and check-ins. No elaborate line chart or diagnostic inference.

**Streak:** preserve current `MoodAnalytics.streak` meaning and date reference; do not recalculate it from the selected historical month or calendar-only window. Keep the existing no-diagnosis support note and mental-health action.

## 5. Data flow and security

**Calendar reads:** use `MoodCombinedHistoryRequest.forManilaDateRange(userId, startDateKey, endExclusiveDateKey)` for the visible Monday-through-Sunday calendar grid (includes dates adjacent to first and last day of month). Fetch remaining cursor pages within this bounded range; preserve incomplete/failure flags and expose an explicit retry when needed. Keep calendar history state separate from `v2History` (which is used for streaks and other consumers). Avoid a second mood Firestore collection, duplicate log writers or all-time client scans. No optional cache until performance evidence requires one.

**Day notes:** currently owner note loading looks up entries in recent `v2History`. Extend it narrowly to permit day events from the owner-matched calendar range too; the repository's `_requireCurrentUser` and note ownership checks remain mandatory. Fetch notes only when the student explicitly expands/selects a day (lazy), not for every calendar cell. Clear private notes and cancel/discard stale fetch responses on account switch.

**Academic-year and semester filter:** students cannot call existing admin-only `getAcademicYears`. The minimal backend extension is one authenticated read-only callable (working name: `getStudentAcademicCalendar`) exposing only non-sensitive academic IDs, start/end date keys, status, optional/derived semester groupings and the provenance of those semester dates. No population counts, reports, role changes, roster data, or write permissions. Reuse existing year config and authorization conventions. For default UI, use the relevant currently configured year; historical configured years may be selected. If configured term ranges do not exist, use the existing report's six-month **calendar grouping** only if clearly labeled as an estimated/report grouping, not official term dates; alternatively offer only `Whole academic year` until official term metadata exists. The implementation must not silently invent official semester dates. A malformed/missing year must fail closed (hide period option; preserve unfiltered mood history).

**Function security:** check authenticated active account and role following existing `functions/src/access.ts` conventions; enforce App Check in production where the project requires it and match existing alias routing for staging/development. Test unauthenticated and unauthorized users, verify output has no populations or private student data; never broaden `getAcademicYears` authorization. No deployment without separate approval.

## 6. Delivery & verification

Single feature branch / isolated worktree, with small test-first commits:
1. Pure selected-date/week/month math and summary model.
2. Owner-bounded calendar history read and notes integration.
3. Flutter-native calendar component and selected-day panel.
4. Weekly/monthly recap arrangement and existing UX preservation.
5. Minimal student academic-calendar metadata if not available via safe existing read.
6. Widget/visual, callable emulator, full Flutter + Functions, regression tests, review.

**Acceptance:** 320/390/430px screens, >=1.8 text scaling, no rendering overflows; Manila Monday, Sunday, midnight, leap-year and cross-month weeks; multiple entries/day, identical-source dedupe and ties; previous-month pages (>100 entries); failed/partial query labels; account switch with in-flight data/notes; old paths and feature flags; accurate year/term clipping; auth and App Check routing. Record exact commands and counts. No push, merge, staging or production deploy unless separately authorized.

## 7. Approaches considered

1. Full new analytics schema/dashboard — rejected as unnecessary risk/duplication.
2. UI-only grid over recent loaded pages — rejected because past months and selected weeks could be incomplete and misleading.
3. **Chosen:** native Flutter month grid plus bounded reads and existing analytics, with one narrow academic metadata read if necessary. This is the smallest correct implementation.
