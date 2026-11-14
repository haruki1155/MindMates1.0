# Back-up Data (Phase 1: Firestore managed export) — Design

**Date:** 2026-11-15  
**Requirement:** PACC Web evaluator comment #5 (PR 2 of the 11-requirements plan)  
**Branch:** `feat/pr2-backup-data` (worktree `.worktrees/pr2-backup-data`, based on `origin/main` 230e14b)  
**Status:** Approved scope (Firestore-only Phase 1). Builder calls are marked **[call]** and listed at the end for review.

## Intent

Give the PACC super-administrator a trustworthy **Back-up Data** page: request a backup, see real job status, timestamps, coverage, verification result and errors, and know that a backup exists off-database. Backups are produced by Google Cloud Firestore's managed export into a private Cloud Storage bucket. The web application never carries or downloads database contents.

## Goals

1. Super-admin-only backup initiation and status monitoring, enforced server-side (callables) and in Firestore rules.
2. Honest status: a job is `completed` only when the export operation finished **and** the export metadata file was found in the bucket; otherwise `failed` or `running`.
3. Audit trail for every request, completion and failure.
4. Clear coverage statement: Firestore included; Firebase Authentication and Cloud Storage files **excluded in Phase 1**.
5. Cost and blast-radius safeguards: one running job at a time, a manual-request cap, scheduler disabled until explicitly enabled.
6. Documented IAM, encryption, retention and a restore drill that targets an isolated project only.

## Non-goals (Phase 1)

- Exporting Firebase Auth users or Storage files.
- Deleting old exports from code (retention is a bucket lifecycle rule, documented, applied by an operator).
- Restore from the web app. Restore is an operator runbook into an isolated test project.
- Creating the bucket, IAM bindings or any paid resource in this PR. Deploying Functions.
- Per-collection selection in the UI (export is whole-database).

## Anti-goals

- A job that reads `completed` while the bucket is empty or the operation errored.
- Any signed URL, file listing or document content reaching the browser.
- A scheduler that silently starts billing the moment the Function is deployed.

## Constraints and findings

- `firebase-admin` 13.10 bundles `@google-cloud/firestore` 7.11 (`v1.FirestoreAdminClient.exportDocuments`, `checkExportDocumentsProgress`) and `@google-cloud/storage`; **no new dependencies**.
- Staging Firestore: Native mode, **asia-east1**, point-in-time recovery disabled. Export bucket must be in the same location (or a multi-region containing it) and in the same project.
- Staging has 61 top-level collections, 5,190 top-level documents (subcollection documents not counted; assume ≤ 20k total).
- Functions runtime service account (`978195258114-compute@developer.gserviceaccount.com`) currently holds `roles/editor` on staging. That already includes export permission, but is over-privileged; the runbook recommends a dedicated service account.
- Existing patterns reused: `requireSuperAdmin` (`functions/src/access.ts`), `writeAudit`/`AUDIT_CATEGORIES.system` (`functions/src/audit.ts`), `onSchedule` with `region: "asia-east1"`, `defineString` params, `AdminPortalRepository._callCallable`, super-admin-gated navigation (`_allowed` + `isSuperAdmin`), `admin_audit_logs` rule shape (`isSystemAdmin()` read, no client writes).

## Approaches considered

| | Approach | Trade-offs |
|---|---|---|
| **A (chosen)** | **Managed export from a Cloud Function** (`exportDocuments` → private GCS bucket), manual callable + optional daily schedule, job records in Firestore, status page in the admin web app | Off-database copy the team controls; per-job audit and verification; importable to another project for drills. Costs one document read per exported document plus GCS storage. Needs bucket + IAM setup. |
| B | **Firestore scheduled backups** (`gcloud firestore backups schedules create`, daily/weekly, retention up to 14 weeks) | Zero code, no read charges, managed retention. But: backups live inside Firestore (not a bucket the team can inspect), restore only creates a whole new database, no per-job verification hook or app-visible history without extra polling code, and the admin page would be a thin wrapper over `gcloud`. Recommended as a **complementary** operator-level safety net, not as the audited admin feature. |
| C | **Point-in-time recovery** (7-day) | Protects against accidental writes, not against project loss; nothing to show as a "backup job"; billing change on the database itself. Not a substitute. |

A is implemented; B and C are documented in the runbook as optional additions requiring their own authorization.

## Design

### Data

`backup_jobs/{jobId}` — written only by Functions (rules: `read: isSystemAdmin()`, `write: false`).

```
jobId            string   (doc id, UUID)
status           'running' | 'completed' | 'failed'
trigger          'manual' | 'scheduled'
requestedBy      uid or 'system'
requestedAt      Timestamp (server)
startedAt        Timestamp | null     (operation accepted)
completedAt      Timestamp | null
operationName    string | null        (LRO name, no secrets)
outputUriPrefix  'gs://<bucket>/firestore-exports/<yyyyMMdd-HHmmss>-<jobId>'
coverage         {firestore: 'included', auth: 'excluded', storage: 'excluded'}
progress         {documents: {completed, estimated}, bytes: {completed, estimated}} | null
verification     {status: 'pending' | 'verified' | 'missing', metadataPath, checkedAt} | null
error            {code, message} | null   (sanitised; never document data)
retentionDays    number (from config)
expiresAt        Timestamp (requestedAt + retentionDays) — informational; deletion is a bucket lifecycle rule
revision         number (increments on every server update)
```

### Configuration (Functions params, deploy-time, not client-editable)

- `BACKUP_BUCKET` — e.g. `mindmate-staging-firestore-backups`. Unset ⇒ callable returns `failed-precondition` "Backup destination is not configured"; page shows *Not configured*.
- `BACKUP_RETENTION_DAYS` — default `30`.
- `BACKUP_SCHEDULE_ENABLED` — default `false`. The scheduled function exits immediately (and writes nothing) unless `"true"`.
- `BACKUP_MANUAL_DAILY_LIMIT` — default `3`.

### Server (`functions/src/backup_jobs.ts` pure domain + `functions/src/backup_management.ts` wiring)

Pure, dependency-free functions (unit-tested without emulators):
- `resolveBackupConfig(env)` → `{bucket, retentionDays, scheduleEnabled, manualDailyLimit}` or a typed error.
- `exportPrefixFor(bucket, now, jobId)`.
- `assertCanStart(jobs, now, {trigger, limit})` → throws `failed-precondition` when a job is `running`, or when manual requests in the last 24h ≥ limit.
- `applyOperationState(job, operation, now)` → next job fields: still running (with progress) / completed (needs verification) / failed (sanitised error).
- `verificationFor(prefix, objectExists)` → `verified` when `<prefix>/<basename>.overall_export_metadata` exists, else `missing` ⇒ job `failed` with code `export-metadata-missing`.
- `sanitizeError(unknown)` → `{code, message}` with message truncated, no stack, no paths beyond the bucket prefix.
- `summarize(jobs)` → `{lastVerifiedAt, lastJobStatus, runningJobId, coverage}` (also used by the Flutter page via the model).

Wiring with injected clients (`{db, adminClient, storage, now}`) so emulator tests use fakes for GCP:
- **`requestFirestoreBackup`** (callable): `requireSuperAdmin` → `resolveBackupConfig` → `assertCanStart` (reads the latest jobs) → create job (`running`, `revision: 1`) → `adminClient.exportDocuments({name: databasePath, outputUriPrefix})` → store `operationName`, `startedAt` → audit `BACKUP_REQUESTED`. On export call failure: job `failed`, audit `BACKUP_FAILED`, rethrow sanitised `HttpsError`.
- **`refreshFirestoreBackupStatus`** (callable, `{jobId}`): `requireSuperAdmin` → load job → if `running`, `adminClient.checkExportDocumentsProgress(operationName)` → `applyOperationState` → if operation done without error, check metadata object → `completed`+`verified` (audit `BACKUP_COMPLETED`) or `failed`+`missing` (audit `BACKUP_FAILED`). Idempotent: repeated calls on a terminal job return it unchanged.
- **`scheduledFirestoreBackup`** (`onSchedule`, `every day 02:30`, `Asia/Manila`, `asia-east1`): if `!scheduleEnabled` return; refresh all `running` jobs; then start a job with `trigger: 'scheduled'`, `requestedBy: 'system'`, skipping (with a `BACKUP_SKIPPED` audit) if a job is still running.

Audit actions added to `AUDIT_ACTIONS`: `BACKUP_REQUESTED`, `BACKUP_COMPLETED`, `BACKUP_FAILED`, `BACKUP_SKIPPED` (category `SYSTEM`, targetType `backup_job`).

### Web (Flutter admin portal)

- `AdminPortalPage.backupData` labelled **Back-up Data**, icon `backup_outlined`, in the **System** navigation section above Profile, `_allowed` ⇒ `isSuperAdmin`.
- `lib/features/admin/domain/backup_job.dart`: `BackupJob` model (`fromJson`, status enum, verification enum, `isTerminal`), `BackupSummary.fromJobs`.
- `AdminPortalRepository`: `watchBackupJobs()` (Firestore stream, newest first, limit 50; non-super-admins get an empty stream), `requestFirestoreBackup()` and `refreshBackupJobStatus(id)` via `_callCallable`.
- `lib/features/admin/screens/backup_data_page.dart`: coverage card (Firestore included; Authentication and Storage *excluded in Phase 1*), last verified backup, job table (requested, trigger, status, documents, verification, error code), **Request backup now** with a confirmation dialog stating cost and scope, per-row **Refresh status**. Four distinct states: *loading*, *not authorized* (stream error / permission), *not configured* (callable `failed-precondition`), *backend error* (other codes). No links to bucket objects.

### Rules

```
match /backup_jobs/{jobId} {
  allow read: if isSystemAdmin();
  allow write: if false;
}
```

### Encryption, IAM, retention, billing (runbook, applied by an operator later)

- Bucket: same project, `asia-east1`, uniform bucket-level access, public access prevention enforced, Google-managed encryption at rest by default (CMEK optional; documented), **retention policy** ≥ retention days (prevents early deletion), lifecycle rule deletes objects after retention days, object versioning off (retention policy covers it).
- IAM (least privilege): Firestore service agent `service-<PROJECT_NUMBER>@gcp-sa-firestore.iam.gserviceaccount.com` → `roles/storage.admin` **on the bucket only** (Google requirement for export). Dedicated Functions SA (recommended) → `roles/datastore.importExportAdmin` (project), `roles/storage.objectViewer` **on the bucket** (for metadata verification), plus the roles the existing runtime SA already needs. No human principals on the bucket except break-glass.
- Billing safeguards: one running job; manual cap per 24h; scheduler off by default; a budget alert on the project is recommended in the runbook.
- Estimated cost (staging, verify against the current pricing page): ≤ 20k documents per export ≈ 20k reads ≈ **~$0.01 per export**; 30 daily exports retained ≈ a few hundred MB ≈ **< $0.10/month** storage. Production scales linearly with document count (1M documents ≈ $0.60 per export in reads).

### Restore (runbook only)

Import an export prefix into an **isolated test project's** database with `gcloud firestore import gs://…/<prefix>` after granting that project's Firestore service agent read access to the bucket; verify collection counts and a sample of non-clinical fields; never import into production without a separate authorization and a pre-restore export.

### Testing strategy

- Pure domain: node unit tests (no emulator) for config resolution, start guards, operation-state mapping, verification and sanitisation.
- Callables: emulator test (Auth + Firestore) with fake admin/storage clients: super-admin succeeds and writes job + audit; non-admin denied; second request while running denied; export failure marks job failed; refresh completes with verification; missing metadata marks failed.
- Rules: emulator test — super-admin reads `backup_jobs`, admin-non-super/counselor/staff/student denied, all client writes denied.
- Flutter: model parsing tests; page widget tests for the four states and the confirmation flow; navigation visibility test (super-admin only).
- **Not automated (needs GCP):** a real export against a bucket and the restore drill. Documented as the staging acceptance step requiring separate authorization.

## Builder calls to review **[call]**

1. Nightly 02:30 Asia/Manila schedule, **disabled by default**, 30-day retention, manual cap 3/24h.
2. Whole-database export (no collection filter) so the restore drill is complete.
3. "Completed" requires the `overall_export_metadata` object to exist; nothing else is inspected.
4. Retention enforced by bucket lifecycle + retention policy, not by code.
5. Page placed under **System** above Profile; super-admin only (the configured `SUPER_ADMIN_UID`), not every `admin` role.
