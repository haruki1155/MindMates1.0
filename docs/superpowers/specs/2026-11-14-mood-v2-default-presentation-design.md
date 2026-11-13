# Mood V2 as the default staging presentation

Status: approved in conversation; awaiting written-design approval.

## Intent and why

Every staging APK should show the current Mood V2 design — Log Mood, My Mood Journey, the home
dashboard card, profile statistics and insights — without anyone remembering six `--dart-define`
flags at build time. Today those flags all default to `false`, so a plain
`flutter build apk --debug --flavor staging --dart-define=APP_ENV=staging` produces the old look, and
the design that has already been reviewed is invisible to the person testing it.

The reason this is not simply "turn the flags on" is that one flag currently does two unrelated jobs.
`MoodV2FeatureFlag.enabled` selects the V2 layout **and** routes saving to the protected V2 writer.
That writer is refused by the server for ordinary accounts:
`functions/src/mood_entries.ts:59` throws `permission-denied` ("Mood V2 is not enabled for this
account") unless the project is `mindmate-staging` *and* the uid is in the pilot allowlist. Enabling
the flag would therefore show the new design and break saving for every non-pilot student.

So the work is to separate three concerns that are currently tangled: **presentation**, **reading**,
and **writing**.

## Goals

- A standard staging build shows the complete current Mood V2 presentation with no extra flags.
- The five read surfaces (provider, home, profile, history, insights) are on by default in staging.
- Ordinary accounts keep saving successfully through the existing legacy writer.
- Production behaviour is unchanged: every flag still defaults to `false` outside staging.
- Explicit `--dart-define` overrides continue to work in both directions.

## Non-goals

- Enabling the protected V2 writer. It stays `false` everywhere, including staging.
- Any change to Firestore rules, Cloud Functions, App Check, or the pilot allowlist.
- Removing the flags. They remain the control surface; only their defaults and their separation change.
- Restoring the duplicate Home buttons deliberately removed by PR #18.

## Anti-goals

Outcomes that would make this a failure even if it builds and ships:

- A build where the interface offers something the backend will refuse — most importantly multiple
  entries in one day, which the legacy writer does not support.
- A confirmation screen that says a V2 entry was saved when the legacy writer actually wrote it.
- My Mood Journey or the home card appearing empty for ordinary accounts, whose data lives in the
  legacy store, because a V2-only reader was used.
- Any path where enabling presentation silently enables the writer.

## Constraints

- **These are compile-time constants.** `bool.fromEnvironment` needs a const `defaultValue`.
  `AppEnvironmentConfig._name` is already `const` (`lib/core/config/app_environment.dart:8`), but
  `isStaging` is a getter and therefore unusable as a default. A new
  `static const isStagingBuild = _name == 'staging';` is required.
- `APP_ENV` falls back to `FLUTTER_APP_FLAVOR`, so `--flavor staging` alone also yields `staging`.
- **The writer is server-gated and must stay that way.** The client may not assume it can write V2.
- **Reads are already permitted.** `firestore.rules:255` allows `get, list` on `moodEntries` for the
  owner, and forbids all client writes. Turning the read flags on grants no new access; for an
  account with no V2 entries the queries simply return nothing.
- `MoodCombinedHistoryRepository` already merges legacy and V2 sources and is wired into `MoodProvider`
  (`lib/main.dart:73`), so a combined view is available rather than needing to be built.
- The home dashboard already falls back correctly: `home_screen.dart:263-274` uses the V2 entry when
  present and the legacy `todayMood` otherwise. Other surfaces must be verified to behave the same.

## Approaches considered

- **A — Split the flag into presentation / writer / reads (chosen).** `presentation` defaults to
  `isStagingBuild`; `enabled` keeps its meaning as the writer and stays `false`; the five read flags
  default to `isStagingBuild`. Each of the ~25 `widget.moodV2Enabled` references in
  `log_mood_screen.dart` is classified as layout or persistence and repointed.
  Smallest change, matches the file's existing idiom, production untouched. The risk is the
  classification itself, which is bounded and testable.
- **B — A `MoodV2Capabilities` object** built once and injected into the screen and provider, so call
  sites ask a capability rather than a global boolean. More testable and harder to misuse later, but a
  wider refactor across the provider and several screens for the same user-visible result today. The
  better destination if this gating grows beyond mood.
- **C — Runtime capability probe.** Ask the backend whether this account may write V2 and adapt.
  Needs no flags and self-corrects as the pilot list changes, but adds a network round trip before the
  screen can render honestly, needs an offline fallback, and the server already answers definitively
  when a save is attempted. Over-built for this change.

The user chose A.

## The design, as decided

### Environment

Add to `AppEnvironmentConfig`:

```dart
static const isStagingBuild = _name == 'staging';
```

`isStaging` (the getter) stays as it is; nothing that uses it changes.

### Flags

In `MoodV2FeatureFlag`:

- **New** `presentation` — `bool.fromEnvironment('ENABLE_MOOD_V2_PRESENTATION', defaultValue: AppEnvironmentConfig.isStagingBuild)`.
- `enabled` — unchanged name, unchanged `defaultValue: false`, and its documentation comment updated to
  say plainly that it controls the protected **writer** only.
- `providerRead`, `homeRead`, `profileRead`, `historyRead`, `insightsRead` — `defaultValue` becomes
  `AppEnvironmentConfig.isStagingBuild`.
- `actionLabel` keeps its `writerEnabled` parameter; its default continues to come from `enabled`.

Production and development builds therefore see `false` for all six, exactly as today.

### Log Mood

Every `widget.moodV2Enabled` reference is classified. The screen takes both a `presentation` and a
`writerEnabled` input (each defaulting from the flags, both injectable for tests).

- **Presentation** governs: layout and styling, headers, the mood selection cards, the notes and
  reflection interface, the Check Expression entry point, compact/expanded variants, navigation
  affordances, and the bottom bar.
- **The writer flag** governs: the branch at `log_mood_screen.dart:552` that calls `_saveMoodV2`, the
  `_confirmedV2Entry` state and the V2-specific confirmation and retry behaviour that depends on it,
  and any affordance offering more than one entry per day.
- With presentation on and the writer off, saving goes through the legacy path and the screen shows
  the V2-styled confirmation populated from the legacy result — the new look, an honest message, and
  no claim that a V2 entry exists.
- The existing one-check-in-per-day behaviour is preserved exactly, including the
  `View today's mood` state that `actionLabel` already produces when the writer is off.

### Reading surfaces

My Mood Journey, home, profile and insights read through the already-authorized combined reader where
one applies, so an account whose history is entirely legacy still sees its own data. Each surface is
checked for a legacy fallback of the kind the home dashboard already has; where one is missing, it is
added. No surface may require the writer flag — that coupling is specifically audited for.

Account isolation stays as it is: the existing ownership checks (such as `home_screen.dart`'s
`_ownedV2History`, which rejects history whose events are not all the signed-in uid) are preserved.

### Already logged today (user's decision)

A student who already has today's legacy entry and reopens Log Mood sees **the V2 confirmation,
rendered from that legacy entry**, not a blank form and not the old V1 card. This case currently falls
through every branch: `_loadTodayMood` (`log_mood_screen.dart:749-757`) returns early on the V2 branch
and never loads the legacy entry, the loading / error / result branches at lines 289, 295 and 304 are
all `!widget.moodV2Enabled`, and `_MoodSaved` hangs off `_confirmedV2Entry`, which only `_saveMoodV2`
ever sets. So with presentation on and the writer off, the legacy load must run and its result must
reach the confirmation.

Consequences, settled:

- `_MoodSaved` takes a **source-neutral view** (label, timestamp, optional note) instead of requiring a
  `MoodV2Event`. Nothing fabricates a `MoodV2Event` from a legacy entry: a synthetic event would carry
  an invented id, dateKey and clientRequestId, and could leak into combined history.
- The legacy path must **not** call `MoodProvider.recordConfirmedMoodV2Entry`
  (`log_mood_screen.dart:673`). That call injects a `v2`-source event into combined history and would
  reach the home card and streak as a phantom entry. The legacy save refreshes today's mood through
  the existing legacy provider path instead.
- `_loadTodayMood`, `_isLoadingToday`, `_todayError` and `_todayMood` become **presentation-governed,
  not writer-governed** — the legacy load runs whenever the writer is off, and its retry-on-error state
  must remain reachable inside the V2 layout.
- `onAnother` / `_startAdditionalMoodEntry` is hidden when the writer is off: a second entry per day is
  an anti-goal. The bottom-bar condition at line 206 (`moodV2Enabled && _confirmedV2Entry == null`)
  therefore needs a new basis — presentation plus "no confirmation currently shown".

### Other couplings found by the builder check (my calls)

- **`MoodV2Repository.fetchHistory` is gated on the writer flag** (`mood_v2_repository.dart:71` returns
  `const []` when `enabled` is false). It has no production caller and bypasses the combined reader to
  return V2-only events. It is **left as it is** and must not be repointed to a read flag — doing so
  would hand callers a V2-only history and reintroduce the empty-Journey failure for legacy accounts.
  Its one test keeps asserting the empty result.
- **`MoodV2Repository.create` throws a bare `StateError`** when the writer is off
  (`mood_v2_repository.dart:51`). With the writer off `_saveMoodV2` must be unreachable, but a
  mis-classified call site would surface an unhandled error to the student. The save path gains a
  defensive guard so any such mistake produces the normal error message rather than a crash.
- **The insights caption at `mental_health_insights_screen.dart:918`** branches on `enabled`; it is a
  caption, not policy, so it is repointed to `presentation`.
- **`MoodV2FeatureFlag.actionLabel` keeps `writerEnabled = enabled`.** The `View today's mood` wording
  when the writer is off is deliberate policy, not a styling leftover, and stays.

### Test environment (user's decision)

The existing suite stays on today's defaults so no existing test's behaviour shifts underneath it.
`.github/workflows/android-verify.yml:35` and `mood-v2-emulator-validation.yml:115` currently run
`flutter test --dart-define=APP_ENV=staging`; they are pinned to a neutral environment, and **one new
focused CI job** runs the mood, home, profile and insights tests with `--dart-define=APP_ENV=staging`
to prove the new defaults. This keeps the change contained rather than suite-wide while still covering
the staging configuration.

Because `bool.fromEnvironment` cannot be varied at runtime, per-reader on/off coverage comes from
injected values in widget tests plus a narrow unit test over the constants themselves — read surfaces
gain injection seams only where a test genuinely needs both states, not as a blanket refactor.

### Verification

Tests cover: staging defaults on and production defaults off for presentation and each reader; the
writer false in both; a legacy save made through the V2 interface, with its confirmation; history with
legacy-only records, and with both legacy and V2 records; today's mood, streak and insights refreshing
after a legacy save; no second daily entry offered through the legacy writer; explicit `--dart-define`
overrides in both directions; account switching and error paths. Plus `flutter analyze` and a staging
APK build with no Mood V2 flags.

## What is left to the builder

- The per-site classification of each `widget.moodV2Enabled` reference — the design states the rule;
  applying it to each line is the builder's reading of what that line actually controls.
- Whether the screen takes two booleans or a small record/parameter object, and the naming of its
  injectable inputs.
- Which surfaces genuinely need a fallback added versus already having one, determined by reading them.
- Which read surfaces get injection seams — only those whose tests need both states, per the test-environment section.
- How compile-time defaults are asserted in tests, given `bool.fromEnvironment` cannot be varied at
  runtime — likely by injecting the values rather than reading the constants in widget tests, with the
  constants themselves covered by a narrow unit test.
