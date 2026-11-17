import {FieldPath, getFirestore} from "firebase-admin/firestore";
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
const READ_BATCH = 500;

type HistoryRecord = {id: string; data: FirebaseFirestore.DocumentData};

/**
 * Every appointment whose verified `userId` is this student, read in
 * document-ID batches so a long history is never silently sampled. Stops at
 * `cap` and reports `truncated` if more exist.
 */
export async function readStudentAppointments(
  db: FirebaseFirestore.Firestore, studentId: string, batchSize = READ_BATCH, cap = MAX_HISTORY_RECORDS,
): Promise<{records: HistoryRecord[]; truncated: boolean}> {
  const records: HistoryRecord[] = [];
  let last: string | null = null;
  for (;;) {
    let query = db.collection("appointments").where("userId", "==", studentId).orderBy(FieldPath.documentId()).limit(batchSize);
    if (last != null) query = query.startAfter(last);
    const snap = await query.get();
    for (const doc of snap.docs) {
      // Defence in depth: the query already filters on userId.
      if (doc.data().userId !== studentId) continue;
      if (records.length >= cap) return {records, truncated: true};
      records.push({id: doc.id, data: doc.data()});
    }
    if (snap.size < batchSize) return {records, truncated: false};
    last = snap.docs[snap.docs.length - 1].id;
  }
}

/**
 * One student's appointments (current and archived), newest first, for an
 * authorized counselor or the configured super-administrator. Records are
 * matched only by the verified `userId` the server stored at booking, never by
 * name. Every page read is audited as COUNSELING_HISTORY_VIEWED.
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
    // Entitlement first: no appointment content is read for a refused caller.
    const [profileSnap, assignedSnap] = await Promise.all([
      db.collection("users").doc(studentId).get(),
      db.collection("appointments").where("userId", "==", studentId).where("assignedStaffId", "==", actorId).limit(1).get(),
    ]);
    const target = profileSnap.exists ? profileSnap.data() ?? {} : null;
    const basis = decideCaseHistoryAccess({
      actorId,
      actor,
      superAdminUid: superAdminUid.value().trim(),
      target,
      assignedToActor: !assignedSnap.empty,
    });

    const {records: kept, truncated} = await readStudentAppointments(db, studentId);
    const page = pageCaseHistory(sortCaseHistory(kept), cursor, pageSize);
    {
      // Every page is audited, committed before anything is returned. The
      // cursor is client-supplied, so auditing only the first page would let
      // a forged cursor read the history unaudited.
      const batch = db.batch();
      writeAuditBatch(batch, db, {
        actorId,
        actorNameSnapshot: actorName(actor),
        actorRoleSnapshot: roleOf(actor),
        action: "COUNSELING_HISTORY_VIEWED",
        category: AUDIT_CATEGORIES.security,
        targetType: "student",
        targetId: studentId,
        metadata: {basis, page: cursor == null ? "first" : "next", returned: page.items.length, recordCount: kept.length, truncated},
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
