# Mood Tracking & Analytics V2 — Technical Contract

Status: contract approved; Phase 1 pure-Dart analytics implemented. Persistence remains design-only.
Base: `0bd77f0aead2aa09198857e1f20ac8dc765c667a` (`origin/main`).
No application source, Rules, indexes, Functions, Firebase data, or deployment resources are changed by this document.

## Conditional-approval decisions

The approved V2 persistence boundary is one authenticated, server-authoritative callable. Clients will not directly create, edit, or delete `moodEntries`; Rules will deny all such writes. The callable will authenticate the caller, derive both `occurredAt` and `dateKey` from one server instant, and atomically resolve `clientRequestId` idempotency. Concurrent retries with the same request ID and same canonical payload return the original event; a matching request ID with a conflicting payload fails deterministically. Optional tags, edits, historical backdating, numeric-average presentation, and admin analytics are not part of Phase 1.

## 1. Current contract and evidence

### Legacy mood records

`MoodModel` maps the legacy `moods` shape: `userId`, integer `level` (1–5), optional `label` and `note`, `dateKey`, `timezone`, optional expression-assist metadata, and `createdAt` ([`lib/models/mood_model.dart`](../lib/models/mood_model.dart)).

`MoodRepository.saveDailyMood` writes exactly one deterministic document per user and Manila calendar day: `moods/daily_<uid>_<yyyyMMdd>`. It first calls `fetchTodayMood`, then uses a Firestore transaction to avoid a same-day duplicate ([`lib/repositories/mood_repository.dart`](../lib/repositories/mood_repository.dart)). `LogMoodScreen` treats a returned `todayMood` as a completed check-in ([`lib/features/mood/screens/log_mood_screen.dart`](../lib/features/mood/screens/log_mood_screen.dart)).

Rules reinforce that contract: client-created IDs must match `daily_<auth uid>_<eight digits>`, `createdAt` must equal `request.time`, and the permitted field set is closed ([`firestore.rules`](../firestore.rules), `match /moods/{moodId}`). Existing composite indexes support `moods` queries by `userId, createdAt` ascending and descending ([`firestore.indexes.json`](../firestore.indexes.json)).

### Writers and readers

| Area | Current behavior | Source |
| --- | --- | --- |
| Manual/expression mood write | `MoodProvider.logDailyMood` → `MoodRepository.saveDailyMood` | `lib/providers/mood_provider.dart`, `lib/repositories/mood_repository.dart` |
| Legacy wrapper | `MoodProvider.logMood` → `createMood` → same daily save | `lib/providers/mood_provider.dart` |
| Recent/today mood reads | `fetchRecentMoods`, `watchRecentMoods`, `fetchTodayMood` | `lib/repositories/mood_repository.dart` |
| Home | recent moods populate activity dates; profile `dayStreak` is rendered | `lib/features/home/screens/home_screen.dart` |
| inSIGHT display | `InsightMetricsSummary` uses weekly mood events and total event count | `lib/features/insights/models/insights_models.dart` |
| inSIGHT recommendations | repository consumes reports and static content/rules; it does not independently aggregate mood events | `lib/repositories/insights_repository.dart` |
| Reports/MindAid | query `moods` directly and derive recent averages/trends | `lib/repositories/report_repository.dart`, `lib/repositories/mind_aid_context_repository.dart`, `functions/src/mind_aid.ts` |

### Existing activity-wide streak

`StreakCalculator` uses local device `DateTime.toLocal()` and fields in `users/<uid>`: `lastActivityDateKey`, `dayStreak`, `longestStreak`, and a capped `activeDateKeys` list. `MoodRepository.saveDailyMood` updates those fields in its transaction; other `UserActivityType` writers do too ([`lib/repositories/user_repository.dart`](../lib/repositories/user_repository.dart)). Home, Profile, reports, and MindAid consume this activity-wide streak. Mood V2 must not change it in its first release.

The legacy mood path separately derives its `dateKey` using a fixed UTC+8 wall-clock conversion and stores `Asia/Manila` ([`lib/repositories/mood_repository.dart`](../lib/repositories/mood_repository.dart)). This differs from the activity-wide streak's `toLocal()` convention and is the reason Mood V2 needs an explicit isolated date contract.

### Existing regression coverage

`test/repositories/mood_repository_test.dart` asserts Manila rollover and the deterministic daily ID. `test/providers/mood_provider_test.dart` asserts same-day preservation, midnight behavior, and legacy save-clock sampling. `test/repositories/insights_repository_test.dart` covers content/rule ordering and role isolation, but does not distinguish mood events from unique mood-active days. These tests must remain valid for the legacy path.

### Compatibility matrix

| Consumer | Current input/behavior | Phase 1 impact | Later V2 migration contract |
| --- | --- | --- | --- |
| Home | `MoodProvider` and `users.dayStreak`; legacy daily check-in | None | Use a normalized analytics snapshot only behind a flag; do not change activity-wide streak |
| Profile | renders `dayStreak`/`longestStreak` from the user profile | None | Keep activity-wide counters until a separately approved Mood-streak presentation exists |
| Reports | reads legacy `moods` and profile counters | None | Read normalized history with explicit event/day semantics; preserve legacy report fallback |
| inSIGHT | uses report context and `InsightMetricsSummary` event counts | None | Receive privacy-bounded analytics snapshot and invalidate user cache after confirmed writes |
| MindAid | queries recent legacy mood levels and activity-wide streak | None | Continue legacy context until a separately reviewed trusted V2 context adapter is introduced |

## 2. Additive `moodEntries` event schema

Add a new top-level collection; do not rename, overwrite, or backfill `moods` during initial rollout.

```text
moodEntries/<entryId>
  userId: string                    // immutable, equals auth UID
  level: int                        // 1..5; ordered scale already used by MoodModel
  label: string                     // <= 40, optional empty string allowed
  note: string                      // <= 300, optional empty string allowed
  tags: string[]                    // optional; bounded and allow-listed in implementation
  dateKey: "YYYY-MM-DD"             // immutable Manila date of occurredAt
  timezone: "Asia/Manila"           // immutable
  occurredAt: timestamp             // server-authoritative event time
  createdAt: timestamp              // server timestamp
  entryMethod: string?              // existing manual/expression-assisted vocabulary
  expressionAssistUsed: bool?
  expressionSuggestionAccepted: bool?
  expressionModelVersion: string?
  clientRequestId: string           // idempotency key, opaque UUID
  editedAt: timestamp?              // only if edit support is approved
  revision: int                     // begins at 1; only if edit support is approved
```

**ID and idempotency.** The client generates an opaque UUID `clientRequestId`; the trusted callable resolves the UID-scoped request record and event in one transaction. Retrying the same canonical payload returns the original event. A concurrent or later retry with the same key but a different canonical level/label/note/method fails with an idempotency-conflict error. A second intentional entry receives a new key. The repository must never use a deterministic day ID for V2 events.

**Authority and validation.** The callable requires Firebase Auth, applies the constrained field set/types/lengths, assigns one server `Timestamp.now()` value to `occurredAt`, derives its `Asia/Manila` `dateKey`, rejects unsupported fields, and persists the event/request record atomically. V2 Rules deny direct create, update, and delete; authenticated owners may read/list only their events and admins follow the existing trusted read policy. This prevents client-clock and concurrent-retry ambiguity.

**Immutability/editing.** Initial V2 user behavior is append-only: users cannot edit or delete events. Authorized privacy/account-deletion processing is distinct from normal user behavior, must run in trusted infrastructure, and must audit/reconcile affected aggregates. A later edit feature needs a separately approved trusted operation, retains original `dateKey`/`occurredAt`, increments `revision`, sets `editedAt`, and recomputes affected aggregates.

**Legacy compatibility.** A read adapter returns a normalized union of legacy `moods` and V2 `moodEntries`, with `source = legacy | v2`. During transition it deduplicates only on stable identity, never merely matching level/date: V2 writes are new events and legacy records remain historical. No backfill is required for V2 functionality. A future optional, separately approved migration may create V2 *derived* entries with `source=legacy_migration`, but readers must exclude either original or migrated duplicate, not both.

## 3. Manila date and Mood-specific streak contract

### Date contract

1. `occurredAt` is the authoritative instant; the trusted write path maps it to `Asia/Manila` (`UTC+08:00`) and writes an immutable `dateKey`.
2. A mood-active day is a unique `dateKey` with at least one accepted V2 event, or a legacy record where `dateKey` is present; legacy records missing it derive it through the existing Manila conversion.
3. Multiple events on one `dateKey` count as one mood-active day. Retry of the same `clientRequestId` counts once.
4. Historical entries retain their original `dateKey` even if an editable note/label is introduced later. Historical entry insertion needs explicit product approval because it can alter historical analytics; it never updates the activity-wide user streak.
5. Events whose `occurredAt` is materially in the future are rejected. First-time users have zero current/longest Mood streak until their first accepted active day.

### Current and longest Mood streaks

This is a *Mood V2 analytics value*, separate from `users.dayStreak` and `users.longestStreak`.

* Current streak is the count of consecutive unique Manila date keys ending today, or ending yesterday if there is no event today. It is zero when the latest active day is before yesterday.
* Longest streak is the maximum consecutive run in the requested, complete history window. A partial/paginated history must label this as a windowed value, not an all-time value.
* Duplicate, retry, and out-of-order events first reduce to a sorted set of `dateKey`s.

Examples:

| Active Manila dates / reference date | Current | Longest | Rationale |
| --- | ---: | ---: | --- |
| none / 2026-07-10 | 0 | 0 | first-time user |
| 2026-07-10 / 2026-07-10 | 1 | 1 | first accepted event today |
| 2026-07-09, 2026-07-10 (three events on 10th) / 10th | 2 | 2 | same-day events do not inflate streak |
| 2026-07-08, 2026-07-09 / 10th | 2 | 2 | yesterday-ending streak remains current |
| 2026-07-08 / 10th | 0 | 1 | a missed full Manila day breaks current streak |
| 2026-07-07 16:00Z / 2026-07-08 Manila | 1 | 1 | UTC instant maps to Manila 2026-07-08 |

## 4. Analytics contract

### Daily aggregation

Source of truth is normalized event history, grouped by immutable Manila `dateKey`; aggregates are derived/cached views, never a replacement for raw events.

```text
MoodDailyAggregate
  dateKey
  entryCount
  isMoodActiveDay
  levelCounts: { "1": n, ... "5": n }
  latestLevel
  latestOccurredAt
  sourceCoverage: legacy | v2 | mixed
```

Do not present an average as a clinical conclusion. The existing 1–5 ordered scale can support a clearly labelled descriptive mean/trend only after product/clinical review; the default UI should show distribution, entry count, active-day count, and latest mood.

**Weekly range.** Monday 00:00 through the next Monday 00:00, in `Asia/Manila`. Weekly reports expose both `entryCount` and `activeDayCount`. Missing days mean “no recorded mood”; they do not mean a negative mood, lack of consent, or inactivity outside Mood V2.

**Calculation placement.** Phase 1 repository calculation over a bounded per-user date-range query is transparent and requires no migration. Add server-maintained aggregates only when performance/consistency evidence warrants it. If server aggregates are added, Functions own mutation/reconciliation and client treats them as read-only cache.

## 5. Proposed Rules, indexes, APIs, and inSIGHT contract

### Firestore Rules proposal (not applied)

`match /moodEntries/{entryId}` should permit owner reads/listing and trusted-admin reads, while `allow create, update, delete: if false`. The callable uses the Admin SDK and remains the sole write path. It must not weaken legacy `moods` Rules.

### Index proposal (not applied)

Add `moodEntries(userId ASC, occurredAt DESC)` for recent/history; add `moodEntries(userId ASC, dateKey ASC, occurredAt ASC)` only if date-range aggregation queries need it. Validate actual query shapes with the emulator before adding any index.

### Repository API proposal

```dart
Future<MoodEntry> createMoodEntry(CreateMoodEntryRequest request);
Future<List<NormalizedMoodEvent>> fetchMoodHistory(String uid, MoodDateRange range);
Future<MoodAnalyticsSnapshot> fetchMoodAnalytics(String uid, MoodDateRange range);
Stream<MoodAnalyticsSnapshot> watchMoodAnalytics(String uid, MoodDateRange range);
```

Use bounded date ranges and explicit page cursors. Keep legacy `MoodRepository.saveDailyMood`, `fetchTodayMood`, and `MoodProvider.hasCheckedInToday` unchanged until a separate UI migration is approved.

### inSIGHT contract

After confirmed V2 creation, invalidate the current user's `InsightsProvider` cache and refresh in the background while retaining last successful content. The invalidation must be user-scoped, must not expose another user's cache, and must preserve existing role filtering. inSIGHT receives a privacy-bounded `MoodAnalyticsSnapshot` (counts/trend/distribution), not notes, tags, raw expression signals, or entry text. If V2 or legacy history is unavailable, retain existing report/static fallback and expose data freshness rather than fabricate metrics.

## 6. Regression-test matrix

| Case | Setup / expected result | Layer |
| --- | --- | --- |
| One event today | one V2 UUID; one entry and one active day | repository + emulator Rules |
| Multiple same-day events | unique UUIDs; entry count 3, active-day count 1, streak +1 only | repository |
| Retry | same UUID twice; one document/event | callable/transaction emulator |
| Consecutive and gap | date-key sets in examples above | pure analytics/streak unit tests |
| Manila boundaries | `15:59Z` vs `16:00Z`; correct calendar date | date utility unit tests |
| First/out-of-order/future | zero initial streak; sort dates; reject future event | repository/callable tests |
| Legacy only/new only/mixed | normalized reader retains history and avoids identity duplicates | repository fixtures |
| Edit/delete | append-only rejection initially; later revision preserves date key and recomputes aggregate | Rules + trusted-operation tests |
| Empty/partial history | explicit empty snapshot; paged longest streak marked windowed | repository/UI tests |
| Permissions | owner allowed; another user denied; admin boundary follows current role policy | Firestore emulator Rules |
| Analytics semantics | event count differs from unique active days; distribution supports mixed levels | pure analytics + widget tests |
| Existing activity streak | mood V2 writes do not change `users.dayStreak` | emulator integration |
| inSIGHT | user-scoped invalidation, role content remains isolated, fallback survives unavailable metrics | provider/repository tests |

## 7. Risks, open decisions, and implementation phases

**Open decisions requiring approval:** whether users can edit/delete events; historical-entry UX; final future-clock tolerance; tag taxonomy; whether to display a numeric mean; retention policy; and whether any counselor/admin aggregate view is needed. These decisions affect Rules, privacy review, and data contracts.

**Phased implementation:**

1. Add pure immutable event/date/analytics models and tests; no UI or cloud change.
2. Add the authenticated callable and its atomic request-ID transaction, then emulator-test conflict/retry behavior.
3. Deploy Rules/indexes only after the callable is available; add read-only union readers behind a feature flag.
4. Switch UI writer behind the flag, then add history/analytics presentation and user-scoped inSIGHT invalidation.
5. Stage with synthetic accounts, monitor duplicate/idempotency and date-boundary telemetry, then decide whether server aggregates or legacy migration are necessary.

Assessment Phase 8.1 and Gate B are outside this contract and remain unchanged.
