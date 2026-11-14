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

Set them in `functions/.env.<project>` (gitignored). See `functions/.env.example`.

## 4. Required Google Cloud permissions (least privilege)

Project number for staging: `978195258114`. Replace for other projects.

| Principal | Role | Scope | Why |
|---|---|---|---|
| Firestore service agent `service-<PROJECT_NUMBER>@gcp-sa-firestore.iam.gserviceaccount.com` | `roles/storage.admin` | **bucket only** | Google's documented requirement for export/import to write objects. |
| Functions runtime service account (recommended: a dedicated SA, not the default compute SA) | `roles/datastore.importExportAdmin` | project | Start exports and read operation status. |
| Same Functions SA | `roles/storage.objectViewer` | **bucket only** | Verify the `overall_export_metadata` object exists. Nothing more. |
| Humans | none by default | — | Break-glass access through a documented, audited grant only. |

Finding (2026-11-15): the staging runtime SA `978195258114-compute@developer.gserviceaccount.com` currently holds `roles/editor`. That already includes export rights but is far broader than needed. Recommended follow-up (separate authorization): create `firestore-backup@<project>.iam.gserviceaccount.com`, bind the two roles above, and deploy the three backup Functions with `serviceAccount` set to it.

## 5. Bucket creation (requires authorization; not done)

```bash
PROJECT=mindmate-staging
BUCKET=${PROJECT}-firestore-backups
gcloud storage buckets create gs://$BUCKET --project=$PROJECT --location=asia-east1 \
  --uniform-bucket-level-access --public-access-prevention
# Objects cannot be deleted or overwritten before the retention period.
gcloud storage buckets update gs://$BUCKET --retention-period=30d
# Lifecycle: delete objects after 30 days (the only deletion mechanism; code never deletes).
cat > lifecycle.json <<'EOF'
{"rule":[{"action":{"type":"Delete"},"condition":{"age":30}}]}
EOF
gcloud storage buckets update gs://$BUCKET --lifecycle-file=lifecycle.json
# IAM (bucket-scoped)
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member=serviceAccount:service-978195258114@gcp-sa-firestore.iam.gserviceaccount.com --role=roles/storage.admin
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member=serviceAccount:<functions-sa> --role=roles/storage.objectViewer
gcloud projects add-iam-policy-binding $PROJECT \
  --member=serviceAccount:<functions-sa> --role=roles/datastore.importExportAdmin
```

Encryption: Google-managed encryption at rest is on by default. For CMEK, create a Cloud KMS key in `asia-east1`, grant the Storage service agent `roles/cloudkms.cryptoKeyEncrypterDecrypter`, and pass `--default-encryption-key` at bucket creation. Firestore exports inherit the bucket default.

Location rule: the bucket must be in the same location as the database (`asia-east1`) or a multi-region that contains it, in the same project.

## 6. Deploying (requires authorization; not done)

Deploy by name, never `--force`, never a blanket deploy (see memory note on staging deploy traps):

```bash
firebase deploy --project mindmate-staging --only firestore:rules
firebase deploy --project mindmate-staging --only functions:requestFirestoreBackup,functions:refreshFirestoreBackupStatus,functions:scheduledFirestoreBackup
```

Enable the schedule only after one successful manual job and one restore drill: set `BACKUP_SCHEDULE_ENABLED=true` in `functions/.env.<project>` and redeploy `functions:scheduledFirestoreBackup`.

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
- `failed-precondition` "already running": refresh the running job; if the operation is gone, mark it failed via a refresh (the operation lookup fails ⇒ `failed`).

## 9. Restore drill (requires authorization; never production)

1. Pick a verified job and its `outputUriPrefix`.
2. In an **isolated test project** (`mindmate-restore-drill`), grant that project's Firestore service agent `roles/storage.objectViewer` on the backup bucket.
3. `gcloud firestore import gs://<bucket>/firestore-exports/<prefix> --project=mindmate-restore-drill`
4. Verify: collection list and document counts match the source at export time (use `runAggregationQuery` counts), sample non-clinical fields (e.g. `colleges`, `system_config`) for integrity. Do not open or copy clinical documents beyond counts.
5. Record the drill (date, job id, counts, duration) in the operations log; delete the drill database afterwards under its own authorization.

Production restore: only after a separate authorization, a fresh pre-restore export of production, and this drill repeated against the exact export to be restored.

## 10. Alternatives and complements

| Option | Pros | Cons | Status |
|---|---|---|---|
| Firestore scheduled backups (`gcloud firestore backups schedules create --recurrence=daily --retention=7d`) | No code, no read charges, managed retention up to 14 weeks | Backups live inside Firestore (not an inspectable bucket), restore creates a whole new database, no app-visible job history or per-job verification | Recommended complement; separate authorization |
| Point-in-time recovery (7 days) | Protects against bad writes | Not a copy outside the database; billing change | Optional |
| Phase 2: Auth + Storage coverage | Full system backup | New IAM/cost surface, separate design | Planned, not scheduled |
