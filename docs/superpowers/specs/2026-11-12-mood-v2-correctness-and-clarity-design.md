# Mood V2 correctness and clarity

Status: proposed design distilled from the user's manual testing and follow-up requests; implementation awaits review.

## Intent
Make student Mood V2 trustworthy and easier to understand: show the latest saved mood, reveal saved notes, make period filters visibly affect the journey, and reduce the visual pile-up of entries.

## Required behavior
- Today's mood uses the latest confirmed entry for the current Manila day, including after returning Home or reopening the app. A failed save never becomes today's mood.
- Owner-only check-in details show the saved note verbatim. Truly empty notes show `No note added.` Existing records are preserved.
- `This week` means Monday through today in Manila; `This month` means the first of the month through today. Selection filters both summary statistics and check-ins. Show an obvious selected state and the date range. Never represent partial history as complete.
- Check-ins start collapsed into one row per Manila date, newest first. Proposed compact heading: weekday only, for example `Thursday`, with a chevron and check-in count. Opening a day reveals the complete localized date as secondary information and its entries, newest first. Each entry retains its time, mood, and expandable note. Duplicate weekday names across weeks are allowed; the expanded full date disambiguates them. Screen-reader labels always include the full date.
- Selecting a mood offers an optional reflection prompt: `Why do you feel this way?` / `You can share a little insight in the note below. It's optional.` Actions: `Skip` and `Add note`. Skip keeps the selected mood and existing draft; Add note focuses the existing note field. Proposed frequency: once per unsaved entry, not every change of selection; reset after a confirmed save or account change. Dismissing the prompt acts like Skip. Never save automatically or require a note.
- Journey navigation and Mood Streak use white surfaces with soft static yellow edge glow, dark text, and clear icons. Journey navigation has `My Mood Journey`, supporting copy and a chevron; expose button semantics and tap feedback. Streak emphasizes its label and day count without implying rewards or medical benefit.
- Check Expression is a prominent yellow action with dark text and a recognizable camera icon. No green CTA, green selected period, or green streak/navigation text.
- Check-ins use mood-specific glyphs and restrained accent colors, not uniform green dots; color is supplementary to labels. Use the existing mood palette and glyph mapping where available.
- Use existing `HomePalette.sun` (#FFC414), white surfaces and dark ink. Maintain consistent 16px outer spacing, flexible content and comfortable tap targets. Verify 320/390px portrait, phone landscape, keyboard, and 1.8x text scaling without overflow.

## Architecture and approaches
Recommended approach for this proposed plan: repair the existing provider/history path, use one shared period selection at Journey screen level, and read private notes only on explicit day expansion. Keep aggregated analytics free of notes.

Alternatives considered: projecting notes into every shared history consumer is shorter but weakens the existing privacy boundary; replacing the Mood data/UI stack creates unnecessary scope and regression risk. Neither is proposed. These are engineering recommendations, not previously selected user preferences.

## Constraints and non-goals
No new dependencies, framework, schema migration, deletion, production change, or backend authorization bypass. Preserve feature-flag defaults, the protected callable, App Check, server eligibility, request UUID/idempotency, midnight retry, account isolation, and existing legacy behavior when V2 is disabled. Keep Mood streak distinct from activity streak. Do not log notes or credentials. Preserve unrelated `pubspec.lock` changes.

## Delivery and acceptance
Implement with focused failing regression tests first, then enabled V2 and default-disabled regressions, analysis, and layout checks. After a separately confirmed build/install step, hand the enabled staging APK to the user for manual student testing; do not claim hosted Save Mood success from mocks. Do not disable or roll back the working staging flags after tests. No deployment is included.

## Builder decisions proposed for review
Weekday-only collapsed headings; once-per-entry reflection prompt; `Add note` plus `Skip`; period selection leaves the all-time streak unchanged and filters only period summaries/check-ins; partial history retains explicit coverage messaging and Load more.
