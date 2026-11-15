import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireSuperAdmin, requireUid} from "./access";
import {actorName, AUDIT_CATEGORIES, writeAudit} from "./audit";
import {CollegeAssignmentError, MAX_ASSIGNED_COLLEGES, planCollegeAssignmentChange} from "./college_assignments";

const USER_ID = /^[A-Za-z0-9_-]{1,128}$/;
const COLLEGE_ID = /^[A-Za-z0-9_-]{1,128}$/;

function reasonText(value: unknown): string {
  const text = typeof value === "string" ? value.trim() : "";
  if (text.length < 3 || text.length > 500) throw new HttpsError("invalid-argument", "Reason must be 3-500 characters.");
  return text;
}

/**
 * Super-administrator assigns the colleges a PACC staff member or counselor
 * serves. Writes users/{uid}.assignedCollegeIds with optimistic concurrency
 * (`expectedRevision`) and an audit record. Clients can never write these
 * fields directly: firestore.rules only permits allow-listed self-updates.
 */
export const setStaffCollegeAssignments = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireSuperAdmin(actorId);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const userId = typeof data.userId === "string" ? data.userId.trim() : "";
  if (!USER_ID.test(userId)) throw new HttpsError("invalid-argument", "A staff user ID is required.");
  const reason = reasonText(data.reason);
  const requested = data.collegeIds;
  if (!Array.isArray(requested) || requested.length > MAX_ASSIGNED_COLLEGES * 2 ||
      requested.some((id) => typeof id !== "string" || !COLLEGE_ID.test(id))) {
    throw new HttpsError("invalid-argument", "Provide a list of valid college IDs.");
  }
  const db = getFirestore();
  const target = db.collection("users").doc(userId);

  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(target);
    const profile = snapshot.exists ? snapshot.data() ?? {} : null;
    const lookup = [...new Set([...(requested as string[]), ...((profile?.assignedCollegeIds as unknown[] | undefined) ?? []).filter((id): id is string => typeof id === "string" && COLLEGE_ID.test(id))])];
    const collegeDocs = lookup.length > 0 ? await tx.getAll(...lookup.map((id) => db.collection("colleges").doc(id))) : [];
    const colleges = new Map(collegeDocs.filter((d) => d.exists).map((d) => [d.id, {active: d.data()?.active === true}]));

    let plan;
    try {
      plan = planCollegeAssignmentChange({target: profile, requested, colleges, expectedRevision: data.expectedRevision});
    } catch (error) {
      if (error instanceof CollegeAssignmentError) {
        throw new HttpsError(error.code === "invalid-id" || error.code === "too-many" ? "invalid-argument" : "failed-precondition", error.message, {reason: error.code});
      }
      throw error;
    }
    if (!plan.changed) return {ok: true, revision: plan.revision, collegeIds: plan.next};

    const revision = plan.revision + 1;
    tx.update(target, {
      assignedCollegeIds: plan.next,
      collegeAssignmentRevision: revision,
      collegeAssignmentUpdatedBy: actorId,
      collegeAssignmentUpdatedAt: FieldValue.serverTimestamp(),
    });
    writeAudit(tx, db, {
      actorId,
      actorNameSnapshot: actorName(actor),
      actorRoleSnapshot: String(actor.accessRole),
      action: "STAFF_COLLEGE_ASSIGNMENTS_UPDATED",
      category: AUDIT_CATEGORIES.userManagement,
      targetType: "staff",
      targetId: userId,
      metadata: {before: plan.before, after: plan.next, added: plan.added, removed: plan.removed, revision, reason},
    });
    return {ok: true, revision, collegeIds: plan.next};
  });
});
