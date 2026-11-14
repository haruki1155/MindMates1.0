# Staging multi-mood, messaging repair, and palette alignment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In a staging build: a student can log more than one mood a day, messaging works, and the green surfaces in appointments and My Mood Journey use the app palette.

**Architecture:** Three independent threads. (1) The server's existing `MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED` parameter is switched on for staging — no server code changes — and the client's protected writer turns on in staging — the presentation/writer separation built earlier means the multi-entry UI returns with no UI surgery. (2) Three callables that are exported but never deployed get deployed, which unblocks messaging. (3) Off-palette greens are repointed at `AppColors`.

**Tech Stack:** Firebase Functions v2 (TypeScript, `node:test`), Flutter, Firestore rules (unchanged).

**Decisions taken by the user this session:** multiple entries for *all* staging accounts (not just a pilot uid); deploy all three missing callables.

## Global Constraints

- **Production behaviour must not change.** `createMoodEntry` stays refused outside `mindmate-staging`, and every client flag stays `false` in development and production builds.
- **No change to `firestore.rules`, App Check, or any authorization helper** (`requireAdmin`, `requireClinical`, `access.ts`).
- **Deploy by name only. Never `--force`** — a blanket deploy would delete staging-only functions that do not exist on main.
- **Ordering is a hard dependency, not a preference.** Task 2 (client writer on) must not ship before Task 1 (server gate) is deployed. Shipping it first makes every non-pilot student's mood save fail with `permission-denied`. See Review Focus 1.
- The palette work touches colour only — no layout, copy, or behaviour changes.
- Commit trailer: `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. No push or merge without the user's approval.
- Baseline on this branch (`7514e98`): full suite under `APP_ENV=staging` = **1143 pass, 1 skip, 0 fail**; `flutter analyze` clean. Under `APP_ENV=development` there are 32 **pre-existing, unrelated** failures in `quick_assessment`/`student_assessment`/one home test — not this work's to fix, and not to be reported as new.

## Review Focus

1. **The deploy-order trap.** If the client flag ships before the server gate is deployed, every ordinary student's mood save fails with `permission-denied` — a total loss of the core feature, worse than the bug being fixed. Task 2 opens with a step that *verifies the deployed gate* before changing the flag.
2. **A production build picking up the staging writer.** `enabled` moving off a hard `false` is exactly the change the earlier work was careful to avoid; a mistake here enables a server-refused writer in production. Pinned in Task 2.
3. **An account on a *different* project.** The gate keys on `projectId`, so a dev build pointed at staging credentials, or vice versa, changes who may write. Pinned in Task 1.
4. **Messaging failing for a reason other than the missing callable.** The rules require a string `collegeId`; deploying the repair callable only helps if the repair actually fills it. Task 3 verifies end-to-end on the device rather than assuming the deploy fixed it.
5. **A colour change that silently alters a *state* signal.** Appointment status colours (pending / confirmed / cancelled) carry meaning; flattening them all to one green would destroy the distinction. Pinned in Task 4.

---

## File Structure

- **No change to `functions/src/mood_entries.ts`** — the staging student rollout already exists; only its parameter is switched on.
- Modify `lib/features/mood/config/mood_v2_feature_flag.dart` — `enabled` default.
- Modify `test/features/mood/mood_v2_feature_flag_test.dart`, `test/features/mood/mood_v2_repository_test.dart` — the flag contract.
- Modify `lib/features/counseling/widgets/appointment_presentation.dart`, `lib/features/counseling/screens/pacc_counseling_screen.dart`, and the Mood Journey green surfaces — colour tokens only.
- No file under `functions/src/access.ts`, `firestore.rules`, or `lib/repositories/` changes.

---

### Task 1: Switch on the staging student rollout (configuration, no code)

**Files:** none. **This task changes no source.**

`functions/src/mood_entries.ts` already implements exactly what was asked, by design:
`createMoodEntryForUser` accepts a **non-pilot** account when `projectId === "mindmate-staging"`,
the caller passes `allowStudentRollout`, `gate.studentRolloutEnabled === true`, the account is
active and its role fields are consistent. The callable handler at line 264 already passes
`allowStudentRollout = true`, and the student-rollout path is already covered by
`mood_entries.test.ts`. The only thing holding it shut is the parameter
`MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED` (`defineBoolean`, default `false`).

So this is a configuration change plus a redeploy so the function picks the value up. **Do not edit
the gate.** Removing the pilot clause by hand would throw away the role and account-status checks
that this path performs and that the pilot path does not.

- [ ] **Step 1: Confirm the current value** of `MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED` on
  `mindmate-staging`, and record it so it can be restored.
- [ ] **Step 2: Run the existing functions tests** — `cd functions && npm test` — and confirm the
  student-rollout cases already pass. No new test is needed for behaviour that is already pinned;
  if a case is missing (a non-pilot active student on staging being accepted *with* the flag on,
  and refused *with it off*), add just that one.
- [ ] **Step 3: Set the parameter to `true` for `mindmate-staging` only**, via the project's
  existing parameter mechanism (`.env.mindmate-staging` or the equivalent already in use — find how
  the other params are set rather than inventing a new mechanism). Production must keep `false`.
- [ ] **Step 4:** the deploy happens in Task 3. Do not deploy from this task.
- [ ] **Step 5: Commit** only if a config file in the repo changed:
  `chore(mood): enable the staging student rollout for Mood V2`

**Note for the implementer:** the rollout path additionally requires `accountStatus` active and
consistent role fields. An account with inconsistent legacy `role` vs `populationRole` will still be
refused. If the user's test account is refused after this change, that is the reason — report it,
do not loosen the role check.

### Task 2: Turn the protected writer on in staging builds

**Do not start until Task 3's deploy has put Task 1's rollout flag live on `mindmate-staging`.** The branch is useless-to-harmful in between.

**Files:**
- Modify: `lib/features/mood/config/mood_v2_feature_flag.dart`
- Test: `test/features/mood/mood_v2_feature_flag_test.dart`, `test/features/mood/mood_v2_repository_test.dart`

- [ ] **Step 1: Verify the deployed gate first.** Confirm Task 1's change is live on `mindmate-staging` (the deploy in Task 3 reports it). If it is not, stop — do not change the flag.
- [ ] **Step 2: Write the failing tests.** The contract becomes: `enabled` follows `isStagingBuild`, exactly like `presentation` and the five readers; it is still `false` in development and production; `--dart-define=ENABLE_MOOD_V2=false` still overrides it off in staging. Update the existing assertions that pin `enabled` to `false` in every environment, and keep the `VERIFY_MOOD_V2_WRITER_ONLY_PILOT` guards intact.
- [ ] **Step 3: Run to verify they fail.**
- [ ] **Step 4: Implement** — `enabled`'s `defaultValue` becomes `AppEnvironmentConfig.isStagingBuild`. Update its doc comment: it is no longer "disabled everywhere", it is "on in staging, where the server now accepts any account; off in development and production".
- [ ] **Step 5: Run to verify they pass**, in all three shapes: `APP_ENV=staging`, `APP_ENV=development`, and the pilot shape. Then `flutter test test/features/mood test/features/home test/features/profile test/providers --dart-define=APP_ENV=staging`.
- [ ] **Step 6: Confirm the multi-entry UI returned** — with the writer on, `onAnother` is non-null, so "Log another mood" and the "check in again" copy render again. The existing writer-on tests already assert this; confirm they run and pass rather than adding new ones.
- [ ] **Step 7: Commit** `feat(mood): enable the V2 writer in staging builds`

---

### Task 3: Deploy the three missing callables and the mood gate

**Files:** none — this task deploys.

**This is the only task that touches `mindmate-staging`.** Deploy by name. Never `--force`.

- [ ] **Step 1: Record what is deployed now** — `firebase functions:list --project mindmate-staging`, saved so a regression is detectable. There are 108 functions; `repairMyStudentCollege`, `acknowledgeMindAidEmergencyAlert` and `resolveMindAidEmergencyAlert` are absent.
- [ ] **Step 2: Build the functions** — `cd functions && npm run build`. Do not deploy a failed build.
- [ ] **Step 3: Deploy by name:**
```
firebase deploy --project mindmate-staging --only \
  functions:repairMyStudentCollege,functions:acknowledgeMindAidEmergencyAlert,functions:resolveMindAidEmergencyAlert,functions:createMoodEntry
```
- [ ] **Step 4: Verify** — list functions again and confirm all four are present and the other 108 are untouched. Report the before/after counts, and confirm `createMoodEntry` picked up `MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED=true`.
- [ ] **Step 5: No commit** (nothing changed in the tree). Report the deploy result.

---

### Task 4: Align the appointment and Mood Journey greens with `AppColors`

**Files:**
- Modify: `lib/features/counseling/widgets/appointment_presentation.dart`
- Modify: `lib/features/counseling/screens/pacc_counseling_screen.dart`
- Modify: the Mood Journey green surfaces (locate them first — `mood_journey_screen.dart` draws on `HomePalette`, which has no green, so the green comes from a widget it composes)
- Test: the existing counseling and mood widget suites

**Interfaces — Consumes:** `AppColors` (`lib/core/constants/app_colors.dart`): `primary = #2F7D6D`, `secondary = #F2B84B`, `accent = #8E6AD8`.

**Known off-palette greens:** `appointment_presentation.dart` `teal = #285D59`, the confirmed-status pair `#E7F5EF` / `#187557`, the icon tint `#658D81`; `pacc_counseling_screen.dart:2132` `#187557`. `MoodLogPalette.green` is already `#2F7D6D` and is correct — leave it.

- [ ] **Step 1: Find every green** in the appointment widgets/screens and on the Mood Journey route, and list each with what it signifies (brand surface, confirmed status, icon tint, success check). Do this before changing anything — the census is the deliverable of this step.
- [ ] **Step 2: Write/extend the failing tests.** Assert that the appointment status colours remain **mutually distinct** (pending ≠ confirmed ≠ cancelled) and that the brand green equals `AppColors.primary`. The distinctness assertion is the guard for Review Focus 5.
- [ ] **Step 3: Run to verify they fail.**
- [ ] **Step 4: Implement.** Repoint brand/structural greens to `AppColors.primary` and derive tints from it rather than inventing new hexes. **Keep status colours distinct**: confirmed may move to the palette green, but pending (gold) and cancelled (red) keep their own hues. Change colour only — no layout, spacing, or copy.
- [ ] **Step 5: Run to verify they pass**, plus `flutter test test/features/counseling test/features/mood test/features/home --dart-define=APP_ENV=staging` and `flutter analyze` on the touched files.
- [ ] **Step 6: Commit** `style(ui): align appointment and Mood Journey greens with the app palette`

---

### Task 5: Verify end-to-end and rebuild the APK

- [ ] **Step 1: Full regression** — `flutter test --dart-define=APP_ENV=staging` (baseline 1143 pass / 1 skip / 0 fail) and `flutter analyze`. Report real numbers.
- [ ] **Step 2: Functions tests** — `cd functions && npm test`.
- [ ] **Step 3: Rebuild** — `flutter build apk --debug --flavor staging --dart-define=APP_ENV=staging`. Record the path and source commit.
- [ ] **Step 4: Install** to the connected device with `adb install -r` (upgrade, preserving data) — **only after the user approves**.
- [ ] **Step 5: On-device verification**, which is the only proof that matters here:
  - log a mood, then log a **second** mood the same day — both save, both appear in My Mood Journey
  - send a message to a counselor — it sends, with no "College assignment could not be verified"
  - My Appointments and My Mood Journey greens match the palette, and appointment statuses are still visually distinct
- [ ] **Step 6: Report** changed files, commits, test results, deploy result, APK path, and anything still broken.

---

## Acceptance criteria

- A staging build lets any account log more than one mood per day, and each entry reaches My Mood Journey.
- `createMoodEntry` still refuses every account on production and development projects.
- Messaging sends without the college-assignment error.
- All four previously-missing callables are deployed; the other 108 are untouched.
- Greens on the named screens come from `AppColors`, and appointment status colours remain distinct.
- Development and production client builds behave exactly as before.
- Full staging suite green; `flutter analyze` clean.

## Rollback

- **Client:** revert the Task 2 and Task 4 commits, or build with `--dart-define=ENABLE_MOOD_V2=false` to restore one-check-in-per-day without touching the tree.
- **Server:** revert the Task 1 commit and redeploy `createMoodEntry` by name; the gate returns to the pilot allowlist. The three newly-deployed callables can be left in place — they are additive and nothing depended on their absence.
- **Data:** no migration, no schema change, nothing to undo. V2 entries written during the test period remain valid and owner-readable.
