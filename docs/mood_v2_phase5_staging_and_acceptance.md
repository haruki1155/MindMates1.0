# Mood V2 Phase 5 staging readiness and acceptance plan

Status: local preparation only. This document authorizes neither a Firebase
deployment nor client feature activation.

## Current release controls

- `ENABLE_MOOD_V2=false` remains the default, so the legacy daily writer is
  still the only production/staging client writer.
- All client reader flags default to `false`: provider, Home, Profile, history,
  inSIGHT, Reports, and MindAid are independently gated.
- `MOOD_V2_STAGING_PILOT_UIDS` defaults to the empty string. The callable
  rejects every caller until a staging-only deployer supplies an explicit,
  verified synthetic UID allowlist.
- `createMoodEntry` and `createMoodEntryDev` derive identity, timestamp, and
  Manila date key on the server. Clients cannot submit a UID, date key, or
  authoritative timestamp.

## Future staging deployment manifest

Run these steps only after a separate staging deployment authorization and from
the reviewed Mood V2 feature/release commit, never from the CI-only branch.

1. Confirm the target before any deployment:

   ```powershell
   firebase.cmd use staging
   firebase.cmd projects:list
   git rev-parse HEAD
   git status --short
   ```

   The selected project must be `mindmate-staging`; a dirty worktree, a
   production target, or an unreviewed commit is a stop condition.

2. Use a protected, ignored Functions environment file for the first deploy:

   ```text
   # functions/.env.mindmate-staging (never commit)
   MOOD_V2_STAGING_PILOT_UIDS=
   ```

   The initial deployment must keep this value empty. It closes the callable
   to every account while Rules/indexes and Function revisions are introduced.

3. Build and review the exact scope, then deploy only these resources:

   ```powershell
   npm.cmd run build --prefix functions
   firebase.cmd deploy --only firestore:rules,firestore:indexes,functions:createMoodEntry,functions:createMoodEntryDev --project mindmate-staging
   ```

   Do not use `--force`, do not deploy Hosting, and do not deploy unrelated
   Functions. Review any deletion or additional-resource prompt as a stop
   condition.

4. After a separate pilot authorization, replace the empty value with only
   approved disposable synthetic UID(s), redeploy the two callables, and
   record the authorized UID list outside source control. Never place personal
   or real-student IDs in the allowlist.

## Resource and rollback review

| Resource | Intended change | Safety check |
| --- | --- | --- |
| `createMoodEntry` / `createMoodEntryDev` | New server-authoritative V2 writers | Auth, profile eligibility, staging-project identity, and allowlist remain enforced. |
| `firestore.rules` | Owner-only V2 reads; direct V2 writes denied | Legacy `moods` rules are unchanged. |
| `firestore.indexes.json` | `moodEntries` owner/history query indexes only | No index deletion or unrelated index change. |
| Client APK | No change during backend rollout | Keep every V2 flag false until a separately approved pilot APK. |

Rollback is additive and preserves `moodEntries` records:

1. Close `MOOD_V2_STAGING_PILOT_UIDS` to the empty value and redeploy only the
   two callables if a pilot must stop accepting writes.
2. Disable all V2 client build-time flags in the next pilot build or withdraw
   distribution of a pilot build. Existing legacy logging remains available.
3. If a Function revision itself is defective, restore the previously reviewed
   revision through the approved staging release process. New callables may
   have no earlier revision; in that case keep the allowlist empty rather than
   deleting records or weakening Rules.
4. Do not delete or mutate existing V2/legacy mood records as a rollback step.

## Flag matrix

| State | Server pilot allowlist | `ENABLE_MOOD_V2` | Reader flags | Result |
| --- | --- | --- | --- | --- |
| Legacy-only baseline | Empty | false | all false | Existing legacy writer/readers only. |
| Read-only compatibility test | Empty | false | one approved reader flag true | Combined reader can be observed; no V2 write path is enabled. |
| Synthetic pilot writing | Explicit disposable UID only | true in a dedicated pilot APK | only approved readers true | Callable permits only that synthetic account; retry remains UUID-idempotent. |
| Rollback | Empty | false in replacement APK | all false | Legacy behavior resumes; historical records remain read-only. |

`ENABLE_MOOD_V2_REPORTS_READ` and `ENABLE_MOOD_V2_MINDAID_READ` remain
separate client/build controls. The MindAid Function-side history behavior must
also remain disabled unless its own reviewed environment control is enabled.

## Phase 5C acceptance cases

Use disposable staging fixtures and synthetic levels only. Capture record
counts, request IDs, event IDs, and timestamps without recording notes,
credentials, raw responses, or expression/camera data.

1. First V2 mood entry creates one event with server `occurredAt` and Manila
   `dateKey`.
2. Second and third intentional same-day entries use different UUIDs, yield
   three events, and one mood-active day.
3. Retry after timeout uses the original UUID/payload and returns the original
   event; a changed payload with that UUID returns `already-exists`.
4. Refresh/history retain legacy and V2 records without identity duplicates;
   partial coverage is visibly labelled rather than treated as all history.
5. Mood-specific current/longest streaks use unique Manila dates while
   `users.dayStreak` remains unchanged.
6. Home, Profile, Reports, MindAid, and inSIGHT each retain legacy fallback
   while their V2 reader flag is false, then are tested one flag at a time.
7. Log out/account switch during a pending write; stale completion must not
   affect the new account.
8. Exercise slow-network, timeout, duplicate-tap, retry, and failure-state UI
   behavior without automatic retry or duplicate records.
9. Verify Student, Teaching, and Non-Teaching compatibility where the mood
   feature is normally available, including responsive/accessibility layout.
10. Verify direct Firestore create/update/delete and cross-user reads are
    denied; inspect diagnostics for absence of notes and expression data.

## Required gates before release acceptance

- Docker or equivalent verified offline Mode B execution passes Auth, Rules,
  transaction/idempotency, and callable integration using `mindmate-staging`
  only inside local emulators.
- Focused Mood V2 tests, full staging Flutter suite, analyzer, Functions build,
  Functions tests, and Rules tests pass on the exact candidate commit.
- A separately authorized staging deployment keeps the pilot allowlist empty
  first, followed by synthetic-account smoke tests after explicit approval.
- A pilot APK and physical-device acceptance occur only after backend
  authorization; the preserved TECNO Assessment session is out of scope.

Until these gates pass, panel comments Major #5, Major #6, and Minor #38 remain
**IN PROGRESS**. No completion status is inferred from a green CI workflow that
reports `MODE_B=BLOCKED`.
