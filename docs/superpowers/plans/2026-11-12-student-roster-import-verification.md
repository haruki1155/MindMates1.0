# Student roster import — final verification (Task 12)

Branch `feat/student-roster-import` at `f61a159` (worktree `.worktrees/student-roster-import`).
Verified against the already-running shared emulator: Firestore `127.0.0.1:8380`, Auth `127.0.0.1:9399`,
project `demo-mindmate-roster`, `SUPER_ADMIN_UID=super-admin-test`. No emulator was started or stopped;
nothing was pushed or deployed.

## 1. Suites run (real exit codes and counts)

| Suite | Command | Exit | Result |
| --- | --- | --- | --- |
| Functions build | `npm --prefix functions run build` | 0 | clean (`tsc`, no diagnostics) |
| Functions tests (all) | `npm --prefix functions test` | 1 | 263 tests, 261 pass, **1 fail (pre-existing)**, 1 skip, 69.1 s |
| Firestore rules | `node --test functions/lib/student_roster_rules.rules.js functions/lib/profile_rules.rules.js` | 0 | 11 tests, 11 pass, 0 fail |
| Flutter analyze (project) | `flutter analyze` | 0 | "No issues found!" |
| Flutter tests (all) | `flutter test` | 1 | 761 pass, **31 fail (all pre-existing, assessment area)** |
| Flutter tests (feature scope) | `flutter test test/features/admin test/features/authentication test/features/student_info test/models test/repositories test/features/profile` | 0 | 280 pass, 0 fail |
| Whitespace / dirt | `git diff --check`, `git status -s` | 0 | no whitespace errors; only `pubspec.lock` + generated plugin registrant files dirty (from `flutter pub get`), as expected |

### The one functions failure is the known, unrelated one
`lib/mood_entries_callable_emulator.test.js` → "authenticated non-pilot is rejected by `createMoodEntryDev`
without a Firestore write": expected `functions/permission-denied`, got `functions/internal`, because it calls
the Functions emulator on `:5001`, which is not running in this shared setup. It is the **only** failing test,
no new failures appeared, and the single skip is the same file's pilot test, skipped because
`MOOD_V2_TEST_PILOT_UID` is unset. Nothing in the roster feature is involved.

### The 31 Flutter failures are pre-existing and unrelated
All of them live in the assessment area: `student_v4_completion_test.dart` (11),
`assessment_flow_controller_test.dart` (8), `student_assessment_calculator_test.dart` (6),
`quick_assessment_test.dart` (3), `workplace_v4_assessment_test.dart` (2), `home_screen_test.dart` (1) —
a mix of 30-second `TimeoutException`s, `[core/no-app] No Firebase App '[DEFAULT]'`, and stale
expectation mismatches. Evidence they are not ours: `git diff --name-only 33fc099^ HEAD -- '*.dart'`
(every roster-feature commit, `docs(spec)` through `f61a159`) touches **none** of those files or their
sources, and the last commits to touch them (`05ebc20`, `6dd17e6`, `bd2cddc`, `faa22b7`) all predate the
feature branch. The 280 tests covering the roster feature itself pass. These failures were left alone.

## 2. End-to-end walkthrough (real callables, shared emulator)

Driven by a throwaway script (`.superpowers/sdd/2026-11-12-student-roster-import/walkthrough.js`,
intentionally **not committed**) that invokes the exported callable handlers via
`.run({auth: {uid}, data})` with a unique `WT<timestamp>` prefix, asserts each step, and deletes every
document and Auth user it creates. Final run: **exit 0, all 11 steps PASS**; a post-run sweep of
`student_roster`, `student_activation_attempts`, `student_id_reservations`,
`student_correction_requests`, `student_personal_info`, `student_roster_imports`, `admin_audit_logs`,
`users`, `colleges`, `courses`, `departments` found zero leftovers.

| # | Step | Result |
| --- | --- | --- |
| 1 | Admin previews then imports 4 rows (3 new + 1 pre-existing legacy account) | PASS — preview `["new","new","link","new"]`, counts `{new:3, update:0, link:1, error:0}`; commit `status:"complete"`, `{new:3, updated:0, linked:1}`, **3 codes (new rows only)**, no code for the linked row; link row `activated:true`, `userId` = legacy uid, `activationCode:null`; legacy `users` doc gets `rosterLinked:true`, `personalInfoRequired:true`, refreshed academics, **name fields untouched**; `STUDENT_ROSTER_IMPORTED` audit written |
| 2 | Student activates with Student No. + real code + DOB (lowercase, spaced Student No., lowercase code) | PASS — `{ok:true,email}`; Auth user created, profile `personalInfoRequired:true`, `rosterLinked:true`, `verifiedBy:"roster-activation"`; `student_id_reservations` entry created; roster `activated:true`, `activationCode:null`, `consumedActivationCode` stored |
| 3 | `resolveSchoolIdAuthEmailDev` for `2021-00123` / `2021 00123` / `202100123` spellings | PASS — all three return the activated email |
| 4 | Student saves Student Information with consent | PASS — `{ok:true}`; `personalInfoRequired:false`, `users.gender` seeded from Sex, `privacyConsent.policyVersion = "2026-11-ra10173-v1"`, cellphone normalized to `09171234567` |
| 5 | Student edits again (`privacyConsent:false`) | PASS — new value saved, consent `acceptedAt`/`policyVersion` unchanged |
| 6 | Student requests a `yearLevel` correction → admin approves | PASS — pending request visible to the student, official name read from the roster; approve updates roster **and** `users` to `3rd Year`; exactly one `STUDENT_CORRECTION_APPROVED` audit |
| 7 | Counselor views the student's information | PASS — response is exactly `{official, personal}`; `official` is the 9-field allowlist; no `privacyConsent`/`userId` leak; one `STUDENT_PERSONAL_INFO_VIEWED` audit with `actorId` = counselor, `category: SECURITY` |
| 8 | Portal staff attempts the same view | PASS — `permission-denied`, and **no** audit entry written |
| 9 | Old self-registration path (`provisionAppUserProfileDev`, student-role email) | PASS — `failed-precondition` with the exact copy `Students activate accounts through the roster. Tap 'Activate student account'.` |
| 10 | Admin revokes a wrongful activation, student re-activates | PASS — Auth user disabled; roster `activated:false`, `userId:null`, `consumedActivationCode:null`, fresh `activationCode`, `revokedUserIds:[uid]`; `users.accountStatus:"revoked"`; reservation deleted; `STUDENT_ACTIVATION_REVOKED` audit; re-activation with the new code succeeds and relinks the row |
| 11 | Failure paths and lockout | PASS — wrong code, wrong DOB, unknown Student No. and a deactivated row all return the identical `not-found` / `Those details don't match our records.`; the 5th failure on one Student No. sets `failedCount:5` + `lockedUntil`, and a subsequent attempt with the **correct** code returns the same generic error |

Not exercised here: the email-verification link itself (Task 12 brief step 2). Roster activation
deliberately creates the Auth user with `emailVerified:false` and `verifiedBy:"roster-activation"`, so the
verification mail belongs to the pre-existing registration flow and has its own coverage
(`email_verification_screen_test.dart`, `account_recovery_email.test.ts`).

## 3. Deviations and findings

1. **Missing composite indexes for combined roster filters (fixed here).** The admin Student Roster page
   sends `search` + `status` + `yearLevel` independently, so `listStudentRoster` can issue
   `yearLevel ==` + `status ==` (+ `activated ==`) together with a `surnameNormalized` range and
   `orderBy`. The declared index set only covered one filter at a time. Firestore requires a composite
   index whenever equality filters are combined with a range on another field, and the emulator does not
   enforce indexes, so the suites could not catch this. Added to `firestore.indexes.json`:
   `student_roster (yearLevel, status, surnameNormalized)` and
   `student_roster (yearLevel, status, activated, surnameNormalized)`.
2. **Missing composite index for the audit filter + module filter (fixed here).** The audit log dialog
   lets an admin pick a category *and* the action "Student information viewed", producing
   `actorId ==` + `category ==` + `action ==` + `orderBy createdAt desc`; only
   `(actorId, action, createdAt)` was declared. Added `admin_audit_logs (actorId, category, action, createdAt desc)`.
   Without it the page falls back to its "a required database index is not deployed" message rather than
   failing silently, which is how the gap was traced.
3. **Pre-existing, left alone:** the same category+action combination on the *staff* side
   (`targetUserId ==` + `category ==` + `action ==` + `orderBy createdAt`) also has no composite index.
   It predates this branch (`targetUserId+category+createdAt` and `targetUserId+action+createdAt` are both
   older entries) and is out of scope for this feature.
4. **`users.college` is not refreshed by import or link.** `userAcademicFields` writes `schoolId`,
   `dateOfBirth`, `collegeId`, `courseId`, `departmentId`, `department`, `course`, `yearLevel`,
   `populationRole` — the college *display name* is absent, so a linked legacy account keeps a stale
   `users.college` string while its `collegeId` is correct. This matches the spec's explicit field list
   (design §Data model, `users/{uid}`) and is harmless in practice: the Dart `UserModel` carries only
   `collegeId`, and every official view reads the roster. Recorded, not changed.
5. **Rollout step 4 cannot be staged separately.** Spec §5 orders the rollout as
   (1) rules/callables/admin page → (2) import → (3) app release → (4) "deploy the student-provisioning
   block". The block is an unconditional `assertSelfProvisioningAllowed` inside
   `provisionAppUserProfileHandler` (`functions/src/account_integrity.ts`), so it goes live with the very
   first functions deploy in step 1; there is no flag that defers it. See the ordering note in the
   checklist below.

No other spec deviation was found: activation input is Student No. + code + DOB, codes are issued only for
new unlinked rows, the generic mismatch copy and lockout thresholds match the global constraints, audits
use the mandated action names and categories, and the counselor read is allowlisted.

## 4. Deployment checklist

### 4.1 Indexes that MUST be deployed before the feature works in production
`firebase deploy --only firestore:indexes` (all are in `firestore.indexes.json`; Firestore builds them
asynchronously — wait for "Enabled" before step 2 of the rollout):

Audit log (`admin_audit_logs`):
- `actorId ASC, action ASC, createdAt DESC` — the "Student information viewed" audit filter (actor-scoped action).
- `actorId ASC, category ASC, action ASC, createdAt DESC` — that filter combined with a module/category filter.
- `targetId ASC, action ASC, createdAt DESC` — **compliance query: "who viewed student X's information".**
  View audits carry `targetId` (the student) with `targetUserId: null`, so without this index the question
  cannot be answered in production at all. Index only; no callable or UI reads it yet.

TTL policy (`fieldOverrides`, same file and same deploy command):
- `student_activation_attempts.expiresAt` with `ttl: true` — the attempts collection is written from an
  **unauthenticated** endpoint, keyed by any canonical-shaped Student No., so without the policy enabled it
  grows without bound. Each doc now carries `expiresAt` = now + lockout window (30 min) + 24 h. Confirm the
  TTL policy reaches "Serving" in the Firestore console after the deploy; until it does, nothing is swept.

Roster search and filters (`student_roster`):
- `collegeId ASC, surnameNormalized ASC`
- `courseId ASC, surnameNormalized ASC`
- `yearLevel ASC, surnameNormalized ASC`
- `status ASC, surnameNormalized ASC`
- `status ASC, activated ASC, surnameNormalized ASC`
- `yearLevel ASC, status ASC, surnameNormalized ASC`
- `yearLevel ASC, status ASC, activated ASC, surnameNormalized ASC`

Without these, the roster list and the audit filter return `FAILED_PRECONDITION` and the admin page shows
its load error instead of data.

### 4.2 Rollout order (spec §5, with the step-4 correction)
1. Deploy `firestore.rules` and `firestore.indexes.json`, then the functions, then the admin Student
   Roster page. **Note:** this deploy also turns on the student self-provisioning block (finding 5), so
   publish the app release (step 3) first, or accept that students on the old build cannot self-register
   during the window. Recommended order in practice: indexes → app release (step 3) → rules + functions +
   admin page → import.
2. Admin imports the roster, reviews the "Legacy – not in roster" list, and downloads the activation-slip
   file (plain codes are returned exactly once — they are never logged or stored).
3. Release the app update carrying activation, the Student Information form, and the employee-only Sign Up.
4. Confirm the block is live: a student-role email hitting `provisionAppUserProfile` must fail with
   `Students activate accounts through the roster. Tap 'Activate student account'.`
5. Run the one-time admin migration `backfillStudentInfoRequirement` (sets `personalInfoRequired: true` on
   existing student profiles without `student_personal_info` and reports students with no roster row).
   **Ruling R19 — this step has no UI entry point and will not happen by itself.** `backfillStudentInfoRequirement`
   is an admin callable with no button, link or menu item anywhere in the app or the admin portal; it must be
   invoked deliberately at rollout from a console or script, authenticated as the configured `SUPER_ADMIN_UID`
   (for example `firebase functions:shell` → `backfillStudentInfoRequirement({})`, or a small admin-SDK script
   calling the callable). The first-login Student Information gate keys off `personalInfoRequired`, which legacy
   student profiles do not have, so **until this migration is run the gate never fires for any legacy student** —
   they reach Home with the mandatory consent form unfilled and the rollout is silently incomplete. Verify
   afterwards by spot-checking that a known legacy student profile now carries `personalInfoRequired: true` and
   is sent to the form on next sign in (both the password and the Google sign-in paths enforce it).
6. Spot-check in production: one activation end to end, one counselor view (confirm the
   `STUDENT_PERSONAL_INFO_VIEWED` entry appears in the audit log), and one admin correction approval.

Pre-deploy reminders: `SUPER_ADMIN_UID` must be configured for the functions runtime (admin callables fail
with `failed-precondition` otherwise), and App Check must be live for the enforced
`activateStudentAccount` variant (staging aliases to `activateStudentAccountDev`).
