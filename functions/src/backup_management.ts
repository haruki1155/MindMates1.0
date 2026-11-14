import {randomUUID} from "node:crypto";
import {v1 as firestoreAdmin} from "@google-cloud/firestore";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {requireSuperAdmin, requireUid} from "./access";
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
  };
  objectExists(bucket: string, path: string): Promise<boolean>;
  env: Record<string, string | undefined>;
  projectId: string;
  now(): Date;
  newJobId(): string;
};

const SYSTEM_ACTOR: BackupActor = {uid: "system", name: "Scheduled backup", role: "system"};
const JOBS = "backup_jobs";

let adminClient: InstanceType<typeof firestoreAdmin.FirestoreAdminClient> | null = null;

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
    },
    async objectExists(bucket, path) {
      const [exists] = await getStorage().bucket(bucket).file(path).exists();
      return exists;
    },
    env: process.env,
    projectId: process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "",
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
    const recent = await tx.get(deps.db.collection(JOBS).orderBy("requestedAt", "desc").limit(50));
    try {
      assertCanStart(recent.docs.map((doc) => toRecord(doc.data())), now, {trigger, manualDailyLimit: config.manualDailyLimit});
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

  try {
    const [operation] = await deps.exporter.exportDocuments({
      name: `projects/${deps.projectId}/databases/(default)`,
      outputUriPrefix,
    });
    await deps.db.runTransaction(async (tx) => {
      tx.update(ref, {
        operationName: operation.name ?? null,
        startedAt: Timestamp.fromDate(deps.now()),
        revision: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    return {jobId, status: "running"};
  } catch (error) {
    const safe = sanitizeError(error);
    await deps.db.runTransaction(async (tx) => {
      tx.update(ref, {
        status: "failed",
        error: safe,
        completedAt: Timestamp.fromDate(deps.now()),
        revision: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
      audit(tx, deps.db, actor, "BACKUP_FAILED", jobId, {stage: "export-request", error: safe});
    });
    throw new HttpsError("internal", `The export request was rejected (${safe.code}).`);
  }
}

export async function refreshBackup(deps: BackupDeps, actor: BackupActor, jobId: string): Promise<{jobId: string; status: BackupJobStatus}> {
  const ref = deps.db.collection(JOBS).doc(jobId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Backup job not found.");
  const data = snapshot.data() ?? {};
  const status = String(data.status) as BackupJobStatus;
  if (status !== "running") return {jobId, status};
  if (typeof data.operationName !== "string" || !data.operationName) return {jobId, status};

  // An operation that can no longer be read (expired, deleted, permission
  // lost) must not leave the job running forever and block every later
  // backup: it is recorded as a failure with the sanitised reason.
  let next: ReturnType<typeof applyOperationState>;
  try {
    next = applyOperationState(await deps.exporter.checkExportDocumentsProgress(data.operationName));
  } catch (error) {
    next = {status: "failed", error: sanitizeError(error)};
  }
  const now = deps.now();
  const revision = Number(data.revision ?? 0);
  const metadataPath = String(data.verification?.metadataPath ?? "");
  const bucket = String(data.outputUriPrefix ?? "").replace(/^gs:\/\//, "").split("/")[0];
  const exists = next.status === "exported" ? await deps.objectExists(bucket, metadataPath) : false;

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
