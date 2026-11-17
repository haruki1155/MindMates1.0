import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireClinical, requireUid, roleOf, superAdminUid} from "./access";
import {AUDIT_CATEGORIES, actorName, writeAudit, writeAuditBatch} from "./audit";
import {
  CaseRemarksError,
  MAX_VERSIONS_RETURNED,
  NOT_AUTHORIZED_REMARKS,
  decideCaseRemarksAccess,
  expectedRevisionOf,
  normalizeRemarks,
  planRemarksSave,
  remarksView,
} from "./case_remarks";

const DOC_ID = /^[A-Za-z0-9_-]{1,128}$/;

type Access = {
  actorId: string;
  actor: FirebaseFirestore.DocumentData;
  appointmentId: string;
  studentId: string;
  basis: "college" | "assigned";
};

function appointmentIdOf(data: Record<string, unknown>): string {
  const value = typeof data.appointmentId === "string" ? data.appointmentId.trim() : "";
  if (!DOC_ID.test(value)) throw new HttpsError("invalid-argument", "A case is required.");
  return value;
}

/**
 * The PR 7 case-history entitlement, restricted to counselors. An unknown
 * appointment is refused exactly like an out-of-scope one, so the callable
 * cannot be used to discover records.
 */
async function authorize(db: FirebaseFirestore.Firestore, actorId: string, actor: FirebaseFirestore.DocumentData, appointmentId: string): Promise<Access> {
  const appointment = await db.collection("appointments").doc(appointmentId).get();
  const studentId = String(appointment.data()?.userId ?? "");
  if (!appointment.exists || !DOC_ID.test(studentId)) throw new CaseRemarksError("permission-denied", NOT_AUTHORIZED_REMARKS);
  const [profileSnap, assignedSnap] = await Promise.all([
    db.collection("users").doc(studentId).get(),
    db.collection("appointments").where("userId", "==", studentId).where("assignedStaffId", "==", actorId).limit(1).get(),
  ]);
  const basis = decideCaseRemarksAccess({
    actorId,
    actor,
    superAdminUid: superAdminUid.value().trim(),
    target: profileSnap.exists ? profileSnap.data() ?? {} : null,
    assignedToActor: !assignedSnap.empty,
  });
  return {actorId, actor, appointmentId, studentId, basis};
}

function remarksRef(db: FirebaseFirestore.Firestore, appointmentId: string) {
  return db.collection("appointments").doc(appointmentId).collection("case_remarks").doc("current");
}

async function readView(db: FirebaseFirestore.Firestore, appointmentId: string) {
  const ref = remarksRef(db, appointmentId);
  const [current, versions] = await Promise.all([
    ref.get(),
    ref.collection("versions").orderBy("revision", "desc").limit(MAX_VERSIONS_RETURNED).get(),
  ]);
  return remarksView(appointmentId, current.exists ? current.data() ?? {} : null, versions.docs.map((d) => d.data()));
}

function auditEvent(access: Access, action: string, metadata: Record<string, unknown>) {
  return {
    actorId: access.actorId,
    actorNameSnapshot: actorName(access.actor),
    actorRoleSnapshot: roleOf(access.actor),
    action,
    category: AUDIT_CATEGORIES.security,
    targetType: "appointment",
    targetId: access.appointmentId,
    metadata: {studentId: access.studentId, basis: access.basis, ...metadata},
  };
}

function rethrow(error: unknown): never {
  if (error instanceof CaseRemarksError) throw new HttpsError(error.code, error.message);
  throw error;
}

/**
 * Optional transcript / remarks for one case (evaluator requirement #10), for
 * a counselor entitled to the student's case history. Every read is audited
 * as CASE_REMARKS_VIEWED before anything is returned. The note text is never
 * written to the audit log.
 */
export const getCaseRemarks = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireClinical(actorId);
  const appointmentId = appointmentIdOf((request.data ?? {}) as Record<string, unknown>);
  try {
    const db = getFirestore();
    const access = await authorize(db, actorId, actor, appointmentId);
    const view = await readView(db, appointmentId);
    const batch = db.batch();
    writeAuditBatch(batch, db, auditEvent(access, "CASE_REMARKS_VIEWED", {revision: view.revision}));
    await batch.commit();
    return view;
  } catch (error) {
    rethrow(error);
  }
});

/**
 * Saves (or clears) the remarks. Blank is valid. `expectedRevision` must match
 * the stored revision, else `aborted` and nothing is written. Each change
 * creates an immutable version and an audit row in the same transaction.
 */
export const saveCaseRemarks = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireClinical(actorId);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const appointmentId = appointmentIdOf(data);
  try {
    const text = normalizeRemarks(data.text);
    const expectedRevision = expectedRevisionOf(data.expectedRevision);
    const db = getFirestore();
    const access = await authorize(db, actorId, actor, appointmentId);
    const ref = remarksRef(db, appointmentId);
    await db.runTransaction(async (tx) => {
      const [appointment, current] = await Promise.all([
        tx.get(db.collection("appointments").doc(appointmentId)),
        tx.get(ref),
      ]);
      // The case must still belong to the student the entitlement was decided for.
      if (String(appointment.data()?.userId ?? "") !== access.studentId) {
        throw new CaseRemarksError("permission-denied", NOT_AUTHORIZED_REMARKS);
      }
      const existing = current.exists ? current.data() ?? {} : null;
      if (data.text == null && typeof existing?.text === "string" && existing.text !== "") {
        throw new CaseRemarksError("invalid-argument", "Provide remarks text, or pass an empty string to clear saved remarks.");
      }
      const plan = planRemarksSave({current: existing, text, expectedRevision});
      if (plan.kind === "unchanged") return;
      const author = {
        authorId: actorId,
        authorNameSnapshot: actorName(actor),
        authorRoleSnapshot: roleOf(actor),
      };
      tx.set(ref, {
        appointmentId,
        studentId: access.studentId,
        text,
        revision: plan.revision,
        ...author,
        createdAt: existing?.createdAt ?? FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.create(ref.collection("versions").doc(String(plan.revision)), {
        revision: plan.revision,
        text,
        ...author,
        createdAt: FieldValue.serverTimestamp(),
      });
      writeAudit(tx, db, auditEvent(access, "CASE_REMARKS_UPDATED", {
        revision: plan.revision, length: text.length, cleared: text === "",
      }));
    });
    return await readView(db, appointmentId);
  } catch (error) {
    rethrow(error);
  }
});
