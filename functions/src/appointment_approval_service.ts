import {getAuth} from "firebase-admin/auth";
import {FieldPath, getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {configuredSuperAdminUid, requireStaff, requireUid} from "./access";
import {
  ApprovalAuthority,
  ApprovalError,
  ApprovalScope,
  AuthState,
  decideApprovalAuthority,
  decideApprovalScope,
  isEligibleCounselor,
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
  const unique = [...new Set(uids.filter((id) => Boolean(id)))];
  const states = new Map<string, AuthState>();
  for (let i = 0; i < unique.length; i += 100) {
    const result = await getAuth().getUsers(unique.slice(i, i + 100).map((uid) => ({uid})));
    for (const user of result.users) states.set(user.uid, {disabled: user.disabled, emailVerified: user.emailVerified});
  }
  return states;
}

function resolveStaffProfile(profile: FirebaseFirestore.DocumentData): {accessRole: string} {
  const legacyRole = String(profile.role ?? "").toLowerCase();
  const accessRole = String(profile.accessRole ??
    (legacyRole === "admin" || legacyRole === "counselor" ? legacyRole : "appUser"));
  if (!["portalStaff", "counselor", "admin"].includes(accessRole)) {
    throw new HttpsError("permission-denied", "Staff access is required.");
  }
  const accountStatus = profile.accountStatus == null ? "active" : String(profile.accountStatus);
  const staffAccountStatus = profile.staffAccountStatus == null ? null : String(profile.staffAccountStatus);
  if (accountStatus !== "active" ||
      (accessRole !== "admin" && staffAccountStatus != null && staffAccountStatus !== "approved")) {
    throw new HttpsError("permission-denied", "Your PACC portal access is not active.");
  }
  return {accessRole};
}

function decideFromInputs(
  uid: string,
  role: string,
  assignedCollegeIds: unknown,
  scope: ApprovalScope,
  exceptionReason?: unknown,
): ApprovalAuthority {
  try {
    return decideApprovalAuthority({
      actor: {role, isSuperAdmin: role === "admin" && uid === superAdminUid(), assignedCollegeIds},
      scope,
      exceptionReason,
    });
  } catch (error) {
    if (error instanceof ApprovalError) {
      throw new HttpsError(error.code === "override_reason_required" ? "failed-precondition" : "permission-denied", error.message, {reason: error.code});
    }
    throw error;
  }
}

export type CollegeCounselorRecord = {uid: string; profile: Record<string, unknown>; auth: AuthState};

async function collegeCounselors(collegeId: string, cache?: Map<string, Promise<CollegeCounselorRecord[]>>) {
  const load = async () => {
    const assigned = await db().collection("users").where("assignedCollegeIds", "array-contains", collegeId).get();
    const auth = await authStates(assigned.docs.map((d) => d.id));
    return assigned.docs.map((d) => ({uid: d.id, profile: d.data(), auth: auth.get(d.id) ?? null}));
  };
  if (!cache) return load();
  if (!cache.has(collegeId)) cache.set(collegeId, load());
  return cache.get(collegeId)!;
}

/** Scope of a student's appointments: college-approvable or administrative exception. */
export async function resolveApprovalScope(
  studentId: string,
  cache?: Map<string, Promise<CollegeCounselorRecord[]>>,
): Promise<ApprovalScope> {
  const student = ID.test(studentId) ? await db().collection("users").doc(studentId).get() : null;
  const data = student?.exists ? student.data() ?? {} : null;
  const collegeId = typeof data?.collegeId === "string" ? data.collegeId.trim() : "";
  const collegeExists = ID.test(collegeId) ? (await db().collection("colleges").doc(collegeId).get()).exists : false;
  const counselors = collegeExists && data?.verificationStatus === "verified" ? await collegeCounselors(collegeId, cache) : [];
  return decideApprovalScope({student: data, collegeExists, counselors});
}

/**
 * Authorized portal notification recipients for a student's appointment:
 * eligible counselors serving the student's verified college, or the
 * configured active, verified super-administrator when the appointment is in
 * the administrative exception scope. Never returns portalStaff or other
 * colleges' counselors.
 */
export async function appointmentPortalRecipients(studentId: string): Promise<string[]> {
  const cache = new Map<string, Promise<Array<{uid: string; profile: Record<string, unknown>; auth: AuthState}>>>();
  const scope = await resolveApprovalScope(studentId, cache);
  if (scope.scope === "college") {
    const counselors = await collegeCounselors(scope.collegeId, cache);
    return counselors
      .filter(({profile, auth}) =>
        Array.isArray(profile.assignedCollegeIds) &&
        profile.assignedCollegeIds.includes(scope.collegeId) &&
        isEligibleCounselor(profile, auth),
      )
      .map(({uid}) => uid);
  }
  const adminUid = superAdminUid();
  if (!ID.test(adminUid)) return [];
  const [adminSnap, auth] = await Promise.all([
    db().collection("users").doc(adminUid).get(),
    authStates([adminUid]),
  ]);
  const adminData = adminSnap.data();
  const adminAuth = auth.get(adminUid);
  const legacyRole = String(adminData?.role ?? "").toLowerCase();
  const accessRole = String(adminData?.accessRole ?? (legacyRole === "admin" ? "admin" : ""));
  const accountStatus = adminData?.accountStatus == null ? "active" : String(adminData.accountStatus);
  if (!adminSnap.exists || accessRole !== "admin" || accountStatus !== "active" ||
      !adminAuth || adminAuth.disabled || !adminAuth.emailVerified) {
    return [];
  }
  return [adminUid];
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
  const approvalAuthority = decideFromInputs(uid, role, actor.assignedCollegeIds, scope, exceptionReason);
  return {...actor, approvalAuthority};
}

/**
 * Re-verifies clinical staff eligibility, student college scope, and approval
 * authority inside an active Firestore transaction before any writes occur,
 * preventing TOCTOU races if assignments, lifecycle, or colleges change concurrently.
 */
export async function authorizeAppointmentApprovalInTransaction(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  studentId: string,
  exceptionReason?: unknown,
): Promise<FirebaseFirestore.DocumentData & {approvalAuthority: ApprovalAuthority}> {
  const staffRef = db().collection("users").doc(uid);
  const studentRef = ID.test(studentId) ? db().collection("users").doc(studentId) : null;
  const [staffSnap, studentSnap] = await Promise.all([
    tx.get(staffRef),
    studentRef ? tx.get(studentRef) : Promise.resolve(null),
  ]);
  const staffProfile = staffSnap.data() ?? {};
  const {accessRole: role} = resolveStaffProfile(staffProfile);
  if (role !== "counselor" && role !== "admin") {
    throw new HttpsError("permission-denied", "Counselor or administrator access is required for clinical appointment actions.");
  }

  const studentData = studentSnap?.exists ? studentSnap.data() ?? {} : null;
  const collegeId = typeof studentData?.collegeId === "string" ? studentData.collegeId.trim() : "";
  const verifiedCollege = ID.test(collegeId) && studentData?.verificationStatus === "verified";
  const [collegeSnap, assignedSnap] = verifiedCollege
    ? await Promise.all([
      tx.get(db().collection("colleges").doc(collegeId)),
      tx.get(db().collection("users").where("assignedCollegeIds", "array-contains", collegeId)),
    ])
    : [null, null];
  const collegeExists = Boolean(collegeSnap?.exists);
  const assignedDocs = collegeExists && assignedSnap ? assignedSnap.docs : [];
  const auth = await authStates([uid, ...assignedDocs.map((d) => d.id)]);
  const actorAuth = auth.get(uid) ?? null;
  if (!actorAuth || actorAuth.disabled || !actorAuth.emailVerified) {
    throw new HttpsError("permission-denied", "Your PACC portal access is not active.");
  }
  const counselors = assignedDocs.map((d) => ({profile: d.data(), auth: auth.get(d.id) ?? null}));
  const scope = decideApprovalScope({student: studentData, collegeExists, counselors});
  const approvalAuthority = decideFromInputs(uid, role, staffProfile.assignedCollegeIds, scope, exceptionReason);
  return {...staffProfile, accessRole: role, approvalAuthority};
}

/** Audit metadata for an approval decision. */
export function approvalMetadata(authority: ApprovalAuthority | undefined): Record<string, unknown> {
  return authority ? {approval: {...authority}} : {};
}

/**
 * History fields for an approval decision. appointments/{id}/history is
 * readable by the student (firestore.rules), so it records only which path
 * approved the action. The college, the scope reason and any super-admin
 * exception reason stay in admin_audit_logs (approvalMetadata), which only
 * the super-administrator can read.
 */
export function approvalHistoryFields(authority: ApprovalAuthority | undefined): Record<string, unknown> {
  return authority ? {approvalMode: authority.mode} : {};
}

const ACTIVE_RAW_STATUSES = ["requested", "pending", "confirmed", "upcoming", "reschedule_proposed", "reschedule_required"];

function needsDecision(data: FirebaseFirestore.DocumentData): boolean {
  if (data.archivedAt) return false;
  const status = canonicalAppointmentStatus(data.status);
  if (status === "requested" || status === "reschedule_proposed") return true;
  return data.proposalStatus === "pending" && data.proposedBy === "student";
}

export type ListAppointmentApprovalsOptions = {
  limit?: number;
  cursor?: string | null;
  pageSize?: number;
  maxPages?: number;
};

export type ListAppointmentApprovalsResult = {
  ok: true;
  items: Array<Record<string, unknown>>;
  nextCursor: string | null;
  hasMore: boolean;
  done: boolean;
  truncated: boolean;
  scanned: number;
};

/**
 * Bounded, deterministic, cursor-based scan over active appointment records.
 * Separated so tests can exercise multi-page cursoring with small `pageSize` /
 * `maxPages` without exposing those scan knobs to client RPCs.
 */
export async function listAppointmentApprovalsBatch(
  uid: string,
  options: ListAppointmentApprovalsOptions = {},
): Promise<ListAppointmentApprovalsResult> {
  const actor = await requireStaff(uid);
  const role = String(actor.accessRole);
  const isSuperAdmin = role === "admin" && uid === superAdminUid();
  if (role !== "counselor" && !isSuperAdmin) {
    throw new HttpsError("permission-denied", "Approvals are listed for counselors and the super-administrator.");
  }
  let cursor = options.cursor ?? null;
  if (cursor !== null && !ID.test(cursor)) {
    throw new HttpsError("invalid-argument", "Invalid continuation cursor.");
  }
  const limit = Math.min(Math.max(Math.trunc(options.limit ?? 50), 1), 100);
  const pageSize = Math.min(Math.max(Math.trunc(options.pageSize ?? 200), 1), 500);
  const maxPages = Math.min(Math.max(Math.trunc(options.maxPages ?? 5), 1), 10);

  const served = Array.isArray(actor.assignedCollegeIds) ? actor.assignedCollegeIds as string[] : [];
  const cache = new Map<string, Promise<CollegeCounselorRecord[]>>();
  const scopes = new Map<string, Promise<ApprovalScope>>();
  const seen = new Set<string>();
  const items: Array<Record<string, unknown>> = [];
  let scanned = 0;

  for (let page = 0; page < maxPages; page++) {
    let query = db()
      .collection("appointments")
      .where("status", "in", ACTIVE_RAW_STATUSES)
      .orderBy(FieldPath.documentId())
      .limit(pageSize);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) {
      return {ok: true, items, nextCursor: null, hasMore: false, done: true, truncated: false, scanned};
    }
    for (let i = 0; i < snapshot.docs.length; i++) {
      const doc = snapshot.docs[i];
      scanned += 1;
      cursor = doc.id;
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
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
      if (items.length >= limit) {
        const hasMore = i < snapshot.docs.length - 1 || snapshot.docs.length === pageSize;
        return {
          ok: true,
          items,
          nextCursor: hasMore ? cursor : null,
          hasMore,
          done: !hasMore,
          truncated: hasMore,
          scanned,
        };
      }
    }
    if (snapshot.docs.length < pageSize) {
      return {ok: true, items, nextCursor: null, hasMore: false, done: true, truncated: false, scanned};
    }
  }
  return {ok: true, items, nextCursor: cursor, hasMore: true, done: false, truncated: true, scanned};
}

/**
 * Counselors: pending decisions for students in the colleges they serve.
 * Super-admin: administrative exceptions with their reason. Returns
 * identifiers, status, schedule, scope and continuation metadata only,
 * never clinical text.
 */
export const listAppointmentApprovals = onCall(async (request) => {
  const uid = requireUid(request);
  const rawData = request.data;
  if (rawData != null && typeof rawData !== "object") {
    throw new HttpsError("invalid-argument", "Invalid approval list request.");
  }
  const input = (rawData ?? {}) as {limit?: unknown; cursor?: unknown};
  let cursor: string | null = null;
  if (input.cursor != null && input.cursor !== "") {
    if (typeof input.cursor !== "string" || !ID.test(input.cursor.trim())) {
      throw new HttpsError("invalid-argument", "Invalid continuation cursor.");
    }
    cursor = input.cursor.trim();
  }
  let limit = 50;
  if (input.limit !== undefined && input.limit !== null) {
    if (typeof input.limit !== "number" || !Number.isInteger(input.limit) || input.limit < 1 || input.limit > 100) {
      throw new HttpsError("invalid-argument", "Limit must be an integer between 1 and 100.");
    }
    limit = input.limit;
  }
  return listAppointmentApprovalsBatch(uid, {limit, cursor});
});

export type GetAppointmentForApprovalResult =
  | {ok: true; available: true; appointment: Record<string, unknown>}
  | {ok: true; available: false; reason: "not_found" | "not_pending_approval"; appointment: null};

function optionalTrimmedString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function optionalIsoTimestamp(value: unknown): string | undefined {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? undefined : value.toISOString();
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? undefined : new Date(parsed).toISOString();
  }
  return undefined;
}

/**
 * Authorized single-appointment lookup for the approval queue UI. Enforces the
 * exact same role, lifecycle, student college scope, and super-admin exception
 * rules as `listAppointmentApprovals`, returns only review-dialog fields (never
 * clinical notes, audit logs, or internal override metadata), and returns
 * `{available: false}` if the appointment no longer needs a decision.
 */
export async function getAuthorizedAppointmentForApproval(
  uid: string,
  appointmentId: string,
): Promise<GetAppointmentForApprovalResult> {
  const id = appointmentId.trim();
  if (!ID.test(id)) {
    throw new HttpsError("invalid-argument", "Invalid appointment ID.");
  }
  const actor = await requireStaff(uid);
  const role = String(actor.accessRole);
  const isSuperAdmin = role === "admin" && uid === superAdminUid();
  if (role !== "counselor" && !isSuperAdmin) {
    throw new HttpsError(
      "permission-denied",
      "Approval details are restricted to eligible counselors and the super-administrator.",
    );
  }

  const snap = await db().collection("appointments").doc(id).get();
  if (!snap.exists) {
    return {ok: true, available: false, reason: "not_found", appointment: null};
  }
  const data = snap.data()!;
  const studentId = String(data.userId ?? "").trim();
  const scope = await resolveApprovalScope(studentId);
  const served = Array.isArray(actor.assignedCollegeIds) ? actor.assignedCollegeIds as string[] : [];
  if (role === "counselor") {
    if (scope.scope !== "college" || !served.includes(scope.collegeId)) {
      throw new HttpsError(
        "permission-denied",
        "Only counselors assigned to this student's college can access this approval record.",
      );
    }
  } else if (scope.scope !== "exception") {
    throw new HttpsError(
      "permission-denied",
      "Super-administrator approval lookup is limited to exception-queue appointments.",
    );
  }

  const rawStatus = String(data.status ?? "").trim().toLowerCase();
  if (!ACTIVE_RAW_STATUSES.includes(rawStatus) || !needsDecision(data)) {
    return {ok: true, available: false, reason: "not_pending_approval", appointment: null};
  }

  const scheduledAt = optionalIsoTimestamp(data.scheduledAt);
  const createdAt = optionalIsoTimestamp(data.createdAt);
  const proposedScheduledAt = optionalIsoTimestamp(data.proposedScheduledAt);
  const course = optionalTrimmedString(data.course);
  const yearLevel = optionalTrimmedString(data.yearLevel);
  const therapyBefore = optionalTrimmedString(data.therapyBefore);
  const proposedScheduledTime = optionalTrimmedString(data.proposedScheduledTime);
  const proposedBy = optionalTrimmedString(data.proposedBy);
  const proposalStatus = optionalTrimmedString(data.proposalStatus);
  const staffReply = optionalTrimmedString(data.staffReply);
  const rescheduleReason = optionalTrimmedString(data.rescheduleReason);
  const department = optionalTrimmedString(data.department);

  const appointment: Record<string, unknown> = {
    id: snap.id,
    userId: studentId,
    fullName: typeof data.fullName === "string" ? data.fullName : "",
    email: typeof data.email === "string" ? data.email.trim() : "",
    contactNumber: typeof data.contactNumber === "string" ? data.contactNumber.trim() : "",
    preferredContactMethod: typeof data.preferredContactMethod === "string" ? data.preferredContactMethod.trim() : "",
    concern: typeof data.concern === "string" ? data.concern : "",
    ...(scheduledAt ? {scheduledAt} : {}),
    scheduledTime: typeof data.scheduledTime === "string" ? data.scheduledTime : "",
    location: typeof data.location === "string" ? data.location : "",
    status: canonicalAppointmentStatus(data.status),
    ...(createdAt ? {createdAt} : {}),
    ...(Number.isSafeInteger(data.scheduleRevision) ? {scheduleRevision: data.scheduleRevision} : {}),
    proposalRevision: Number.isSafeInteger(data.proposalRevision) ? data.proposalRevision : 0,
    ...(course ? {course} : {}),
    ...(yearLevel ? {yearLevel} : {}),
    ...(therapyBefore ? {therapyBefore} : {}),
    ...(proposedScheduledAt ? {proposedScheduledAt} : {}),
    ...(proposedScheduledTime ? {proposedScheduledTime} : {}),
    ...(proposedBy ? {proposedBy} : {}),
    ...(proposalStatus ? {proposalStatus} : {}),
    ...(staffReply ? {staffReply} : {}),
    ...(rescheduleReason ? {rescheduleReason} : {}),
    ...(department ? {department} : {}),
  };

  return {ok: true, available: true, appointment};
}

/**
 * Retrieves an authorized single pending appointment for review when it is not
 * present in the caller's local client stream. Uses identical college-scope
 * and exception-queue rules as `listAppointmentApprovals`.
 */
export const getAppointmentForApproval = onCall(async (request) => {
  const uid = requireUid(request);
  const rawData = request.data;
  if (rawData == null || typeof rawData !== "object" || Array.isArray(rawData)) {
    throw new HttpsError("invalid-argument", "Invalid appointment lookup request.");
  }
  const input = rawData as {appointmentId?: unknown};
  if (typeof input.appointmentId !== "string") {
    throw new HttpsError("invalid-argument", "Invalid appointment ID.");
  }
  return getAuthorizedAppointmentForApproval(uid, input.appointmentId);
});
