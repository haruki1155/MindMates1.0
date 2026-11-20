import {randomUUID} from "node:crypto";
import {DocumentReference, FieldValue, GeoPoint, getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireSuperAdmin, requireUid} from "./access";
import {actorName, AUDIT_CATEGORIES, writeAudit} from "./audit";
import {BackupActor} from "./backup_management";

export type BackupExportFormat = "csv" | "xlsx";

export type BackupExportCursor = {
  currentCollection: string;
  afterDocId: string | null;
  queue: string[];
};

export type ExportedBackupCollection = {
  collectionKey: string;
  collectionPath: string;
};

export type ExportedBackupDocument = {
  documentId: string;
  documentPath: string;
  collectionPath: string;
  collectionKey: string;
  parentCollection: string | null;
  parentDocumentId: string | null;
  createTime: string | null;
  updateTime: string | null;
  fields: Record<string, unknown>;
};

export type BackupExportPageResult = {
  exportId: string;
  exportedAt: string;
  format: BackupExportFormat | null;
  scope: typeof BACKUP_EXPORT_SCOPE;
  documents: ExportedBackupDocument[];
  visitedCollections: ExportedBackupCollection[];
  hasMore: boolean;
  nextCursor: BackupExportCursor | null;
};

export type BackupExportPageRequest = {
  exportId?: unknown;
  cursor?: unknown;
  pageSize?: unknown;
  format?: unknown;
};

export type BackupExportDeps = {
  db: FirebaseFirestore.Firestore;
  now(): Date;
  newExportId(): string;
  maxResponseBytes?: number;
};

const DEFAULT_PAGE_SIZE = 200;
const MAX_PAGE_SIZE = 500;
const DEFAULT_MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const SUBCOLLECTION_CONCURRENCY = 20;
const GET_ALL_BATCH_SIZE = 250;
const MAX_QUEUE_LENGTH = 100000;

// Internal server-only operational state, device push credentials, and
// counselor-exclusive case remarks (not accessible to super-admin per
// case_remarks.ts) are excluded from browser-downloaded backup exports.
const EXCLUDED_ROOT_COLLECTIONS = new Set([
  "employee_id_reservations",
  "pending_registration_cancellations",
  "public_user_id_reservations",
  "student_activation_attempts",
  "student_id_reservations",
  "user_devices",
  "user_public_ids",
]);

const EXCLUDED_SUBCOLLECTION_NAMES = new Set([
  "case_remarks",
]);

const REDACTED_CREDENTIAL_FIELDS = new Set([
  "fcmToken",
  "passwordHash",
  "privateKey",
]);

/**
 * Explicit approved export scope for MindMate Backup Data downloads:
 * includes all Firestore domain collections and subcollections while
 * excluding internal server-only state, device push credentials, and
 * counselor-exclusive case remarks, and redacting credential hashes/salts.
 */
export const BACKUP_EXPORT_SCOPE = {
  mode: "all-firestore-excluding-internal-and-credentials",
  excludedRootCollections: [...EXCLUDED_ROOT_COLLECTIONS].sort(),
  excludedSubcollections: [...EXCLUDED_SUBCOLLECTION_NAMES].sort(),
  excludedPrefix: "_",
  redactedFields: [
    "activationCode.hash",
    "activationCode.salt",
    "consumedActivationCode.hash",
    "consumedActivationCode.salt",
    "fcmToken",
    "passwordHash",
    "privateKey",
  ],
} as const;

export function isExcludedBackupCollectionPath(collectionPath: string): boolean {
  const segments = collectionPath.split("/").filter(Boolean);
  if (segments.length === 0 || segments.length % 2 !== 1) return true;
  if (EXCLUDED_ROOT_COLLECTIONS.has(segments[0])) return true;
  for (let i = 0; i < segments.length; i += 2) {
    const colSegment = segments[i];
    if (colSegment.startsWith("_")) return true;
    if (i > 0 && EXCLUDED_SUBCOLLECTION_NAMES.has(colSegment)) return true;
  }
  return false;
}

function redactActivationCodeRecord(value: unknown): unknown {
  if (!value || typeof value !== "object" || Array.isArray(value)) return value;
  const copy = {...(value as Record<string, unknown>)};
  if ("hash" in copy && copy.hash != null) copy.hash = "[REDACTED]";
  if ("salt" in copy && copy.salt != null) copy.salt = "[REDACTED]";
  return copy;
}

export function redactSensitiveBackupFields(
  collectionKey: string,
  fields: Record<string, unknown>,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(fields)) {
    if (REDACTED_CREDENTIAL_FIELDS.has(key) && value != null) {
      out[key] = "[REDACTED]";
      continue;
    }
    if (
      collectionKey === "student_roster" &&
      (key === "activationCode" || key === "consumedActivationCode")
    ) {
      out[key] = redactActivationCodeRecord(value);
      continue;
    }
    out[key] = value;
  }
  return out;
}

export function compareUtf8(a: string, b: string): number {
  if (a === b) return 0;
  return Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

/**
 * Maps a Firestore collection path to a logical dataset key.
 * Top-level collections keep their ID (`users`); nested subcollections join
 * collection segments (`appointments/a1/history` -> `appointments__history`).
 */
export function collectionKeyForPath(collectionPath: string): string {
  const segments = collectionPath.split("/").filter(Boolean);
  const collectionSegments: string[] = [];
  for (let i = 0; i < segments.length; i += 2) {
    collectionSegments.push(segments[i]);
  }
  return collectionSegments.join("__");
}

function isValidCollectionPath(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > 1500 || trimmed !== value) return false;
  if (trimmed.startsWith("/") || trimmed.endsWith("/")) return false;
  const segments = trimmed.split("/");
  if (segments.length % 2 !== 1) return false;
  return segments.every((segment) => segment.length > 0 && segment !== "." && segment !== "..");
}

function parseFormat(raw: unknown): BackupExportFormat | null {
  if (raw === undefined || raw === null || raw === "") return null;
  if (raw === "csv" || raw === "xlsx") return raw;
  throw new HttpsError("invalid-argument", "Export format must be 'csv' or 'xlsx'.");
}

function parsePageSize(raw: unknown): number {
  if (raw === undefined || raw === null) return DEFAULT_PAGE_SIZE;
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 1) {
    throw new HttpsError("invalid-argument", "pageSize must be a positive integer.");
  }
  return Math.min(raw, MAX_PAGE_SIZE);
}

function parseExportId(raw: unknown): string {
  if (typeof raw !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(raw.trim())) {
    throw new HttpsError("invalid-argument", "A valid exportId is required when continuing an export.");
  }
  return raw.trim();
}

function parseCursor(raw: unknown): BackupExportCursor | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "Invalid export cursor.");
  }
  const record = raw as Record<string, unknown>;
  if (!isValidCollectionPath(record.currentCollection) || isExcludedBackupCollectionPath(record.currentCollection)) {
    throw new HttpsError("invalid-argument", "Invalid export cursor collection.");
  }
  let afterDocId: string | null = null;
  if (record.afterDocId !== undefined && record.afterDocId !== null) {
    if (
      typeof record.afterDocId !== "string" ||
      record.afterDocId.length === 0 ||
      record.afterDocId.includes("/")
    ) {
      throw new HttpsError("invalid-argument", "Invalid export cursor document ID.");
    }
    afterDocId = record.afterDocId;
  }
  if (!Array.isArray(record.queue) || record.queue.length > MAX_QUEUE_LENGTH) {
    throw new HttpsError("invalid-argument", "Invalid export cursor queue.");
  }
  const queue: string[] = [];
  for (const item of record.queue) {
    if (!isValidCollectionPath(item) || isExcludedBackupCollectionPath(item)) {
      throw new HttpsError("invalid-argument", "Invalid export cursor queued collection.");
    }
    queue.push(item);
  }
  return {
    currentCollection: record.currentCollection,
    afterDocId,
    queue,
  };
}

export function serializeFirestoreValue(value: unknown): unknown {
  if (value === null || value === undefined) return null;
  if (typeof value === "boolean" || typeof value === "string") return value;
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : String(value);
  }
  if (value instanceof Date) return value.toISOString();
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof DocumentReference) return `ref:${value.path}`;
  if (value instanceof GeoPoint) {
    return {_type: "geopoint", latitude: value.latitude, longitude: value.longitude};
  }
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    return {_type: "bytes", base64: Buffer.from(value).toString("base64")};
  }
  if (Array.isArray(value)) {
    return value.map((item) => serializeFirestoreValue(item));
  }
  if (typeof value === "object") {
    const maybeTs = value as {toDate?: unknown; seconds?: unknown};
    if (typeof maybeTs.toDate === "function" && typeof maybeTs.seconds === "number") {
      return (maybeTs.toDate as () => Date)().toISOString();
    }
    const maybeRef = value as {path?: unknown; id?: unknown; firestore?: unknown};
    if (typeof maybeRef.path === "string" && typeof maybeRef.id === "string" && maybeRef.firestore != null) {
      return `ref:${maybeRef.path}`;
    }
    const out: Record<string, unknown> = {};
    const entries = value instanceof Map
      ? [...value.entries()].map(([k, v]) => [String(k), v] as const)
      : Object.entries(value as Record<string, unknown>);
    entries.sort(([a], [b]) => compareUtf8(a, b));
    for (const [k, v] of entries) {
      if (v !== undefined) {
        out[k] = serializeFirestoreValue(v);
      }
    }
    return out;
  }
  return String(value);
}

function serializeSnapshot(
  snap: FirebaseFirestore.DocumentSnapshot,
  collectionPath: string,
): ExportedBackupDocument {
  const segments = snap.ref.path.split("/").filter(Boolean);
  const isSubcollection = segments.length >= 4;
  const parentCollection = isSubcollection ? segments[segments.length - 4] : null;
  const parentDocumentId = isSubcollection ? segments[segments.length - 3] : null;
  const raw = snap.data() ?? {};
  const fields: Record<string, unknown> = {};
  const keys = Object.keys(raw).sort(compareUtf8);
  for (const key of keys) {
    const val = raw[key];
    if (val !== undefined) {
      fields[key] = serializeFirestoreValue(val);
    }
  }
  const collectionKey = collectionKeyForPath(collectionPath);
  return {
    documentId: snap.id,
    documentPath: snap.ref.path,
    collectionPath,
    collectionKey,
    parentCollection,
    parentDocumentId,
    createTime: snap.createTime ? snap.createTime.toDate().toISOString() : null,
    updateTime: snap.updateTime ? snap.updateTime.toDate().toISOString() : null,
    fields: redactSensitiveBackupFields(collectionKey, fields),
  };
}

async function getAllInBatches(
  db: FirebaseFirestore.Firestore,
  refs: FirebaseFirestore.DocumentReference[],
): Promise<FirebaseFirestore.DocumentSnapshot[]> {
  const snapshots: FirebaseFirestore.DocumentSnapshot[] = [];
  for (let i = 0; i < refs.length; i += GET_ALL_BATCH_SIZE) {
    const slice = refs.slice(i, i + GET_ALL_BATCH_SIZE);
    const batch = await db.getAll(...slice);
    snapshots.push(...batch);
  }
  return snapshots;
}

async function discoverSubcollectionPaths(
  refs: FirebaseFirestore.DocumentReference[],
): Promise<string[]> {
  const found: string[] = [];
  for (let i = 0; i < refs.length; i += SUBCOLLECTION_CONCURRENCY) {
    const slice = refs.slice(i, i + SUBCOLLECTION_CONCURRENCY);
    const results = await Promise.all(slice.map((ref) => ref.listCollections()));
    for (const cols of results) {
      for (const col of cols) {
        if (!isExcludedBackupCollectionPath(col.path)) {
          found.push(col.path);
        }
      }
    }
  }
  return found.sort(compareUtf8);
}

async function writeExportAudit(
  db: FirebaseFirestore.Firestore,
  actor: BackupActor,
  action: "BACKUP_EXPORT_STARTED" | "BACKUP_EXPORT_COMPLETED",
  exportId: string,
  metadata: Record<string, unknown>,
): Promise<void> {
  await db.runTransaction(async (tx) => {
    writeAudit(tx, db, {
      actorId: actor.uid,
      actorNameSnapshot: actor.name,
      actorRoleSnapshot: actor.role,
      action,
      category: AUDIT_CATEGORIES.system,
      targetType: "backup_export",
      targetId: exportId,
      metadata,
    });
  });
}

export async function exportBackupPage(
  deps: BackupExportDeps,
  actor: BackupActor,
  requestData: BackupExportPageRequest = {},
): Promise<BackupExportPageResult> {
  const format = parseFormat(requestData.format);
  const pageSize = parsePageSize(requestData.pageSize);
  const maxResponseBytes = deps.maxResponseBytes ?? DEFAULT_MAX_RESPONSE_BYTES;
  const parsedCursor = parseCursor(requestData.cursor);

  const isFirstPage = parsedCursor === null;
  const exportId = isFirstPage ? deps.newExportId() : parseExportId(requestData.exportId);
  const exportedAt = deps.now().toISOString();

  let queue: string[];
  let currentCollection: string | null;
  let afterDocId: string | null;

  if (parsedCursor === null) {
    const rootCollections = await deps.db.listCollections();
    queue = rootCollections
      .map((col) => col.path)
      .filter((colPath) => !isExcludedBackupCollectionPath(colPath))
      .sort(compareUtf8);
    currentCollection = queue.shift() ?? null;
    afterDocId = null;
    await writeExportAudit(deps.db, actor, "BACKUP_EXPORT_STARTED", exportId, {
      format,
      rootCollectionCount: queue.length + (currentCollection ? 1 : 0),
    });
  } else {
    queue = [...parsedCursor.queue];
    currentCollection = parsedCursor.currentCollection;
    afterDocId = parsedCursor.afterDocId;
  }

  const documents: ExportedBackupDocument[] = [];
  const visitedMap = new Map<string, ExportedBackupCollection>();
  let approxBytes = 0;
  let inspectedRefs = 0;

  while (
    currentCollection !== null &&
    inspectedRefs < pageSize &&
    (documents.length === 0 || approxBytes < maxResponseBytes)
  ) {
    visitedMap.set(currentCollection, {
      collectionKey: collectionKeyForPath(currentCollection),
      collectionPath: currentCollection,
    });

    const colRef = deps.db.collection(currentCollection);
    const allRefs = (await colRef.listDocuments()).slice().sort((a, b) => compareUtf8(a.id, b.id));
    const remaining = afterDocId === null
      ? allRefs
      : allRefs.filter((ref) => compareUtf8(ref.id, afterDocId!) > 0);

    if (remaining.length === 0) {
      currentCollection = queue.shift() ?? null;
      afterDocId = null;
      continue;
    }

    const budget = Math.max(1, pageSize - inspectedRefs);
    const batchRefs = remaining.slice(0, budget);
    const snaps = await getAllInBatches(deps.db, batchRefs);

    let processedCount = 0;
    let byteLimitReached = false;

    for (let i = 0; i < batchRefs.length; i++) {
      const snap = snaps[i];
      if (snap.exists) {
        const serialized = serializeSnapshot(snap, currentCollection);
        const docBytes = Buffer.byteLength(JSON.stringify(serialized), "utf8");
        if (documents.length > 0 && approxBytes + docBytes > maxResponseBytes) {
          byteLimitReached = true;
          break;
        }
        documents.push(serialized);
        approxBytes += docBytes;
      }
      processedCount++;
    }

    const processedRefs = batchRefs.slice(0, processedCount);
    if (processedRefs.length > 0) {
      inspectedRefs += processedRefs.length;
      const subPaths = await discoverSubcollectionPaths(processedRefs);
      if (subPaths.length > 0) {
        queue.push(...subPaths);
      }
    }

    if (byteLimitReached || processedCount < remaining.length) {
      afterDocId = processedCount > 0 ? batchRefs[processedCount - 1].id : afterDocId;
      break;
    }

    currentCollection = queue.shift() ?? null;
    afterDocId = null;
  }

  const nextCursor: BackupExportCursor | null = currentCollection !== null
    ? {currentCollection, afterDocId, queue}
    : null;
  const hasMore = nextCursor !== null;

  if (!hasMore) {
    await writeExportAudit(deps.db, actor, "BACKUP_EXPORT_COMPLETED", exportId, {
      format,
      finalPageDocuments: documents.length,
      completedAt: FieldValue.serverTimestamp(),
    });
  }

  return {
    exportId,
    exportedAt,
    format,
    scope: BACKUP_EXPORT_SCOPE,
    documents,
    visitedCollections: [...visitedMap.values()],
    hasMore,
    nextCursor,
  };
}

export function defaultBackupExportDeps(): BackupExportDeps {
  return {
    db: getFirestore(),
    now: () => new Date(),
    newExportId: () => randomUUID(),
  };
}

export const exportFirestoreBackupPage = onCall(
  {timeoutSeconds: 300, memory: "512MiB"},
  async (request) => {
    const uid = requireUid(request);
    const admin = await requireSuperAdmin(uid);
    const actor: BackupActor = {
      uid,
      name: actorName(admin),
      role: String(admin.accessRole),
    };
    const data = (request.data && typeof request.data === "object" ? request.data : {}) as BackupExportPageRequest;
    return exportBackupPage(defaultBackupExportDeps(), actor, data);
  },
);
