import {getAuth} from "firebase-admin/auth";
import {FieldPath, FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {configuredSuperAdminUid, requireStaff, requireSuperAdmin, requireUid} from "./access";
import {actorName, AUDIT_CATEGORIES, writeAudit} from "./audit";
import {
  assigneeNotificationId,
  AuthState,
  buildInquiryStatusProjection,
  Candidate,
  decideRouting,
  escalationNotificationId,
  InquiryRoutingError,
  planReassignment,
  shouldWriteInquiryProjection,
  triageNotificationId,
} from "./inquiry_routing";

// Server-side routing, status projection, and workflow for student inquiries.
// Every transition updates both the canonical `inquiries/{id}` record and its
// sanitized `inquiry_statuses/{id}` projection in the same transaction alongside
// an audit record; notifications carry no inquiry content and use deterministic IDs.

type Actor = {uid: string; name: string; role: string};
const SYSTEM: Actor = {uid: "system", name: "Inquiry routing", role: "system"};
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const STATUSES = new Set(["pending", "in_progress", "resolved"]);
export const INQUIRY_STATUSES_COLLECTION = "inquiry_statuses";

const db = () => getFirestore();
const statusCollection = () => db().collection(INQUIRY_STATUSES_COLLECTION);

function superAdminUid(): string {
  try {
    return configuredSuperAdminUid();
  } catch {
    return "";
  }
}

function label(profile: FirebaseFirestore.DocumentData): string {
  const full = [profile.firstName, profile.lastName].filter((v) => typeof v === "string" && v.trim()).join(" ");
  return String(profile.name ?? "").trim() || full || "PACC staff";
}

async function authStates(uids: string[]): Promise<Map<string, AuthState>> {
  const states = new Map<string, AuthState>();
  for (let i = 0; i < uids.length; i += 100) {
    const result = await getAuth().getUsers(uids.slice(i, i + 100).map((uid) => ({uid})));
    for (const user of result.users) states.set(user.uid, {disabled: user.disabled, emailVerified: user.emailVerified});
  }
  return states;
}

function notification(recipient: string, inquiryId: string, title: string, body: string): Record<string, unknown> {
  return {
    userId: recipient, type: "inquiry", audience: "portal", title, body, inquiryId,
    createdAt: FieldValue.serverTimestamp(), readAt: null, resolvedAt: null,
    archiveEligibleAt: null, archivedAt: null, expiresAt: null,
  };
}

/** Create once; an existing document (retry) counts as delivered. */
async function createOnce(id: string, payload: Record<string, unknown>): Promise<void> {
  try {
    await db().collection("notifications").doc(id).create(payload);
  } catch (error: unknown) {
    const code = typeof error === "object" && error !== null && "code" in error ? String((error as {code?: unknown}).code) : "";
    if (code !== "6" && code !== "already-exists") throw error;
  }
}

/**
 * Make sure a recipient has an active notification with this ID. Creates it
 * when missing; when it exists but was archived (for example the recipient
 * was removed from an inquiry and later re-added), reactivates it as unread.
 * An already active notification is left untouched, so retries never
 * duplicate or reset it.
 */
export async function ensureActiveNotification(id: string, payload: Record<string, unknown>): Promise<void> {
  const ref = db().collection("notifications").doc(id);
  await db().runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (!current.exists) {
      tx.create(ref, {
        createdAt: FieldValue.serverTimestamp(), readAt: null, resolvedAt: null,
        archiveEligibleAt: null, archivedAt: null, expiresAt: null, ...payload,
      });
      return;
    }
    if (current.data()?.archivedAt == null) return;
    tx.update(ref, {
      ...payload,
      createdAt: FieldValue.serverTimestamp(),
      readAt: null,
      resolvedAt: null,
      archiveEligibleAt: null,
      archivedAt: null,
      expiresAt: null,
    });
  });
}

async function notifyRouting(inquiryId: string, data: FirebaseFirestore.DocumentData): Promise<void> {
  if (String(data.status ?? "") === "resolved") return;
  if (data.routingStatus === "routed") {
    const clinical = Array.isArray(data.assigneeIds) ? data.assigneeIds as string[] : [];
    const monitors = Array.isArray(data.monitoringStaffIds) ? data.monitoringStaffIds as string[] : [];
    const recipients = [...new Set([...clinical, ...monitors])];
    await Promise.all(recipients.map((uid) => createOnce(assigneeNotificationId(inquiryId, uid),
      notification(uid, inquiryId, "New inquiry", "A new inquiry for your college is ready for review."))));
    return;
  }
  const admin = superAdminUid();
  if (!admin) {
    console.warn("Inquiry needs triage but SUPER_ADMIN_UID is not configured.", inquiryId);
    return;
  }
  await createOnce(triageNotificationId(inquiryId),
    notification(admin, inquiryId, "Inquiry needs routing", "An inquiry could not be routed to a college and needs review."));
}

/**
 * Synchronizes `inquiry_statuses/{inquiryId}` from the live canonical inquiry
 * inside a transaction. Always re-reads the current `inquiries/{inquiryId}` doc
 * and rejects regressive `routingRevision` writes so delayed triggers never
 * restore revoked staff access.
 */
export async function syncInquiryStatusProjection(inquiryId: string): Promise<boolean> {
  if (!ID.test(inquiryId)) return false;
  const inquiryRef = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  return db().runTransaction(async (tx) => {
    const [inquirySnap, statusSnap] = await Promise.all([tx.get(inquiryRef), tx.get(statusRef)]);
    if (!inquirySnap.exists) {
      if (statusSnap.exists) {
        tx.delete(statusRef);
        return true;
      }
      return false;
    }
    const next = buildInquiryStatusProjection(inquiryId, inquirySnap.data() ?? {});
    if (!shouldWriteInquiryProjection(statusSnap.exists ? statusSnap.data() : null, next)) {
      return false;
    }
    tx.set(statusRef, {...next, projectedAt: FieldValue.serverTimestamp()});
    return true;
  });
}

/**
 * Route one inquiry. Idempotent: routing is written only when absent; every
 * call ensures both the sanitized projection and notifications are up to date.
 */
export async function routeInquiry(inquiryId: string, actor: Actor = SYSTEM): Promise<{routingStatus: string; assigneeIds: string[]; alreadyRouted: boolean}> {
  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const snapshot = await ref.get();
  if (!snapshot.exists) return {routingStatus: "missing", assigneeIds: [], alreadyRouted: false};
  let data = snapshot.data() ?? {};
  let alreadyRouted = data.routingStatus != null;

  if (!alreadyRouted) {
    const studentId = typeof data.userId === "string" && ID.test(data.userId) ? data.userId : "";
    const student = studentId ? await db().collection("users").doc(studentId).get() : null;
    const studentData = student?.exists ? student.data() ?? {} : null;
    const collegeId = typeof studentData?.collegeId === "string" ? studentData.collegeId.trim() : "";
    const collegeExists = ID.test(collegeId) ? (await db().collection("colleges").doc(collegeId).get()).exists : false;
    let candidates: Candidate[] = [];
    if (collegeExists && studentData?.verificationStatus === "verified") {
      // Automatic clinical routing uses active, verified counselors assigned
      // to the college (PR #63). Any legacy portalStaff still carrying
      // assignedCollegeIds are excluded by decideRouting.
      const assigned = await db().collection("users").where("assignedCollegeIds", "array-contains", collegeId).get();
      const auth = await authStates(assigned.docs.map((d) => d.id));
      candidates = assigned.docs.map((d) => ({uid: d.id, label: label(d.data()), profile: d.data(), auth: auth.get(d.id) ?? null}));
    }
    const decision = decideRouting({student: studentData, collegeExists, candidates});
    const nowTs = Timestamp.now();

    await db().runTransaction(async (tx) => {
      const [current, currentProjection] = await Promise.all([tx.get(ref), tx.get(statusRef)]);
      const live = current.data() ?? {};
      if (live.routingStatus != null) {
        alreadyRouted = true;
        const projection = buildInquiryStatusProjection(inquiryId, live);
        if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, projection)) {
          tx.set(statusRef, {...projection, projectedAt: FieldValue.serverTimestamp()});
        }
        return;
      }
      const updates = {
        ...decision,
        ownerId: null,
        routingMode: "automatic",
        routedAt: FieldValue.serverTimestamp(),
        routingRevision: 1,
        escalation: null,
      };
      tx.update(ref, updates);
      const nextProjection = buildInquiryStatusProjection(inquiryId, {
        ...live,
        ...decision,
        ownerId: null,
        routingMode: "automatic",
        routedAt: nowTs,
        routingRevision: 1,
        escalation: null,
      });
      if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, nextProjection)) {
        tx.set(statusRef, {...nextProjection, projectedAt: FieldValue.serverTimestamp()});
      }
      writeAudit(tx, db(), {
        actorId: actor.uid, actorNameSnapshot: actor.name, actorRoleSnapshot: actor.role,
        action: "INQUIRY_ROUTED", category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
        metadata: {routingStatus: decision.routingStatus, routingReason: decision.routingReason, collegeId: decision.collegeId, assigneeIds: decision.assigneeIds},
      });
    });
    data = (await ref.get()).data() ?? {};
  } else {
    await syncInquiryStatusProjection(inquiryId);
  }
  await notifyRouting(inquiryId, data);
  return {routingStatus: String(data.routingStatus), assigneeIds: (data.assigneeIds as string[] | undefined) ?? [], alreadyRouted};
}

/** Assignee (clinical counselor or operational monitor) or configured super-administrator. */
async function inquiryActor(request: {auth?: {uid: string} | null}): Promise<{actor: Actor; isSuperAdmin: boolean; role: string}> {
  const uid = requireUid(request);
  const profile = await requireStaff(uid);
  const role = String(profile.accessRole);
  return {actor: {uid, name: actorName(profile), role}, isSuperAdmin: role === "admin" && uid === superAdminUid(), role};
}

/** Clinical handling/ownership (`assigneeIds` counselor or super-admin). */
function canHandleClinical(who: {actor: Actor; isSuperAdmin: boolean; role: string}, inquiry: FirebaseFirestore.DocumentData): boolean {
  if (who.isSuperAdmin) return true;
  return who.role === "counselor" &&
    Array.isArray(inquiry.assigneeIds) && inquiry.assigneeIds.includes(who.actor.uid);
}

/** Operational monitoring + acknowledgment/escalation (`monitoringStaffIds` portalStaff, or clinical handler). */
function canOperateOnInquiry(who: {actor: Actor; isSuperAdmin: boolean; role: string}, inquiry: FirebaseFirestore.DocumentData): boolean {
  if (canHandleClinical(who, inquiry)) return true;
  return who.role === "portalStaff" &&
    Array.isArray(inquiry.monitoringStaffIds) && inquiry.monitoringStaffIds.includes(who.actor.uid);
}

function inquiryIdFrom(data: unknown): string {
  const id = typeof (data as {inquiryId?: unknown})?.inquiryId === "string" ? (data as {inquiryId: string}).inquiryId.trim() : "";
  if (!ID.test(id)) throw new HttpsError("invalid-argument", "Inquiry ID is required.");
  return id;
}

function reasonFrom(data: unknown): string {
  const text = typeof (data as {reason?: unknown})?.reason === "string" ? (data as {reason: string}).reason.trim() : "";
  if (text.length < 3 || text.length > 500) throw new HttpsError("invalid-argument", "Reason must be 3-500 characters.");
  return text;
}

const DENIED = "Only the staff assigned to this inquiry or the super-administrator can do this.";

export const acknowledgeInquiry = onCall(async (request) => {
  const who = await inquiryActor(request);
  const inquiryId = inquiryIdFrom(request.data);
  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const nowTs = Timestamp.now();
  await db().runTransaction(async (tx) => {
    const [current, currentProjection] = await Promise.all([tx.get(ref), tx.get(statusRef)]);
    if (!current.exists) throw new HttpsError("not-found", "Inquiry not found.");
    const data = current.data()!;
    if (!canOperateOnInquiry(who, data)) throw new HttpsError("permission-denied", DENIED);
    if (String(data.status ?? "pending").toLowerCase() === "resolved") {
      throw new HttpsError("failed-precondition", "Resolved inquiries cannot be acknowledged.");
    }
    if (data.acknowledgedAt) throw new HttpsError("failed-precondition", "A receipt notification was already sent.");
    const userId = String(data.userId ?? "");
    if (!userId) throw new HttpsError("failed-precondition", "Inquiry has no sender.");
    // Only clinical counselors or the super-admin claim inquiry `ownerId`;
    // operational monitors acknowledge receipt without gaining counselor ownership.
    const nextOwnerId = who.role === "portalStaff" ? (data.ownerId ?? null) : (data.ownerId ?? who.actor.uid);
    tx.update(ref, {
      status: "in_progress",
      acknowledgedAt: FieldValue.serverTimestamp(),
      acknowledgedBy: who.actor.uid,
      ownerId: nextOwnerId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const projection = buildInquiryStatusProjection(inquiryId, {
      ...data,
      status: "in_progress",
      acknowledgedAt: nowTs,
      ownerId: nextOwnerId,
      updatedAt: nowTs,
    });
    if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, projection)) {
      tx.set(statusRef, {...projection, projectedAt: FieldValue.serverTimestamp()});
    }
    tx.create(db().collection("notifications").doc(), {
      userId, inquiryId, type: "inquiry", title: "Form received",
      body: `PACC received your ${String(data.subject ?? "form")}. Our staff will review it.`,
      staffName: who.actor.name || "PACC staff", createdAt: FieldValue.serverTimestamp(), readAt: null,
    });
    writeAudit(tx, db(), {
      actorId: who.actor.uid, actorNameSnapshot: who.actor.name, actorRoleSnapshot: who.role,
      action: "INQUIRY_ACKNOWLEDGED", category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
      metadata: {before: String(data.status ?? "pending"), after: "in_progress", ownerId: nextOwnerId},
    });
  });
  return {ok: true};
});

export const setInquiryStatus = onCall(async (request) => {
  const who = await inquiryActor(request);
  const inquiryId = inquiryIdFrom(request.data);
  const status = String((request.data as {status?: unknown})?.status ?? "");
  if (!STATUSES.has(status)) throw new HttpsError("invalid-argument", "Choose pending, in progress or resolved.");
  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const nowTs = Timestamp.now();
  return db().runTransaction(async (tx) => {
    const [current, currentProjection] = await Promise.all([tx.get(ref), tx.get(statusRef)]);
    if (!current.exists) throw new HttpsError("not-found", "Inquiry not found.");
    const data = current.data()!;
    if (!canHandleClinical(who, data)) {
      throw new HttpsError("permission-denied", "Only the counselor assigned to this inquiry or the super-administrator can change clinical inquiry status.");
    }
    const before = String(data.status ?? "pending");
    if (before === status) return {ok: true, changed: false};
    tx.update(ref, {
      status,
      updatedAt: FieldValue.serverTimestamp(),
      resolvedAt: status === "resolved" ? FieldValue.serverTimestamp() : null,
      resolvedBy: status === "resolved" ? who.actor.uid : null,
    });
    const projection = buildInquiryStatusProjection(inquiryId, {
      ...data,
      status,
      updatedAt: nowTs,
      resolvedAt: status === "resolved" ? nowTs : null,
    });
    if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, projection)) {
      tx.set(statusRef, {...projection, projectedAt: FieldValue.serverTimestamp()});
    }
    writeAudit(tx, db(), {
      actorId: who.actor.uid, actorNameSnapshot: who.actor.name, actorRoleSnapshot: who.role,
      action: status === "resolved" ? "INQUIRY_RESOLVED" : "INQUIRY_STATUS_CHANGED",
      category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
      metadata: {before, after: status},
    });
    return {ok: true, changed: true};
  });
});

export const escalateInquiry = onCall(async (request) => {
  const who = await inquiryActor(request);
  const inquiryId = inquiryIdFrom(request.data);
  const reason = reasonFrom(request.data);
  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const admin = superAdminUid();
  if (!admin) throw new HttpsError("failed-precondition", "No escalation recipient is configured.");
  const nowTs = Timestamp.now();
  const revision = await db().runTransaction(async (tx) => {
    const [current, currentProjection] = await Promise.all([tx.get(ref), tx.get(statusRef)]);
    if (!current.exists) throw new HttpsError("not-found", "Inquiry not found.");
    const data = current.data()!;
    // Escalation is an assigned handler's or monitoring staff member's request for administrator review.
    if (who.isSuperAdmin || !canOperateOnInquiry(who, data)) {
      throw new HttpsError("permission-denied", "Only staff assigned to this inquiry can escalate it.");
    }
    if (data.status === "resolved") throw new HttpsError("failed-precondition", "Resolved inquiries cannot be escalated.");
    if (data.escalation?.status === "requested") throw new HttpsError("failed-precondition", "This inquiry is already escalated.");
    const nextEscalation = {status: "requested", reason, requestedBy: who.actor.uid, requestedAt: FieldValue.serverTimestamp()};
    tx.update(ref, {
      escalation: nextEscalation,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const projection = buildInquiryStatusProjection(inquiryId, {
      ...data,
      escalation: {status: "requested"},
      updatedAt: nowTs,
    });
    if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, projection)) {
      tx.set(statusRef, {...projection, projectedAt: FieldValue.serverTimestamp()});
    }
    writeAudit(tx, db(), {
      actorId: who.actor.uid, actorNameSnapshot: who.actor.name, actorRoleSnapshot: who.role,
      action: "INQUIRY_ESCALATED", category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
      metadata: {reason, recipient: admin},
    });
    return Number(data.routingRevision ?? 0);
  });
  await createOnce(escalationNotificationId(inquiryId, revision),
    notification(admin, inquiryId, "Inquiry escalated", "An assigned inquiry was escalated for administrator review."));
  return {ok: true};
});

export const reassignInquiry = onCall(async (request) => {
  const uid = requireUid(request);
  const admin = await requireSuperAdmin(uid);
  const actor: Actor = {uid, name: actorName(admin), role: String(admin.accessRole)};
  const inquiryId = inquiryIdFrom(request.data);
  const reason = reasonFrom(request.data);
  const input = request.data as {assigneeIds?: unknown; monitoringStaffIds?: unknown; expectedRevision?: unknown};
  const requestedClinical = Array.isArray(input.assigneeIds)
    ? input.assigneeIds.filter((id): id is string => typeof id === "string" && ID.test(id))
    : [];
  const requestedMonitors = Array.isArray(input.monitoringStaffIds)
    ? input.monitoringStaffIds.filter((id): id is string => typeof id === "string" && ID.test(id))
    : [];
  const unique = [...new Set([...requestedClinical, ...requestedMonitors])].slice(0, 22);
  const profiles = unique.length > 0 ? await db().getAll(...unique.map((id) => db().collection("users").doc(id))) : [];
  const auth = await authStates(profiles.filter((p) => p.exists).map((p) => p.id));
  const candidates = new Map(profiles.filter((p) => p.exists).map((p) => [p.id, {label: label(p.data() ?? {}), profile: p.data() ?? {}, auth: auth.get(p.id) ?? null}]));
  const ref = db().collection("inquiries").doc(inquiryId);
  const statusRef = statusCollection().doc(inquiryId);
  const nowTs = Timestamp.now();

  const outcome = await db().runTransaction(async (tx) => {
    const [current, currentProjection] = await Promise.all([tx.get(ref), tx.get(statusRef)]);
    if (!current.exists) throw new HttpsError("not-found", "Inquiry not found.");
    const data = current.data()!;
    let plan;
    try {
      plan = planReassignment({
        inquiry: data,
        requested: input.assigneeIds,
        requestedMonitoring: input.monitoringStaffIds,
        candidates,
        expectedRevision: input.expectedRevision,
      });
    } catch (error) {
      if (error instanceof InquiryRoutingError) {
        throw new HttpsError(error.code === "invalid-assignees" ? "invalid-argument" : "failed-precondition", error.message, {reason: error.code});
      }
      throw error;
    }
    const escalation = data.escalation?.status === "requested"
      ? {...data.escalation, status: "handled", handledBy: uid, handledAt: FieldValue.serverTimestamp()}
      : data.escalation ?? null;
    const updates = {
      routingStatus: "routed",
      routingReason: null,
      routingMode: "manual",
      assigneeIds: plan.assigneeIds,
      assigneeLabels: plan.assigneeLabels,
      monitoringStaffIds: plan.monitoringStaffIds,
      monitoringStaffLabels: plan.monitoringStaffLabels,
      ownerId: plan.ownerId,
      routingRevision: plan.revision,
      routedAt: FieldValue.serverTimestamp(),
      escalation,
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.update(ref, updates);
    const projection = buildInquiryStatusProjection(inquiryId, {
      ...data,
      ...updates,
      routedAt: nowTs,
      updatedAt: nowTs,
    });
    if (shouldWriteInquiryProjection(currentProjection.exists ? currentProjection.data() : null, projection)) {
      tx.set(statusRef, {...projection, projectedAt: FieldValue.serverTimestamp()});
    }
    writeAudit(tx, db(), {
      actorId: actor.uid, actorNameSnapshot: actor.name, actorRoleSnapshot: actor.role,
      action: "INQUIRY_REASSIGNED", category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
      metadata: {
        before: data.assigneeIds ?? [],
        after: plan.assigneeIds,
        beforeMonitors: data.monitoringStaffIds ?? [],
        afterMonitors: plan.monitoringStaffIds,
        added: plan.added,
        removed: plan.removed,
        outOfCollege: plan.outOfCollege,
        collegeId: data.collegeId ?? "",
        revision: plan.revision,
        reason,
      },
    });
    return {plan, status: String(data.status ?? "pending")};
  });

  const now = FieldValue.serverTimestamp();
  await Promise.all(outcome.plan.removed.map(async (removed) => {
    const note = db().collection("notifications").doc(assigneeNotificationId(inquiryId, removed));
    const existing = await note.get();
    if (existing.exists && !existing.data()?.archivedAt) await note.update({archivedAt: now, resolvedAt: now, archiveEligibleAt: null});
  }));
  if (outcome.status !== "resolved") {
    // A re-added assignee may still hold an archived notification under the
    // same deterministic ID; reactivate it instead of treating it as sent.
    await Promise.all(outcome.plan.added.map((added) => ensureActiveNotification(assigneeNotificationId(inquiryId, added), {
      userId: added, type: "inquiry", audience: "portal", inquiryId,
      title: "Inquiry assigned to you", body: "An inquiry was assigned to you for review.",
    })));
  }
  return {ok: true, revision: outcome.plan.revision};
});

export type BackfillOptions = {limit?: number; cursor?: string | null; pageSize?: number; maxPages?: number};
export type BackfillResult = {routed: number; needsTriage: number; projectionsSynced: number; scanned: number; nextCursor: string | null; done: boolean};

/**
 * Route inquiries that predate college routing (and backfill any missing
 * `inquiry_statuses` projections for previously routed inquiries), in
 * document-ID order. Bounded and resumable via `nextCursor`.
 */
export async function routeExistingInquiriesBatch(actor: Actor, options: BackfillOptions = {}): Promise<BackfillResult> {
  const limit = Math.min(Math.max(Math.trunc(options.limit ?? 50), 1), 100);
  const pageSize = Math.min(Math.max(Math.trunc(options.pageSize ?? 500), 1), 500);
  const maxPages = Math.min(Math.max(Math.trunc(options.maxPages ?? 10), 1), 20);
  let cursor = options.cursor ?? null;
  let routed = 0;
  let needsTriage = 0;
  let projectionsSynced = 0;
  let scanned = 0;
  for (let page = 0; page < maxPages; page++) {
    let query = db().collection("inquiries").orderBy(FieldPath.documentId()).limit(pageSize);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) return {routed, needsTriage, projectionsSynced, scanned, nextCursor: null, done: true};
    const projectionRefs = snapshot.docs.map((docSnap) => statusCollection().doc(docSnap.id));
    const projectionSnaps = projectionRefs.length > 0 ? await db().getAll(...projectionRefs) : [];
    const hasProjection = new Map(projectionSnaps.map((snap) => [snap.id, snap.exists]));
    for (const inquiry of snapshot.docs) {
      scanned += 1;
      cursor = inquiry.id;
      if (inquiry.data().routingStatus != null) {
        if (!hasProjection.get(inquiry.id)) {
          if (await syncInquiryStatusProjection(inquiry.id)) projectionsSynced += 1;
        }
        continue;
      }
      const result = await routeInquiry(inquiry.id, actor);
      if (!result.alreadyRouted) {
        routed += 1;
        if (result.routingStatus === "needs_triage") needsTriage += 1;
      }
      if (routed >= limit) return {routed, needsTriage, projectionsSynced, scanned, nextCursor: cursor, done: false};
    }
    if (snapshot.size < pageSize) return {routed, needsTriage, projectionsSynced, scanned, nextCursor: null, done: true};
  }
  return {routed, needsTriage, projectionsSynced, scanned, nextCursor: cursor, done: false};
}

export const routeExistingInquiries = onCall(async (request) => {
  const uid = requireUid(request);
  const admin = await requireSuperAdmin(uid);
  const actor: Actor = {uid, name: actorName(admin), role: String(admin.accessRole)};
  const data = (request.data ?? {}) as {limit?: unknown; cursor?: unknown};
  const rawLimit = Number(data.limit ?? 50);
  const cursor = data.cursor == null || data.cursor === "" ? null : String(data.cursor);
  if (cursor !== null && !ID.test(cursor)) throw new HttpsError("invalid-argument", "Invalid continuation cursor.");
  const result = await routeExistingInquiriesBatch(actor, {limit: Number.isInteger(rawLimit) ? rawLimit : 50, cursor});
  return {ok: true, ...result};
});
