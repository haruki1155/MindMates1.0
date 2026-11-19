import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireSuperAdmin, requireUid} from "./access";
import {actorName, AUDIT_CATEGORIES, writeAudit} from "./audit";
import {buildInquiryStatusProjection, shouldWriteInquiryProjection} from "./inquiry_routing";
import {Actor, canHandleClinical, createOnce, DENIED, inquiryActor, inquiryIdFrom, notification, reasonFrom, revisionOf, STALE_REVISION, statusCollection} from "./inquiry_routing_service";
import {InquirySlaError, parseSlaHours, replyMessage, requestIdFrom} from "./inquiry_sla";

// Authored replies, super-admin takeover and the response target. Every
// mutation is a transaction with an audit record and a revision check.

const db = () => getFirestore();
// Reply and takeover are new in PR 5, so no legacy client omits the revision:
// it is always required here.
const STALE = STALE_REVISION;

function validated<T>(fn: () => T): T {
  try {
    return fn();
  } catch (error) {
    if (error instanceof InquirySlaError) throw new HttpsError("invalid-argument", error.message, {reason: error.code});
    throw error;
  }
}

const currentRevision = revisionOf;

/** Super-administrator chooses the response target (24/48/72 h). */
export const setInquirySla = onCall(async (request) => {
  const uid = requireUid(request);
  const admin = await requireSuperAdmin(uid);
  const hours = validated(() => parseSlaHours((request.data as {hours?: unknown})?.hours));
  const ref = db().collection("system_config").doc("inquiry_sla");
  await db().runTransaction(async (tx) => {
    const before = (await tx.get(ref)).data()?.hours ?? null;
    tx.set(ref, {hours, updatedBy: uid, updatedAt: FieldValue.serverTimestamp()});
    writeAudit(tx, db(), {
      actorId: uid, actorNameSnapshot: actorName(admin), actorRoleSnapshot: String(admin.accessRole),
      action: "INQUIRY_SLA_UPDATED", category: AUDIT_CATEGORIES.inquiries, targetType: "system_config", targetId: "inquiry_sla",
      metadata: {before, after: hours},
    });
  });
  return {ok: true, hours};
});

/**
 * An assignee or the super-administrator replies. The reply document ID is
 * the client's requestId, so a retried call returns the existing reply.
 */
export const replyToInquiry = onCall(async (request) => {
  const who = await inquiryActor(request);
  const inquiryId = inquiryIdFrom(request.data);
  const input = request.data as {message?: unknown; expectedRevision?: unknown; requestId?: unknown};
  const message = validated(() => replyMessage(input.message));
  const replyId = validated(() => requestIdFrom(input.requestId));
  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const replyRef = ref.collection("replies").doc(replyId);
  const nowTs = Timestamp.now();

  const outcome = await db().runTransaction(async (tx) => {
    const [current, currentProjection] = await Promise.all([tx.get(ref), tx.get(statusRef)]);
    if (!current.exists) throw new HttpsError("not-found", "Inquiry not found.");
    const data = current.data()!;
    if (!canHandleClinical(who, data)) {
      throw new HttpsError(
        "permission-denied",
        data.takeover
          ? "An administrator has taken over this inquiry."
          : "Only the counselor assigned to this inquiry or the super-administrator can post clinical replies.",
      );
    }
    const existing = await tx.get(replyRef);
    if (existing.exists) {
      // Retry of a committed reply: report it, change nothing.
      return {duplicate: true, revision: currentRevision(data), data, author: existing.data() as FirebaseFirestore.DocumentData};
    }
    const revision = currentRevision(data);
    if (input.expectedRevision !== revision) throw new HttpsError("failed-precondition", STALE);
    if (data.status === "resolved") throw new HttpsError("failed-precondition", "Resolved inquiries cannot receive new replies.");
    const nextStatus = data.status === "pending" ? "in_progress" : data.status;
    const nextOwnerId = data.ownerId ?? who.actor.uid;
    const prevResponseCount = Number.isInteger(data.responseCount) && Number(data.responseCount) >= 0 ? Number(data.responseCount) : 0;
    const nextResponseCount = prevResponseCount + 1;
    const author: FirebaseFirestore.DocumentData = {authorId: who.actor.uid, authorName: who.actor.name, authorRole: who.role};
    tx.create(replyRef, {message, ...author, createdAt: FieldValue.serverTimestamp()});
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
      actorId: who.actor.uid, actorNameSnapshot: who.actor.name, actorRoleSnapshot: who.role,
      action: "INQUIRY_RESPONDED", category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
      metadata: {replyId, length: message.length, revision: revision + 1, byAdministrator: who.isSuperAdmin},
    });
    return {duplicate: false, revision: revision + 1, data, author};
  });

  // Notifications are idempotent per reply, so a retry repairs, never duplicates.
  // Keep student push/notification previews generic so sensitive clinical reply text
  // stays inside the authorized `inquiries/{id}/replies` subcollection.
  const studentId = String(outcome.data.userId ?? "");
  const authorId = String(outcome.author.authorId ?? who.actor.uid);
  if (studentId) {
    await createOnce(`inquiry_reply_${inquiryId}_${replyId}`, {
      userId: studentId, inquiryId, type: "inquiry", title: "PACC replied to your inquiry",
      body: "A counselor replied to your inquiry. Open MindMate to read the reply.",
      createdAt: FieldValue.serverTimestamp(), readAt: null,
    });
  }
  const assignees = Array.isArray(outcome.data.assigneeIds) ? outcome.data.assigneeIds as string[] : [];
  const monitors = Array.isArray(outcome.data.monitoringStaffIds) ? outcome.data.monitoringStaffIds as string[] : [];
  const recipients = [...new Set([...assignees, ...monitors])];
  await Promise.all(recipients.filter((recipient) => recipient !== authorId).map((recipient) =>
    createOnce(`portal_inquiry_reply_${inquiryId}_${replyId}_${recipient}`,
      notification(recipient, inquiryId, "Reply posted", "A reply was posted on an inquiry assigned to you."))));
  return {ok: true, replyId, duplicate: outcome.duplicate, revision: outcome.revision};
});

/** Super-administrator takes over an unresolved inquiry; assignees are told. */
export const takeOverInquiry = onCall(async (request) => {
  const uid = requireUid(request);
  const admin = await requireSuperAdmin(uid);
  const actor: Actor = {uid, name: actorName(admin), role: String(admin.accessRole)};
  const inquiryId = inquiryIdFrom(request.data);
  const reason = reasonFrom(request.data);
  const expected = (request.data as {expectedRevision?: unknown})?.expectedRevision;
  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const nowTs = Timestamp.now();

  const outcome = await db().runTransaction(async (tx) => {
    const [current, currentProjection] = await Promise.all([tx.get(ref), tx.get(statusRef)]);
    if (!current.exists) throw new HttpsError("not-found", "Inquiry not found.");
    const data = current.data()!;
    const revision = currentRevision(data);
    if (expected !== revision) throw new HttpsError("failed-precondition", STALE);
    if (data.status === "resolved") throw new HttpsError("failed-precondition", "Resolved inquiries cannot be taken over.");
    if (data.takeover) throw new HttpsError("failed-precondition", "This inquiry is already taken over.");
    const escalation = data.escalation?.status === "requested"
      ? {...data.escalation, status: "handled", handledBy: uid, handledAt: FieldValue.serverTimestamp()}
      : data.escalation ?? null;
    const nextTakeover = {by: uid, byName: actor.name, reason, at: FieldValue.serverTimestamp()};
    tx.update(ref, {
      takeover: nextTakeover,
      ownerId: uid,
      escalation,
      routingRevision: revision + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const projection = buildInquiryStatusProjection(inquiryId, {
      ...data,
      takeover: {by: uid, byName: actor.name},
      ownerId: uid,
      escalation: escalation ? {status: escalation.status} : null,
      routingRevision: revision + 1,
      updatedAt: nowTs,
    });
    if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, projection)) {
      tx.set(statusRef, {...projection, projectedAt: FieldValue.serverTimestamp()});
    }
    writeAudit(tx, db(), {
      actorId: uid, actorNameSnapshot: actor.name, actorRoleSnapshot: actor.role,
      action: "INQUIRY_TAKEN_OVER", category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
      metadata: {reason, previousOwnerId: data.ownerId ?? null, assigneeIds: data.assigneeIds ?? [], revision: revision + 1},
    });
    const clinical = Array.isArray(data.assigneeIds) ? data.assigneeIds as string[] : [];
    const monitors = Array.isArray(data.monitoringStaffIds) ? data.monitoringStaffIds as string[] : [];
    return {revision: revision + 1, recipients: [...new Set([...clinical, ...monitors])]};
  });

  await Promise.all(outcome.recipients.map((recipient) =>
    createOnce(`portal_inquiry_takeover_${inquiryId}_${outcome.revision}_${recipient}`,
      notification(recipient, inquiryId, "Inquiry taken over", "An administrator took over an inquiry assigned to you."))));
  return {ok: true, revision: outcome.revision};
});
