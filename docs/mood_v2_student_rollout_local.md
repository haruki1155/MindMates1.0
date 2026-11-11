# Mood V2 student rollout: local implementation checkpoint

Scope: local only, 2026-11-10. No deployment, remote configuration, device action, or live writes authorized or performed.

## Policy

`MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED` is a server-side Boolean parameter, default false. Only the protected `createMoodEntry` handler opts into the student path. The Dev handler remains pilot-only, even when the parameter is true. Client payloads cannot select a handler, rollout state, identity, profile role/status, or authoritative event time.

Both paths retain the existing eligible-app-user check and exact `mindmate-staging` project requirement. The synthetic pilot allowlist retains its existing profile policy. Non-pilot access additionally requires the server flag, an app-user student profile, all supplied population/declared/legacy role fields to agree on student, and accountStatus either absent or exactly active. Explicit null or invalid status is denied for non-pilots. Absent status remains compatible with current legitimate provisioning. Inconsistent historical role fields fail closed; do not repair real profiles automatically.

Local Rules deny client profile creation and changes/removal of protected role/status fields. Role-correction requests do not change eligibility until trusted administrator review. Mood V2 Rules remain owner-read-only, with all direct writes denied. No Rules/index/schema changes are needed by this patch.

Protected App Check enforcement remains true. UID, timestamps, Manila dates, idempotency transactions, legacy records and activity streaks retain their existing behavior. Handler `.run` tests bypass HTTP middleware and are not live App Check acceptance evidence.

## Verification

Root cause: the existing staging pilot-only gate rejects ordinary students. Five files changed: backend policy, backend tests, Rules tests, example configuration, and this handoff. No existing Flutter source/test files were changed.

| Check | Result |
| --- | --- |
| Functions TypeScript build | PASS, exit 0 |
| Backend/Rules/HTTP middleware suite | 35 pass, 0 fail, 0 skip, exit 0 |
| Enabled Mood V2 focused Flutter suite | 56 pass, 0 fail, exit 0 |
| Flutter analyzer | No issues, exit 0 |
| Bare Flutter full suite (development default) | 601 pass, 31 fail, exit 1 |
| Full Flutter suite using documented staging configuration | 631 named pass, 104 loading events, 0 fail/skip, exit 0 |
| Midnight retry diagnostic | 0 pass, 1 fail, exit 1; separate existing defect reproduced |
| Network-isolated staging-identity callable suite | BLOCKED: Docker unavailable; no tests ran |
| Diff whitespace and original-file hash checks | PASS; all nine pre-existing files byte-for-byte unchanged |

Initial test-first build failed because the new server-path argument did not exist. Emitted JavaScript run against the original implementation produced 31 passes and 2 expected failures: the new positive student-rollout and absent-account-status cases received permission-denied. These passed after implementation. Additional security checks then increased the final backend total to 35.

The bare full suite is not passing. Example failures included assessment preview requests expected length 1 but actual 0, expected recoverableError but actual answering, and a delayed-preview test timeout. Assessment V4 is explicitly gated to staging; repository CI and existing Mood documentation specify APP_ENV=staging. The subsequent documented staging run passed without changing application code or assertions. Do not describe the bare command as passing.

Exact verification commands, from the canonical repository (PowerShell):

```powershell
# Cached emulator only; launched directly, loopback and disposable demo identity.
$env:GCLOUD_PROJECT='demo-mindmate-mood-v2-phase2'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8187'
java -jar "$env:USERPROFILE/.cache/firebase/emulators/cloud-firestore-emulator-v1.22.0.jar" --host 127.0.0.1 --port 8187 --project_id demo-mindmate-mood-v2-phase2

# Separate shell with the same demo project and emulator variables:
npm.cmd run build --prefix functions
node --test --test-concurrency=1 functions/lib/mood_entries.test.js functions/lib/mood_entries_rules.test.js
# Final run redirected output to C:/Users/Mj/.codex/tmp/mood-v2-phase2-backend.txt.
flutter analyze
flutter test --reporter expanded
flutter test --dart-define=APP_ENV=staging --reporter json > C:/Users/Mj/.codex/tmp/mood-v2-phase2-flutter-staging.jsonl 2> C:/Users/Mj/.codex/tmp/mood-v2-phase2-flutter-staging.stderr.txt
flutter test --reporter expanded --dart-define=APP_ENV=staging --dart-define=ENABLE_MOOD_V2=true --dart-define=ENABLE_MOOD_V2_PROVIDER_READ=true --dart-define=ENABLE_MOOD_V2_HOME_READ=true --dart-define=ENABLE_MOOD_V2_PROFILE_READ=true --dart-define=ENABLE_MOOD_V2_HISTORY_READ=true --dart-define=ENABLE_MOOD_V2_INSIGHTS_READ=true test/features/mood/log_mood_screen_test.dart test/providers/mood_provider_test.dart test/features/home/home_screen_test.dart test/features/insights/insight_mood_v2_metrics_test.dart
flutter test C:/Users/Mj/.codex/tmp/mood_v2_midnight_retry_diagnostic_test.dart --reporter expanded
$env:MOOD_V2_TEST_PILOT_UID='mood-v2-local-synthetic'
$env:MOOD_V2_STAGING_PILOT_UIDS='mood-v2-local-synthetic'
bash ci/run_mood_v2_staging_identity_docker.sh
# MODE_B=BLOCKED: Docker is unavailable; staging-identity tests were not run.
git diff --check
```

Backend tests used only the loopback Firestore emulator and synthetic profiles. Server handler tests temporarily select staging identity in process configuration while the initialized Firestore client remains pinned to the demo emulator. The HTTP wrapper test also binds loopback and verifies missing-App-Check rejection before the business handler. Valid-token acceptance and the complete Auth/Functions emulator transport remain unverified. No hosted state is inferred from local tests. Expected PERMISSION_DENIED messages from negative Rules tests are passing denial assertions, not test failures.

App Check enforcement stays true on the protected callable; missing-token HTTP rejection was verified locally. Dev isolation was verified through the actual exported callable handlers with student rollout enabled. The full network-isolated authenticated callable transport suite remains blocked.

## Separate issue: midnight retry

A focused widget diagnostic copied the existing test harness outside the repository to `C:/Users/Mj/.codex/tmp/mood_v2_midnight_retry_diagnostic_test.dart`. A failed save before Manila midnight followed by a retry after midnight used a different request UUID. Expected retained first UUID; actual second UUID. This can defeat retry deduplication after an uncertain outcome. The diagnostic fails as intended (0 pass, 1 fail). No Flutter source or existing test file was modified. A fix requires separate approval.

## Next checkpoint: deployment readiness review

Do not deploy from this dirty working tree. First resolve/approve treatment of the midnight retry issue and complete blocked callable integration. Review the exact source artifact, relevant client flags, effective staging configuration, and a fresh read-only inventory under separate authorization. Local evidence does not establish current deployed revisions, allowlists, Rules or indexes.

Proposed deployment scope, only after separate explicit authorization:

```powershell
firebase.cmd deploy --only functions:createMoodEntry --project mindmate-staging
```

Dev and all unrelated functions must remain outside deployment scope. Preserve App Check and production configuration. General-student activation requires the staging student parameter true; default false remains closed except approved pilots. Do not change private environment files during preparation.

Before deployment, capture current protected-function configuration, serving revision/traffic and approved rollback artifact in private evidence storage without credentials or student content. After deployment, verify ready revision, exact staging project, effective parameter, App Check, and 100 percent intended traffic; separately authorized synthetic acceptance must demonstrate protected success, Dev rejection, production exclusion, replay/conflict handling, history and streaks. Do not predict a revision identifier.

Rollback: under separate authorization disable the student parameter and redeploy only the protected function, or restore the captured known-good revision/artifact using the reviewed procedure. Clear the pilot allowlist as well if all writes must close. Verify effective configuration, serving traffic and non-pilot rejection. Preserve every existing mood record; no data rollback or deletion.

No-go: failed checks, unresolved acceptance/security defects, unavailable isolated callable evidence, unexpected resource/deletion prompts, wrong project, or missing deployment/live-test authorization. Current status is no-go for deployment and live acceptance.
