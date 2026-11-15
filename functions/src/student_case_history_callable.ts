import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireClinical, requireUid, roleOf, superAdminUid} from "./access";
import {AUDIT_CATEGORIES, actorName, writeAuditBatch} from "./audit";
import {
  CaseHistoryError,
  MAX_HISTORY_RECORDS,
  caseHistoryEntry,
  decideCaseHistoryAccess,
  decodeCursor,
  pageCaseHistory,
  pageSizeOf,
  sortCaseHistory,
  studentDisplayName,
} from "./student_case_history";

const USER_ID = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * One student's appointments (current and archived), newest first, for an
 * authorized counselor or the configured super-administrator. Records are
 * matched only by the verified `userId` the server stored at booking, never by
 * name. The first page of every view is audited as COUNSELING_HISTORY_VIEWED.
 */
export const getStudentCaseHistory = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireClinical(actorId);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const studentId = typeof data.studentId === "string" ? data.studentId.trim() : "";
  if (!USER_ID.test(studentId)) throw new HttpsError("invalid-argument", "A student is required.");
  const pageSize = pageSizeOf(data.pageSize);
  const cursor = data.cursor == null ? null : String(data.cursor);
  try {
    if (cursor != null) decodeCursor(cursor);

    const db = getFirestore();
    const [profileSnap, appointmentSnap] = await Promise.all([
      db.collection("users").doc(studentId).get(),
      db.collection("appointments").where("userId", "==", studentId).limit(MAX_HISTORY_RECORDS + 1).get(),
    ]);
    const records = appointmentSnap.docs
      // Defence in depth: the query already filters on userId.
      .filter((doc) => doc.data().userId === studentId)
      .map((doc) => ({id: doc.id, data: doc.data()}));
    const truncated = records.length > MAX_HISTORY_RECORDS;
    const kept = records.slice(0, MAX_HISTORY_RECORDS);
    const target = profileSnap.exists ? profileSnap.data() ?? {} : null;

    const basis = decideCaseHistoryAccess({
      actorId,
      actor,
      superAdminUid: superAdminUid.value().trim(),
      target,
      assignedToActor: kept.some((record) => record.data.assignedStaffId === actorId),
    });

    const page = pageCaseHistory(sortCaseHistory(kept), cursor, pageSize);
    if (cursor == null) {
      // Committed before anything is returned to the caller.
      const batch = db.batch();
      writeAuditBatch(batch, db, {
        actorId,
        actorNameSnapshot: actorName(actor),
        actorRoleSnapshot: roleOf(actor),
        action: "COUNSELING_HISTORY_VIEWED",
        category: AUDIT_CATEGORIES.security,
        targetType: "student",
        targetId: studentId,
        metadata: {basis, recordCount: kept.length, truncated},
      });
      await batch.commit();
    }
    return {
      student: {id: studentId, displayName: studentDisplayName(target ?? {}), collegeId: String(target?.collegeId ?? "")},
      basis,
      items: page.items.map((record) => caseHistoryEntry(record.id, record.data)),
      nextCursor: page.nextCursor,
      truncated,
    };
  } catch (error) {
    if (error instanceof CaseHistoryError) throw new HttpsError(error.code, error.message);
    throw error;
  }
});
