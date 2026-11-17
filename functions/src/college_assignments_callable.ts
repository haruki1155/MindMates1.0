import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireSuperAdmin, requireUid} from "./access";
import {actorName, AUDIT_CATEGORIES, writeAudit} from "./audit";
import {
  CollegeAssignmentError,
  MAX_ASSIGNED_COLLEGES,
  planCollegeAssignmentChange,
  planCollegeCounselorTransfer,
  storedAssignedCollegeIds,
  storedAssignmentRevision,
} from "./college_assignments";

const USER_ID = /^[A-Za-z0-9_-]{1,128}$/;
const COLLEGE_ID = /^[A-Za-z0-9_-]{1,128}$/;
export const COLLEGE_OWNERSHIP_COLLECTION = "college_counselor_assignments";

function reasonText(value: unknown): string {
  const text = typeof value === "string" ? value.trim() : "";
  if (text.length < 3 || text.length > 500) throw new HttpsError("invalid-argument", "Reason must be 3-500 characters.");
  return text;
}

function mapError(error: unknown): never {
  if (error instanceof CollegeAssignmentError) {
    throw new HttpsError(
      error.code === "invalid-id" || error.code === "too-many" ? "invalid-argument" : "failed-precondition",
      error.message,
      {reason: error.code},
    );
  }
  throw error;
}

function ownershipRef(db: FirebaseFirestore.Firestore, collegeId: string) {
  return db.collection(COLLEGE_OWNERSHIP_COLLECTION).doc(collegeId);
}

/**
 * Super-administrator assigns the colleges a counselor serves (`accessRole ==
 * "counselor"`). Enforces both optimistic concurrency (`expectedRevision`) and
 * race-safe one-counselor-per-college ownership via transactional per-college
 * locks in `college_counselor_assignments/{collegeId}`.
 *
 * Legacy `portalStaff` accounts cannot receive new assignments; only removals
 * of pre-existing assignments are permitted for audited cleanup.
 */
export const setStaffCollegeAssignments = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireSuperAdmin(actorId);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const userId = typeof data.userId === "string" ? data.userId.trim() : "";
  if (!USER_ID.test(userId)) throw new HttpsError("invalid-argument", "A counselor user ID is required.");
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
    const beforeIds = storedAssignedCollegeIds(profile?.assignedCollegeIds);
    const lookup = [...new Set([...(requested as string[]), ...beforeIds])];

    const collegeDocs = lookup.length > 0
      ? await tx.getAll(...lookup.map((id) => db.collection("colleges").doc(id)))
      : [];
    const lockDocs = lookup.length > 0
      ? await tx.getAll(...lookup.map((id) => ownershipRef(db, id)))
      : [];
    const chunks: string[][] = [];
    for (let i = 0; i < lookup.length; i += 30) chunks.push(lookup.slice(i, i + 30));
    const userQueries = await Promise.all(
      chunks.map((c) => tx.get(db.collection("users").where("assignedCollegeIds", "array-contains-any", c))),
    );

    const colleges = new Map(collegeDocs.filter((d) => d.exists).map((d) => [d.id, {active: d.data()?.active === true}]));
    const lockByCollege = new Map(lockDocs.map((d) => [d.id, d]));

    // Collect distinct OTHER counselor owners from queried users + verify any out-of-sync lock docs.
    const ownersByCollege = new Map<string, Set<string>>();
    const queriedById = new Map<string, FirebaseFirestore.DocumentData>();
    for (const qSnap of userQueries) {
      for (const doc of qSnap.docs) queriedById.set(doc.id, doc.data());
    }
    const extraLockOwners: string[] = [];
    for (const [cid, lockSnap] of lockByCollege.entries()) {
      const lockOwner = lockSnap.exists ? String(lockSnap.data()?.counselorId ?? "") : "";
      if (USER_ID.test(lockOwner) && lockOwner !== userId && !queriedById.has(lockOwner)) {
        extraLockOwners.push(lockOwner);
      }
    }
    if (extraLockOwners.length > 0) {
      const uniqueExtras = [...new Set(extraLockOwners)];
      const extraDocs = await tx.getAll(...uniqueExtras.map((id) => db.collection("users").doc(id)));
      for (const d of extraDocs) {
        if (d.exists) queriedById.set(d.id, d.data() ?? {});
      }
    }

    for (const cid of lookup) ownersByCollege.set(cid, new Set());
    for (const [uid, uData] of queriedById.entries()) {
      if (uid === userId) continue;
      if (String(uData.accessRole ?? "") !== "counselor") continue;
      const held = storedAssignedCollegeIds(uData.assignedCollegeIds);
      for (const cid of held) {
        ownersByCollege.get(cid)?.add(uid);
      }
    }
    for (const [cid, lockSnap] of lockByCollege.entries()) {
      const lockOwner = lockSnap.exists ? String(lockSnap.data()?.counselorId ?? "") : "";
      if (!lockOwner || lockOwner === userId) continue;
      const ownerData = queriedById.get(lockOwner);
      if (ownerData && String(ownerData.accessRole ?? "") === "counselor" &&
          storedAssignedCollegeIds(ownerData.assignedCollegeIds).includes(cid)) {
        ownersByCollege.get(cid)?.add(lockOwner);
      }
    }

    const collegeOwners = new Map(
      [...ownersByCollege.entries()].map(([cid, set]) => [cid, [...set].sort()]),
    );

    let plan;
    try {
      plan = planCollegeAssignmentChange({
        target: profile,
        requested,
        colleges,
        expectedRevision: data.expectedRevision,
        collegeOwners,
      });
    } catch (error) {
      mapError(error);
    }
    if (!plan.changed) return {ok: true, revision: plan.revision, collegeIds: plan.next};

    const revision = plan.revision + 1;
    tx.update(target, {
      assignedCollegeIds: plan.next,
      collegeAssignmentRevision: revision,
      collegeAssignmentUpdatedBy: actorId,
      collegeAssignmentUpdatedAt: FieldValue.serverTimestamp(),
    });

    if (!plan.legacyStaffCleanup) {
      for (const cid of plan.added) {
        tx.set(ownershipRef(db, cid), {
          collegeId: cid,
          counselorId: userId,
          updatedBy: actorId,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      for (const cid of plan.removed) {
        const lockSnap = lockByCollege.get(cid);
        const remaining = collegeOwners.get(cid) ?? [];
        if (remaining.length === 0) {
          if (lockSnap?.exists) tx.delete(ownershipRef(db, cid));
        } else if (remaining.length === 1 && (!lockSnap?.exists || lockSnap.data()?.counselorId === userId)) {
          tx.set(ownershipRef(db, cid), {
            collegeId: cid,
            counselorId: remaining[0],
            updatedBy: actorId,
            updatedAt: FieldValue.serverTimestamp(),
          });
        } else if (lockSnap?.exists && lockSnap.data()?.counselorId === userId) {
          tx.delete(ownershipRef(db, cid));
        }
      }
      for (const cid of plan.next) {
        if (plan.added.includes(cid)) continue;
        const lockSnap = lockByCollege.get(cid);
        const otherOwners = collegeOwners.get(cid) ?? [];
        if (!lockSnap?.exists && otherOwners.length === 0) {
          tx.set(ownershipRef(db, cid), {
            collegeId: cid,
            counselorId: userId,
            updatedBy: actorId,
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      }
    }

    writeAudit(tx, db, {
      actorId,
      actorNameSnapshot: actorName(actor),
      actorRoleSnapshot: String(actor.accessRole),
      action: "STAFF_COLLEGE_ASSIGNMENTS_UPDATED",
      category: AUDIT_CATEGORIES.userManagement,
      targetType: "staff",
      targetId: userId,
      metadata: {
        before: plan.before,
        after: plan.next,
        added: plan.added,
        removed: plan.removed,
        revision,
        reason,
        ...(plan.legacyStaffCleanup ? {legacyStaffCleanup: true} : {}),
      },
    });
    return {ok: true, revision, collegeIds: plan.next};
  });
});

/**
 * Explicitly assigns, transfers, unassigns, or resolves a duplicate-counselor
 * conflict for one college atomically across all affected counselor profiles
 * and the `college_counselor_assignments/{collegeId}` ownership record.
 */
export const reassignCollegeCounselor = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireSuperAdmin(actorId);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const collegeId = typeof data.collegeId === "string" ? data.collegeId.trim() : "";
  if (!COLLEGE_ID.test(collegeId)) throw new HttpsError("invalid-argument", "A valid college ID is required.");

  let toCounselorId: string | null = null;
  if (data.toCounselorId != null) {
    if (typeof data.toCounselorId !== "string" || !USER_ID.test(data.toCounselorId.trim())) {
      throw new HttpsError("invalid-argument", "Provide a valid counselor user ID or null to unassign.");
    }
    toCounselorId = data.toCounselorId.trim();
  }
  const reason = reasonText(data.reason);

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const collegeRef = db.collection("colleges").doc(collegeId);
    const lockRef = ownershipRef(db, collegeId);
    const [collegeSnap, lockSnap, ownersSnap, targetSnap] = await Promise.all([
      tx.get(collegeRef),
      tx.get(lockRef),
      tx.get(db.collection("users").where("assignedCollegeIds", "array-contains", collegeId)),
      toCounselorId ? tx.get(db.collection("users").doc(toCounselorId)) : Promise.resolve(null),
    ]);

    const college = collegeSnap.exists ? {active: collegeSnap.data()?.active === true} : null;
    const currentOwners = ownersSnap.docs
      .filter((d) => String(d.data()?.accessRole ?? "") === "counselor")
      .map((d) => ({uid: d.id, profile: d.data()}));
    const targetCounselor = toCounselorId && targetSnap?.exists
      ? {uid: targetSnap.id, profile: targetSnap.data() ?? {}}
      : (toCounselorId ? {uid: toCounselorId, profile: {}} : null);
    if (toCounselorId && !targetSnap?.exists) {
      throw new HttpsError("failed-precondition", "Selected counselor account was not found.", {reason: "role-mismatch"});
    }

    let plan;
    try {
      plan = planCollegeCounselorTransfer({
        collegeId,
        college,
        currentOwners,
        targetCounselor,
        expectedOwnerIds: data.expectedOwnerIds,
        expectedRevisions: data.expectedRevisions,
      });
    } catch (error) {
      mapError(error);
    }

    const lockMatches = toCounselorId == null
      ? !lockSnap.exists
      : lockSnap.exists && lockSnap.data()?.counselorId === toCounselorId;

    const revisions: Record<string, number> = {};
    for (const o of currentOwners) revisions[o.uid] = storedAssignmentRevision(o.profile);
    if (targetCounselor) revisions[targetCounselor.uid] = storedAssignmentRevision(targetCounselor.profile);

    if (!plan.changed && lockMatches) {
      return {
        ok: true,
        changed: false,
        collegeId,
        counselorId: toCounselorId,
        revisions,
      };
    }

    for (const rem of plan.removals) {
      tx.update(db.collection("users").doc(rem.userId), {
        assignedCollegeIds: rem.next,
        collegeAssignmentRevision: rem.nextRevision,
        collegeAssignmentUpdatedBy: actorId,
        collegeAssignmentUpdatedAt: FieldValue.serverTimestamp(),
      });
      revisions[rem.userId] = rem.nextRevision;
      writeAudit(tx, db, {
        actorId,
        actorNameSnapshot: actorName(actor),
        actorRoleSnapshot: String(actor.accessRole),
        action: "STAFF_COLLEGE_ASSIGNMENTS_UPDATED",
        category: AUDIT_CATEGORIES.userManagement,
        targetType: "staff",
        targetId: rem.userId,
        metadata: {
          before: rem.before,
          after: rem.next,
          added: [],
          removed: [collegeId],
          revision: rem.nextRevision,
          reason,
          transferredTo: toCounselorId,
          conflictResolution: plan.conflictResolved,
        },
      });
    }

    if (plan.addition) {
      const add = plan.addition;
      tx.update(db.collection("users").doc(add.userId), {
        assignedCollegeIds: add.next,
        collegeAssignmentRevision: add.nextRevision,
        collegeAssignmentUpdatedBy: actorId,
        collegeAssignmentUpdatedAt: FieldValue.serverTimestamp(),
      });
      revisions[add.userId] = add.nextRevision;
      writeAudit(tx, db, {
        actorId,
        actorNameSnapshot: actorName(actor),
        actorRoleSnapshot: String(actor.accessRole),
        action: "STAFF_COLLEGE_ASSIGNMENTS_UPDATED",
        category: AUDIT_CATEGORIES.userManagement,
        targetType: "staff",
        targetId: add.userId,
        metadata: {
          before: add.before,
          after: add.next,
          added: [collegeId],
          removed: [],
          revision: add.nextRevision,
          reason,
          transferredFrom: plan.beforeOwnerIds,
          conflictResolution: plan.conflictResolved,
        },
      });
    }

    if (toCounselorId != null) {
      tx.set(lockRef, {
        collegeId,
        counselorId: toCounselorId,
        updatedBy: actorId,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else if (lockSnap.exists) {
      tx.delete(lockRef);
    }

    if (plan.changed) {
      writeAudit(tx, db, {
        actorId,
        actorNameSnapshot: actorName(actor),
        actorRoleSnapshot: String(actor.accessRole),
        action: "COLLEGE_COUNSELOR_TRANSFERRED",
        category: AUDIT_CATEGORIES.userManagement,
        targetType: "college",
        targetId: collegeId,
        metadata: {
          collegeId,
          beforeOwnerIds: plan.beforeOwnerIds,
          afterOwnerIds: plan.afterOwnerIds,
          conflictResolved: plan.conflictResolved,
          reason,
        },
      });
    }

    return {
      ok: true,
      changed: plan.changed,
      collegeId,
      counselorId: toCounselorId,
      revisions,
    };
  });
});
