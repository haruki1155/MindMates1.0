# Firestore backup runbook (Back-up Data, Phase 1)

Operator guide for the PACC portal's Firestore managed-export backups. Every command below that creates, changes or deletes a Google Cloud resource **requires separate written authorization**; this document records how, not permission to do it.

Design: `docs/superpowers/specs/2026-11-15-backup-data-design.md`.

## 1. Scope and exclusions

| Source | Phase 1 | Notes |
|---|---|---|
| Cloud Firestore `(default)` database | **Included** | Whole-database managed export (`exportDocuments`) to a private bucket in the same project. |
| Firebase Authentication users | **Excluded** | Needs an Admin SDK `listUsers` export that would contain emails and password hashes; separate design and storage controls required. |
| Cloud Storage files (session evidence, profile photos) | **Excluded** | Needs bucket-to-bucket transfer with equivalent ACLs. |
| Point-in-time recovery | Not enabled | Optional complement; see §9. |

The admin page states these exclusions on every job (`coverage` field) so nobody mistakes a Firestore export for a full system backup.

## 2. What the software does

- `requestFirestoreBackup` (callable, super-admin only): creates `backup_jobs/<id>` with `status: running`, calls the Firestore export API, stores the operation name, audits `BACKUP_REQUESTED`. Refuses when a job is running or the manual limit (default 3 per 24 h) is reached.
- `refreshFirestoreBackupStatus` (callable, super-admin only): polls the export operation. A finished export becomes `completed` **only if** `<prefix>/<name>.overall_export_metadata` exists in the bucket; otherwise `failed` with `export-metadata-missing`. Audits `BACKUP_COMPLETED` / `BACKUP_FAILED`.
- `scheduledFirestoreBackup` (daily 02:30 Asia/Manila, asia-east1): exits immediately unless `BACKUP_SCHEDULE_ENABLED=true`. When enabled it refreshes running jobs, skips (audit `BACKUP_SKIPPED`) if one is still running, otherwise starts a `scheduled` job as actor `system`.
- Firestore rules: `backup_jobs` readable only by the configured super-administrator (`system_config/security.superAdminUid`), never writable by clients.
- The web app never receives bucket listings, object URLs or document contents.

## 3. Configuration (Functions params, deploy-time)

| Param | Default | Meaning |
|---|---|---|
| `BACKUP_BUCKET` | unset | Destination bucket name (no `gs://`). Unset ⇒ requests fail with "Backup destination is not configured." |
| `BACKUP_RETENTION_DAYS` | `30` | Informational `expiresAt` on jobs; must match the bucket retention/lifecycle below. |
| `BACKUP_SCHEDULE_ENABLED` | `false` | Scheduler is a no-op until `true`. |
| `BACKUP_MANUAL_DAILY_LIMIT` | `3` | Billing safeguard for manual requests. |
| `BACKUP_SERVICE_ACCOUNT` | unset | Dedicated runtime SA email (`firestore-backup@<project>.iam.gserviceaccount.com` or `firestore-backup@`) applied **only** to `requestFirestoreBackup`, `refreshFirestoreBackupStatus`, and `scheduledFirestoreBackup`. Must match the target project when set. Leave empty for local emulator/CI discovery. |

Set them in `functions/.env.<project>` (gitignored; see `functions/.env.example`), keeping `mindmate-staging` and `mind-mates-cd2cf` in separate files:

- **Never overwrite an existing `functions/.env.<project>`** (or re-run provisioning scripts that overwrite it). Merge `BACKUP_*` entries alongside existing keys such as `SUPER_ADMIN_UID`, `ADMIN_WEB_URL`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_SENDER`, `MOOD_V2_STAGING_PILOT_UIDS`, `MOOD_V2_STAGING_STUDENT_ROLLOUT_ENABLED`, and `ACADEMIC_YEAR_EXTENDED_LIFECYCLE_ENABLED`.
- If setting up from a fresh worktree without `.env.<project>`, first restore or verify the project's existing deploy-time keys (especially `SUPER_ADMIN_UID`) before appending `BACKUP_*` settings.

## 4. Required Google Cloud permissions (least privilege)

Project number for staging: `978195258114`. Replace for other projects. Keep the two service identities strictly separated:

| Principal | Role | Scope | Why |
|---|---|---|---|
| Firestore service agent `service-<PROJECT_NUMBER>@gcp-sa-firestore.iam.gserviceaccount.com` | `roles/storage.admin` | **bucket only** (`gs://$BUCKET`) | Google's documented requirement for Firestore managed export/import to write export objects. Do **not** grant this to the Functions runtime SA. |
| Dedicated backup Functions runtime SA `firestore-backup@<project>.iam.gserviceaccount.com` | `roles/datastore.importExportAdmin` | project | Start Firestore exports and poll/list export operations. |
| Same dedicated backup Functions SA | `roles/datastore.user` | project | Read `users`/`system_config` for `requireSuperAdmin` and read/write `backup_jobs` and `admin_audit_logs`. |
| Same dedicated backup Functions SA | `roles/firebaseauth.viewer` | project | Read Auth disabled/emailVerified state in `requireStaff`. |
| Same dedicated backup Functions SA | `roles/storage.objectViewer` | **bucket only** (`gs://$BUCKET`) | Verify `<prefix>/<name>.overall_export_metadata` exists. Nothing more. |
| Same dedicated backup Functions SA | `roles/run.invoker` | service (`scheduledFirestoreBackup`) | Allow Cloud Scheduler OIDC invocation as `firestore-backup@<project>.iam.gserviceaccount.com`. |
| Deployer identity (human/CI running `firebase deploy`) | `roles/iam.serviceAccountUser` | SA (`firestore-backup@<project>.iam.gserviceaccount.com`) | Required `iam.serviceAccounts.actAs` to attach the dedicated SA to the three backup Functions and Cloud Scheduler job. |
| Unrelated MindMate Functions | unchanged | — | All other ~118 Functions continue using their existing runtime SA configuration and do not receive `BACKUP_SERVICE_ACCOUNT`. |
| Humans | none on bucket by default | — | Break-glass access through a documented, audited grant only. |

Finding (2026-11-15): `mindmate-staging` currently has default App Engine (`mindmate-staging@appspot.gserviceaccount.com`), default Compute Engine (`978195258114-compute@developer.gserviceaccount.com`, holding broad `roles/editor`), and Firebase Admin SDK service accounts; the dedicated `firestore-backup@mindmate-staging.iam.gserviceaccount.com` SA and backup bucket do not yet exist. `functions/src/backup_management.ts` wires `BACKUP_SERVICE_ACCOUNT` only onto `requestFirestoreBackup`, `refreshFirestoreBackupStatus`, and `scheduledFirestoreBackup`.

## 5. Service account & bucket creation (requires authorization; not done)

```bash
PROJECT=mindmate-staging
PROJECT_NUMBER=978195258114
BUCKET=${PROJECT}-firestore-backups
BACKUP_SA_ID=firestore-backup
BACKUP_SA=${BACKUP_SA_ID}@${PROJECT}.iam.gserviceaccount.com
DEPLOYER=user:<deployer-email> # or serviceAccount:<ci-deployer-sa>

# 1. Create dedicated backup runtime SA (only for the 3 backup Functions)
gcloud iam service-accounts create $BACKUP_SA_ID --project=$PROJECT \
  --display-name="MindMate Firestore Backup Functions"

# 2. Grant least-privilege runtime roles to the backup SA
gcloud projects add-iam-policy-binding $PROJECT \
  --member=serviceAccount:$BACKUP_SA --role=roles/datastore.importExportAdmin
gcloud projects add-iam-policy-binding $PROJECT \
  --member=serviceAccount:$BACKUP_SA --role=roles/datastore.user
gcloud projects add-iam-policy-binding $PROJECT \
  --member=serviceAccount:$BACKUP_SA --role=roles/firebaseauth.viewer

# 3. Allow the deployer to attach the dedicated SA during firebase deploy
gcloud iam service-accounts add-iam-policy-binding $BACKUP_SA --project=$PROJECT \
  --member=$DEPLOYER --role=roles/iam.serviceAccountUser

# 4. Create the private same-region backup bucket with retention + lifecycle
gcloud storage buckets create gs://$BUCKET --project=$PROJECT --location=asia-east1 \
  --uniform-bucket-level-access --public-access-prevention
# Objects cannot be deleted or overwritten before the retention period.
gcloud storage buckets update gs://$BUCKET --retention-period=30d
# Lifecycle: delete objects after 30 days (the only deletion mechanism; code never deletes).
cat > lifecycle.json <<'EOF'
{"rule":[{"action":{"type":"Delete"},"condition":{"age":30}}]}
EOF
gcloud storage buckets update gs://$BUCKET --lifecycle-file=lifecycle.json

# 5. Grant bucket-scoped IAM (separated by service identity)
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member=serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-firestore.iam.gserviceaccount.com \
  --role=roles/storage.admin
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member=serviceAccount:$BACKUP_SA --role=roles/storage.objectViewer
```

Encryption: Google-managed encryption at rest is on by default. For CMEK, create a Cloud KMS key in `asia-east1`, grant the Storage service agent `roles/cloudkms.cryptoKeyEncrypterDecrypter`, and pass `--default-encryption-key` at bucket creation. Firestore exports inherit the bucket default.

Location rule: the bucket must be in the same location as the database (`asia-east1`) or a multi-region that contains it, in the same project.

## 6. Deploying (requires authorization; not done)

Pre-flight checks before deploying:

1. Verify `functions/.env.$PROJECT` retains `SUPER_ADMIN_UID` and all non-backup params for `$PROJECT`, sets `BACKUP_BUCKET=$BUCKET`, `BACKUP_SERVICE_ACCOUNT=$BACKUP_SA`, `BACKUP_RETENTION_DAYS=30`, `BACKUP_MANUAL_DAILY_LIMIT=3`, and keeps `BACKUP_SCHEDULE_ENABLED=false`.
2. Deploy by exact target name — never `--force`, never a blanket deploy:

```bash
firebase deploy --project mindmate-staging --only firestore:rules
firebase deploy --project mindmate-staging --only functions:requestFirestoreBackup,functions:refreshFirestoreBackupStatus,functions:scheduledFirestoreBackup
```

3. Verify only the three backup Functions bound `$BACKUP_SA` (Cloud Functions v2 `serviceConfig.serviceAccountEmail` and Cloud Scheduler `httpTarget.oidcToken.serviceAccountEmail`), and confirm `scheduledFirestoreBackup` grants `roles/run.invoker` to `$BACKUP_SA`:

```bash
for fn in requestFirestoreBackup refreshFirestoreBackupStatus; do
  gcloud functions describe $fn --gen2 --region=us-central1 --project=mindmate-staging \
    --format="value(serviceConfig.serviceAccountEmail)"
done
gcloud functions describe scheduledFirestoreBackup --gen2 --region=asia-east1 --project=mindmate-staging \
  --format="value(serviceConfig.serviceAccountEmail)"
gcloud scheduler jobs describe firebase-schedule-scheduledFirestoreBackup-asia-east1 \
  --location=asia-east1 --project=mindmate-staging \
  --format="value(httpTarget.oidcToken.serviceAccountEmail)"
gcloud run services get-iam-policy scheduledfirestorebackup --region=asia-east1 --project=mindmate-staging
```

Note on rotating or retrofitting `$BACKUP_SA` for an already-deployed `scheduledFirestoreBackup`: `firebase-tools` (`cloudscheduler.js::needUpdate`) does not compare `httpTarget.oidcToken.serviceAccountEmail` when updating an existing Cloud Scheduler job, whereas `firebase deploy` replaces the Cloud Run `roles/run.invoker` binding with the new SA. If the scheduler job's `oidcToken.serviceAccountEmail` is stale, run:

```bash
gcloud scheduler jobs update http firebase-schedule-scheduledFirestoreBackup-asia-east1 \
  --location=asia-east1 --project=mindmate-staging \
  --oidc-service-account-email=$BACKUP_SA
```

Enable the schedule only after one successful manual job and one restore drill: set `BACKUP_SCHEDULE_ENABLED=true` in `functions/.env.<project>` and redeploy `functions:scheduledFirestoreBackup`.

Rollback (safe pause without deleting history): set `BACKUP_SCHEDULE_ENABLED=false` and unset `BACKUP_BUCKET=` in `functions/.env.<project>`, then redeploy only `functions:requestFirestoreBackup,functions:refreshFirestoreBackupStatus,functions:scheduledFirestoreBackup`.

## 7. Cost estimate (verify against the current pricing page before enabling)

Staging today: 61 top-level collections, 5,190 top-level documents (subcollections uncounted; assume ≤ 20,000 documents).

| Item | Basis | Staging estimate |
|---|---|---|
| Export reads | one document read per exported document | ≤ 20k reads ≈ **$0.01 per export** |
| Storage | export size ≈ a few MB per 1k docs; 30 daily exports retained | **< $0.10 / month** |
| Scheduler + Functions | 1 invocation/day, seconds of runtime | negligible |

Production scales linearly with document count (≈ $0.60 per export per 1M documents in reads). Set a Cloud Billing budget alert before enabling the daily schedule.

## 8. Monitoring and troubleshooting

- Admin page: last verified backup, per-job status, documents exported, error code.
- `backup_jobs` fields: `status`, `operationName`, `progress`, `verification`, `error`, `revision`.
- `admin_audit_logs`: `BACKUP_REQUESTED`, `BACKUP_COMPLETED`, `BACKUP_FAILED`, `BACKUP_SKIPPED` (category `SYSTEM`, targetType `backup_job`).
- `export-7` (PERMISSION_DENIED): the service agent lacks `roles/storage.admin` on the bucket, or the Functions SA lacks `datastore.importExportAdmin`.
- `export-metadata-missing`: the export reported done but the metadata object is absent — check the bucket and operation in Cloud Console; treat the job as failed.
- `failed-precondition` "already running": a job is `running`, possibly with `reconciliation.status: uncertain`. This is deliberate: an export whose outcome is unknown keeps new exports blocked so no duplicate paid export can start.
  - `export-start-ambiguous`, `export-response-without-name`, `operation-name-not-persisted`: the export may have been accepted. *Refresh status* looks up export operations (running and completed) by the job's exact output prefix and adopts a match; only when both listings answer and none matches, after 10 minutes, is the job failed as `export-start-orphaned`.
  - `status-lookup-failed` / `operation-listing-unavailable`: the status could not be read. Nothing is decided; refresh again later. A definitive result read from the operation itself is the only thing that completes or fails the job.
  - If a job stays uncertain because the API keeps refusing lookups, an operator inspects the operation in Cloud Console (`gcloud firestore operations list --database='(default)'`, filter by the output prefix) and resolves it under a separate authorization. Never clear it on a timer.

## 9. Restore drill (requires authorization; never production)

1. Pick a verified job and its `outputUriPrefix`.
2. In an **isolated test project** (`mindmate-restore-drill`), grant that project's Firestore service agent `roles/storage.objectViewer` on the backup bucket.
3. `gcloud firestore import <outputUriPrefix> --project=mindmate-restore-drill` (where `<outputUriPrefix>` is `gs://<bucket>/firestore-exports/<stamp>-<jobId>`).
4. Verify: collection list and document counts match the source at export time (use `runAggregationQuery` counts), sample non-clinical fields (e.g. `colleges`, `system_config`) for integrity. Do not open or copy clinical documents beyond counts.
5. Record the drill (date, job id, counts, duration) in the operations log; delete the drill database afterwards under its own authorization.

Production restore: only after a separate authorization, a fresh pre-restore export of production, and this drill repeated against the exact export to be restored.

## 10. Alternatives and complements

| Option | Pros | Cons | Status |
|---|---|---|---|
| Firestore scheduled backups (`gcloud firestore backups schedules create --recurrence=daily --retention=7d`) | No code, no read charges, managed retention up to 14 weeks | Backups live inside Firestore (not an inspectable bucket), restore creates a whole new database, no app-visible job history or per-job verification | Recommended complement; separate authorization |
| Point-in-time recovery (7 days) | Protects against bad writes | Not a copy outside the database; billing change | Optional |
| Phase 2: Auth + Storage coverage | Full system backup | New IAM/cost surface, separate design | Planned, not scheduled |
