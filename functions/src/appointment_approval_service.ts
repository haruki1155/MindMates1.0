import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {configuredSuperAdminUid, requireStaff, requireUid} from "./access";
import {
  ApprovalAuthority,
  ApprovalError,
  ApprovalScope,
  AuthState,
  decideApprovalAuthority,
  decideApprovalScope,
} from "./appointment_approval";
import {canonicalAppointmentStatus} from "./appointment_lifecycle";

// Server enforcement of college-scoped clinical appointment approval.
// Authority is re-evaluated for every action from the student's current
// verified college and the live counselor assignments, so a change of
// assignment or of the student's college takes effect immediately.

const ID = /^[A-Za-z0-9_-]{1,128}$/;
const db = () => getFirestore();

function superAdminUid(): string {
  try {
    return configuredSuperAdminUid();
  } catch {
    return "";
  }
}

async function authStates(uids: string[]): Promise<Map<string, AuthState>> {
  const states = new Map<string, AuthState>();
  for (let i = 0; i < uids.length; i += 100) {
    const result = await getAuth().getUsers(uids.slice(i, i + 100).map((uid) => ({uid})));
    for (const user of result.users) states.set(user.uid, {disabled: user.disabled, emailVerified: user.emailVerified});
  }
  return states;
}

async function collegeCounselors(collegeId: string, cache?: Map<string, Promise<Array<{profile: Record<string, unknown>; auth: AuthState}>>>) {
  const load = async () => {
    const assigned = await db().collection("users").where("assignedCollegeIds", "array-contains", collegeId).get();
    const auth = await authStates(assigned.docs.map((d) => d.id));
    return assigned.docs.map((d) => ({profile: d.data(), auth: auth.get(d.id) ?? null}));
  };
  if (!cache) return load();
  if (!cache.has(collegeId)) cache.set(collegeId, load());
  return cache.get(collegeId)!;
}

/** Scope of a student's appointments: college-approvable or administrative exception. */
export async function resolveApprovalScope(
  studentId: string,
  cache?: Map<string, Promise<Array<{profile: Record<string, unknown>; auth: AuthState}>>>,
): Promise<ApprovalScope> {
  const student = ID.test(studentId) ? await db().collection("users").doc(studentId).get() : null;
  const data = student?.exists ? student.data() ?? {} : null;
  const collegeId = typeof data?.collegeId === "string" ? data.collegeId.trim() : "";
  const collegeExists = ID.test(collegeId) ? (await db().collection("colleges").doc(collegeId).get()).exists : false;
  const counselors = collegeExists && data?.verificationStatus === "verified" ? await collegeCounselors(collegeId, cache) : [];
  return decideApprovalScope({student: data, collegeExists, counselors});
}

/**
 * Clinical staff gate plus college scope. Returns the actor profile with
 * `approvalAuthority`; throws permission-denied for the wrong college or a
 * non-super admin, and failed-precondition when an override needs a reason.
 */
export async function authorizeAppointmentApproval(
  uid: string,
  appointment: FirebaseFirestore.DocumentData,
  exceptionReason?: unknown,
): Promise<FirebaseFirestore.DocumentData & {approvalAuthority: ApprovalAuthority}> {
  const actor = await requireStaff(uid);
  const role = String(actor.accessRole);
  if (role !== "counselor" && role !== "admin") {
    throw new HttpsError("permission-denied", "Counselor or administrator access is required for clinical appointment actions.");
  }
  const scope = await resolveApprovalScope(String(appointment.userId ?? ""));
  try {
    const approvalAuthority = decideApprovalAuthority({
      actor: {role, isSuperAdmin: role === "admin" && uid === superAdminUid(), assignedCollegeIds: actor.assignedCollegeIds},
      scope,
      exceptionReason,
    });
    return {...actor, approvalAuthority};
  } catch (error) {
    if (error instanceof ApprovalError) {
      throw new HttpsError(error.code === "override_reason_required" ? "failed-precondition" : "permission-denied", error.message, {reason: error.code});
    }
    throw error;
  }
}

/** Audit metadata for an approval decision. */
export function approvalMetadata(authority: ApprovalAuthority | undefined): Record<string, unknown> {
  return authority ? {approval: {...authority}} : {};
}

/** History fields for an approval decision. */
export function approvalHistoryFields(authority: ApprovalAuthority | undefined): Record<string, unknown> {
  if (!authority) return {};
  return {
    approvalMode: authority.mode,
    approvalCollegeId: authority.collegeId,
    ...(authority.scopeReason ? {approvalScopeReason: authority.scopeReason} : {}),
    ...(authority.exceptionReason ? {approvalExceptionReason: authority.exceptionReason} : {}),
  };
}

const ACTIVE_RAW_STATUSES = ["requested", "pending", "confirmed", "upcoming", "reschedule_proposed", "reschedule_required"];

function needsDecision(data: FirebaseFirestore.DocumentData): boolean {
  if (data.archivedAt) return false;
  const status = canonicalAppointmentStatus(data.status);
  if (status === "requested" || status === "reschedule_proposed") return true;
  return data.proposalStatus === "pending" && data.proposedBy === "student";
}

/**
 * Counselors: pending decisions for students in the colleges they serve.
 * Super-admin: administrative exceptions with their reason. Returns
 * identifiers, status, schedule and scope only, never clinical text.
 */
export const listAppointmentApprovals = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireStaff(uid);
  const role = String(actor.accessRole);
  const isSuperAdmin = role === "admin" && uid === superAdminUid();
  if (role !== "counselor" && !isSuperAdmin) {
    throw new HttpsError("permission-denied", "Approvals are listed for counselors and the super-administrator.");
  }
  const served = Array.isArray(actor.assignedCollegeIds) ? actor.assignedCollegeIds as string[] : [];
  const snapshot = await db().collection("appointments").where("status", "in", ACTIVE_RAW_STATUSES).limit(500).get();
  const cache = new Map<string, Promise<Array<{profile: Record<string, unknown>; auth: AuthState}>>>();
  const scopes = new Map<string, Promise<ApprovalScope>>();
  const items: Array<Record<string, unknown>> = [];
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (!needsDecision(data)) continue;
    const studentId = String(data.userId ?? "");
    if (!scopes.has(studentId)) scopes.set(studentId, resolveApprovalScope(studentId, cache));
    const scope = await scopes.get(studentId)!;
    const visible = role === "counselor" ? scope.scope === "college" && served.includes(scope.collegeId) : scope.scope === "exception";
    if (!visible) continue;
    items.push({
      appointmentId: doc.id,
      status: canonicalAppointmentStatus(data.status),
      scheduledAt: data.scheduledAt instanceof Timestamp ? data.scheduledAt.toMillis() : null,
      pendingStudentProposal: data.proposalStatus === "pending" && data.proposedBy === "student",
      collegeId: scope.collegeId,
      scope: scope.scope,
      reason: scope.reason,
    });
  }
  items.sort((a, b) => Number(a.scheduledAt ?? 0) - Number(b.scheduledAt ?? 0));
  return {ok: true, items, truncated: snapshot.size >= 500};
});
