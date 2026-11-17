import {randomUUID} from "node:crypto";
import {v1 as firestoreAdmin} from "@google-cloud/firestore";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {requireSuperAdmin, requireUid} from "./access";
import {
  ExportOperationSummary,
  findOperationForPrefix,
  listExportOperations as listExportOperationsFrom,
  OperationListingUnavailableError,
  RawOperation,
} from "./backup_operations";
import {actorName, AUDIT_CATEGORIES, writeAudit} from "./audit";
import {
  applyOperationState,
  assertCanStart,
  BACKUP_COVERAGE,
  BackupConfigError,
  BackupJobRecord,
  BackupJobStatus,
  BackupTrigger,
  exportPrefixFor,
  isDefinitiveExportRejection,
  OperationState,
  resolveBackupConfig,
  sanitizeError,
  StartBlockedError,
  verificationFor,
} from "./backup_jobs";

// Firestore managed exports into a private bucket. Phase 1 covers Firestore
// only; Firebase Auth users and Storage files are excluded and every job says
// so in `coverage`. Clients never receive bucket contents or signed URLs.

export type BackupActor = {uid: string; name: string; role: string};

export type BackupDeps = {
  db: FirebaseFirestore.Firestore;
  exporter: {
    exportDocuments(request: {name: string; outputUriPrefix: string}): Promise<[{name?: string | null}]>;
    checkExportDocumentsProgress(name: string): Promise<OperationState>;
    /**
     * Export operations known to the database (running, failed and completed),
     * used to reconcile a job whose start was interrupted. Must throw
     * OperationListingUnavailableError when the answer is incomplete.
     */
    listExportOperations(databaseName: string): Promise<ExportOperationSummary[]>;
  };
  objectExists(bucket: string, path: string): Promise<boolean>;
  env: Record<string, string | undefined>;
  projectId: string;
  now(): Date;
  newJobId(): string;
};

const SYSTEM_ACTOR: BackupActor = {uid: "system", name: "Scheduled backup", role: "system"};
const JOBS = "backup_jobs";
// A job created without an operation name may still be mid-start (the export
// call is in flight). Only after this long do we treat the start as orphaned.
export const ORPHAN_GRACE_MS = 10 * 60 * 1_000;

let adminClient: InstanceType<typeof firestoreAdmin.FirestoreAdminClient> | null = null;

function resolveProjectId(env: Record<string, string | undefined> = process.env): string {
  const direct = (env.GCLOUD_PROJECT ?? env.GOOGLE_CLOUD_PROJECT ?? "").trim();
  if (direct) return direct;
  try {
    const parsed = JSON.parse(env.FIREBASE_CONFIG ?? "{}") as {projectId?: unknown};
    return typeof parsed.projectId === "string" ? parsed.projectId.trim() : "";
  } catch {
    return "";
  }
}

export function defaultDeps(): BackupDeps {
  adminClient ??= new firestoreAdmin.FirestoreAdminClient();
  const client = adminClient;
  return {
    db: getFirestore(),
    exporter: {
      async exportDocuments(request) {
        const [operation] = await client.exportDocuments(request);
        return [{name: operation.name}];
      },
      async checkExportDocumentsProgress(name) {
        const operation = await client.checkExportDocumentsProgress(name);
        return operation as unknown as OperationState;
      },
      async listExportOperations(databaseName) {
        // The admin client's own long-running descriptor decodes the Any-wrapped
        // ExportDocumentsMetadata; no separate protobuf dependency is needed.
        const decoder = client.descriptors?.longrunning?.exportDocuments?.metadataDecoder as ((bytes: Uint8Array) => unknown) | undefined;
        if (typeof decoder !== "function") throw new OperationListingUnavailableError("Export metadata decoder is unavailable.");
        const page = (filter: string): AsyncIterable<RawOperation> => client.operationsClient.listOperationsAsync(
          {name: databaseName, filter} as unknown as Parameters<typeof client.operationsClient.listOperationsAsync>[0],
        ) as AsyncIterable<RawOperation>;
        return listExportOperationsFrom(page, decoder);
      },
    },
    async objectExists(bucket, path) {
      const [exists] = await getStorage().bucket(bucket).file(path).exists();
      return exists;
    },
    env: process.env,
    projectId: resolveProjectId(process.env),
    now: () => new Date(),
    newJobId: () => randomUUID(),
  };
}

function toRecord(data: FirebaseFirestore.DocumentData): BackupJobRecord {
  const at = (value: unknown): Date => value instanceof Timestamp ? value.toDate() : new Date(0);
  return {
    status: String(data.status ?? "failed") as BackupJobStatus,
    trigger: String(data.trigger ?? "manual") as BackupTrigger,
    requestedBy: String(data.requestedBy ?? ""),
    requestedAt: at(data.requestedAt),
    operationName: data.operationName ?? null,
    progress: data.progress ?? null,
    verification: data.verification
      ? {...data.verification, checkedAt: data.verification.checkedAt instanceof Timestamp ? data.verification.checkedAt.toDate() : null}
      : null,
    error: data.error ?? null,
  };
}

function audit(
  tx: FirebaseFirestore.Transaction,
  db: FirebaseFirestore.Firestore,
  actor: BackupActor,
  action: "BACKUP_REQUESTED" | "BACKUP_COMPLETED" | "BACKUP_FAILED" | "BACKUP_SKIPPED",
  jobId: string,
  metadata: Record<string, unknown>,
): void {
  writeAudit(tx, db, {
    actorId: actor.uid,
    actorNameSnapshot: actor.name,
    actorRoleSnapshot: actor.role,
    action,
    category: AUDIT_CATEGORIES.system,
    targetType: "backup_job",
    targetId: jobId,
    metadata,
  });
}

function configOrThrow(env: Record<string, string | undefined>) {
  try {
    return resolveBackupConfig(env);
  } catch (error) {
    if (error instanceof BackupConfigError) throw new HttpsError("failed-precondition", error.message);
    throw error;
  }
}

export async function startBackup(deps: BackupDeps, actor: BackupActor, trigger: BackupTrigger): Promise<{jobId: string; status: BackupJobStatus}> {
  const config = configOrThrow(deps.env);
  const now = deps.now();
  const jobId = deps.newJobId();
  const {outputUriPrefix, metadataPath} = exportPrefixFor(config.bucket, now, jobId);
  const ref = deps.db.collection(JOBS).doc(jobId);
  const requestedAt = Timestamp.fromDate(now);

  await deps.db.runTransaction(async (tx) => {
    const [running, recent] = await Promise.all([
      tx.get(deps.db.collection(JOBS).where("status", "==", "running").limit(1)),
      tx.get(deps.db.collection(JOBS).orderBy("requestedAt", "desc").limit(50)),
    ]);
    const uniqueDocs = new Map<string, FirebaseFirestore.DocumentData>();
    for (const doc of [...running.docs, ...recent.docs]) uniqueDocs.set(doc.id, doc.data());
    try {
      assertCanStart([...uniqueDocs.values()].map(toRecord), now, {trigger, manualDailyLimit: config.manualDailyLimit});
    } catch (error) {
      if (error instanceof StartBlockedError) throw new HttpsError("failed-precondition", error.message);
      throw error;
    }
    tx.create(ref, {
      jobId,
      status: "running",
      trigger,
      requestedBy: actor.uid,
      requestedAt,
      startedAt: null,
      completedAt: null,
      operationName: null,
      outputUriPrefix,
      coverage: {...BACKUP_COVERAGE},
      progress: null,
      verification: {status: "pending", metadataPath, checkedAt: null},
      error: null,
      retentionDays: config.retentionDays,
      expiresAt: Timestamp.fromMillis(requestedAt.toMillis() + config.retentionDays * 24 * 60 * 60 * 1_000),
      revision: 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    audit(tx, deps.db, actor, "BACKUP_REQUESTED", jobId, {trigger, outputUriPrefix, retentionDays: config.retentionDays});
  });

  // Step 1: ask Firestore to start the export. Only a definitive rejection is
  // terminal; any other error leaves open whether the paid export started.
  let operation: {name?: string | null};
  try {
    [operation] = await deps.exporter.exportDocuments({
      name: `projects/${deps.projectId}/databases/(default)`,
      outputUriPrefix,
    });
  } catch (error) {
    const safe = sanitizeError(error);
    if (!isDefinitiveExportRejection(error)) {
      // Keep the job running (new starts stay blocked) until reconciliation
      // finds the operation by prefix or proves none exists.
      await markUncertain(deps, ref, "export-start-ambiguous", safe.code);
      throw new HttpsError("unavailable", `The export request outcome is unknown (${safe.code}). The job stays open until it is reconciled.`);
    }
    await deps.db.runTransaction(async (tx) => {
      tx.update(ref, {
        status: "failed",
        error: safe,
        completedAt: Timestamp.fromDate(deps.now()),
        revision: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
      audit(tx, deps.db, actor, "BACKUP_FAILED", jobId, {stage: "export-request-rejected", error: safe});
    });
    throw new HttpsError("internal", `The export request was rejected (${safe.code}).`);
  }

  // Step 2: the export was accepted. From here on nothing may mark the job
  // failed: a persistence error only means we could not record the name.
  if (typeof operation.name !== "string" || !operation.name.trim()) {
    await markUncertain(deps, ref, "export-response-without-name", null);
    return {jobId, status: "running"};
  }
  const operationName = operation.name;
  try {
    await deps.db.runTransaction(async (tx) => {
      tx.update(ref, {
        operationName,
        startedAt: Timestamp.fromDate(deps.now()),
        revision: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  } catch (error) {
    await markUncertain(deps, ref, "operation-name-not-persisted", sanitizeError(error).code);
  }
  return {jobId, status: "running"};
}

/**
 * Record that a running job's export outcome is not yet known. Best effort:
 * if even this write fails, the job is still `running` with no operation name,
 * which reconciliation already treats as needing a lookup by prefix.
 */
async function markUncertain(
  deps: BackupDeps,
  ref: FirebaseFirestore.DocumentReference,
  reason: string,
  lastErrorCode: string | null,
): Promise<void> {
  try {
    await deps.db.runTransaction(async (tx) => {
      const current = (await tx.get(ref)).data() ?? {};
      if (current.status !== "running") return;
      tx.update(ref, {
        reconciliation: {status: "uncertain", reason, lastErrorCode, checkedAt: Timestamp.fromDate(deps.now())},
        revision: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  } catch (error) {
    console.warn("Backup job uncertainty could not be recorded; the job remains running.", sanitizeError(error).code);
  }
}

export async function refreshBackup(deps: BackupDeps, actor: BackupActor, jobId: string): Promise<{jobId: string; status: BackupJobStatus}> {
  const ref = deps.db.collection(JOBS).doc(jobId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Backup job not found.");
  const data = snapshot.data() ?? {};
  const status = String(data.status) as BackupJobStatus;
  if (status !== "running") return {jobId, status};
  if (typeof data.operationName !== "string" || !data.operationName) {
    return reconcileOrphanedStart(deps, actor, jobId, data);
  }

  // A failed status lookup says nothing about the export itself (it may still
  // be running), so it never ends the job. Only the operation's own result,
  // read successfully, can mark it completed or failed. The job stays running,
  // keeping new exports blocked, until a later refresh reads the real state.
  let next: ReturnType<typeof applyOperationState>;
  try {
    next = applyOperationState(await deps.exporter.checkExportDocumentsProgress(data.operationName));
  } catch (error) {
    await markUncertain(deps, ref, "status-lookup-failed", sanitizeError(error).code);
    return {jobId, status: "running"};
  }
  const now = deps.now();
  const revision = Number(data.revision ?? 0);
  const metadataPath = String(data.verification?.metadataPath ?? "");
  const bucket = String(data.outputUriPrefix ?? "").replace(/^gs:\/\//, "").split("/")[0];
  const exists = next.status === "exported" && bucket.length > 0 && metadataPath.length > 0
    ? await deps.objectExists(bucket, metadataPath)
    : false;

  return deps.db.runTransaction(async (tx) => {
    const current = await tx.get(ref);
    const live = current.data() ?? {};
    // Another refresh finished first: report what it decided, change nothing.
    if (live.status !== "running" || Number(live.revision ?? 0) !== revision) {
      return {jobId, status: String(live.status) as BackupJobStatus};
    }
    const base = {revision: revision + 1, updatedAt: FieldValue.serverTimestamp()};
    if (next.status === "running") {
      tx.update(ref, {...base, progress: next.progress});
      return {jobId, status: "running" as const};
    }
    if (next.status === "failed") {
      tx.update(ref, {...base, status: "failed", error: next.error, completedAt: Timestamp.fromDate(now)});
      audit(tx, deps.db, actor, "BACKUP_FAILED", jobId, {stage: "export-operation", error: next.error});
      return {jobId, status: "failed" as const};
    }
    const verification = verificationFor(metadataPath, exists, now);
    const stored = {...verification, checkedAt: Timestamp.fromDate(now)};
    if (verification.status === "verified") {
      tx.update(ref, {...base, status: "completed", verification: stored, completedAt: Timestamp.fromDate(now), error: null});
      audit(tx, deps.db, actor, "BACKUP_COMPLETED", jobId, {metadataPath, documents: live.progress?.documents ?? null});
      return {jobId, status: "completed" as const};
    }
    const error = {code: "export-metadata-missing", message: "The export finished but its metadata file was not found in the backup bucket."};
    tx.update(ref, {...base, status: "failed", verification: stored, error, completedAt: Timestamp.fromDate(now)});
    audit(tx, deps.db, actor, "BACKUP_FAILED", jobId, {stage: "verification", error});
    return {jobId, status: "failed" as const};
  });
}

/**
 * A job that is `running` without an operation name had its start interrupted
 * between creating the record and storing the export API's answer. Never guess:
 * ask the database for export operations targeting this job's prefix. If one
 * exists, adopt it (the paid export is already running, do not start another).
 * If none exists after the grace period, the start never happened: fail the
 * job so later backups are unblocked. Inside the grace period, leave it alone.
 */
async function reconcileOrphanedStart(
  deps: BackupDeps,
  actor: BackupActor,
  jobId: string,
  data: FirebaseFirestore.DocumentData,
): Promise<{jobId: string; status: BackupJobStatus}> {
  const ref = deps.db.collection(JOBS).doc(jobId);
  const now = deps.now();
  const prefix = String(data.outputUriPrefix ?? "");
  const revision = Number(data.revision ?? 0);
  const guard = (current: FirebaseFirestore.DocumentData) =>
    current.status === "running" && Number(current.revision ?? 0) === revision && !current.operationName;

  let operations: ExportOperationSummary[];
  try {
    operations = await deps.exporter.listExportOperations(`projects/${deps.projectId}/databases/(default)`);
  } catch (error) {
    // Unknown whether an export is running: keep the job running (which keeps
    // new exports blocked) and record why, so an operator can see it.
    const reason = error instanceof OperationListingUnavailableError ? "operation-listing-unavailable" : "operation-listing-error";
    await deps.db.runTransaction(async (tx) => {
      const current = (await tx.get(ref)).data() ?? {};
      if (!guard(current)) return;
      tx.update(ref, {
        reconciliation: {status: "uncertain", reason, checkedAt: Timestamp.fromDate(now), detail: sanitizeError(error).message},
        revision: revision + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    return {jobId, status: "running"};
  }

  const live = findOperationForPrefix(operations, prefix);
  if (live) {
    // Running or already finished: adopt the operation, then let the normal
    // refresh path verify and record its outcome. Never start another export.
    const adopted = await deps.db.runTransaction(async (tx) => {
      const current = (await tx.get(ref)).data() ?? {};
      if (!guard(current)) return false;
      tx.update(ref, {
        operationName: live.name,
        startedAt: Timestamp.fromDate(now),
        reconciliation: {status: "adopted", reason: live.done ? "operation-already-finished" : "operation-running", checkedAt: Timestamp.fromDate(now)},
        revision: revision + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    return adopted ? refreshBackup(deps, actor, jobId) : {jobId, status: "running"};
  }

  const requestedAt = data.requestedAt instanceof Timestamp ? data.requestedAt.toMillis() : 0;
  if (now.getTime() - requestedAt < ORPHAN_GRACE_MS) return {jobId, status: "running"};
  // Both listings answered and neither knows this prefix: the export was never
  // accepted. Failing the job unblocks later backups without duplicating one.
  const error = {code: "export-start-orphaned", message: "The backup record was created but no export operation exists for it."};
  return deps.db.runTransaction(async (tx) => {
    const current = (await tx.get(ref)).data() ?? {};
    if (!guard(current)) return {jobId, status: String(current.status) as BackupJobStatus};
    tx.update(ref, {
      status: "failed", error, completedAt: Timestamp.fromDate(now),
      reconciliation: {status: "orphaned", reason: "no-operation-for-prefix", checkedAt: Timestamp.fromDate(now)},
      revision: revision + 1, updatedAt: FieldValue.serverTimestamp(),
    });
    audit(tx, deps.db, actor, "BACKUP_FAILED", jobId, {stage: "orphaned-start", error});
    return {jobId, status: "failed" as const};
  });
}

export async function runScheduledBackup(deps: BackupDeps): Promise<{started: boolean; reason?: "disabled" | "job-running" | "not-configured"}> {
  if ((deps.env.BACKUP_SCHEDULE_ENABLED ?? "").trim().toLowerCase() !== "true") return {started: false, reason: "disabled"};
  try {
    resolveBackupConfig(deps.env);
  } catch (error) {
    if (error instanceof BackupConfigError) return {started: false, reason: "not-configured"};
    throw error;
  }
  const running = await deps.db.collection(JOBS).where("status", "==", "running").get();
  for (const job of running.docs) await refreshBackup(deps, SYSTEM_ACTOR, job.id);
  const stillRunning = await deps.db.collection(JOBS).where("status", "==", "running").limit(1).get();
  if (!stillRunning.empty) {
    const blocking = stillRunning.docs[0].id;
    await deps.db.runTransaction(async (tx) => {
      audit(tx, deps.db, SYSTEM_ACTOR, "BACKUP_SKIPPED", blocking, {reason: "job-running"});
    });
    return {started: false, reason: "job-running"};
  }
  await startBackup(deps, SYSTEM_ACTOR, "scheduled");
  return {started: true};
}

async function callableActor(request: {auth?: {uid: string} | null}): Promise<BackupActor> {
  const uid = requireUid(request);
  const admin = await requireSuperAdmin(uid);
  return {uid, name: actorName(admin), role: String(admin.accessRole)};
}

export const requestFirestoreBackup = onCall(async (request) => {
  const actor = await callableActor(request);
  return startBackup(defaultDeps(), actor, "manual");
});

export const refreshFirestoreBackupStatus = onCall(async (request) => {
  const actor = await callableActor(request);
  const jobId = typeof request.data?.jobId === "string" ? request.data.jobId.trim() : "";
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(jobId)) throw new HttpsError("invalid-argument", "A backup job ID is required.");
  return refreshBackup(defaultDeps(), actor, jobId);
});

export const scheduledFirestoreBackup = onSchedule(
  {schedule: "every day 02:30", timeZone: "Asia/Manila", region: "asia-east1", timeoutSeconds: 300},
  async () => {
    await runScheduledBackup(defaultDeps());
  },
);
