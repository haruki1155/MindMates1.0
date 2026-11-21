import {createHash} from "node:crypto";
import {getApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError} from "firebase-functions/v2/https";

import {configuredSuperAdminUid, requireClinical, roleOf} from "./access";
import {AUDIT_CATEGORIES, AuditWrite, actorName, writeAuditBatch} from "./audit";

export interface ClinicalEvidenceAttachment {
  path: string;
  name: string;
  contentType: string;
  size: number;
}

export interface SessionEvidence {
  attachments: ClinicalEvidenceAttachment[];
}

const maxFileBytes = 5 * 1024 * 1024;
const mimeByExtension: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  pdf: "application/pdf",
  doc: "application/msword",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
};

function validId(value: string): boolean {
  return /^[A-Za-z0-9_-]{1,120}$/.test(value);
}

export function sessionEvidencePathFor(appointmentId: string, uploaderUid: string, nonce: string, extension: string): string {
  if (!validId(appointmentId) || !validId(uploaderUid) || !/^[a-f0-9]{32}$/.test(nonce) || !Object.hasOwn(mimeByExtension, extension)) {
    throw new HttpsError("invalid-argument", "Invalid private attachment path.");
  }
  return `counseling_session_files/${appointmentId}/${uploaderUid}/${nonce}.${extension}`;
}

export function validateSessionEvidence(
  source: Record<string, unknown>,
  appointmentId: string,
  uploaderUid: string,
): SessionEvidence {
  if (!validId(appointmentId) || !validId(uploaderUid)) throw new HttpsError("invalid-argument", "Invalid appointment record.");
  // Reject obsolete text-only fields rather than silently storing them.
  for (const field of ["interviewQuestions", "requirementsChecked", "materialsUsed"]) {
    if (Object.prototype.hasOwnProperty.call(source, field)) {
      throw new HttpsError("invalid-argument", "Unsupported interview text fields.");
    }
  }
  const raw = source.attachments ?? [];
  if (!Array.isArray(raw)) throw new HttpsError("invalid-argument", "Attachments must be a list.");
  if (raw.length > 5) throw new HttpsError("invalid-argument", "Upload at most five files.");
  const paths = new Set<string>();
  const attachments: ClinicalEvidenceAttachment[] = raw.map((value: unknown) => {
    if (value == null || typeof value !== "object" || Array.isArray(value)) throw new HttpsError("invalid-argument", "Invalid attachment.");
    const entry = value as Record<string, unknown>;
    const {path, name, contentType, size} = entry;
    if (typeof path !== "string" || typeof name !== "string" || typeof contentType !== "string" ||
        typeof size !== "number" || !Number.isSafeInteger(size) || size <= 0 || size > maxFileBytes ||
        name.trim().length === 0 || name.length > 120 || /[\\/\x00-\x1f]/.test(name)) {
      throw new HttpsError("invalid-argument", "Invalid attachment name, type or size.");
    }
    const prefix = `counseling_session_files/${appointmentId}/${uploaderUid}/`;
    if (!path.startsWith(prefix)) throw new HttpsError("invalid-argument", "Attachment owner does not match the appointment.");
    const filename = path.slice(prefix.length);
    const matched = /^[a-f0-9]{32}\.(jpg|jpeg|png|pdf|doc|docx)$/.exec(filename);
    if (!matched || mimeByExtension[matched[1]] !== contentType) throw new HttpsError("invalid-argument", "Attachment type does not match its filename.");
    if (paths.has(path)) throw new HttpsError("invalid-argument", "Duplicate attachment paths.");
    paths.add(path);
    return {path, name: name.trim(), contentType, size};
  });
  return {attachments};
}

export function resolveEvidenceBucket() {
  let configBucket: string | undefined;
  try {
    const parsed = JSON.parse(process.env.FIREBASE_CONFIG ?? "{}") as {storageBucket?: unknown};
    if (typeof parsed.storageBucket === "string" && parsed.storageBucket.trim()) {
      configBucket = parsed.storageBucket.trim();
    }
  } catch {
    // Ignore malformed FIREBASE_CONFIG and fall back to app options / env.
  }
  const bucketName =
    getApp().options.storageBucket ||
    process.env.FIREBASE_STORAGE_BUCKET?.trim() ||
    configBucket ||
    (process.env.GCLOUD_PROJECT?.trim() ? `${process.env.GCLOUD_PROJECT.trim()}.appspot.com` : undefined);
  return bucketName ? getStorage().bucket(bucketName) : getStorage().bucket();
}

/** The privileged callable verifies each uploaded object before committing clinical references. */
export async function verifySessionEvidenceObjects(evidence: SessionEvidence, appointmentId: string, uploaderUid: string): Promise<void> {
  if (evidence.attachments.length === 0) return;
  const bucket = resolveEvidenceBucket();
  for (const file of evidence.attachments) {
    let metadata;
    try {
      [metadata] = await bucket.file(file.path).getMetadata();
    } catch (_error) {
      throw new HttpsError("failed-precondition", "A selected interview file was not uploaded. Review your attachments.");
    }
    if (Number(metadata.size) !== file.size || metadata.contentType !== file.contentType ||
      metadata.metadata?.uploadedBy !== uploaderUid || metadata.metadata?.appointmentId !== appointmentId) {
      throw new HttpsError("failed-precondition", "A selected interview file failed verification.");
    }
  }
}

const SESSION_EVIDENCE_PATH_PATTERN =
  /^counseling_session_files\/([A-Za-z0-9_-]{1,120})\/([A-Za-z0-9_-]{1,120})\/([a-f0-9]{32}\.(jpg|jpeg|png|pdf|doc|docx))$/;

export interface SessionEvidenceDownloadRequest {
  appointmentId: string;
  path: string;
}

export interface DownloadSessionEvidenceResult {
  name: string;
  contentType: string;
  size: number;
  dataBase64: string;
}

export interface StorageObjectMetadataView {
  size?: unknown;
  contentType?: unknown;
  metadata?: Record<string, unknown>;
}

export interface DownloadSessionEvidenceDeps {
  requireClinical?: (uid: string) => Promise<FirebaseFirestore.DocumentData>;
  superAdminUid?: () => string;
  readAppointment?: (appointmentId: string) => Promise<FirebaseFirestore.DocumentData | null>;
  readStudentUser?: (studentId: string) => Promise<FirebaseFirestore.DocumentData | null>;
  readSessionNote?: (appointmentId: string) => Promise<FirebaseFirestore.DocumentData | null>;
  readObjectMetadata?: (path: string) => Promise<StorageObjectMetadataView | null>;
  downloadObjectBytes?: (path: string) => Promise<Buffer>;
  writeAudit?: (event: AuditWrite) => Promise<void>;
}

export function validateSessionEvidenceDownloadRequest(data: unknown): SessionEvidenceDownloadRequest {
  if (data == null || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "Invalid private attachment request.");
  }
  const record = data as Record<string, unknown>;
  const appointmentId = typeof record.appointmentId === "string" ? record.appointmentId.trim() : "";
  const path = typeof record.path === "string" ? record.path : "";
  if (!validId(appointmentId) ||
      path.trim() !== path ||
      path.includes("..") ||
      path.includes("\\") ||
      path.includes("%") ||
      /[\x00-\x1f]/.test(path)) {
    throw new HttpsError("invalid-argument", "Invalid private attachment request.");
  }
  const matched = SESSION_EVIDENCE_PATH_PATTERN.exec(path);
  if (!matched || matched[1] !== appointmentId) {
    throw new HttpsError("invalid-argument", "Invalid private attachment request.");
  }
  return {appointmentId, path};
}

function isStorageNotFoundError(error: unknown): boolean {
  if (error == null || typeof error !== "object") return false;
  const err = error as {code?: unknown; status?: unknown; message?: unknown};
  if (err.code === 404 || err.status === 404 || err.code === "storage/object-not-found") return true;
  const msg = String(err.message ?? "");
  return msg.includes("No such object") || msg.includes("Not Found");
}

function safeDisplayFilename(rawName: unknown, extension: string): string {
  if (typeof rawName === "string") {
    const trimmed = rawName.trim();
    if (trimmed.length > 0 && trimmed.length <= 120 && !/[\\/\x00-\x1f]/.test(trimmed)) {
      return trimmed;
    }
  }
  return `attachment.${extension}`;
}

export async function downloadSessionEvidenceFile(
  input: {actorId: string; appointmentId: string; path: string},
  deps: DownloadSessionEvidenceDeps = {},
): Promise<DownloadSessionEvidenceResult> {
  const {appointmentId, path} = validateSessionEvidenceDownloadRequest(input);
  const matched = SESSION_EVIDENCE_PATH_PATTERN.exec(path)!;
  const pathUploaderUid = matched[2];
  const extension = matched[4];
  const expectedMime = mimeByExtension[extension];

  const requireClinicalFn = deps.requireClinical ?? requireClinical;
  const actor = await requireClinicalFn(input.actorId);
  const role = roleOf(actor);

  const safeSuperAdminUid = (): string => {
    try {
      return (deps.superAdminUid ?? configuredSuperAdminUid)().trim();
    } catch {
      return "";
    }
  };

  if (role === "admin") {
    const superUid = safeSuperAdminUid();
    if (!superUid || input.actorId !== superUid) {
      throw new HttpsError("permission-denied", "You do not have permission to download this private file.");
    }
  } else if (role === "counselor") {
    const readAppointmentFn =
      deps.readAppointment ??
      (async (id: string) => {
        const snap = await getFirestore().collection("appointments").doc(id).get();
        return snap.exists ? snap.data() ?? {} : null;
      });
    const appointment = await readAppointmentFn(appointmentId);
    const studentId = typeof appointment?.userId === "string" ? appointment.userId.trim() : "";
    if (!appointment || !validId(studentId)) {
      throw new HttpsError("permission-denied", "You do not have permission to download this private file.");
    }
    const readStudentFn =
      deps.readStudentUser ??
      (async (uid: string) => {
        const snap = await getFirestore().collection("users").doc(uid).get();
        return snap.exists ? snap.data() ?? {} : null;
      });
    const student = await readStudentFn(studentId);
    const studentCollegeId = typeof student?.collegeId === "string" ? student.collegeId.trim() : "";
    const assignedColleges = Array.isArray(actor.assignedCollegeIds) ? actor.assignedCollegeIds : [];
    if (!student ||
        String(student.verificationStatus ?? "") !== "verified" ||
        studentCollegeId.length === 0 ||
        !assignedColleges.includes(studentCollegeId)) {
      throw new HttpsError("permission-denied", "You do not have permission to download this private file.");
    }
  } else {
    throw new HttpsError("permission-denied", "You do not have permission to download this private file.");
  }

  const readSessionNoteFn =
    deps.readSessionNote ??
    (async (id: string) => {
      const snap = await getFirestore().collection("appointments").doc(id).collection("clinical_notes").doc("session").get();
      return snap.exists ? snap.data() ?? {} : null;
    });
  const sessionNote = await readSessionNoteFn(appointmentId);
  const attachments = Array.isArray(sessionNote?.attachments) ? sessionNote.attachments : [];
  const attachmentEntry = attachments.find(
    (entry: unknown): entry is Record<string, unknown> =>
      entry != null && typeof entry === "object" && !Array.isArray(entry) && (entry as Record<string, unknown>).path === path,
  );
  if (!attachmentEntry) {
    throw new HttpsError("not-found", "This private file is no longer available.");
  }
  if (attachmentEntry.contentType != null && attachmentEntry.contentType !== expectedMime) {
    throw new HttpsError("failed-precondition", "This private file failed verification.");
  }

  const readObjectMetadataFn =
    deps.readObjectMetadata ??
    (async (objectPath: string): Promise<StorageObjectMetadataView | null> => {
      try {
        const [metadata] = await resolveEvidenceBucket().file(objectPath).getMetadata();
        return {
          size: metadata.size,
          contentType: metadata.contentType,
          metadata: metadata.metadata as Record<string, unknown> | undefined,
        };
      } catch (error) {
        if (isStorageNotFoundError(error)) return null;
        throw error;
      }
    });

  const metadata = await readObjectMetadataFn(path);
  if (!metadata) {
    throw new HttpsError("not-found", "This private file is no longer available.");
  }
  const size = Number(metadata.size);
  if (!Number.isSafeInteger(size) ||
      size <= 0 ||
      size > maxFileBytes ||
      metadata.contentType !== expectedMime ||
      metadata.metadata?.uploadedBy !== pathUploaderUid ||
      metadata.metadata?.appointmentId !== appointmentId) {
    throw new HttpsError("failed-precondition", "This private file failed verification.");
  }

  const downloadObjectBytesFn =
    deps.downloadObjectBytes ??
    (async (objectPath: string) => {
      try {
        const [bytes] = await resolveEvidenceBucket().file(objectPath).download();
        return bytes;
      } catch (error) {
        if (isStorageNotFoundError(error)) {
          throw new HttpsError("not-found", "This private file is no longer available.");
        }
        throw error;
      }
    });

  const bytes = await downloadObjectBytesFn(path);
  if (bytes.length <= 0 || bytes.length > maxFileBytes || bytes.length !== size) {
    throw new HttpsError("failed-precondition", "This private file failed verification.");
  }

  const attachmentPathHash = createHash("sha256").update(path).digest("hex").slice(0, 16);
  const writeAuditFn =
    deps.writeAudit ??
    (async (event: AuditWrite) => {
      const db = getFirestore();
      const batch = db.batch();
      writeAuditBatch(batch, db, event);
      await batch.commit();
    });

  await writeAuditFn({
    actorId: input.actorId,
    actorNameSnapshot: actorName(actor),
    actorRoleSnapshot: role,
    action: "CLINICAL_ATTACHMENT_DOWNLOADED",
    category: AUDIT_CATEGORIES.security,
    targetType: "appointment",
    targetId: appointmentId,
    metadata: {
      contentType: expectedMime,
      size: bytes.length,
      attachmentPathHash,
    },
  });

  return {
    name: safeDisplayFilename(attachmentEntry.name, extension),
    contentType: expectedMime,
    size: bytes.length,
    dataBase64: bytes.toString("base64"),
  };
}
