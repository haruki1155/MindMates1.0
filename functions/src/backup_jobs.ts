// Pure decision logic for Firestore managed-export backup jobs.
// No Firebase or GCP imports: everything here is unit-tested without emulators.

export type BackupJobStatus = "running" | "completed" | "failed";
export type BackupTrigger = "manual" | "scheduled";

export type BackupVerification = {
  status: "pending" | "verified" | "missing";
  metadataPath: string;
  checkedAt: Date | null;
};

export type BackupProgress = {
  documents: {completed: number; estimated: number};
  bytes: {completed: number; estimated: number};
} | null;

export type BackupError = {code: string; message: string} | null;

export type BackupConfig = {
  bucket: string;
  retentionDays: number;
  scheduleEnabled: boolean;
  manualDailyLimit: number;
};

export type BackupJobRecord = {
  status: BackupJobStatus;
  trigger: BackupTrigger;
  requestedBy: string;
  requestedAt: Date;
  operationName: string | null;
  progress: BackupProgress;
  verification: BackupVerification | null;
  error: BackupError;
};

/** Phase 1 scope. Stored on every job so the UI never implies wider coverage. */
export const BACKUP_COVERAGE = {firestore: "included", auth: "excluded", storage: "excluded"} as const;

export const BACKUP_DEFAULTS = {retentionDays: 30, manualDailyLimit: 3} as const;
const MAX_ERROR_MESSAGE = 300;
const DAY_MS = 24 * 60 * 60 * 1_000;
const SERVICE_ACCOUNT_ID = "[a-z][a-z0-9-]{4,28}[a-z0-9]";
const SERVICE_ACCOUNT_SHORTHAND_RE = new RegExp(`^${SERVICE_ACCOUNT_ID}@$`);
const SERVICE_ACCOUNT_EMAIL_RE = new RegExp(`^${SERVICE_ACCOUNT_ID}@([a-z0-9-]+)\\.iam\\.gserviceaccount\\.com$`);

export class BackupConfigError extends Error {
  constructor(
    public readonly code: "bucket-missing" | "bucket-invalid" | "invalid-number" | "service-account-invalid",
    message: string,
  ) {
    super(message);
    this.name = "BackupConfigError";
  }
}

export class StartBlockedError extends Error {
  constructor(public readonly code: "job-running" | "manual-limit", message: string) {
    super(message);
    this.name = "StartBlockedError";
  }
}

function positiveInteger(raw: string | undefined, fallback: number, label: string): number {
  if (raw == null || raw.trim() === "") return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1) {
    throw new BackupConfigError("invalid-number", `${label} must be a positive integer.`);
  }
  return value;
}

export function resolveBackupConfig(env: Record<string, string | undefined>): BackupConfig {
  const bucket = (env.BACKUP_BUCKET ?? "").trim();
  if (!bucket) throw new BackupConfigError("bucket-missing", "Backup destination is not configured.");
  if (bucket.includes("/") || bucket.includes(":") || /\s/.test(bucket)) {
    throw new BackupConfigError("bucket-invalid", "BACKUP_BUCKET must be a plain bucket name without 'gs://' or '/'.");
  }
  return {
    bucket,
    retentionDays: positiveInteger(env.BACKUP_RETENTION_DAYS, BACKUP_DEFAULTS.retentionDays, "BACKUP_RETENTION_DAYS"),
    scheduleEnabled: (env.BACKUP_SCHEDULE_ENABLED ?? "").trim().toLowerCase() === "true",
    manualDailyLimit: positiveInteger(env.BACKUP_MANUAL_DAILY_LIMIT, BACKUP_DEFAULTS.manualDailyLimit, "BACKUP_MANUAL_DAILY_LIMIT"),
  };
}

/**
 * Resolves the optional dedicated least-privilege runtime service account for
 * the three backup Functions only. Leaving `BACKUP_SERVICE_ACCOUNT` unset or
 * empty omits `serviceAccount` so unit tests, CI, and Firebase emulator
 * discovery work without cloud IAM state while per-project `.env.<projectId>`
 * files bind staging and production independently.
 */
export function resolveBackupServiceAccount(
  env: Record<string, string | undefined>,
  projectId?: string,
): string | undefined {
  const raw = (env.BACKUP_SERVICE_ACCOUNT ?? "").trim();
  if (!raw) return undefined;
  if (/\s/.test(raw) || raw.includes(":")) {
    throw new BackupConfigError(
      "service-account-invalid",
      "BACKUP_SERVICE_ACCOUNT must be a plain service account email or '{account-id}@' shorthand.",
    );
  }
  const normalizedProject = (projectId ?? "").trim();
  const saId = raw.split("@", 1)[0];
  if (saId.startsWith("firebase-adminsdk-")) {
    throw new BackupConfigError(
      "service-account-invalid",
      "BACKUP_SERVICE_ACCOUNT must use a dedicated least-privilege service account, not a Firebase Admin SDK service account.",
    );
  }
  if (SERVICE_ACCOUNT_SHORTHAND_RE.test(raw)) {
    return normalizedProject ? `${raw}${normalizedProject}.iam.gserviceaccount.com` : raw;
  }
  const match = SERVICE_ACCOUNT_EMAIL_RE.exec(raw);
  if (!match) {
    throw new BackupConfigError(
      "service-account-invalid",
      "BACKUP_SERVICE_ACCOUNT must match '<account-id>@<project>.iam.gserviceaccount.com' or '<account-id>@'.",
    );
  }
  const saProject = match[1];
  if (normalizedProject && !normalizedProject.startsWith("demo-") && saProject !== normalizedProject) {
    throw new BackupConfigError(
      "service-account-invalid",
      `BACKUP_SERVICE_ACCOUNT belongs to project '${saProject}', expected '${normalizedProject}'.`,
    );
  }
  return raw;
}

function stamp(now: Date): string {
  const two = (n: number) => String(n).padStart(2, "0");
  return `${now.getUTCFullYear()}${two(now.getUTCMonth() + 1)}${two(now.getUTCDate())}-` +
    `${two(now.getUTCHours())}${two(now.getUTCMinutes())}${two(now.getUTCSeconds())}`;
}

export function exportPrefixFor(bucket: string, now: Date, jobId: string): {outputUriPrefix: string; metadataPath: string} {
  const folder = `${stamp(now)}-${jobId}`;
  const relative = `firestore-exports/${folder}`;
  return {
    outputUriPrefix: `gs://${bucket}/${relative}`,
    // The export writes <prefix>/<last path segment>.overall_export_metadata.
    metadataPath: `${relative}/${folder}.overall_export_metadata`,
  };
}

export function assertCanStart(
  jobs: BackupJobRecord[],
  now: Date,
  options: {trigger: BackupTrigger; manualDailyLimit: number},
): void {
  if (jobs.some((job) => job.status === "running")) {
    throw new StartBlockedError("job-running", "A backup is already running. Refresh its status before requesting another.");
  }
  if (options.trigger !== "manual") return;
  const since = now.getTime() - DAY_MS;
  const recentManual = jobs.filter((job) => job.trigger === "manual" && job.requestedAt.getTime() > since).length;
  if (recentManual >= options.manualDailyLimit) {
    throw new StartBlockedError("manual-limit", `The manual backup limit of ${options.manualDailyLimit} per 24 hours has been reached.`);
  }
}

export type OperationState = {
  done: boolean;
  error?: {code?: number; message?: string} | null;
  metadata?: {
    progressDocuments?: {completedWork?: string | number; estimatedWork?: string | number} | null;
    progressBytes?: {completedWork?: string | number; estimatedWork?: string | number} | null;
  } | null;
};

const count = (value: string | number | undefined): number => {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : 0;
};

export function applyOperationState(
  operation: OperationState,
): {status: "running"; progress: BackupProgress} | {status: "failed"; error: BackupError} | {status: "exported"} {
  if (!operation.done) {
    const meta = operation.metadata;
    if (!meta) return {status: "running", progress: null};
    return {
      status: "running",
      progress: {
        documents: {completed: count(meta.progressDocuments?.completedWork), estimated: count(meta.progressDocuments?.estimatedWork)},
        bytes: {completed: count(meta.progressBytes?.completedWork), estimated: count(meta.progressBytes?.estimatedWork)},
      },
    };
  }
  if (operation.error) {
    return {status: "failed", error: sanitizeError({code: operation.error.code, message: operation.error.message})};
  }
  return {status: "exported"};
}

export function verificationFor(metadataPath: string, exists: boolean, now: Date): BackupVerification {
  return {status: exists ? "verified" : "missing", metadataPath, checkedAt: now};
}

// gRPC codes that prove the export request was refused and nothing started:
// INVALID_ARGUMENT, NOT_FOUND, ALREADY_EXISTS, PERMISSION_DENIED,
// RESOURCE_EXHAUSTED, FAILED_PRECONDITION, OUT_OF_RANGE, UNIMPLEMENTED,
// UNAUTHENTICATED. Everything else (CANCELLED, UNKNOWN, DEADLINE_EXCEEDED,
// ABORTED, INTERNAL, UNAVAILABLE, DATA_LOSS, or no code at all, e.g. a dropped
// socket) leaves open whether the export was accepted.
const DEFINITIVE_REJECTION_CODES = new Set([3, 5, 6, 7, 8, 9, 11, 12, 16]);

/** True only when an export-start error proves no export was started. */
export function isDefinitiveExportRejection(error: unknown): boolean {
  const code = error && typeof error === "object" ? (error as {code?: unknown}).code : undefined;
  return typeof code === "number" && DEFINITIVE_REJECTION_CODES.has(code);
}

/** Error shape safe to store and show: a short code and a bounded message, nothing else. */
export function sanitizeError(error: unknown): NonNullable<BackupError> {
  let code = "unknown";
  let message = "Unknown error";
  if (typeof error === "string") {
    message = error;
  } else if (error && typeof error === "object") {
    const record = error as {code?: unknown; message?: unknown};
    if (typeof record.code === "number") code = `export-${record.code}`;
    else if (typeof record.code === "string" && record.code.trim()) code = record.code.trim();
    if (typeof record.message === "string" && record.message.trim()) message = record.message;
  }
  return {code, message: message.length > MAX_ERROR_MESSAGE ? message.slice(0, MAX_ERROR_MESSAGE) : message};
}

export function summarizeJobs(
  jobs: Array<BackupJobRecord & {completedAt: Date | null}>,
): {lastVerifiedAt: Date | null; runningCount: number; lastStatus: BackupJobStatus | null} {
  let lastVerifiedAt: Date | null = null;
  let newest: (BackupJobRecord & {completedAt: Date | null}) | null = null;
  for (const job of jobs) {
    if (job.status === "completed" && job.verification?.status === "verified" && job.completedAt &&
        (!lastVerifiedAt || job.completedAt > lastVerifiedAt)) {
      lastVerifiedAt = job.completedAt;
    }
    if (!newest || job.requestedAt > newest.requestedAt) newest = job;
  }
  return {
    lastVerifiedAt,
    runningCount: jobs.filter((job) => job.status === "running").length,
    lastStatus: newest?.status ?? null,
  };
}
