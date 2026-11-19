# Back-up Data (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Super-admin-only Back-up Data page backed by Cloud Functions that run Firestore managed exports into a private bucket, record honest job status, verify output, and audit every step.

**Architecture:** A pure domain module (`backup_jobs.ts`) decides config, start guards, operation-state mapping and verification; a wiring module (`backup_management.ts`) injects the Firestore Admin export client, Storage client and Firestore so callables and the scheduler are testable with fakes. Job records live in `backup_jobs` (server-written, super-admin-read). The Flutter admin portal adds a `BackupJob` model, three repository methods and a page under the System navigation section.

**Tech Stack:** TypeScript Cloud Functions v2 (`firebase-functions/v2/https`, `v2/scheduler`, `params`), `@google-cloud/firestore` `v1.FirestoreAdminClient` and `@google-cloud/storage` (both bundled by `firebase-admin`), Firestore rules, Flutter/Dart, node:test, `@firebase/rules-unit-testing`, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-15-backup-data-design.md`

## Global Constraints

- No new npm or pub dependencies.
- No GCP resources created, no live exports, no Function deployment, no bucket/IAM changes in this PR.
- Job `status` ∈ `running | completed | failed`; `completed` requires verification `verified`.
- Params: `BACKUP_BUCKET` (unset ⇒ `failed-precondition` "Backup destination is not configured."), `BACKUP_RETENTION_DAYS` default `30`, `BACKUP_SCHEDULE_ENABLED` default `false`, `BACKUP_MANUAL_DAILY_LIMIT` default `3`.
- Export prefix: `gs://<bucket>/firestore-exports/<yyyyMMdd-HHmmss>-<jobId>`; metadata object checked: `firestore-exports/<yyyyMMdd-HHmmss>-<jobId>/<yyyyMMdd-HHmmss>-<jobId>.overall_export_metadata`.
- Coverage on every job: `{firestore: 'included', auth: 'excluded', storage: 'excluded'}`.
- Audit actions: `BACKUP_REQUESTED`, `BACKUP_COMPLETED`, `BACKUP_FAILED`, `BACKUP_SKIPPED`, category `SYSTEM`, targetType `backup_job`.
- Sanitised errors only: `{code, message}` with message ≤ 300 chars; never document contents, never stack traces.
- Navigation label exactly `Back-up Data`; visible only when `isSuperAdmin`.

## Review Focus

1. Export operation reports `done: true` with no `error` but the metadata object is absent (eventual consistency or wrong prefix) → job must be `failed`/`missing`, never `completed`. (Task 1, Task 3)
2. Two super-admin clicks within a second → exactly one running job; the second gets `failed-precondition` and no second export call. (Task 3)
3. Scheduler deployed with `BACKUP_SCHEDULE_ENABLED` unset → no job doc, no export call, no audit row. (Task 3)
4. Operation progress payload missing `progressDocuments`/`progressBytes` → progress `null`, job still `running`, no crash. (Task 1)
5. A non-super `admin` role, counselor, staff or student opening the page or querying `backup_jobs` → stream error surfaces as *not authorized*, never as *no backups yet*. (Task 4, Task 6)

---

### Task 1: Pure backup domain module

**Files:**
- Create: `functions/src/backup_jobs.ts`
- Test: `functions/src/backup_jobs.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export type BackupJobStatus = "running" | "completed" | "failed";
  export type BackupTrigger = "manual" | "scheduled";
  export type BackupVerification = {status: "pending" | "verified" | "missing"; metadataPath: string; checkedAt: Date | null};
  export type BackupProgress = {documents: {completed: number; estimated: number}; bytes: {completed: number; estimated: number}} | null;
  export type BackupError = {code: string; message: string} | null;
  export type BackupConfig = {bucket: string; retentionDays: number; scheduleEnabled: boolean; manualDailyLimit: number};
  export type BackupJobRecord = {status: BackupJobStatus; trigger: BackupTrigger; requestedBy: string; requestedAt: Date; operationName: string | null; progress: BackupProgress; verification: BackupVerification | null; error: BackupError};
  export const BACKUP_COVERAGE = {firestore: "included", auth: "excluded", storage: "excluded"} as const;
  export class BackupConfigError extends Error { constructor(public readonly code: "bucket-missing" | "invalid-number", message: string) }
  export function resolveBackupConfig(env: Record<string, string | undefined>): BackupConfig;      // throws BackupConfigError
  export function exportPrefixFor(bucket: string, now: Date, jobId: string): {outputUriPrefix: string; metadataPath: string};
  export function assertCanStart(jobs: BackupJobRecord[], now: Date, options: {trigger: BackupTrigger; manualDailyLimit: number}): void; // throws StartBlockedError(code: "job-running" | "manual-limit")
  export class StartBlockedError extends Error { constructor(public readonly code: "job-running" | "manual-limit", message: string) }
  export type OperationState = {done: boolean; error?: {code?: number; message?: string} | null; metadata?: {progressDocuments?: {completedWork?: string | number; estimatedWork?: string | number}; progressBytes?: {completedWork?: string | number; estimatedWork?: string | number}} | null};
  export function applyOperationState(operation: OperationState): {status: "running"} & {progress: BackupProgress} | {status: "failed"; error: BackupError} | {status: "exported"};
  export function verificationFor(metadataPath: string, exists: boolean, now: Date): BackupVerification;
  export function sanitizeError(error: unknown): NonNullable<BackupError>;
  export function summarizeJobs(jobs: Array<BackupJobRecord & {completedAt: Date | null}>): {lastVerifiedAt: Date | null; runningCount: number; lastStatus: BackupJobStatus | null};
  ```

- [ ] **Step 1: Write the failing tests** in `functions/src/backup_jobs.test.ts` (node:test, no emulator):

```ts
test("resolveBackupConfig applies defaults and rejects a missing bucket", () => {
  assert.deepEqual(resolveBackupConfig({BACKUP_BUCKET: "b"}), {bucket: "b", retentionDays: 30, scheduleEnabled: false, manualDailyLimit: 3});
  assert.equal(resolveBackupConfig({BACKUP_BUCKET: "b", BACKUP_SCHEDULE_ENABLED: "true", BACKUP_RETENTION_DAYS: "7", BACKUP_MANUAL_DAILY_LIMIT: "1"}).scheduleEnabled, true);
  assert.throws(() => resolveBackupConfig({}), (e: BackupConfigError) => e.code === "bucket-missing");
  assert.throws(() => resolveBackupConfig({BACKUP_BUCKET: "b", BACKUP_RETENTION_DAYS: "0"}), (e: BackupConfigError) => e.code === "invalid-number");
});
test("exportPrefixFor builds the dated prefix and metadata path", () => {
  const r = exportPrefixFor("bkt", new Date(Date.UTC(2026, 10, 15, 2, 30, 0)), "job1");
  assert.equal(r.outputUriPrefix, "gs://bkt/firestore-exports/20261115-023000-job1");
  assert.equal(r.metadataPath, "firestore-exports/20261115-023000-job1/20261115-023000-job1.overall_export_metadata");
});
test("assertCanStart blocks while a job runs and after the manual daily limit", () => {
  const now = new Date("2026-11-15T10:00:00Z");
  const job = (over: Partial<BackupJobRecord>): BackupJobRecord => ({status: "completed", trigger: "manual", requestedBy: "u", requestedAt: new Date("2026-11-15T09:00:00Z"), operationName: null, progress: null, verification: null, error: null, ...over});
  assert.throws(() => assertCanStart([job({status: "running"})], now, {trigger: "manual", manualDailyLimit: 3}), (e: StartBlockedError) => e.code === "job-running");
  assert.throws(() => assertCanStart([job({}), job({}), job({})], now, {trigger: "manual", manualDailyLimit: 3}), (e: StartBlockedError) => e.code === "manual-limit");
  assert.doesNotThrow(() => assertCanStart([job({}), job({}), job({})], now, {trigger: "scheduled", manualDailyLimit: 3}));
  assert.doesNotThrow(() => assertCanStart([job({requestedAt: new Date("2026-11-14T09:00:00Z")}), job({}), job({})], now, {trigger: "manual", manualDailyLimit: 3}));
});
test("applyOperationState maps running, failed and exported operations", () => {
  assert.deepEqual(applyOperationState({done: false, metadata: {progressDocuments: {completedWork: "10", estimatedWork: "100"}, progressBytes: {completedWork: 5, estimatedWork: 50}}}), {status: "running", progress: {documents: {completed: 10, estimated: 100}, bytes: {completed: 5, estimated: 50}}});
  assert.deepEqual(applyOperationState({done: false}), {status: "running", progress: null});
  assert.deepEqual(applyOperationState({done: true, error: {code: 7, message: "denied"}}), {status: "failed", error: {code: "export-7", message: "denied"}});
  assert.deepEqual(applyOperationState({done: true}), {status: "exported"});
});
test("verificationFor requires the metadata object", () => {
  const now = new Date();
  assert.equal(verificationFor("p/x.overall_export_metadata", true, now).status, "verified");
  assert.equal(verificationFor("p/x.overall_export_metadata", false, now).status, "missing");
});
test("sanitizeError strips stacks and truncates", () => {
  const e = sanitizeError(Object.assign(new Error("x".repeat(500)), {code: 13}));
  assert.equal(e.code, "export-13"); assert.equal(e.message.length, 300);
  assert.deepEqual(sanitizeError("boom"), {code: "unknown", message: "boom"});
});
test("summarizeJobs reports last verified completion and running count", () => { /* two jobs: one running, one completed+verified at T → lastVerifiedAt T, runningCount 1, lastStatus from newest requestedAt */ });
```

- [ ] **Step 2: Run** `cd functions && npx tsc && node --test lib/backup_jobs.test.js` → FAIL (module not found).
- [ ] **Step 3: Implement `functions/src/backup_jobs.ts`** with the Interfaces above. `exportPrefixFor` formats UTC `yyyyMMdd-HHmmss`. `assertCanStart` counts manual jobs with `requestedAt > now - 24h` regardless of status. Numeric `completedWork` may arrive as string → `Number()`, non-finite → `0`. `sanitizeError` code: numeric gRPC `code` ⇒ `export-<n>`, string `code` kept, else `unknown`.
- [ ] **Step 4: Run** the test → PASS. Also `npm run lint` if present (check `functions/package.json`); otherwise `npx tsc` clean.
- [ ] **Step 5: Commit** `feat(backup): add pure backup job domain module`.

### Task 2: Audit actions, collection constant, Firestore rules for `backup_jobs`

**Files:**
- Modify: `functions/src/audit.ts` (AUDIT_ACTIONS array, after `"ACADEMIC_CATALOGUE_IMPORTED"`)
- Modify: `firestore.rules` (after the `admin_audit_logs` block)
- Modify: `lib/database/firestore_collections.dart` (add `static const backupJobs = 'backup_jobs';`)
- Test: `functions/src/backup_rules.test.ts`

**Interfaces:**
- Produces: rule `match /backup_jobs/{jobId} { allow read: if isSystemAdmin(); allow write: if false; }`; audit actions listed in Global Constraints.

- [ ] **Step 1: Write the failing rules test** mirroring `functions/src/portal_staff_access_rules.test.ts` setup: users `admin` (`{accessRole:'admin', accountStatus:'active'}`), `other-admin` (same), `counselor`, `portal-staff`, `student`; `system_config/security {superAdminUid:'admin'}`; `backup_jobs/job-1 {status:'completed'}`. Assert: `admin` (verified token) `getDoc`/`getDocs` succeed; `other-admin`, `counselor`, `portal-staff`, `student` fail; `admin` `setDoc`/`updateDoc`/`deleteDoc` fail.
- [ ] **Step 2: Run** `firebase emulators:exec --only firestore --config <temp config on free ports> --project demo-mindmate-pr2 "cd functions && node --test lib/backup_rules.test.js"` → FAIL (`admin` read denied: no rule).
- [ ] **Step 3: Add** the rule block, the four audit actions, and the Dart constant.
- [ ] **Step 4: Run** the rules test → PASS; also rerun `lib/portal_staff_access_rules.test.js` (if present on this branch) / `lib/appointment_privacy_rules.test.js` → PASS.
- [ ] **Step 5: Commit** `feat(backup): guard backup_jobs collection and register audit actions`.

### Task 3: Backup callables and scheduler with injected clients

**Files:**
- Create: `functions/src/backup_management.ts`
- Modify: `functions/src/index.ts` (add `export {requestFirestoreBackup, refreshFirestoreBackupStatus, scheduledFirestoreBackup} from "./backup_management";` next to the other module re-exports)
- Test: `functions/src/backup_management.test.ts` (Auth + Firestore emulators; skip without `FIRESTORE_EMULATOR_HOST`)

**Interfaces:**
- Consumes: Task 1 exports; `requireSuperAdmin` from `./access`; `writeAudit`, `AUDIT_CATEGORIES` from `./audit`; `actorName` helper (check `functions/src/index.ts` for `actorName(actor)`; if not exported, reimplement locally as `String(profile.name ?? "").trim() || "Administrator"`).
- Produces:
  ```ts
  export type BackupDeps = {
    db: FirebaseFirestore.Firestore;
    exporter: {exportDocuments(request: {name: string; outputUriPrefix: string}): Promise<[{name?: string | null}]>; checkExportDocumentsProgress(name: string): Promise<OperationState>};
    objectExists(bucket: string, path: string): Promise<boolean>;
    env: Record<string, string | undefined>;
    projectId: string;
    now(): Date;
    newJobId(): string;
  };
  export function defaultDeps(): BackupDeps;                       // real FirestoreAdminClient/Storage, process.env, randomUUID
  export async function startBackup(deps: BackupDeps, actor: {uid: string; name: string; role: string}, trigger: BackupTrigger): Promise<{jobId: string; status: BackupJobStatus}>;
  export async function refreshBackup(deps: BackupDeps, actor: {uid: string; name: string; role: string}, jobId: string): Promise<{jobId: string; status: BackupJobStatus}>;
  export async function runScheduledBackup(deps: BackupDeps): Promise<{started: boolean; reason?: "disabled" | "job-running" | "not-configured"}>;
  export const requestFirestoreBackup: CallableFunction;   // onCall → requireSuperAdmin → startBackup(defaultDeps(), actor, "manual")
  export const refreshFirestoreBackupStatus: CallableFunction; // onCall({jobId}) → requireSuperAdmin → refreshBackup
  export const scheduledFirestoreBackup: ScheduleFunction;  // onSchedule({schedule:"every day 02:30", timeZone:"Asia/Manila", region:"asia-east1", timeoutSeconds:300}) → runScheduledBackup(defaultDeps())
  ```
  Job document fields exactly as the spec's Data section; `requestedAt`/`startedAt`/`completedAt` are Firestore `Timestamp`s; `revision` starts at 1 and increments on every update; `retentionDays` and `expiresAt` from config.

- [ ] **Step 1: Write the failing emulator tests** using a fake `exporter` (records calls; configurable `checkExportDocumentsProgress` result) and fake `objectExists`:
  1. `startBackup` as super-admin writes `backup_jobs/<id>` with `status:'running'`, `coverage`, `operationName:'op-1'`, `revision:1`, `expiresAt = requestedAt + 30d`, and one `admin_audit_logs` row `action:'BACKUP_REQUESTED'`, `targetType:'backup_job'`.
  2. `startBackup` with `env` lacking `BACKUP_BUCKET` throws `HttpsError` `failed-precondition` and writes no job.
  3. Second `startBackup` while the first is `running` throws `failed-precondition` (code message contains "already running") and `exporter.exportDocuments` was called once in total.
  4. `exporter.exportDocuments` rejecting ⇒ job `failed` with sanitised `error`, audit `BACKUP_FAILED`, `HttpsError` rethrown with code `internal`.
  5. `refreshBackup`: operation `{done:false, metadata:{progressDocuments:{completedWork:"4",estimatedWork:"8"}}}` ⇒ job still `running`, `progress.documents.completed === 4`, `revision:2`.
  6. `refreshBackup`: operation `{done:true}` + `objectExists → true` ⇒ `completed`, `verification.status:'verified'`, `completedAt` set, audit `BACKUP_COMPLETED`; calling `refreshBackup` again changes nothing (`revision` unchanged, no second audit row).
  7. `refreshBackup`: operation `{done:true}` + `objectExists → false` ⇒ `failed`, `verification.status:'missing'`, `error.code:'export-metadata-missing'`, audit `BACKUP_FAILED`.
  8. `runScheduledBackup` with `BACKUP_SCHEDULE_ENABLED` unset ⇒ `{started:false, reason:'disabled'}`, no job, no export call, no audit row.
  9. `runScheduledBackup` enabled with a running job ⇒ `{started:false, reason:'job-running'}` and one audit row `BACKUP_SKIPPED`; enabled with none running ⇒ `{started:true}` and a job with `trigger:'scheduled'`, `requestedBy:'system'`.
  10. Callable `requestFirestoreBackup.run({auth:{uid: counselorUid}})` rejects `permission-denied` (fixtures as in `access.test.ts`: create Auth users with `emailVerified:true`, set `process.env.SUPER_ADMIN_UID` to the admin uid).
- [ ] **Step 2: Run** `firebase emulators:exec --only auth,firestore --config <temp> --project demo-mindmate-pr2 "cd functions && node --test lib/backup_management.test.js"` → FAIL (module not found).
- [ ] **Step 3: Implement `functions/src/backup_management.ts`**. `startBackup` runs guard + job creation inside one `db.runTransaction` (query `backup_jobs` ordered by `requestedAt desc` limit 50 for the guard), then calls `exportDocuments` outside the transaction, then updates the job (`operationName`, `startedAt`) or marks it failed. `refreshBackup` is a transaction that reads the job, returns early when terminal, and applies `applyOperationState` + verification. Database path: `projects/${projectId}/databases/(default)`; `projectId` from `process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT`. Map `BackupConfigError` → `HttpsError("failed-precondition", "Backup destination is not configured.")`, `StartBlockedError` → `failed-precondition`.
- [ ] **Step 4: Run** the suite → PASS; `npx tsc` clean; `npm run build`.
- [ ] **Step 5: Commit** `feat(backup): add Firestore export callables and gated scheduler`.

### Task 4: Flutter model and repository methods

**Files:**
- Create: `lib/features/admin/domain/backup_job.dart`
- Modify: `lib/repositories/admin_portal_repository.dart` (near `watchAdminAudit` / `_callCallable`)
- Test: `test/features/admin/backup_job_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum BackupJobStatus { running, completed, failed; static BackupJobStatus parse(Object? v) }   // unknown → failed
  enum BackupVerificationStatus { pending, verified, missing; static parse(Object?) }           // unknown → pending
  class BackupJob { id, status, trigger ('manual'|'scheduled'), requestedBy, DateTime requestedAt, DateTime? startedAt, DateTime? completedAt,
                    int? documentsCompleted, int? documentsEstimated, BackupVerificationStatus verification, String? errorCode, String? errorMessage,
                    Map<String,String> coverage, int retentionDays, DateTime? expiresAt; factory fromJson(Map<String,dynamic> json, {String? id}); bool get isTerminal; }
  class BackupSummary { DateTime? lastVerifiedAt; bool hasRunning; BackupJob? latest; factory fromJobs(List<BackupJob>) }
  // repository
  Stream<List<BackupJob>> watchBackupJobs();                 // empty stream unless isSuperAdmin; newest first
  Future<String> requestFirestoreBackup();                    // _callCallable('requestFirestoreBackup', {}) → jobId
  Future<void> refreshBackupJobStatus(String jobId);          // _callCallable('refreshFirestoreBackupStatus', {'jobId': jobId})
  ```
- [ ] **Step 1: Write failing tests**: `fromJson` parses Firestore-shaped map (Timestamps via existing `dateTimeFromFirestore` from `lib/core/utils/firestore_mapper.dart`), unknown status → `failed`, missing progress → nulls, `isTerminal`; `BackupSummary.fromJobs` picks newest and last verified `completedAt`; `AdminPortalRepository(callableInvoker: fake)` → `requestFirestoreBackup()` calls `'requestFirestoreBackup'` and returns `jobId` from `{'jobId': 'j1'}`; `refreshBackupJobStatus('j1')` passes `{'jobId': 'j1'}`.
- [ ] **Step 2: Run** `flutter test test/features/admin/backup_job_test.dart` → FAIL (compile).
- [ ] **Step 3: Implement** model and repository methods (`watchBackupJobs` uses `_firestoreService.watchDocuments(FirestoreCollections.backupJobs, orderBy: 'requestedAt', descending: true, limit: 50)`).
- [ ] **Step 4: Run** test → PASS; `flutter analyze` clean.
- [ ] **Step 5: Commit** `feat(backup): add BackupJob model and repository bindings`.

### Task 5: Back-up Data page

**Files:**
- Create: `lib/features/admin/screens/backup_data_page.dart`
- Test: `test/features/admin/backup_data_page_test.dart`

**Interfaces:**
- Consumes: Task 4 model and repository methods.
- Produces: `class BackupDataPage extends StatefulWidget { const BackupDataPage({super.key, required this.repository}); }`.
- Copy pinned by the spec: title `Back-up Data`; coverage card rows `Firestore database — Included`, `Firebase Authentication users — Excluded in Phase 1`, `Storage files — Excluded in Phase 1`; button `Request backup now`; confirm dialog text contains `one managed Firestore export` and `may incur Google Cloud charges`; state messages: loading `Loading backup history…`; unauthorized `Backup history requires the configured super-administrator account.`; not configured (callable `failed-precondition`) `Backup destination is not configured. Ask the operator to set BACKUP_BUCKET before requesting a backup.`; generic callable error `Backup request failed (<code>).`; empty `No backups have been recorded yet.`

- [ ] **Step 1: Write failing widget tests** with a repository subclass overriding `watchBackupJobs`, `requestFirestoreBackup`, `refreshBackupJobStatus`, `isSuperAdmin`:
  1. Stream error ⇒ unauthorized text shown, button absent.
  2. Empty list ⇒ empty text, coverage card rows present, button enabled.
  3. One running + one completed/verified job ⇒ rows show `Running` / `Completed · Verified`, button disabled while running, `Refresh status` present on the running row.
  4. Tap button → dialog → confirm ⇒ `requestFirestoreBackup` called once; when it throws `FirebaseFunctionsException(code: 'failed-precondition')` the not-configured text appears.
  5. No bucket link or `gs://` text anywhere (`find.textContaining('gs://')` ⇒ nothing).
- [ ] **Step 2: Run** `flutter test test/features/admin/backup_data_page_test.dart` → FAIL.
- [ ] **Step 3: Implement** the page (reuse `AdminColors`, `StreamBuilder`, `ValueNotifier` not needed; a `_busy` flag like `StaffQueueRefreshButton`).
- [ ] **Step 4: Run** → PASS; `flutter analyze` clean.
- [ ] **Step 5: Commit** `feat(backup): add Back-up Data admin page`.

### Task 6: Navigation wiring

**Files:**
- Modify: `lib/features/admin/screens/admin_portal.dart` — `AdminPortalPage` enum (add `backupData` before `profile`), `label` (`'Back-up Data'`), `icon` (`Icons.backup_outlined`), `_buildPage` (`AdminPortalPage.backupData => BackupDataPage(repository: _repository)`), `_allowed` (`AdminPortalPage.backupData => isSuperAdmin`), `_NavSection('System', [AdminPortalPage.backupData, AdminPortalPage.profile])`.
- Test: `test/features/admin/backup_navigation_test.dart` (mirror `test/features/admin/announcement_navigation_test.dart` for how the nav rail is pumped).

- [ ] **Step 1: Write failing tests**: with `isSuperAdmin: true, accessRole: admin` the rail shows `Back-up Data`; with `isSuperAdmin: false` (admin, counselor, portalStaff) it does not.
- [ ] **Step 2: Run** → FAIL (enum value missing).
- [ ] **Step 3: Implement** the six edits.
- [ ] **Step 4: Run** this test plus `test/features/admin/announcement_navigation_test.dart` and `test/features/admin/admin_portal_leave_guard_test.dart` → PASS; `flutter analyze` clean.
- [ ] **Step 5: Commit** `feat(backup): expose Back-up Data to the super-administrator`.

### Task 7: Operations runbook and exclusions

**Files:**
- Create: `docs/operations/firestore-backup-runbook.md`
- Modify: `functions/.env.example` if it exists (add the four params with comments); otherwise document them only.

- [ ] **Step 1: Write** the runbook with sections: Scope and exclusions (Auth, Storage, PITR); Required Google Cloud permissions (service agent `roles/storage.admin` on bucket; Functions SA `roles/datastore.importExportAdmin` + `roles/storage.objectViewer` on bucket; note current `roles/editor` over-privilege); Bucket creation commands (same project, `asia-east1`, uniform access, public access prevention, retention policy = `BACKUP_RETENTION_DAYS`, lifecycle delete after the same, Google-managed encryption default, CMEK optional) marked **requires separate authorization**; Deploy-by-name commands; Enabling the schedule; Cost estimate (from the spec); Monitoring (job doc fields, audit actions, budget alert); Restore drill into an isolated project (`gcloud firestore import`), verification checklist, and the rule that production restore needs its own authorization and a pre-restore export; Alternatives (Firestore scheduled backups, PITR) with trade-offs.
- [ ] **Step 2: Check** `git diff --check` clean.
- [ ] **Step 3: Commit** `docs(backup): add Firestore backup runbook and Phase 1 exclusions`.

### Task 8: Verification gate and PR

- [ ] `cd functions && npm run build && node --test lib/backup_jobs.test.js` → PASS.
- [ ] Emulator runs: `backup_rules.test.js`, `backup_management.test.js`, plus existing rules suites (`appointment_privacy_rules`, `announcements_rules`, `mind_aid_emergency_rules`) → all PASS.
- [ ] `flutter analyze` → No issues; `flutter test test/features/admin test/models test/repositories` → PASS.
- [ ] `git diff --check`; confirm no `gs://`, bucket name or credentials in Flutter code; confirm no new dependencies in `pubspec.yaml`/`functions/package.json`.
- [ ] Push `feat/pr2-backup-data`; write PR body: problem, design link, permissions, cost estimate, exclusions, tests run, what needs separate authorization (bucket, IAM, deploy, enabling schedule, restore drill). Do not merge.
