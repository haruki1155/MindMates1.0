import assert from "node:assert/strict";
import {test} from "node:test";

import {
  applyOperationState,
  assertCanStart,
  BackupConfigError,
  BackupJobRecord,
  exportPrefixFor,
  resolveBackupConfig,
  resolveBackupServiceAccount,
  isDefinitiveExportRejection,
  sanitizeError,
  StartBlockedError,
  summarizeJobs,
  verificationFor,
} from "./backup_jobs";

const job = (over: Partial<BackupJobRecord> = {}): BackupJobRecord => ({
  status: "completed",
  trigger: "manual",
  requestedBy: "u",
  requestedAt: new Date("2026-11-15T09:00:00Z"),
  operationName: null,
  progress: null,
  verification: null,
  error: null,
  ...over,
});

test("resolveBackupConfig applies defaults and rejects a missing bucket", () => {
  assert.deepEqual(resolveBackupConfig({BACKUP_BUCKET: "b"}), {bucket: "b", retentionDays: 30, scheduleEnabled: false, manualDailyLimit: 3});
  const custom = resolveBackupConfig({BACKUP_BUCKET: " b ", BACKUP_SCHEDULE_ENABLED: "true", BACKUP_RETENTION_DAYS: "7", BACKUP_MANUAL_DAILY_LIMIT: "1"});
  assert.deepEqual(custom, {bucket: "b", retentionDays: 7, scheduleEnabled: true, manualDailyLimit: 1});
  assert.throws(() => resolveBackupConfig({}), (e: unknown) => e instanceof BackupConfigError && e.code === "bucket-missing");
  assert.throws(() => resolveBackupConfig({BACKUP_BUCKET: ""}), (e: unknown) => e instanceof BackupConfigError && e.code === "bucket-missing");
  assert.throws(() => resolveBackupConfig({BACKUP_BUCKET: "gs://b"}), (e: unknown) => e instanceof BackupConfigError && e.code === "bucket-invalid");
  assert.throws(() => resolveBackupConfig({BACKUP_BUCKET: "b/prefix"}), (e: unknown) => e instanceof BackupConfigError && e.code === "bucket-invalid");
  assert.throws(() => resolveBackupConfig({BACKUP_BUCKET: "b", BACKUP_RETENTION_DAYS: "0"}), (e: unknown) => e instanceof BackupConfigError && e.code === "invalid-number");
  assert.throws(() => resolveBackupConfig({BACKUP_BUCKET: "b", BACKUP_MANUAL_DAILY_LIMIT: "x"}), (e: unknown) => e instanceof BackupConfigError && e.code === "invalid-number");
});

test("exportPrefixFor builds the dated prefix and metadata path", () => {
  const r = exportPrefixFor("bkt", new Date(Date.UTC(2026, 10, 15, 2, 30, 0)), "job1");
  assert.equal(r.outputUriPrefix, "gs://bkt/firestore-exports/20261115-023000-job1");
  assert.equal(r.metadataPath, "firestore-exports/20261115-023000-job1/20261115-023000-job1.overall_export_metadata");
});

test("assertCanStart blocks while a job runs and after the manual daily limit", () => {
  const now = new Date("2026-11-15T10:00:00Z");
  assert.throws(() => assertCanStart([job({status: "running"})], now, {trigger: "manual", manualDailyLimit: 3}), (e: unknown) => e instanceof StartBlockedError && e.code === "job-running");
  assert.throws(() => assertCanStart([job({status: "running"})], now, {trigger: "scheduled", manualDailyLimit: 3}), (e: unknown) => e instanceof StartBlockedError && e.code === "job-running");
  assert.throws(() => assertCanStart([job(), job(), job({status: "failed"})], now, {trigger: "manual", manualDailyLimit: 3}), (e: unknown) => e instanceof StartBlockedError && e.code === "manual-limit");
  assert.doesNotThrow(() => assertCanStart([job(), job(), job()], now, {trigger: "scheduled", manualDailyLimit: 3}));
  assert.doesNotThrow(() => assertCanStart([job({requestedAt: new Date("2026-11-14T09:00:00Z")}), job(), job()], now, {trigger: "manual", manualDailyLimit: 3}));
  assert.doesNotThrow(() => assertCanStart([job({trigger: "scheduled"}), job(), job()], now, {trigger: "manual", manualDailyLimit: 3}));
  assert.doesNotThrow(() => assertCanStart([], now, {trigger: "manual", manualDailyLimit: 3}));
});

test("applyOperationState maps running, failed and exported operations", () => {
  assert.deepEqual(
    applyOperationState({done: false, metadata: {progressDocuments: {completedWork: "10", estimatedWork: "100"}, progressBytes: {completedWork: 5, estimatedWork: 50}}}),
    {status: "running", progress: {documents: {completed: 10, estimated: 100}, bytes: {completed: 5, estimated: 50}}},
  );
  assert.deepEqual(applyOperationState({done: false}), {status: "running", progress: null});
  assert.deepEqual(applyOperationState({done: false, metadata: {progressDocuments: {completedWork: "nope"}}}), {status: "running", progress: {documents: {completed: 0, estimated: 0}, bytes: {completed: 0, estimated: 0}}});
  assert.deepEqual(applyOperationState({done: true, error: {code: 7, message: "denied"}}), {status: "failed", error: {code: "export-7", message: "denied"}});
  assert.deepEqual(applyOperationState({done: true}), {status: "exported"});
  assert.deepEqual(applyOperationState({done: true, error: null}), {status: "exported"});
});

test("verificationFor requires the metadata object", () => {
  const now = new Date("2026-11-15T03:00:00Z");
  assert.deepEqual(verificationFor("p/x.overall_export_metadata", true, now), {status: "verified", metadataPath: "p/x.overall_export_metadata", checkedAt: now});
  assert.equal(verificationFor("p/x.overall_export_metadata", false, now).status, "missing");
});

test("sanitizeError strips stacks and truncates", () => {
  const e = sanitizeError(Object.assign(new Error("x".repeat(500)), {code: 13}));
  assert.equal(e.code, "export-13");
  assert.equal(e.message.length, 300);
  assert.equal(Object.keys(e).sort().join(","), "code,message");
  assert.deepEqual(sanitizeError(Object.assign(new Error("bad bucket"), {code: "not-found"})), {code: "not-found", message: "bad bucket"});
  assert.deepEqual(sanitizeError("boom"), {code: "unknown", message: "boom"});
  assert.deepEqual(sanitizeError(undefined), {code: "unknown", message: "Unknown error"});
});

test("only definitive gRPC rejections count as a failed export start; anything else is uncertain", () => {
  for (const code of [3, 5, 6, 7, 8, 9, 11, 12, 16]) assert.equal(isDefinitiveExportRejection({code}), true, `code ${code}`);
  for (const code of [1, 2, 4, 10, 13, 14, 15]) assert.equal(isDefinitiveExportRejection({code}), false, `code ${code}`);
  assert.equal(isDefinitiveExportRejection(new Error("socket hang up")), false);
  assert.equal(isDefinitiveExportRejection(undefined), false);
  assert.equal(isDefinitiveExportRejection({code: "permission-denied"}), false);
});

test("summarizeJobs reports last verified completion and running count", () => {
  const verifiedAt = new Date("2026-11-15T03:00:00Z");
  const jobs = [
    {...job({status: "running", requestedAt: new Date("2026-11-15T10:00:00Z")}), completedAt: null},
    {...job({verification: {status: "verified", metadataPath: "p", checkedAt: verifiedAt}, requestedAt: new Date("2026-11-15T02:30:00Z")}), completedAt: verifiedAt},
    {...job({status: "failed", requestedAt: new Date("2026-11-14T02:30:00Z")}), completedAt: new Date("2026-11-14T02:40:00Z")},
  ];
  assert.deepEqual(summarizeJobs(jobs), {lastVerifiedAt: verifiedAt, runningCount: 1, lastStatus: "running"});
  assert.deepEqual(summarizeJobs([]), {lastVerifiedAt: null, runningCount: 0, lastStatus: null});
});

test("resolveBackupServiceAccount validates project-scoped SA and leaves unset clean", () => {
  assert.equal(resolveBackupServiceAccount({}, "mindmate-staging"), undefined);
  assert.equal(resolveBackupServiceAccount({BACKUP_SERVICE_ACCOUNT: "   "}, "mindmate-staging"), undefined);
  assert.equal(
    resolveBackupServiceAccount(
      {BACKUP_SERVICE_ACCOUNT: " firestore-backup@mindmate-staging.iam.gserviceaccount.com "},
      "mindmate-staging",
    ),
    "firestore-backup@mindmate-staging.iam.gserviceaccount.com",
  );
  assert.equal(
    resolveBackupServiceAccount({BACKUP_SERVICE_ACCOUNT: "firestore-backup@"}, "mindmate-staging"),
    "firestore-backup@mindmate-staging.iam.gserviceaccount.com",
  );
  assert.equal(
    resolveBackupServiceAccount({BACKUP_SERVICE_ACCOUNT: "firestore-backup@"}, "mind-mates-cd2cf"),
    "firestore-backup@mind-mates-cd2cf.iam.gserviceaccount.com",
  );
  assert.equal(resolveBackupServiceAccount({BACKUP_SERVICE_ACCOUNT: "firestore-backup@"}), "firestore-backup@");

  for (const bad of [
    "serviceAccount:firestore-backup@mindmate-staging.iam.gserviceaccount.com",
    "mindmate-staging@appspot.gserviceaccount.com",
    "978195258114-compute@developer.gserviceaccount.com",
    "firestore-backup@mindmate-staging.iam.gserviceaccount.com extra",
    "ab@",
    "BadUpper@mindmate-staging.iam.gserviceaccount.com",
  ]) {
    assert.throws(
      () => resolveBackupServiceAccount({BACKUP_SERVICE_ACCOUNT: bad}, "mindmate-staging"),
      (e: unknown) => e instanceof BackupConfigError && e.code === "service-account-invalid",
      bad,
    );
  }

  assert.throws(
    () =>
      resolveBackupServiceAccount(
        {BACKUP_SERVICE_ACCOUNT: "firestore-backup@mindmate-staging.iam.gserviceaccount.com"},
        "mind-mates-cd2cf",
      ),
    (e: unknown) => e instanceof BackupConfigError && e.code === "service-account-invalid",
  );
});
