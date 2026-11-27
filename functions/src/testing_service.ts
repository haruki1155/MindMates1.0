import {createHash, randomBytes} from "node:crypto";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {configuredSuperAdminUid, requireUid} from "./access";
import {resolveEvidenceBucket} from "./appointment_session_evidence";
import {AUDIT_CATEGORIES, writeAudit} from "./audit";
import {buildInquiryStatusProjection, shouldWriteInquiryProjection} from "./inquiry_routing";
import {
  canHandleClinical,
  createOnce,
  inquiryActor,
  inquiryIdFrom,
  notification,
  revisionOf,
  routeInquiry,
  STALE_REVISION,
  statusCollection,
} from "./inquiry_routing_service";
import {InquirySlaError, requestIdFrom} from "./inquiry_sla";
import {
  assertCanAcceptTestingSchedule,
  assertCanCancelTestingSchedule,
  assertCanCompleteTestingSchedule,
  assertCanProposeTestingSchedule,
  assertCanRequestTestingReschedule,
  canCounselorDecideTestingSchedule,
  resolveTestingServiceEligibility,
  standardizedTestingDocumentFileName,
  TESTING_DOCUMENT_MAX_BYTES,
  TESTING_DOCUMENT_MIME_BY_EXT,
  TESTING_SERVICE_CATEGORY,
  TESTING_SERVICE_DEFAULT_LOCATION,
  TESTING_SERVICE_FORM_TYPE,
  TESTING_SERVICE_MAX_RESCHEDULES,
  TESTING_SERVICE_TIMEZONE,
  TestingDocumentKind,
  TestingServiceDocumentRef,
  TestingServiceValidationError,
  validateTestingDocumentUploadPayload,
  validateTestingScheduleDateTime,
  validateTestingServiceSubmission,
  visibleContactEmail,
} from "./testing_service_domain";

const db = () => getFirestore();
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{8,128}$/;
const TESTING_DOCUMENT_PATH_PATTERN =
  /^testing_service_files\/([A-Za-z0-9_-]{1,128})\/(endorsement_letter|official_receipt|admission_requirement)\/([a-f0-9]{32}\.(jpg|jpeg|png|pdf))$/;

function superAdminUid(): string {
  try {
    return configuredSuperAdminUid();
  } catch {
    return "";
  }
}

function handleDomainError(error: unknown): never {
  if (error instanceof TestingServiceValidationError) {
    throw new HttpsError(error.code, error.message);
  }
  if (error instanceof InquirySlaError) {
    throw new HttpsError("invalid-argument", error.message, {reason: error.code});
  }
  throw error;
}

function formatManilaDate(millis: number): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: TESTING_SERVICE_TIMEZONE,
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
  }).format(new Date(millis));
}

function resolveActorName(profile: Record<string, unknown>, fallbackEmail: string): string {
  const full = [profile.firstName, profile.lastName]
    .filter((value) => typeof value === "string" && value.trim())
    .join(" ");
  const named = String(profile.name ?? "").trim();
  return full || named || fallbackEmail || "MindMate User";
}

function checkOptionalScheduleRevision(expected: unknown, current: number): void {
  if (expected === undefined || expected === null) return;
  if (!Number.isInteger(expected) || expected !== current) {
    throw new HttpsError("failed-precondition", STALE_REVISION);
  }
}

function staffRecipientsForInquiry(data: FirebaseFirestore.DocumentData): string[] {
  const assignees = Array.isArray(data.assigneeIds) ? data.assigneeIds as string[] : [];
  const monitors = Array.isArray(data.monitoringStaffIds) ? data.monitoringStaffIds as string[] : [];
  const combined = [...new Set([...assignees, ...monitors])].filter(Boolean);
  if (combined.length > 0 && !data.takeover) return combined;
  const admin = superAdminUid();
  return admin ? [admin] : [];
}

async function verifyTestingDocumentObject(
  doc: TestingServiceDocumentRef,
  uploaderUid: string,
): Promise<void> {
  const bucket = resolveEvidenceBucket();
  let metadata;
  try {
    [metadata] = await bucket.file(doc.path).getMetadata();
  } catch {
    throw new HttpsError(
      "failed-precondition",
      `Uploaded file "${doc.name}" was not found. Please re-upload it and try again.`,
    );
  }
  if (
    Number(metadata.size) !== doc.size ||
    String(metadata.contentType ?? "").toLowerCase() !== doc.contentType ||
    metadata.metadata?.uploadedBy !== uploaderUid ||
    metadata.metadata?.documentKind !== doc.kind
  ) {
    throw new HttpsError(
      "failed-precondition",
      `Uploaded file "${doc.name}" failed verification.`,
    );
  }
}

/**
 * Private server-only upload for Testing Service supporting documents
 * (Endorsement Letter, Official Receipt, Admission Requirements).
 */
export const uploadTestingServiceDocument = onCall(async (request) => {
  const uid = requireUid(request);
  const [userSnap, authUser] = await Promise.all([
    db().collection("users").doc(uid).get(),
    getAuth().getUser(uid),
  ]);
  if (authUser.disabled) {
    throw new HttpsError("permission-denied", "Your account is disabled.");
  }
  try {
    resolveTestingServiceEligibility(
      userSnap.exists ? userSnap.data() ?? {} : null,
      {isStudentForOjt: true},
    );
  } catch (error) {
    handleDomainError(error);
  }

  let parsed;
  try {
    parsed = validateTestingDocumentUploadPayload(
      request.data,
      uid,
      randomBytes(16).toString("hex"),
    );
  } catch (error) {
    handleDomainError(error);
  }

  await resolveEvidenceBucket().file(parsed.document.path).save(parsed.bytes, {
    resumable: false,
    preconditionOpts: {ifGenerationMatch: 0},
    metadata: {
      contentType: parsed.document.contentType,
      metadata: {
        uploadedBy: uid,
        documentKind: parsed.document.kind,
      },
    },
  });

  return {ok: true, document: parsed.document};
});

/**
 * Private download/preview for Testing Service documents. Accessible only to
 * the inquiry owner or clinical staff authorized to handle the inquiry.
 */
export const downloadTestingServiceDocument = onCall(async (request) => {
  const uid = requireUid(request);
  const inquiryId = inquiryIdFrom(request.data);
  const rawPath = (request.data as {path?: unknown})?.path;
  const path = typeof rawPath === "string" ? rawPath : "";
  if (
    path.trim() !== path ||
    path.includes("..") ||
    path.includes("\\") ||
    path.includes("%") ||
    /[\x00-\x1f]/.test(path)
  ) {
    throw new HttpsError("invalid-argument", "Invalid document path.");
  }
  const matched = TESTING_DOCUMENT_PATH_PATTERN.exec(path);
  if (!matched) {
    throw new HttpsError("invalid-argument", "Invalid document path.");
  }

  const inquirySnap = await db().collection("inquiries").doc(inquiryId).get();
  if (!inquirySnap.exists) {
    throw new HttpsError("not-found", "Inquiry not found.");
  }
  const data = inquirySnap.data()!;
  if (data.formType !== TESTING_SERVICE_FORM_TYPE) {
    throw new HttpsError("failed-precondition", "Inquiry is not a Testing Service request.");
  }

  const isOwner = String(data.userId ?? "").trim() === uid;
  let actorNameSnapshot = String(data.name ?? "MindMate User");
  let actorRoleSnapshot = "appUser";
  if (!isOwner) {
    const who = await inquiryActor(request);
    if (!canHandleClinical(who, data)) {
      throw new HttpsError(
        "permission-denied",
        "You do not have permission to access this Testing Service document.",
      );
    }
    actorNameSnapshot = who.actor.name;
    actorRoleSnapshot = who.role;
  }

  const docs = (data.testingDocuments && typeof data.testingDocuments === "object")
    ? data.testingDocuments as Record<string, unknown>
    : {};
  const candidates: Array<Record<string, unknown>> = [];
  if (docs.endorsementLetter && typeof docs.endorsementLetter === "object") {
    candidates.push(docs.endorsementLetter as Record<string, unknown>);
  }
  if (docs.officialReceipt && typeof docs.officialReceipt === "object") {
    candidates.push(docs.officialReceipt as Record<string, unknown>);
  }
  if (Array.isArray(docs.admissionRequirements)) {
    for (const item of docs.admissionRequirements) {
      if (item && typeof item === "object") {
        candidates.push(item as Record<string, unknown>);
      }
    }
  }
  const entry = candidates.find((item) => item.path === path);
  if (!entry) {
    throw new HttpsError("not-found", "This document is no longer attached to the inquiry.");
  }

  const pathUploaderUid = matched[1];
  const expectedKind = matched[2];
  const extension = matched[4];
  const expectedMime = TESTING_DOCUMENT_MIME_BY_EXT[extension];
  const file = resolveEvidenceBucket().file(path);
  let metadata;
  try {
    [metadata] = await file.getMetadata();
  } catch {
    throw new HttpsError("not-found", "This document is no longer available.");
  }
  const size = Number(metadata.size);
  if (
    !Number.isSafeInteger(size) ||
    size <= 0 ||
    size > TESTING_DOCUMENT_MAX_BYTES ||
    String(metadata.contentType ?? "").toLowerCase() !== expectedMime ||
    metadata.metadata?.uploadedBy !== pathUploaderUid ||
    metadata.metadata?.documentKind !== expectedKind
  ) {
    throw new HttpsError("failed-precondition", "This document failed verification.");
  }

  const [bytes] = await file.download({decompress: false});
  if (bytes.length <= 0 || bytes.length !== size) {
    throw new HttpsError("failed-precondition", "This document failed verification.");
  }

  const batch = db().batch();
  batch.create(db().collection("admin_audit_logs").doc(), {
    actorId: uid,
    actorNameSnapshot,
    actorRoleSnapshot,
    action: "TESTING_SERVICE_DOCUMENT_DOWNLOADED",
    category: AUDIT_CATEGORIES.security,
    targetType: "inquiry",
    targetId: inquiryId,
    metadata: {
      documentKind: expectedKind,
      contentType: expectedMime,
      size: bytes.length,
      pathHash: createHash("sha256").update(path).digest("hex").slice(0, 16),
    },
    sessionId: null,
    timestamp: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    targetUserId: null,
  });
  await batch.commit();

  return {
    name: standardizedTestingDocumentFileName(
      expectedKind as TestingDocumentKind,
      entry.name ?? `document.${extension}`,
    ),
    contentType: expectedMime,
    size: bytes.length,
    dataBase64: bytes.toString("base64"),
  };
});

/**
 * Authenticated Testing Service inquiry submission. Enforces trusted server
 * role eligibility, uploaded supporting documents, mobile number, preferred
 * schedule, and Personal Data Sheet / Informed Consent confirmations without
 * writing to the `appointments` collection.
 */
export const submitTestingServiceInquiry = onCall(async (request) => {
  const uid = requireUid(request);
  const input = (request.data ?? {}) as {
    isStudentForOjt?: unknown;
    endorsementLetterConfirmed?: unknown;
    officialReceiptConfirmed?: unknown;
    personalDataSheetConfirmed?: unknown;
    informedConsentConfirmed?: unknown;
    mobileNumber?: unknown;
    preferredScheduleAtMillis?: unknown;
    endorsementLetter?: unknown;
    officialReceipt?: unknown;
    admissionRequirements?: unknown;
    personalDataSheet?: unknown;
    message?: unknown;
    preferredScheduleNote?: unknown;
    requestId?: unknown;
  };

  const [userSnap, authUser, availabilitySnap] = await Promise.all([
    db().collection("users").doc(uid).get(),
    getAuth().getUser(uid),
    db().collection("pacc_availability").doc("current").get(),
  ]);
  if (authUser.disabled) {
    throw new HttpsError("permission-denied", "Your account is disabled.");
  }
  const availability = availabilitySnap.exists ? availabilitySnap.data() : undefined;

  let eligibility;
  let submission;
  try {
    eligibility = resolveTestingServiceEligibility(
      userSnap.exists ? userSnap.data() ?? {} : null,
      {isStudentForOjt: input.isStudentForOjt},
    );
    submission = validateTestingServiceSubmission(input, uid, Date.now(), availability);
  } catch (error) {
    handleDomainError(error);
  }

  const rawRequestId = typeof input.requestId === "string" ? input.requestId.trim() : "";
  if (input.requestId !== undefined && input.requestId !== null && !REQUEST_ID_PATTERN.test(rawRequestId)) {
    throw new HttpsError("invalid-argument", "A valid request ID is required.");
  }
  const inquiryRef = rawRequestId
    ? db().collection("inquiries").doc(`testing_${uid}_${rawRequestId}`)
    : db().collection("inquiries").doc();
  const lockRef = db().collection("testing_service_user_locks").doc(uid);

  await Promise.all([
    verifyTestingDocumentObject(submission.documents.endorsementLetter, uid),
    verifyTestingDocumentObject(submission.documents.officialReceipt, uid),
    ...submission.documents.admissionRequirements.map((doc) =>
      verifyTestingDocumentObject(doc, uid),
    ),
  ]);

  const profile = userSnap.data() ?? {};
  const email = visibleContactEmail(authUser.email) ||
    visibleContactEmail(profile.email) ||
    visibleContactEmail(submission.personalDataSheet.email);
  const studentNumber = String(profile.schoolId ?? submission.personalDataSheet.idNumber ?? "").trim();
  const displayName = resolveActorName(profile, email);
  const preferredScheduleTs = submission.preferredSchedule
    ? Timestamp.fromMillis(submission.preferredSchedule.millis)
    : null;
  const preferredScheduleSummary = submission.preferredSchedule
    ? `${formatManilaDate(submission.preferredSchedule.millis)} · ${submission.preferredSchedule.scheduledTime} (PHT)`
    : null;

  const created = await db().runTransaction(async (tx) => {
    const activeQuery = db()
      .collection("inquiries")
      .where("userId", "==", uid)
      .where("formType", "==", TESTING_SERVICE_FORM_TYPE)
      .limit(15);
    const [existing, lockSnap, activeSnap] = await Promise.all([
      tx.get(inquiryRef),
      tx.get(lockRef),
      tx.get(activeQuery),
    ]);
    if (existing.exists) {
      if (existing.data()?.userId !== uid) {
        throw new HttpsError("permission-denied", "Unable to reuse this request identifier.");
      }
      return {duplicate: true};
    }

    const hasOngoingInquiry = activeSnap.docs.some((doc) => {
      const d = doc.data();
      const schedStatus = String((d.testingSchedule as Record<string, unknown> | undefined)?.status ?? "");
      const inqStatus = String(d.status ?? "").trim().toLowerCase();
      return schedStatus !== "completed" && schedStatus !== "cancelled" && inqStatus !== "resolved";
    });
    if (hasOngoingInquiry) {
      throw new HttpsError(
        "failed-precondition",
        "You already have an ongoing Testing Service schedule request. You can submit a new request once PACC marks your current one as completed.",
      );
    }
    if (lockSnap.exists) {
      const lockedInquiryId = String(lockSnap.data()?.inquiryId ?? "").trim();
      const lockedDoc = activeSnap.docs.find((d) => d.id === lockedInquiryId);
      if (lockedInquiryId && !lockedDoc) {
        const lockedInquirySnap = await tx.get(db().collection("inquiries").doc(lockedInquiryId));
        if (lockedInquirySnap.exists) {
          const d = lockedInquirySnap.data()!;
          const schedStatus = String((d.testingSchedule as Record<string, unknown> | undefined)?.status ?? "");
          const inqStatus = String(d.status ?? "").trim().toLowerCase();
          if (schedStatus !== "completed" && schedStatus !== "cancelled" && inqStatus !== "resolved") {
            throw new HttpsError(
              "failed-precondition",
              "You already have an ongoing Testing Service schedule request. You can submit a new request once PACC marks your current one as completed.",
            );
          }
        }
      }
    }

    const pdsLabel = submission.personalDataSheet.email
      ? `${submission.personalDataSheet.fullName} (${submission.personalDataSheet.email})`
      : (studentNumber
          ? `${submission.personalDataSheet.fullName} (Student No. ${studentNumber})`
          : submission.personalDataSheet.fullName);

    const formData: Record<string, unknown> = {
      "Client type": eligibility.requesterLabel,
      "Mobile number": submission.mobileNumber,
      "Endorsement Letter": submission.documents.endorsementLetter.name,
      "Official receipt (PHP 250)": submission.documents.officialReceipt.name,
      ...(submission.documents.admissionRequirements.length > 0
        ? {
            "Admission requirements": submission.documents.admissionRequirements
              .map((doc) => doc.name)
              .join(", "),
          }
        : {}),
      ...(preferredScheduleSummary
        ? {"Preferred schedule": preferredScheduleSummary}
        : {}),
      ...(submission.preferredScheduleNote
        ? {"Preferred schedule note": submission.preferredScheduleNote}
        : {}),
      "Personal Data Sheet": pdsLabel,
      "Informed Consent": "Agreed",
    };

    tx.create(inquiryRef, {
      userId: uid,
      subject: "Testing Service Schedule Request",
      message: submission.message,
      category: TESTING_SERVICE_CATEGORY,
      email,
      ...(studentNumber ? {studentNumber} : {}),
      name: displayName,
      contactNumber: submission.mobileNumber,
      preferredScheduleAt: preferredScheduleTs,
      preferredScheduleTime: submission.preferredSchedule?.scheduledTime ?? null,
      role: eligibility.requesterLabel,
      formType: TESTING_SERVICE_FORM_TYPE,
      formData,
      testingDocuments: {
        endorsementLetter: submission.documents.endorsementLetter,
        officialReceipt: submission.documents.officialReceipt,
        admissionRequirements: submission.documents.admissionRequirements,
      },
      personalDataSheet: submission.personalDataSheet,
      status: "pending",
      testingSchedule: {
        status: "awaiting_schedule",
        scheduledAt: null,
        scheduledTime: null,
        location: TESTING_SERVICE_DEFAULT_LOCATION,
        proposedBy: null,
        proposedByName: null,
        proposedAt: null,
        staffNote: null,
        rescheduleCount: 0,
        maxReschedules: TESTING_SERVICE_MAX_RESCHEDULES,
        rescheduleReason: null,
        rescheduleRequestedAt: null,
        confirmedAt: null,
        confirmedBy: null,
        revision: 0,
      },
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    writeAudit(tx, db(), {
      actorId: uid,
      actorNameSnapshot: displayName,
      actorRoleSnapshot: eligibility.populationRole,
      action: "TESTING_SERVICE_INQUIRY_SUBMITTED",
      category: AUDIT_CATEGORIES.inquiries,
      targetType: "inquiry",
      targetId: inquiryRef.id,
      metadata: {
        requesterType: eligibility.requesterType,
        admissionFileCount: submission.documents.admissionRequirements.length,
      },
    });
    tx.set(lockRef, {
      userId: uid,
      inquiryId: inquiryRef.id,
      status: "active",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {duplicate: false};
  });

  await routeInquiry(inquiryRef.id);
  return {
    ok: true,
    inquiryId: inquiryRef.id,
    requesterType: eligibility.requesterType,
    duplicate: created.duplicate,
  };
});

/**
 * Staff proposes (or revises after a one-time reschedule request) a Testing
 * Service date and time within Mon-Sat 8:00 AM-5:00 PM PHT, records a reply
 * in `inquiries/{id}/replies`, and notifies the user in-app.
 */
export const proposeTestingServiceSchedule = onCall(async (request) => {
  const who = await inquiryActor(request);
  const inquiryId = inquiryIdFrom(request.data);
  const input = (request.data ?? {}) as {
    scheduledAtMillis?: unknown;
    decisionMode?: unknown;
    reason?: unknown;
    note?: unknown;
    location?: unknown;
    expectedRevision?: unknown;
    requestId?: unknown;
  };

  const availabilitySnap = await db().collection("pacc_availability").doc("current").get();
  const availability = availabilitySnap.exists ? availabilitySnap.data() : undefined;

  let replyId;
  let validatedSchedule;
  try {
    replyId = requestIdFrom(input.requestId);
    validatedSchedule = validateTestingScheduleDateTime(input.scheduledAtMillis, Date.now(), availability);
  } catch (error) {
    handleDomainError(error);
  }

  const rawDecisionMode = typeof input.decisionMode === "string"
    ? input.decisionMode.trim()
    : "";
  if (rawDecisionMode && rawDecisionMode !== "accept_requested" && rawDecisionMode !== "reschedule") {
    throw new HttpsError("invalid-argument", "Invalid Testing Service decision mode.");
  }
  const isAcceptRequested = rawDecisionMode === "accept_requested";

  const rawReason = typeof input.reason === "string" ? input.reason.trim() : "";
  if (rawReason.length > 1000) {
    throw new HttpsError("invalid-argument", "Reason must be at most 1000 characters.");
  }
  const rawNote = typeof input.note === "string" ? input.note.trim() : "";
  if (rawNote.length > 1000) {
    throw new HttpsError("invalid-argument", "Note must be at most 1000 characters.");
  }
  const effectiveNote = [rawReason, rawNote]
    .filter((part, index, list) => part.length > 0 && list.indexOf(part) === index)
    .join(" — ");
  const rawLocation = typeof input.location === "string" ? input.location.trim() : "";
  if (rawLocation.length > 120) {
    throw new HttpsError("invalid-argument", "Location must be at most 120 characters.");
  }
  const location = rawLocation || TESTING_SERVICE_DEFAULT_LOCATION;

  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const replyRef = ref.collection("replies").doc(replyId);
  const nowTs = Timestamp.now();
  const scheduledTs = Timestamp.fromMillis(validatedSchedule.millis);
  const replyLines = [
    isAcceptRequested
      ? `Approved Testing Service schedule: ${formatManilaDate(validatedSchedule.millis)} at ${validatedSchedule.scheduledTime} (PHT)`
      : `Proposed Testing Service schedule: ${formatManilaDate(validatedSchedule.millis)} at ${validatedSchedule.scheduledTime} (PHT)`,
    `Location: ${location}`,
    ...(effectiveNote ? ["", effectiveNote] : []),
  ];
  const replyText = replyLines.join("\n");

  const outcome = await db().runTransaction(async (tx) => {
    const [current, currentProjection, existingReply] = await Promise.all([
      tx.get(ref),
      tx.get(statusRef),
      tx.get(replyRef),
    ]);
    if (!current.exists) {
      throw new HttpsError("not-found", "Inquiry not found.");
    }
    const data = current.data()!;
    if (
      !canCounselorDecideTestingSchedule(
        {uid: who.actor.uid, role: who.role, isSuperAdmin: who.isSuperAdmin},
        data,
      )
    ) {
      throw new HttpsError(
        "permission-denied",
        who.isSuperAdmin || who.role === "admin"
          ? "Admin review is read-only. Only assigned counselors can manage Testing Service schedules."
          : "Only the counselor assigned to this inquiry can manage its Testing Service schedule.",
      );
    }

    if (existingReply.exists) {
      const existingSchedule = (data.testingSchedule ?? {}) as Record<string, unknown>;
      return {
        duplicate: true,
        acceptedImmediately: String(existingSchedule.status ?? "") === "confirmed",
        revision: revisionOf(data),
        scheduleRevision: Number(existingSchedule.revision ?? 0),
        scheduledTime: String(existingSchedule.scheduledTime ?? validatedSchedule.scheduledTime),
        data,
      };
    }

    const revision = revisionOf(data);
    if (input.expectedRevision !== revision) {
      throw new HttpsError("failed-precondition", STALE_REVISION);
    }

    let state;
    try {
      state = assertCanProposeTestingSchedule(data);
    } catch (error) {
      handleDomainError(error);
    }

    const prevSchedule = (data.testingSchedule && typeof data.testingSchedule === "object")
      ? data.testingSchedule as Record<string, unknown>
      : {};
    const prevScheduleStatus = String(prevSchedule.status ?? "awaiting_schedule");
    if (isAcceptRequested) {
      if (prevScheduleStatus !== "awaiting_schedule") {
        throw new HttpsError(
          "failed-precondition",
          "Only awaiting Testing Service requests can be approved directly as requested.",
        );
      }
      const preferredTs = data.preferredScheduleAt instanceof Timestamp
        ? data.preferredScheduleAt.toMillis()
        : null;
      if (preferredTs !== validatedSchedule.millis) {
        throw new HttpsError(
          "failed-precondition",
          "To choose a different date or time, use Re-schedule.",
        );
      }
    }

    const nextScheduleRevision = state.scheduleRevision + 1;
    const nextStatus = data.status === "pending" ? "in_progress" : data.status;
    const nextOwnerId = data.ownerId ?? who.actor.uid;
    const prevResponseCount = Number.isInteger(data.responseCount) && Number(data.responseCount) >= 0
      ? Number(data.responseCount)
      : 0;
    const nextResponseCount = prevResponseCount + 1;

    const nextTestingSchedule = {
      ...prevSchedule,
      status: isAcceptRequested ? "confirmed" : "proposed",
      scheduledAt: scheduledTs,
      scheduledTime: validatedSchedule.scheduledTime,
      location,
      proposedBy: who.actor.uid,
      proposedByName: who.actor.name,
      proposedAt: FieldValue.serverTimestamp(),
      ...(isAcceptRequested
        ? {
            confirmedAt: FieldValue.serverTimestamp(),
            confirmedBy: who.actor.uid,
            confirmedByName: who.actor.name,
          }
        : {}),
      staffNote: effectiveNote || null,
      rescheduleCount: state.rescheduleCount,
      maxReschedules: TESTING_SERVICE_MAX_RESCHEDULES,
      revision: nextScheduleRevision,
    };

    tx.create(replyRef, {
      message: replyText,
      authorId: who.actor.uid,
      authorName: who.actor.name,
      authorRole: who.role,
      createdAt: FieldValue.serverTimestamp(),
    });

    tx.update(ref, {
      status: nextStatus,
      ownerId: nextOwnerId,
      firstResponseAt: data.firstResponseAt ?? FieldValue.serverTimestamp(),
      lastResponseAt: FieldValue.serverTimestamp(),
      lastResponseBy: who.actor.uid,
      lastResponseByName: who.actor.name,
      lastResponseRole: who.role,
      responseCount: FieldValue.increment(1),
      routingRevision: revision + 1,
      testingSchedule: nextTestingSchedule,
      updatedAt: FieldValue.serverTimestamp(),
    });

    const projection = buildInquiryStatusProjection(inquiryId, {
      ...data,
      status: nextStatus,
      ownerId: nextOwnerId,
      firstResponseAt: data.firstResponseAt ?? nowTs,
      lastResponseAt: nowTs,
      responseCount: nextResponseCount,
      routingRevision: revision + 1,
      updatedAt: nowTs,
    });
    if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, projection)) {
      tx.set(statusRef, {...projection, projectedAt: FieldValue.serverTimestamp()});
    }

    writeAudit(tx, db(), {
      actorId: who.actor.uid,
      actorNameSnapshot: who.actor.name,
      actorRoleSnapshot: who.role,
      action: isAcceptRequested
        ? "TESTING_SERVICE_SCHEDULE_CONFIRMED_BY_STAFF"
        : "TESTING_SERVICE_SCHEDULE_PROPOSED",
      category: AUDIT_CATEGORIES.inquiries,
      targetType: "inquiry",
      targetId: inquiryId,
      metadata: {
        replyId,
        revision: revision + 1,
        scheduleRevision: nextScheduleRevision,
        rescheduleCount: state.rescheduleCount,
      },
    });

    return {
      duplicate: false,
      acceptedImmediately: isAcceptRequested,
      revision: revision + 1,
      scheduleRevision: nextScheduleRevision,
      scheduledTime: validatedSchedule.scheduledTime,
      data,
    };
  });

  const ownerUid = String(outcome.data.userId ?? "");
  if (ownerUid) {
    await createOnce(
      `testing_schedule_${outcome.acceptedImmediately ? "confirmed" : "proposed"}_${inquiryId}_${outcome.scheduleRevision}`,
      {
        userId: ownerUid,
        inquiryId,
        type: "inquiry",
        title: outcome.acceptedImmediately
          ? "Testing Service schedule confirmed"
          : "Testing Service schedule proposed",
        body: outcome.acceptedImmediately
          ? "PACC approved and confirmed your requested Testing Service schedule."
          : "PACC proposed a schedule for your Testing Service inquiry. Open MindMate to review and respond.",
        createdAt: FieldValue.serverTimestamp(),
        readAt: null,
      },
    );
  }

  const otherStaff = staffRecipientsForInquiry(outcome.data)
    .filter((recipient) => recipient !== who.actor.uid);
  await Promise.all(otherStaff.map((recipient) =>
    createOnce(
      `portal_testing_proposed_${inquiryId}_${outcome.scheduleRevision}_${recipient}`,
      notification(
        recipient,
        inquiryId,
        outcome.acceptedImmediately
          ? "Testing Service schedule confirmed"
          : "Testing Service schedule proposed",
        outcome.acceptedImmediately
          ? "A counselor confirmed a requested Testing Service schedule."
          : "A Testing Service schedule proposal was posted for an inquiry.",
      ),
    ),
  ));

  return {
    ok: true,
    replyId,
    duplicate: outcome.duplicate,
    status: outcome.acceptedImmediately ? "confirmed" : "proposed",
    revision: outcome.revision,
    scheduleRevision: outcome.scheduleRevision,
    scheduledTime: outcome.scheduledTime,
  };
});

/**
 * Staff-only Testing Service schedule cancellation with a recorded reason.
 * Keeps data inside `inquiries` and notifies the requester in-app.
 */
export const cancelTestingServiceSchedule = onCall(async (request) => {
  const who = await inquiryActor(request);
  const inquiryId = inquiryIdFrom(request.data);
  const input = (request.data ?? {}) as {
    reason?: unknown;
    expectedRevision?: unknown;
    requestId?: unknown;
  };

  let replyId;
  try {
    replyId = requestIdFrom(input.requestId);
  } catch (error) {
    handleDomainError(error);
  }

  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const replyRef = ref.collection("replies").doc(replyId);
  const nowTs = Timestamp.now();

  const outcome = await db().runTransaction(async (tx) => {
    const [current, currentProjection, existingReply] = await Promise.all([
      tx.get(ref),
      tx.get(statusRef),
      tx.get(replyRef),
    ]);
    if (!current.exists) {
      throw new HttpsError("not-found", "Inquiry not found.");
    }
    const data = current.data()!;
    const ownerUidForLock = String(data.userId ?? "").trim();
    const lockRef = ownerUidForLock
      ? db().collection("testing_service_user_locks").doc(ownerUidForLock)
      : null;
    const lockSnap = lockRef ? await tx.get(lockRef) : null;
    if (
      !canCounselorDecideTestingSchedule(
        {uid: who.actor.uid, role: who.role, isSuperAdmin: who.isSuperAdmin},
        data,
      )
    ) {
      throw new HttpsError(
        "permission-denied",
        who.isSuperAdmin || who.role === "admin"
          ? "Admin review is read-only. Only assigned counselors can manage Testing Service schedules."
          : "Only the counselor assigned to this inquiry can cancel this Testing Service schedule.",
      );
    }

    if (existingReply.exists) {
      const existingSchedule = (data.testingSchedule ?? {}) as Record<string, unknown>;
      return {
        duplicate: true,
        revision: revisionOf(data),
        scheduleRevision: Number(existingSchedule.revision ?? 0),
        data,
      };
    }

    const revision = revisionOf(data);
    if (input.expectedRevision !== revision) {
      throw new HttpsError("failed-precondition", STALE_REVISION);
    }

    let state;
    try {
      state = assertCanCancelTestingSchedule(data, input.reason);
    } catch (error) {
      handleDomainError(error);
    }

    const nextScheduleRevision = state.scheduleRevision + 1;
    const nextStatus = data.status === "pending" ? "in_progress" : data.status;
    const nextOwnerId = data.ownerId ?? who.actor.uid;
    const prevResponseCount = Number.isInteger(data.responseCount) && Number(data.responseCount) >= 0
      ? Number(data.responseCount)
      : 0;
    const nextResponseCount = prevResponseCount + 1;
    const prevSchedule = (data.testingSchedule && typeof data.testingSchedule === "object")
      ? data.testingSchedule as Record<string, unknown>
      : {};

    const nextTestingSchedule = {
      ...prevSchedule,
      status: "cancelled",
      cancelReason: state.reason,
      cancelledBy: who.actor.uid,
      cancelledByName: who.actor.name,
      cancelledAt: FieldValue.serverTimestamp(),
      revision: nextScheduleRevision,
    };

    tx.create(replyRef, {
      message: `Testing Service schedule cancelled.\nReason: ${state.reason}`,
      authorId: who.actor.uid,
      authorName: who.actor.name,
      authorRole: who.role,
      createdAt: FieldValue.serverTimestamp(),
    });

    tx.update(ref, {
      status: nextStatus,
      ownerId: nextOwnerId,
      firstResponseAt: data.firstResponseAt ?? FieldValue.serverTimestamp(),
      lastResponseAt: FieldValue.serverTimestamp(),
      lastResponseBy: who.actor.uid,
      lastResponseByName: who.actor.name,
      lastResponseRole: who.role,
      responseCount: FieldValue.increment(1),
      routingRevision: revision + 1,
      testingSchedule: nextTestingSchedule,
      updatedAt: FieldValue.serverTimestamp(),
    });

    const projection = buildInquiryStatusProjection(inquiryId, {
      ...data,
      status: nextStatus,
      ownerId: nextOwnerId,
      firstResponseAt: data.firstResponseAt ?? nowTs,
      lastResponseAt: nowTs,
      responseCount: nextResponseCount,
      routingRevision: revision + 1,
      updatedAt: nowTs,
    });
    if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, projection)) {
      tx.set(statusRef, {...projection, projectedAt: FieldValue.serverTimestamp()});
    }

    if (lockRef && lockSnap?.exists && String(lockSnap.data()?.inquiryId ?? "") === inquiryId) {
      tx.delete(lockRef);
    }

    writeAudit(tx, db(), {
      actorId: who.actor.uid,
      actorNameSnapshot: who.actor.name,
      actorRoleSnapshot: who.role,
      action: "TESTING_SERVICE_SCHEDULE_CANCELLED",
      category: AUDIT_CATEGORIES.inquiries,
      targetType: "inquiry",
      targetId: inquiryId,
      metadata: {
        replyId,
        revision: revision + 1,
        scheduleRevision: nextScheduleRevision,
      },
    });

    return {
      duplicate: false,
      revision: revision + 1,
      scheduleRevision: nextScheduleRevision,
      data,
    };
  });

  const ownerUid = String(outcome.data.userId ?? "");
  if (ownerUid) {
    await createOnce(
      `testing_schedule_cancelled_${inquiryId}_${outcome.scheduleRevision}`,
      {
        userId: ownerUid,
        inquiryId,
        type: "inquiry",
        title: "Testing Service schedule cancelled",
        body: "Your Testing Service schedule request was cancelled by PACC. Open MindMate to view details.",
        createdAt: FieldValue.serverTimestamp(),
        readAt: null,
      },
    );
  }

  const otherStaff = staffRecipientsForInquiry(outcome.data)
    .filter((recipient) => recipient !== who.actor.uid);
  await Promise.all(otherStaff.map((recipient) =>
    createOnce(
      `portal_testing_cancelled_${inquiryId}_${outcome.scheduleRevision}_${recipient}`,
      notification(
        recipient,
        inquiryId,
        "Testing Service schedule cancelled",
        "A counselor cancelled a Testing Service schedule request.",
      ),
    ),
  ));

  return {
    ok: true,
    replyId,
    duplicate: outcome.duplicate,
    status: "cancelled",
    revision: outcome.revision,
    scheduleRevision: outcome.scheduleRevision,
  };
});

/**
 * Inquiry owner accepts the proposed Testing Service schedule. Locks the
 * schedule as confirmed (no cancellation or further rescheduling).
 */
export const acceptTestingServiceSchedule = onCall(async (request) => {
  const uid = requireUid(request);
  const inquiryId = inquiryIdFrom(request.data);
  const expectedScheduleRevision = (request.data as {expectedScheduleRevision?: unknown})?.expectedScheduleRevision;
  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const nowTs = Timestamp.now();

  const outcome = await db().runTransaction(async (tx) => {
    const [current, currentProjection] = await Promise.all([tx.get(ref), tx.get(statusRef)]);
    if (!current.exists) {
      throw new HttpsError("not-found", "Inquiry not found.");
    }
    const data = current.data()!;
    let state;
    try {
      state = assertCanAcceptTestingSchedule(data, uid);
    } catch (error) {
      handleDomainError(error);
    }
    checkOptionalScheduleRevision(expectedScheduleRevision, state.scheduleRevision);

    const revision = revisionOf(data);
    const nextScheduleRevision = state.scheduleRevision + 1;
    const prevSchedule = (data.testingSchedule ?? {}) as Record<string, unknown>;
    const nextTestingSchedule = {
      ...prevSchedule,
      status: "confirmed",
      confirmedAt: FieldValue.serverTimestamp(),
      confirmedBy: uid,
      revision: nextScheduleRevision,
    };

    tx.update(ref, {
      status: data.status === "pending" ? "in_progress" : data.status,
      routingRevision: revision + 1,
      testingSchedule: nextTestingSchedule,
      updatedAt: FieldValue.serverTimestamp(),
    });

    const projection = buildInquiryStatusProjection(inquiryId, {
      ...data,
      status: data.status === "pending" ? "in_progress" : data.status,
      routingRevision: revision + 1,
      updatedAt: nowTs,
    });
    if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, projection)) {
      tx.set(statusRef, {...projection, projectedAt: FieldValue.serverTimestamp()});
    }

    writeAudit(tx, db(), {
      actorId: uid,
      actorNameSnapshot: String(data.name ?? "MindMate User"),
      actorRoleSnapshot: "appUser",
      action: "TESTING_SERVICE_SCHEDULE_ACCEPTED",
      category: AUDIT_CATEGORIES.inquiries,
      targetType: "inquiry",
      targetId: inquiryId,
      metadata: {
        revision: revision + 1,
        scheduleRevision: nextScheduleRevision,
      },
    });

    return {
      revision: revision + 1,
      scheduleRevision: nextScheduleRevision,
      data,
    };
  });

  const recipients = staffRecipientsForInquiry(outcome.data);
  await Promise.all(recipients.map((recipient) =>
    createOnce(
      `portal_testing_accepted_${inquiryId}_${outcome.scheduleRevision}_${recipient}`,
      notification(
        recipient,
        inquiryId,
        "Testing schedule accepted",
        "The client confirmed the proposed Testing Service schedule.",
      ),
    ),
  ));

  return {
    ok: true,
    status: "confirmed",
    revision: outcome.revision,
    scheduleRevision: outcome.scheduleRevision,
  };
});

/**
 * Inquiry owner requests their single allowed reschedule. Enforced atomically
 * inside a Firestore transaction so concurrent taps cannot exceed 1 reschedule.
 */
export const requestTestingServiceReschedule = onCall(async (request) => {
  const uid = requireUid(request);
  const inquiryId = inquiryIdFrom(request.data);
  const input = (request.data ?? {}) as {
    reason?: unknown;
    expectedScheduleRevision?: unknown;
  };
  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const nowTs = Timestamp.now();

  const outcome = await db().runTransaction(async (tx) => {
    const [current, currentProjection] = await Promise.all([tx.get(ref), tx.get(statusRef)]);
    if (!current.exists) {
      throw new HttpsError("not-found", "Inquiry not found.");
    }
    const data = current.data()!;
    let state;
    try {
      state = assertCanRequestTestingReschedule(data, uid, input.reason);
    } catch (error) {
      handleDomainError(error);
    }
    checkOptionalScheduleRevision(input.expectedScheduleRevision, state.scheduleRevision);

    const revision = revisionOf(data);
    const nextScheduleRevision = state.scheduleRevision + 1;
    const nextRescheduleCount = state.rescheduleCount + 1;
    const prevSchedule = (data.testingSchedule ?? {}) as Record<string, unknown>;
    const nextTestingSchedule = {
      ...prevSchedule,
      status: "reschedule_requested",
      rescheduleCount: nextRescheduleCount,
      rescheduleReason: state.reason,
      rescheduleRequestedAt: FieldValue.serverTimestamp(),
      revision: nextScheduleRevision,
    };

    tx.update(ref, {
      status: data.status === "pending" ? "in_progress" : data.status,
      routingRevision: revision + 1,
      testingSchedule: nextTestingSchedule,
      updatedAt: FieldValue.serverTimestamp(),
    });

    const projection = buildInquiryStatusProjection(inquiryId, {
      ...data,
      status: data.status === "pending" ? "in_progress" : data.status,
      routingRevision: revision + 1,
      updatedAt: nowTs,
    });
    if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, projection)) {
      tx.set(statusRef, {...projection, projectedAt: FieldValue.serverTimestamp()});
    }

    writeAudit(tx, db(), {
      actorId: uid,
      actorNameSnapshot: String(data.name ?? "MindMate User"),
      actorRoleSnapshot: "appUser",
      action: "TESTING_SERVICE_RESCHEDULE_REQUESTED",
      category: AUDIT_CATEGORIES.inquiries,
      targetType: "inquiry",
      targetId: inquiryId,
      metadata: {
        revision: revision + 1,
        scheduleRevision: nextScheduleRevision,
        rescheduleCount: nextRescheduleCount,
      },
    });

    return {
      revision: revision + 1,
      scheduleRevision: nextScheduleRevision,
      rescheduleCount: nextRescheduleCount,
      data,
    };
  });

  const recipients = staffRecipientsForInquiry(outcome.data);
  await Promise.all(recipients.map((recipient) =>
    createOnce(
      `portal_testing_reschedule_${inquiryId}_${outcome.scheduleRevision}_${recipient}`,
      notification(
        recipient,
        inquiryId,
        "Testing reschedule requested",
        "A one-time reschedule was requested for a Testing Service inquiry.",
      ),
    ),
  ));

  return {
    ok: true,
    status: "reschedule_requested",
    rescheduleCount: outcome.rescheduleCount,
    revision: outcome.revision,
    scheduleRevision: outcome.scheduleRevision,
  };
});

/**
 * Staff-only completion action for Testing Service schedules. Marks
 * `testingSchedule.status` as `"completed"`, resolves the inquiry, and
 * releases `testing_service_user_locks/{uid}` so the user can submit a new
 * Testing Service request later.
 */
export const completeTestingServiceSchedule = onCall(async (request) => {
  const who = await inquiryActor(request);
  const inquiryId = inquiryIdFrom(request.data);
  const input = (request.data ?? {}) as {
    reason?: unknown;
    note?: unknown;
    expectedRevision?: unknown;
    requestId?: unknown;
  };

  let replyId;
  try {
    replyId = requestIdFrom(input.requestId);
  } catch (error) {
    handleDomainError(error);
  }

  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const replyRef = ref.collection("replies").doc(replyId);
  const nowTs = Timestamp.now();

  const outcome = await db().runTransaction(async (tx) => {
    const [current, currentProjection, existingReply] = await Promise.all([
      tx.get(ref),
      tx.get(statusRef),
      tx.get(replyRef),
    ]);
    if (!current.exists) {
      throw new HttpsError("not-found", "Inquiry not found.");
    }
    const data = current.data()!;
    const ownerUidForLock = String(data.userId ?? "").trim();
    const lockRef = ownerUidForLock
      ? db().collection("testing_service_user_locks").doc(ownerUidForLock)
      : null;
    const lockSnap = lockRef ? await tx.get(lockRef) : null;

    if (
      !canCounselorDecideTestingSchedule(
        {uid: who.actor.uid, role: who.role, isSuperAdmin: who.isSuperAdmin},
        data,
      )
    ) {
      throw new HttpsError(
        "permission-denied",
        who.isSuperAdmin || who.role === "admin"
          ? "Admin review is read-only. Only assigned counselors can manage Testing Service schedules."
          : "Only the counselor assigned to this inquiry can mark this Testing Service schedule completed.",
      );
    }

    if (existingReply.exists) {
      const existingSchedule = (data.testingSchedule ?? {}) as Record<string, unknown>;
      return {
        duplicate: true,
        revision: revisionOf(data),
        scheduleRevision: Number(existingSchedule.revision ?? 0),
        data,
      };
    }

    const revision = revisionOf(data);
    if (input.expectedRevision !== revision) {
      throw new HttpsError("failed-precondition", STALE_REVISION);
    }

    const rawCompletionNote = typeof input.note === "string" && input.note.trim()
      ? input.note
      : input.reason;
    let state;
    try {
      state = assertCanCompleteTestingSchedule(data, rawCompletionNote);
    } catch (error) {
      handleDomainError(error);
    }

    const nextScheduleRevision = state.scheduleRevision + 1;
    const nextOwnerId = data.ownerId ?? who.actor.uid;
    const prevResponseCount = Number.isInteger(data.responseCount) && Number(data.responseCount) >= 0
      ? Number(data.responseCount)
      : 0;
    const nextResponseCount = prevResponseCount + 1;
    const prevSchedule = (data.testingSchedule && typeof data.testingSchedule === "object")
      ? data.testingSchedule as Record<string, unknown>
      : {};

    const nextTestingSchedule = {
      ...prevSchedule,
      status: "completed",
      completedAt: FieldValue.serverTimestamp(),
      completedBy: who.actor.uid,
      completedByName: who.actor.name,
      completionNote: state.reason || null,
      revision: nextScheduleRevision,
    };

    tx.create(replyRef, {
      message: state.reason
        ? `Testing Service schedule marked as completed.\nNotes: ${state.reason}`
        : "Testing Service schedule marked as completed.",
      authorId: who.actor.uid,
      authorName: who.actor.name,
      authorRole: who.role,
      createdAt: FieldValue.serverTimestamp(),
    });

    tx.update(ref, {
      status: "resolved",
      ownerId: nextOwnerId,
      resolvedAt: FieldValue.serverTimestamp(),
      resolvedBy: who.actor.uid,
      resolvedByName: who.actor.name,
      firstResponseAt: data.firstResponseAt ?? FieldValue.serverTimestamp(),
      lastResponseAt: FieldValue.serverTimestamp(),
      lastResponseBy: who.actor.uid,
      lastResponseByName: who.actor.name,
      lastResponseRole: who.role,
      responseCount: FieldValue.increment(1),
      routingRevision: revision + 1,
      testingSchedule: nextTestingSchedule,
      updatedAt: FieldValue.serverTimestamp(),
    });

    const projection = buildInquiryStatusProjection(inquiryId, {
      ...data,
      status: "resolved",
      ownerId: nextOwnerId,
      firstResponseAt: data.firstResponseAt ?? nowTs,
      lastResponseAt: nowTs,
      responseCount: nextResponseCount,
      routingRevision: revision + 1,
      updatedAt: nowTs,
    });
    if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, projection)) {
      tx.set(statusRef, {...projection, projectedAt: FieldValue.serverTimestamp()});
    }

    if (lockRef && lockSnap?.exists && String(lockSnap.data()?.inquiryId ?? "") === inquiryId) {
      tx.delete(lockRef);
    }

    writeAudit(tx, db(), {
      actorId: who.actor.uid,
      actorNameSnapshot: who.actor.name,
      actorRoleSnapshot: who.role,
      action: "TESTING_SERVICE_SCHEDULE_COMPLETED",
      category: AUDIT_CATEGORIES.inquiries,
      targetType: "inquiry",
      targetId: inquiryId,
      metadata: {
        replyId,
        revision: revision + 1,
        scheduleRevision: nextScheduleRevision,
      },
    });

    return {
      duplicate: false,
      revision: revision + 1,
      scheduleRevision: nextScheduleRevision,
      data,
    };
  });

  const ownerUid = String(outcome.data.userId ?? "");
  if (ownerUid) {
    await createOnce(
      `testing_schedule_completed_${inquiryId}_${outcome.scheduleRevision}`,
      {
        userId: ownerUid,
        inquiryId,
        type: "inquiry",
        title: "Testing Service completed",
        body: "Your Testing Service schedule has been marked as completed by PACC. You may now request a new schedule if needed.",
        createdAt: FieldValue.serverTimestamp(),
        readAt: null,
      },
    );
  }

  const otherStaff = staffRecipientsForInquiry(outcome.data)
    .filter((recipient) => recipient !== who.actor.uid);
  await Promise.all(otherStaff.map((recipient) =>
    createOnce(
      `portal_testing_completed_${inquiryId}_${outcome.scheduleRevision}_${recipient}`,
      notification(
        recipient,
        inquiryId,
        "Testing Service completed",
        "A counselor marked a Testing Service schedule request as completed.",
      ),
    ),
  ));

  return {
    ok: true,
    replyId,
    duplicate: outcome.duplicate,
    status: "completed",
    revision: outcome.revision,
    scheduleRevision: outcome.scheduleRevision,
  };
});
