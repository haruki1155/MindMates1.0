# MindMate Mood V2 — Approved Student UI Visual-Parity Design

**Status:** Owner-approved visual direction, November 12, 2026. Design/reference only; no code is changed by this document.

**Authoritative visual references (provided separately):**

1. `docs/design/mindmate-mood-v2-approved-board.png` — Home, Mood Log, Mood Journey.
2. `docs/design/mindmate-mood-v2-save-success.png` — post-save confirmation.

**Source of truth for logic:** the user's *local* `fix/mood-v2-primary-experience` branch, not the possibly older GitHub `main`. Reported checkpoint `3d62d13161089e6a99d8442a13d32f18c284b1bb`, foundation `e59524b0b0884e25014ae6f6b7cb7be0af5974c0`. Verify current state before editing. The local worktree contains other unrelated uncommitted changes that must survive intact.

## Intent

Make MindMate's student Mood V2 screens look and behave like one polished, inviting product. Personal usefulness and effortless repeat check-ins—not pressure, rewards, or diagnosis—should support retention. This is a **visual and interaction remediation**, not a new feature or analytics/backend milestone.

### Goals

- Visually reproduce the approved two mockups as faithfully as practical on a real Flutter Android device, retaining their hierarchy, composition, icon treatment, proportions, warm colors, and concise copy.
- Keep Home's *existing* full-width yellow **Log a mood** CTA as its only mood entry CTA. Remove the oversized duplicate **Mood check-ins** Home card in full.
- Move a **compact** Today check-in count + **Mood streak** summary onto the main Mood Log screen.
- Display the seven existing moods in an efficient 2-column picker (Great, Okay, Stressed, Sad, Angry, Tired) plus one compact full-width Excited row; selection is clear, animated gently, and accessible.
- Keep optional existing note (not a new journal), optional existing expression camera, and existing save mechanism.
- Make success an uncluttered state with two clear actions: **Log another mood** and **View My Mood Journey**. Keep Return Home as a tertiary text action; do not render a technical analytics/history dump below success.
- Give the Journey a nonwrapping seven-day strip, Mood streak distinct from Home's general Day streak, This Week/This Month selection, personal summary, and a compact timeline of multiple same-day entries.
- Keep Mindful Essentials as the already approved **placeholder** for existing Sleep Quality/Mindful Breathing until a unified destination is established; Mental Health Support opens the existing **inSIGHT** screen.

### Non-goals / prohibitions

- No new Home mood CTA; no new bottom-navigation tab; no appointment CTA/content added to Mood Log or Journey; no standalone journal; no research dashboard or term-based institutional research charts in the student app.
- No Firestore schema/Rules, Functions, authentication, App Check, environment configuration, rollout defaults, or production deployment changes.
- No modification of the existing general activity streak calculation or its Home card; no merging it with Mood streak.
- No hard-coded `Morris`, November 11, 2026, 4 check-ins, or sample timeline items from mockup. They are *illustrative*, not data requirements.
- No gamified penalties, guilt copy, diagnosis, validated prediction claims, intrusive reminders, or confetti tied to negative moods.

## Visual language and components

Match the mockup **within existing theme architecture**, reusing project tokens where present. The sample reference colors, to reconcile against actual theme classes, are:

| Role | Color | Use |
| --- | --- | --- |
| App canvas | `#F7F1DF` | Warm cream backdrop |
| Card / header | `#FFFEFA` | Ivory/off-white cards |
| Primary gold | `#FFC414` | Primary Save and existing Home Log CTAs |
| Pale gold | `#FFE8A3` | Selection and journey streak accents |
| Dark ink | `#17120A` | Main text/icons |
| Deep sage | `#2F7D6D` | Selected borders, secondary actions, status |
| Pale sage | `#DCEEE5` | Compact check-in and support banners |
| Warm divider | `#E9DFC6` | Quiet card outlines and separators |

- Prefer existing project typography and `HomePalette` / `MoodLogPalette` / theme equivalents over divergent hard-coded colors. Do not introduce a parallel global theme.
- Baseline layout at approximately **390 logical dp**, with 16–20 dp page gutters, an 8 dp spacing rhythm, 12–18 dp card gaps, generally 16–20 dp card radius, faint borders, soft shadows, restrained gold.
- Use the current emoji/vector mood assets and their real label-to-level mappings. Prefer installed `phosphor_flutter` / `phosphor_icons` **only if already present** for utility/navigation icons; do not add a new dependency just for polish.
- All interactive controls: minimum **48 × 48 dp** hit target; test meaningful labels in TalkBack and text scaling; decorative emoji alone cannot convey meaning.
- Interaction feedback: approximately 160–220 ms color/border/scale/fade transitions, using native Flutter animation widgets and `MediaQuery.disableAnimations` / platform accessibility settings to minimize motion. No mandatory delays or animation-dependent behavior.
- Respect safe areas; avoid keyboard occlusion, clipped floating help controls, excessive blank height, and scroll traps. The mockup is visual direction, not an unresponsive fixed screenshot.

## Screen A: Home (mockup left)

Preserve the existing yellow welcome header, general **Day streak**, Announcement, existing yellow **+ Log a mood** CTA, Upcoming Appointments, floating assistance control, and five existing navigation items (Home, Services, Appointment, Secret Chat, Message). **Remove** `HomeMoodV2SummaryCard` and its extra actions from the page; do not replace it with another mood card. The original yellow CTA continues to open the existing Mood Log route. Never change its position to a different part of the Home flow unless unavoidable for responsiveness.

## Screen B: Mood Log (mockup center)

Content hierarchy (top to bottom):

1. Compact existing back/header treatment: `Log your mood`, date in natural language, optional pre-existing feature action if still applicable.
2. **Compact sage summary banner**, roughly 64–76 dp high: `N check-ins today` and `Mood streak · N days`, plus short, nonpressuring caption. These derive from the authenticated user's *current* V2 records and server/Manila day, not the Home general streak. No raw level `2/5` or dense summary.
3. Prompt `How are you feeling right now?` with concise secondary text.
4. Compact selectable mood picker: 2 columns × 3 rows for Great, Okay, Stressed, Sad, Angry, Tired; Excited as a slim full-width final row. Preserve current accessible labels, icons, per-mood accent treatments, and exact underlying value mapping. Selected card gets deep-sage border, subtle soft-gold/ivory fill and a check glyph, with gentle animation; other cards stay calm. Fit efficiently without giant tall tiles.
5. Optional note via current 300-character owner-visible field; a concise expandable treatment is acceptable if it does not erase a user's draft. Optional camera action retains original permission/privacy behavior and clearly states images are not saved (only if already accurate).
6. Primary sticky-safe-area gold `Save mood entry` CTA, enabled only when existing validation allows it. Loading and error states must remain accessible and avoid duplicate writes.

The `Recorded mood summary`, raw level distribution, and full history panel currently embedded in/after the form **must not remain on the Mood Log screen**. Move relevant *personal* historical presentation to Journey; retain the current provider/analytics logic and security as-is.

## Screen C: Mood Saved (second mockup)

Use the same compact header, ivory card, green outline-check icon, chosen mood glyph + label, nonjudgmental acknowledgement, friendly local display of the trusted Manila timestamp, and pale-sage reassurance. Prominent gold **Log another mood** action; secondary outline **View My Mood Journey**; tertiary text **Return Home**. The state must **not** show an embedded raw-statistics/history dump beneath it.

Actual behavior is critical: a *new intentional save* creates a new request ID/event, including if it is the same mood and same day. A retry uses the *same* request ID as the original attempt. Successful save remains successful if the subsequent history refresh fails; history retry never submits a new write. Account switching clears the old owner's note/selected mood/confirmation/history and rejects stale async results.

## Screen D: My Mood Journey (mockup right)

1. Header `My Mood Journey`, warm title `Your feelings, over time` and respectful subcopy.
2. **Mood streak** card: current consecutive Manila mood-active days; never confused with the Home `Day streak`. Prefer the **leaf/sage motif** to distinguish it from Home's flame-based general streak, even if a generated mockup uses a flame.
3. Horizontal, nonwrapping **last seven Manila calendar days**; show day label, date, and whether any entry exists. A logged day is one active day regardless of 1, 3, or 10 records. At 320–360 dp widths, use a horizontally scrollable single row with 48 dp targets instead of squeezing or wrapping.
4. `This Week / This Month` two-state segmented control; compact check-in counts, unique mood-active days and most-logged mood. A tie is `Mixed feelings` or `Most logged moods are tied`; no fabricated dominant emotion. Clearly label history-based metrics as incomplete if the source only loaded part of history.
5. One slim grouped vertical timeline, newest first, showing distinct label and Manila time for each record; notes expand only for their authenticated owner. Repeated timestamps still represent distinct events.
6. Secondary tiles: **Mindful Essentials** (informational placeholder; avoid a misleading active chevron if no real unified route exists) and **Mental Health Support** (route to existing inSIGHT, not to a new counselor feature).

## Interaction and state contract

- Routes, existing five-item Home nav, feature flags/defaults, Mood V2 repository/provider, server timestamp/Manila date, idempotency, and owner isolation are preserved. No repository/Firestore changes required for presentation-only work.
- Never use a generated image as a runtime screenshot or rasterized UI. Build responsive native Flutter widgets matching its hierarchy and appearance.
- Empty state: welcoming invitation to log a mood, `0 check-ins today`, `0-day mood streak`, and no invented trend.
- Partial history: explicit `Based on loaded entries` treatment on affected Journey metrics, not an apparently complete percentage/trend.
- Mood streak: three same-day saves = three records but one active calendar day. A streak stays current if the latest logged calendar day is today or yesterday, per existing policy.
- Default-disabled V2 path and legacy streak/mood behavior remain unchanged.
- All personal suggestions are descriptive/supportive, not clinical; no predictions or diagnostic claims.

## Visual and functional acceptance

1. Compare **Home, Mood Log, Mood Saved, Journey** screenshots on real TECNO or Android emulator to BOTH supplied mockups; match overall geometry/spacing, warm tokens, icon rhythm, concise text, CTA hierarchy. Differences caused by real data, system chrome, accessibility, device size, and honest placeholder status are allowed.
2. No Home duplicate mood card/button; Home general Day streak remains; new compact V2 summary is on Mood Log only.
3. Seven mood choices and all optional existing controls are usable at 320/360/390/430 dp widths; seven-day Journey strip never wraps; font scaling and keyboard cannot hide final CTA.
4. One logged mood, three consecutive same-day intentional saves, repeat of same mood, same-day streak counting, backend error, refresh failure, and account-switch privacy all work exactly as before.
5. Visually meaningful loading/empty/error/partial-data states; reduced-motion and TalkBack testing.
6. Analyzer, V2-enabled focused tests, V2-default-disabled regression, and full staging Flutter suite pass on the final working tree; report any environment/device gaps honestly.

## Approaches and decision

- **Selected:** *Refined Daily Ritual* — faithful Flutter UI modernization inside current Mood V2 and Home architecture. Approved by the owner after reviewing the three-screen board.
- **Rejected:** large guided-step rearchitecture (disrupts working flow) and surface-only typography cleanup (fails visual quality target).

## Builder discretion / constraints

The local coding agent may settle minor responsive dimensions and icon substitutions **only after auditing actual installed assets and comparing to mockup**. Ask the owner before introducing a new navigation destination, altering backend/security, changing data semantics, or removing a previously working optional function.
