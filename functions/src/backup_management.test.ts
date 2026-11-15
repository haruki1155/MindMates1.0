import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {
  BackupDeps,
  refreshBackup,
  requestFirestoreBackup,
  runScheduledBackup,
  startBackup,
} from "./backup_management";
import {OperationState} from "./backup_jobs";

// Runs against the Auth + Firestore emulators with fake GCP export/storage
// clients. Skipped elsewhere; see docs/operations/firestore-backup-runbook.md
// for the live-export acceptance step that needs real Google Cloud access.
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `backup-${Date.now()}`;
const adminUid = `${prefix}-admin`;
const counselorUid = `${prefix}-counselor`;
const actor = {uid: adminUid, name: "Test Admin", role: "admin"};
const db = getFirestore();

type Fake = BackupDeps & {exportCalls: Array<{name: string; outputUriPrefix: string}>; operation: OperationState; exists: boolean; failExport?: Error; liveOperations: Array<{name: string; outputUriPrefix: string; done: boolean; failed: boolean; state: string}>; exportResponseName?: string | null; listingError?: Error; exportAttempts: number; failTransactions: number; failExportAfterAccept?: Error};

function fakeDeps(env: Record<string, string | undefined> = {BACKUP_BUCKET: "test-bucket"}): Fake {
  let counter = 0;
  const proxy = new Proxy(db, {
    get(target, prop) {
      if (prop === "runTransaction" && fake.failTransactions > 0) {
        return async () => {
          fake.failTransactions--;
          throw Object.assign(new Error("10 ABORTED: transaction contention"), {code: 10});
        };
      }
      const value = Reflect.get(target, prop);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const fake: Fake = {
    db: proxy,
    exportCalls: [],
    operation: {done: false},
    exists: true,
    liveOperations: [],
    exportResponseName: "op-1",
    exportAttempts: 0,
    failTransactions: 0,
    env,
    projectId: "demo-mindmate-pr2",
    now: () => new Date("2026-11-15T02:30:00Z"),
    newJobId: () => `${prefix}-job-${++counter}`,
    exporter: {
      async exportDocuments(request) {
        fake.exportAttempts++;
        if (fake.failExport) throw fake.failExport;
        fake.exportCalls.push(request);
        // The upstream API accepted the export but the reply is lost.
        if (fake.failExportAfterAccept) throw fake.failExportAfterAccept;
        return [{name: fake.exportResponseName}];
      },
      async checkExportDocumentsProgress() {
        return fake.operation;
      },
      async listExportOperations() {
        if (fake.listingError) throw fake.listingError;
        return fake.liveOperations;
      },
    },
    objectExists: async () => fake.exists,
  };
  return fake;
}

async function clearJobs(): Promise<void> {
  const jobs = await db.collection("backup_jobs").where("requestedBy", "in", [adminUid, "system"]).get();
  await Promise.all(jobs.docs.map((d) => d.ref.delete()));
}

async function auditRows(action: string): Promise<number> {
  const rows = await db.collection("admin_audit_logs").where("action", "==", action).where("actorId", "in", [adminUid, "system"]).get();
  return rows.size;
}

async function denied(promise: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(promise, (error: unknown) => error instanceof HttpsError && error.code === code);
}

before(async () => {
  if (!emulated) return;
  await getAuth().createUser({uid: adminUid, email: `${adminUid}@example.invalid`, emailVerified: true});
  await getAuth().createUser({uid: counselorUid, email: `${counselorUid}@example.invalid`, emailVerified: true});
  await db.doc(`users/${adminUid}`).set({accessRole: "admin", accountStatus: "active", name: "Test Admin"});
  await db.doc(`users/${counselorUid}`).set({accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"});
});

after(async () => {
  if (!emulated) return;
  await clearJobs();
  await Promise.all([adminUid, counselorUid].map((uid) => getAuth().deleteUser(uid).catch(() => undefined)));
});

test("startBackup records a running job with coverage, retention and an audit row", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  const result = await startBackup(deps, actor, "manual");
  assert.equal(result.status, "running");
  const job = (await db.doc(`backup_jobs/${result.jobId}`).get()).data()!;
  assert.equal(job.status, "running");
  assert.equal(job.trigger, "manual");
  assert.equal(job.requestedBy, adminUid);
  assert.deepEqual(job.coverage, {firestore: "included", auth: "excluded", storage: "excluded"});
  assert.equal(job.operationName, "op-1");
  assert.equal(job.revision, 2);
  assert.equal(job.retentionDays, 30);
  assert.equal(job.outputUriPrefix, `gs://test-bucket/firestore-exports/20261115-023000-${result.jobId}`);
  assert.equal((job.expiresAt as Timestamp).toMillis() - (job.requestedAt as Timestamp).toMillis(), 30 * 24 * 60 * 60 * 1_000);
  assert.deepEqual(deps.exportCalls, [{name: "projects/demo-mindmate-pr2/databases/(default)", outputUriPrefix: job.outputUriPrefix}]);
  assert.equal(await auditRows("BACKUP_REQUESTED"), 1);
});

test("startBackup without a configured bucket is a failed-precondition and writes nothing", {skip: !emulated}, async () => {
  await clearJobs();
  await denied(startBackup(fakeDeps({}), actor, "manual"), "failed-precondition");
  assert.equal((await db.collection("backup_jobs").where("requestedBy", "==", adminUid).get()).size, 0);
});

test("a second request while a job is running is refused without a second export call", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  await startBackup(deps, actor, "manual");
  await denied(startBackup(deps, actor, "manual"), "failed-precondition");
  assert.equal(deps.exportCalls.length, 1);
});

test("an export call failure marks the job failed with a sanitised error", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  deps.failExport = Object.assign(new Error("Permission denied on bucket " + "x".repeat(400)), {code: 7});
  await denied(startBackup(deps, actor, "manual"), "internal");
  const jobs = await db.collection("backup_jobs").where("requestedBy", "==", adminUid).get();
  assert.equal(jobs.size, 1);
  const job = jobs.docs[0].data();
  assert.equal(job.status, "failed");
  assert.equal(job.error.code, "export-7");
  assert.ok(job.error.message.length <= 300);
  assert.equal(job.operationName, null);
  assert.equal(await auditRows("BACKUP_FAILED"), 1);
});

test("refreshBackup keeps a running job running and records progress", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  const {jobId} = await startBackup(deps, actor, "manual");
  deps.operation = {done: false, metadata: {progressDocuments: {completedWork: "4", estimatedWork: "8"}}};
  const result = await refreshBackup(deps, actor, jobId);
  assert.equal(result.status, "running");
  const job = (await db.doc(`backup_jobs/${jobId}`).get()).data()!;
  assert.equal(job.progress.documents.completed, 4);
  assert.equal(job.revision, 3);
});

test("refreshBackup completes only when the export metadata object exists, and is idempotent", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  const {jobId} = await startBackup(deps, actor, "manual");
  deps.operation = {done: true};
  deps.exists = true;
  assert.equal((await refreshBackup(deps, actor, jobId)).status, "completed");
  const job = (await db.doc(`backup_jobs/${jobId}`).get()).data()!;
  assert.equal(job.verification.status, "verified");
  assert.equal(job.verification.metadataPath, `firestore-exports/20261115-023000-${jobId}/20261115-023000-${jobId}.overall_export_metadata`);
  assert.ok(job.completedAt instanceof Timestamp);
  const completedRows = await auditRows("BACKUP_COMPLETED");
  assert.equal(completedRows, 1);
  const revision = job.revision;
  assert.equal((await refreshBackup(deps, actor, jobId)).status, "completed");
  assert.equal((await db.doc(`backup_jobs/${jobId}`).get()).data()!.revision, revision);
  assert.equal(await auditRows("BACKUP_COMPLETED"), completedRows);
});

test("refreshBackup marks a finished export failed when its metadata object is missing", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  const {jobId} = await startBackup(deps, actor, "manual");
  deps.operation = {done: true};
  deps.exists = false;
  assert.equal((await refreshBackup(deps, actor, jobId)).status, "failed");
  const job = (await db.doc(`backup_jobs/${jobId}`).get()).data()!;
  assert.equal(job.verification.status, "missing");
  assert.equal(job.error.code, "export-metadata-missing");
  assert.ok((await auditRows("BACKUP_FAILED")) >= 1);
});

async function expectBlocked(deps: Fake): Promise<void> {
  const attempts = deps.exportAttempts;
  await denied(startBackup(deps, actor, "manual"), "failed-precondition");
  const scheduled = fakeDeps({BACKUP_BUCKET: "test-bucket", BACKUP_SCHEDULE_ENABLED: "true"});
  scheduled.exporter.checkExportDocumentsProgress = deps.exporter.checkExportDocumentsProgress;
  scheduled.listingError = deps.listingError;
  scheduled.liveOperations = deps.liveOperations;
  assert.deepEqual(await runScheduledBackup(scheduled), {started: false, reason: "job-running"});
  assert.equal(deps.exportAttempts, attempts, "no second export attempt during uncertainty");
  assert.equal(scheduled.exportAttempts, 0, "the scheduler must not export during uncertainty");
}

test("a transient status lookup error keeps the job running and blocked, then completes once lookup recovers", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  const {jobId} = await startBackup(deps, actor, "manual");
  const failedBefore = await auditRows("BACKUP_FAILED");
  const lookup = deps.exporter.checkExportDocumentsProgress;
  for (const code of [14, 4, 7, 5]) {
    deps.exporter.checkExportDocumentsProgress = async () => { throw Object.assign(new Error(`lookup failed ${code}`), {code}); };
    assert.equal((await refreshBackup(deps, actor, jobId)).status, "running", `code ${code}`);
    const job = (await db.doc(`backup_jobs/${jobId}`).get()).data()!;
    assert.equal(job.status, "running");
    assert.equal(job.operationName, "op-1");
    assert.equal(job.reconciliation.status, "uncertain");
    assert.equal(job.reconciliation.reason, "status-lookup-failed");
    assert.equal(job.reconciliation.lastErrorCode, `export-${code}`);
    assert.equal(job.completedAt, null);
  }
  assert.equal(await auditRows("BACKUP_FAILED"), failedBefore, "an uncertain lookup is not an audited failure");
  await expectBlocked(deps);
  deps.exporter.checkExportDocumentsProgress = lookup;
  deps.operation = {done: true};
  deps.exists = true;
  assert.equal((await refreshBackup(deps, actor, jobId)).status, "completed");
  assert.equal(deps.exportAttempts, 1);
});

test("a definitive export failure reported by the operation is still terminal", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  const {jobId} = await startBackup(deps, actor, "manual");
  deps.operation = {done: true, error: {code: 7, message: "The caller does not have permission"}};
  assert.equal((await refreshBackup(deps, actor, jobId)).status, "failed");
  assert.equal((await db.doc(`backup_jobs/${jobId}`).get()).data()!.error.code, "export-7");
  assert.equal((await startBackup(deps, actor, "manual")).status, "running");
});

test("an ambiguous export-start error keeps the job running and uncertain, and blocks duplicates", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  deps.failExportAfterAccept = Object.assign(new Error("14 UNAVAILABLE: connection reset"), {code: 14});
  await denied(startBackup(deps, actor, "manual"), "unavailable");
  const jobs = await db.collection("backup_jobs").where("requestedBy", "==", adminUid).get();
  assert.equal(jobs.size, 1);
  const job = jobs.docs[0].data();
  assert.equal(job.status, "running");
  assert.equal(job.operationName, null);
  assert.equal(job.reconciliation.status, "uncertain");
  assert.equal(job.reconciliation.reason, "export-start-ambiguous");
  assert.equal(job.reconciliation.lastErrorCode, "export-14");
  assert.equal(deps.exportAttempts, 1);
  deps.failExportAfterAccept = undefined;
  await expectBlocked(deps);
  // Reconciliation later finds the accepted operation by prefix and adopts it.
  deps.liveOperations = [{name: "op-recovered", outputUriPrefix: job.outputUriPrefix, done: false, failed: false, state: "PROCESSING"}];
  assert.equal((await refreshBackup(deps, actor, jobs.docs[0].id)).status, "running");
  assert.equal((await db.doc(`backup_jobs/${jobs.docs[0].id}`).get()).data()!.operationName, "op-recovered");
  assert.equal(deps.exportAttempts, 1);
});

test("a successful export followed by a failed operation-name save never marks the job failed", {skip: !emulated}, async () => {
  for (const failures of [1, 2]) {
    await clearJobs();
    const deps = fakeDeps();
    const failedBefore = await auditRows("BACKUP_FAILED");
    const exporter = deps.exporter.exportDocuments;
    deps.exporter.exportDocuments = async (request) => {
      const result = await exporter(request);
      deps.failTransactions = failures; // persistence fails only after upstream acceptance
      return result;
    };
    const result = await startBackup(deps, actor, "manual");
    assert.equal(result.status, "running", `failures ${failures}`);
    const job = (await db.doc(`backup_jobs/${result.jobId}`).get()).data()!;
    assert.equal(job.status, "running");
    assert.equal(job.operationName, null);
    assert.equal(await auditRows("BACKUP_FAILED"), failedBefore);
    if (failures === 1) {
      assert.equal(job.reconciliation.status, "uncertain");
      assert.equal(job.reconciliation.reason, "operation-name-not-persisted");
    }
    assert.equal(deps.exportAttempts, 1);
    deps.exporter.exportDocuments = exporter;
    await expectBlocked(deps);
    // The accepted operation is found by prefix and adopted, never re-exported.
    deps.liveOperations = [{name: "op-1", outputUriPrefix: job.outputUriPrefix, done: false, failed: false, state: "PROCESSING"}];
    assert.equal((await refreshBackup(deps, actor, result.jobId)).status, "running");
    assert.equal((await db.doc(`backup_jobs/${result.jobId}`).get()).data()!.operationName, "op-1");
    assert.equal(deps.exportAttempts, 1);
  }
});

async function orphanJob(deps: Fake, ageMinutes: number): Promise<string> {
  const jobId = deps.newJobId();
  const requestedAt = Timestamp.fromMillis(deps.now().getTime() - ageMinutes * 60_000);
  await db.doc(`backup_jobs/${jobId}`).set({
    jobId, status: "running", trigger: "manual", requestedBy: adminUid, requestedAt,
    startedAt: null, completedAt: null, operationName: null,
    outputUriPrefix: `gs://test-bucket/firestore-exports/20261115-023000-${jobId}`,
    coverage: {firestore: "included", auth: "excluded", storage: "excluded"}, progress: null,
    verification: {status: "pending", metadataPath: `firestore-exports/20261115-023000-${jobId}/20261115-023000-${jobId}.overall_export_metadata`, checkedAt: null},
    error: null, retentionDays: 30, expiresAt: requestedAt, revision: 1,
  });
  return jobId;
}

test("an orphaned start with no live export operation is failed after the grace period and unblocks later backups", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  const jobId = await orphanJob(deps, 30);
  assert.equal((await refreshBackup(deps, actor, jobId)).status, "failed");
  const job = (await db.doc(`backup_jobs/${jobId}`).get()).data()!;
  assert.equal(job.error.code, "export-start-orphaned");
  assert.ok(job.completedAt instanceof Timestamp);
  assert.ok((await auditRows("BACKUP_FAILED")) >= 1);
  assert.equal(deps.exportCalls.length, 0);
  assert.equal((await startBackup(deps, actor, "manual")).status, "running");
  assert.equal(deps.exportCalls.length, 1);
});

test("an orphaned start whose export is actually running adopts the operation instead of starting another", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  const jobId = await orphanJob(deps, 30);
  deps.liveOperations = [{name: "op-live", outputUriPrefix: `gs://test-bucket/firestore-exports/20261115-023000-${jobId}`, done: false, failed: false, state: "PROCESSING"}];
  assert.equal((await refreshBackup(deps, actor, jobId)).status, "running");
  const job = (await db.doc(`backup_jobs/${jobId}`).get()).data()!;
  assert.equal(job.operationName, "op-live");
  assert.equal(deps.exportCalls.length, 0);
  await denied(startBackup(deps, actor, "manual"), "failed-precondition");
  // Once adopted, normal completion applies.
  deps.operation = {done: true};
  assert.equal((await refreshBackup(deps, actor, jobId)).status, "completed");
});

test("a very recent nameless job is left alone because its start may still be in flight", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  const jobId = await orphanJob(deps, 1);
  assert.equal((await refreshBackup(deps, actor, jobId)).status, "running");
  const job = (await db.doc(`backup_jobs/${jobId}`).get()).data()!;
  assert.equal(job.operationName, null);
  assert.equal(job.revision, 1);
});

test("an orphaned start whose export already completed is adopted and verified, never re-exported", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  const jobId = await orphanJob(deps, 30);
  deps.liveOperations = [{name: "op-done", outputUriPrefix: `gs://test-bucket/firestore-exports/20261115-023000-${jobId}`, done: true, failed: false, state: "SUCCESSFUL"}];
  deps.operation = {done: true};
  deps.exists = true;
  assert.equal((await refreshBackup(deps, actor, jobId)).status, "completed");
  const job = (await db.doc(`backup_jobs/${jobId}`).get()).data()!;
  assert.equal(job.operationName, "op-done");
  assert.equal(job.verification.status, "verified");
  assert.equal(deps.exportCalls.length, 0);
});

test("an unavailable operation listing leaves an orphaned job running and blocks new exports", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps({BACKUP_BUCKET: "test-bucket", BACKUP_SCHEDULE_ENABLED: "true"});
  const jobId = await orphanJob(deps, 30);
  deps.listingError = new Error("listing PERMISSION_DENIED");
  assert.equal((await refreshBackup(deps, actor, jobId)).status, "running");
  const job = (await db.doc(`backup_jobs/${jobId}`).get()).data()!;
  assert.equal(job.status, "running");
  assert.equal(job.operationName, null);
  assert.equal(job.reconciliation.status, "uncertain");
  await denied(startBackup(deps, actor, "manual"), "failed-precondition");
  assert.equal(deps.exportCalls.length, 0);
  assert.deepEqual(await runScheduledBackup(deps), {started: false, reason: "job-running"});
  assert.equal(deps.exportCalls.length, 0);
  assert.equal((await db.doc(`backup_jobs/${jobId}`).get()).data()!.status, "running");
});

test("an export response without an operation name keeps the job running for reconciliation instead of guessing", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps();
  deps.exportResponseName = null;
  const result = await startBackup(deps, actor, "manual");
  assert.equal(result.status, "running");
  const job = (await db.doc(`backup_jobs/${jobId(result)}`).get()).data()!;
  assert.equal(job.status, "running");
  assert.equal(job.operationName, null);
  assert.equal(job.reconciliation.status, "uncertain");
  assert.equal(job.reconciliation.reason, "export-response-without-name");
  // No duplicate export can be started while the outcome is unknown.
  await denied(startBackup(deps, actor, "manual"), "failed-precondition");
  assert.equal(deps.exportCalls.length, 1);
});

function jobId(result: {jobId: string}): string { return result.jobId; }

test("the scheduler does nothing unless BACKUP_SCHEDULE_ENABLED is true", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps({BACKUP_BUCKET: "test-bucket"});
  const before = await db.collection("admin_audit_logs").get();
  assert.deepEqual(await runScheduledBackup(deps), {started: false, reason: "disabled"});
  assert.equal(deps.exportCalls.length, 0);
  assert.equal((await db.collection("backup_jobs").where("requestedBy", "==", "system").get()).size, 0);
  assert.equal((await db.collection("admin_audit_logs").get()).size, before.size);
  assert.deepEqual(await runScheduledBackup(fakeDeps({BACKUP_SCHEDULE_ENABLED: "true"})), {started: false, reason: "not-configured"});
});

test("the enabled scheduler skips while a job runs and otherwise starts a system job", {skip: !emulated}, async () => {
  await clearJobs();
  const deps = fakeDeps({BACKUP_BUCKET: "test-bucket", BACKUP_SCHEDULE_ENABLED: "true"});
  await startBackup(deps, actor, "manual");
  const skippedBefore = await auditRows("BACKUP_SKIPPED");
  assert.deepEqual(await runScheduledBackup(deps), {started: false, reason: "job-running"});
  assert.equal(await auditRows("BACKUP_SKIPPED"), skippedBefore + 1);
  await clearJobs();
  assert.deepEqual(await runScheduledBackup(deps), {started: true});
  const jobs = await db.collection("backup_jobs").where("requestedBy", "==", "system").get();
  assert.equal(jobs.size, 1);
  assert.equal(jobs.docs[0].data().trigger, "scheduled");
});

test("the callable refuses everyone but the configured super-administrator", {skip: !emulated}, async () => {
  const previous = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = adminUid;
  try {
    const callable = requestFirestoreBackup as unknown as {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<unknown>};
    await denied(callable.run({auth: {uid: counselorUid}, data: {}}), "permission-denied");
    await assert.rejects(callable.run({data: {}}), (error: unknown) => error instanceof HttpsError && error.code === "unauthenticated");
  } finally {
    if (previous == null) delete process.env.SUPER_ADMIN_UID; else process.env.SUPER_ADMIN_UID = previous;
  }
});
