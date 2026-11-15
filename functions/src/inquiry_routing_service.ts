import {getAuth} from "firebase-admin/auth";
import {FieldPath, FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {configuredSuperAdminUid, requireStaff, requireSuperAdmin, requireUid} from "./access";
import {actorName, AUDIT_CATEGORIES, writeAudit} from "./audit";
import {
  assigneeNotificationId,
  AuthState,
  Candidate,
  decideRouting,
  escalationNotificationId,
  InquiryRoutingError,
  planReassignment,
  triageNotificationId,
} from "./inquiry_routing";

// Server-side routing and workflow for student inquiries. Every transition is
// a transaction with an audit record; notifications carry no inquiry content
// and use deterministic IDs so retries never duplicate them.

export type Actor = {uid: string; name: string; role: string};
const SYSTEM: Actor = {uid: "system", name: "Inquiry routing", role: "system"};
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const STATUSES = new Set(["pending", "in_progress", "resolved"]);

const db = () => getFirestore();

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

export function notification(recipient: string, inquiryId: string, title: string, body: string): Record<string, unknown> {
  return {
    userId: recipient, type: "inquiry", audience: "portal", title, body, inquiryId,
    createdAt: FieldValue.serverTimestamp(), readAt: null, resolvedAt: null,
    archiveEligibleAt: null, archivedAt: null, expiresAt: null,
  };
}

/** Create once; an existing document (retry) counts as delivered. */
export async function createOnce(id: string, payload: Record<string, unknown>): Promise<void> {
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
    const assignees = Array.isArray(data.assigneeIds) ? data.assigneeIds as string[] : [];
    await Promise.all(assignees.map((uid) => createOnce(assigneeNotificationId(inquiryId, uid),
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
 * Route one inquiry. Idempotent: routing is written only when absent; every
 * call (re)ensures the notifications for the stored routing.
 */
export async function routeInquiry(inquiryId: string, actor: Actor = SYSTEM): Promise<{routingStatus: string; assigneeIds: string[]; alreadyRouted: boolean}> {
  const ref = db().collection("inquiries").doc(inquiryId);
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
      const assigned = await db().collection("users").where("assignedCollegeIds", "array-contains", collegeId).get();
      const auth = await authStates(assigned.docs.map((d) => d.id));
      candidates = assigned.docs.map((d) => ({uid: d.id, label: label(d.data()), profile: d.data(), auth: auth.get(d.id) ?? null}));
    }
    const decision = decideRouting({student: studentData, collegeExists, candidates});

    await db().runTransaction(async (tx) => {
      const current = await tx.get(ref);
      const live = current.data() ?? {};
      if (live.routingStatus != null) {
        alreadyRouted = true;
        return;
      }
      tx.update(ref, {
        ...decision,
        ownerId: null,
        routingMode: "automatic",
        routedAt: FieldValue.serverTimestamp(),
        routingRevision: 1,
        escalation: null,
      });
      writeAudit(tx, db(), {
        actorId: actor.uid, actorNameSnapshot: actor.name, actorRoleSnapshot: actor.role,
        action: "INQUIRY_ROUTED", category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
        metadata: {routingStatus: decision.routingStatus, routingReason: decision.routingReason, collegeId: decision.collegeId, assigneeIds: decision.assigneeIds},
      });
    });
    data = (await ref.get()).data() ?? {};
  }
  await notifyRouting(inquiryId, data);
  return {routingStatus: String(data.routingStatus), assigneeIds: (data.assigneeIds as string[] | undefined) ?? [], alreadyRouted};
}

/** Assignee (staff/counselor) or the configured super-administrator. */
export async function inquiryActor(request: {auth?: {uid: string} | null}): Promise<{actor: Actor; isSuperAdmin: boolean; role: string}> {
  const uid = requireUid(request);
  const profile = await requireStaff(uid);
  const role = String(profile.accessRole);
  return {actor: {uid, name: actorName(profile), role}, isSuperAdmin: role === "admin" && uid === superAdminUid(), role};
}

export function canHandle(who: {actor: Actor; isSuperAdmin: boolean; role: string}, inquiry: FirebaseFirestore.DocumentData): boolean {
  if (who.isSuperAdmin) return true;
  // After a super-admin takeover the assignees keep read access but can no
  // longer act until the inquiry is reassigned.
  if (inquiry.takeover) return false;
  return (who.role === "portalStaff" || who.role === "counselor") &&
    Array.isArray(inquiry.assigneeIds) && inquiry.assigneeIds.includes(who.actor.uid);
}

export function inquiryIdFrom(data: unknown): string {
  const id = typeof (data as {inquiryId?: unknown})?.inquiryId === "string" ? (data as {inquiryId: string}).inquiryId.trim() : "";
  if (!ID.test(id)) throw new HttpsError("invalid-argument", "Inquiry ID is required.");
  return id;
}

export function reasonFrom(data: unknown): string {
  const text = typeof (data as {reason?: unknown})?.reason === "string" ? (data as {reason: string}).reason.trim() : "";
  if (text.length < 3 || text.length > 500) throw new HttpsError("invalid-argument", "Reason must be 3-500 characters.");
  return text;
}

export const STALE_REVISION = "This inquiry was updated by someone else. Reload and try again.";

/**
 * Optimistic-concurrency policy for inquiry workflow actions. Every mutation
 * (acknowledge, status, escalate, reply, takeover, reassign) advances
 * `routingRevision`.
 * - A supplied `expectedRevision` is always enforced.
 * - Acknowledge, status and escalate also accept an omitted revision, because
 *   PR #4 web clients do not send one; such calls are served and audited as
 *   `revisionChecked: false`. Setting INQUIRY_REQUIRE_EXPECTED_REVISION=true
 *   (after every client sends revisions) makes the revision mandatory.
 * - Reply and takeover always require it.
 */
export function checkExpectedRevision(expected: unknown, revision: number): {revisionChecked: boolean} {
  if (expected === undefined || expected === null) {
    if ((process.env.INQUIRY_REQUIRE_EXPECTED_REVISION ?? "").trim().toLowerCase() === "true") {
      throw new HttpsError("invalid-argument", "expectedRevision is required.");
    }
    return {revisionChecked: false};
  }
  if (!Number.isInteger(expected)) throw new HttpsError("invalid-argument", "expectedRevision must be an integer.");
  if (expected !== revision) throw new HttpsError("failed-precondition", STALE_REVISION);
  return {revisionChecked: true};
}

export function revisionOf(data: FirebaseFirestore.DocumentData): number {
  return Number.isInteger(data.routingRevision) ? Number(data.routingRevision) : 0;
}

export const DENIED = "Only the staff assigned to this inquiry or the super-administrator can do this.";

export const acknowledgeInquiry = onCall(async (request) => {
  const who = await inquiryActor(request);
  const inquiryId = inquiryIdFrom(request.data);
  const ref = db().collection("inquiries").doc(inquiryId);
  await db().runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (!current.exists) throw new HttpsError("not-found", "Inquiry not found.");
    const data = current.data()!;
    if (!canHandle(who, data)) throw new HttpsError("permission-denied", DENIED);
    const revision = revisionOf(data);
    const {revisionChecked} = checkExpectedRevision((request.data as {expectedRevision?: unknown})?.expectedRevision, revision);
    if (data.acknowledgedAt) throw new HttpsError("failed-precondition", "A receipt notification was already sent.");
    const userId = String(data.userId ?? "");
    if (!userId) throw new HttpsError("failed-precondition", "Inquiry has no sender.");
    tx.update(ref, {
      status: "in_progress",
      acknowledgedAt: FieldValue.serverTimestamp(),
      acknowledgedBy: who.actor.uid,
      ownerId: data.ownerId ?? who.actor.uid,
      routingRevision: revision + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db().collection("notifications").doc(), {
      userId, inquiryId, type: "inquiry", title: "Form received",
      body: `PACC received your ${String(data.subject ?? "form")}. Our staff will review it.`,
      staffName: who.actor.name || "PACC staff", createdAt: FieldValue.serverTimestamp(), readAt: null,
    });
    writeAudit(tx, db(), {
      actorId: who.actor.uid, actorNameSnapshot: who.actor.name, actorRoleSnapshot: who.role,
      action: "INQUIRY_ACKNOWLEDGED", category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
      metadata: {before: String(data.status ?? "pending"), after: "in_progress", ownerId: data.ownerId ?? who.actor.uid,
        revision: revision + 1, revisionChecked},
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
  return db().runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (!current.exists) throw new HttpsError("not-found", "Inquiry not found.");
    const data = current.data()!;
    if (!canHandle(who, data)) throw new HttpsError("permission-denied", DENIED);
    const revision = revisionOf(data);
    const {revisionChecked} = checkExpectedRevision((request.data as {expectedRevision?: unknown})?.expectedRevision, revision);
    const before = String(data.status ?? "pending");
    if (before === status) return {ok: true, changed: false, revision};
    tx.update(ref, {
      status,
      routingRevision: revision + 1,
      updatedAt: FieldValue.serverTimestamp(),
      resolvedAt: status === "resolved" ? FieldValue.serverTimestamp() : null,
      resolvedBy: status === "resolved" ? who.actor.uid : null,
    });
    writeAudit(tx, db(), {
      actorId: who.actor.uid, actorNameSnapshot: who.actor.name, actorRoleSnapshot: who.role,
      action: status === "resolved" ? "INQUIRY_RESOLVED" : "INQUIRY_STATUS_CHANGED",
      category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
      metadata: {before, after: status, revision: revision + 1, revisionChecked},
    });
    return {ok: true, changed: true, revision: revision + 1};
  });
});

export const escalateInquiry = onCall(async (request) => {
  const who = await inquiryActor(request);
  const inquiryId = inquiryIdFrom(request.data);
  const reason = reasonFrom(request.data);
  const ref = db().collection("inquiries").doc(inquiryId);
  const admin = superAdminUid();
  if (!admin) throw new HttpsError("failed-precondition", "No escalation recipient is configured.");
  const revision = await db().runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (!current.exists) throw new HttpsError("not-found", "Inquiry not found.");
    const data = current.data()!;
    // Escalation is an assignee's request for administrator review.
    if (who.isSuperAdmin || !canHandle(who, data)) throw new HttpsError("permission-denied", "Only staff assigned to this inquiry can escalate it.");
    if (data.status === "resolved") throw new HttpsError("failed-precondition", "Resolved inquiries cannot be escalated.");
    const revision = revisionOf(data);
    const {revisionChecked} = checkExpectedRevision((request.data as {expectedRevision?: unknown})?.expectedRevision, revision);
    if (data.escalation?.status === "requested") throw new HttpsError("failed-precondition", "This inquiry is already escalated.");
    tx.update(ref, {
      escalation: {status: "requested", reason, requestedBy: who.actor.uid, requestedAt: FieldValue.serverTimestamp()},
      routingRevision: revision + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    writeAudit(tx, db(), {
      actorId: who.actor.uid, actorNameSnapshot: who.actor.name, actorRoleSnapshot: who.role,
      action: "INQUIRY_ESCALATED", category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
      metadata: {reason, recipient: admin, revision: revision + 1, revisionChecked},
    });
    return revision;
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
  const input = request.data as {assigneeIds?: unknown; expectedRevision?: unknown};
  const requested = Array.isArray(input.assigneeIds) ? input.assigneeIds.filter((id): id is string => typeof id === "string" && ID.test(id)) : [];
  const unique = [...new Set(requested)].slice(0, 11);
  const profiles = unique.length > 0 ? await db().getAll(...unique.map((id) => db().collection("users").doc(id))) : [];
  const auth = await authStates(profiles.filter((p) => p.exists).map((p) => p.id));
  const candidates = new Map(profiles.filter((p) => p.exists).map((p) => [p.id, {label: label(p.data() ?? {}), profile: p.data() ?? {}, auth: auth.get(p.id) ?? null}]));
  const ref = db().collection("inquiries").doc(inquiryId);

  const outcome = await db().runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (!current.exists) throw new HttpsError("not-found", "Inquiry not found.");
    const data = current.data()!;
    let plan;
    try {
      plan = planReassignment({inquiry: data, requested: input.assigneeIds, candidates, expectedRevision: input.expectedRevision});
    } catch (error) {
      if (error instanceof InquiryRoutingError) {
        throw new HttpsError(error.code === "invalid-assignees" ? "invalid-argument" : "failed-precondition", error.message, {reason: error.code});
      }
      throw error;
    }
    const escalation = data.escalation?.status === "requested"
      ? {...data.escalation, status: "handled", handledBy: uid, handledAt: FieldValue.serverTimestamp()}
      : data.escalation ?? null;
    tx.update(ref, {
      routingStatus: "routed",
      routingReason: null,
      routingMode: "manual",
      assigneeIds: plan.assigneeIds,
      assigneeLabels: plan.assigneeLabels,
      ownerId: plan.ownerId,
      routingRevision: plan.revision,
      routedAt: FieldValue.serverTimestamp(),
      escalation,
      takeover: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    writeAudit(tx, db(), {
      actorId: actor.uid, actorNameSnapshot: actor.name, actorRoleSnapshot: actor.role,
      action: "INQUIRY_REASSIGNED", category: AUDIT_CATEGORIES.inquiries, targetType: "inquiry", targetId: inquiryId,
      metadata: {before: data.assigneeIds ?? [], after: plan.assigneeIds, added: plan.added, removed: plan.removed,
        outOfCollege: plan.outOfCollege, collegeId: data.collegeId ?? "", revision: plan.revision, reason},
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
export type BackfillResult = {routed: number; needsTriage: number; scanned: number; nextCursor: string | null; done: boolean};

/**
 * Route inquiries that predate college routing, in document-ID order.
 * Bounded per call (at most `maxPages * pageSize` documents read and `limit`
 * inquiries routed) and resumable: pass the returned `nextCursor` until
 * `done`. Routed inquiries are skipped server-side page by page, so records
 * beyond any number of already-routed ones are still reached.
 */
export async function routeExistingInquiriesBatch(actor: Actor, options: BackfillOptions = {}): Promise<BackfillResult> {
  const limit = Math.min(Math.max(Math.trunc(options.limit ?? 50), 1), 100);
  const pageSize = Math.min(Math.max(Math.trunc(options.pageSize ?? 500), 1), 500);
  const maxPages = Math.min(Math.max(Math.trunc(options.maxPages ?? 10), 1), 20);
  let cursor = options.cursor ?? null;
  let routed = 0;
  let needsTriage = 0;
  let scanned = 0;
  for (let page = 0; page < maxPages; page++) {
    let query = db().collection("inquiries").orderBy(FieldPath.documentId()).limit(pageSize);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) return {routed, needsTriage, scanned, nextCursor: null, done: true};
    for (const inquiry of snapshot.docs) {
      scanned += 1;
      cursor = inquiry.id;
      if (inquiry.data().routingStatus != null) continue;
      const result = await routeInquiry(inquiry.id, actor);
      if (!result.alreadyRouted) {
        routed += 1;
        if (result.routingStatus === "needs_triage") needsTriage += 1;
      }
      if (routed >= limit) return {routed, needsTriage, scanned, nextCursor: cursor, done: false};
    }
    if (snapshot.size < pageSize) return {routed, needsTriage, scanned, nextCursor: null, done: true};
  }
  return {routed, needsTriage, scanned, nextCursor: cursor, done: false};
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
