import {getStorage} from "firebase-admin/storage";
import {HttpsError} from "firebase-functions/v2/https";

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

/** The privileged callable verifies each uploaded object before committing clinical references. */
export async function verifySessionEvidenceObjects(evidence: SessionEvidence, appointmentId: string, uploaderUid: string): Promise<void> {
  if (evidence.attachments.length === 0) return;
  const bucket = getStorage().bucket();
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
