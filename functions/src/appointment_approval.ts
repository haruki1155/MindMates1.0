// Pure decisions for college-scoped clinical appointment approval. No
// Firebase imports. The student's verified college comes from
// users/{studentUid}.collegeId; a counselor serves the colleges in
// users/{counselorUid}.assignedCollegeIds (PR #3). Nobody's home college is
// changed here.

export type ApprovalScopeReason = "missing_college" | "unverified_profile" | "unknown_college" | "no_eligible_counselor";

export type ApprovalScope = {
  scope: "college" | "exception";
  collegeId: string;
  reason: ApprovalScopeReason | null;
};

export type ApprovalMode = "college" | "admin_triage" | "admin_override";

export type ApprovalAuthority = {
  mode: ApprovalMode;
  collegeId: string;
  scopeReason: ApprovalScopeReason | null;
  exceptionReason: string | null;
};

export type AuthState = {disabled: boolean; emailVerified: boolean} | null;

export type ApprovalErrorCode = "wrong_college" | "needs_triage" | "not_super_admin" | "override_reason_required" | "operational_staff" | "admin_read_only";

export class ApprovalError extends Error {
  constructor(public readonly code: ApprovalErrorCode, message: string) {
    super(message);
    this.name = "ApprovalError";
  }
}

const ID = /^[A-Za-z0-9_-]{1,128}$/;

/** Approved, active, email-verified counselor (same gates as requireStaff). */
export function isEligibleCounselor(profile: Record<string, unknown>, auth: AuthState): boolean {
  if (!auth || auth.disabled || !auth.emailVerified) return false;
  if (profile.accessRole !== "counselor") return false;
  const staffStatus = profile.staffAccountStatus;
  const accountStatus = profile.accountStatus;
  return (staffStatus == null || staffStatus === "approved") && (accountStatus == null || accountStatus === "active");
}

export function decideApprovalScope(input: {
  student: Record<string, unknown> | null;
  collegeExists: boolean;
  counselors: Array<{profile: Record<string, unknown>; auth: AuthState}>;
}): ApprovalScope {
  const exception = (reason: ApprovalScopeReason, collegeId = ""): ApprovalScope => ({scope: "exception", collegeId, reason});
  const collegeId = typeof input.student?.collegeId === "string" ? input.student.collegeId.trim() : "";
  if (!input.student || !ID.test(collegeId)) return exception("missing_college");
  if (input.student.verificationStatus !== "verified") return exception("unverified_profile");
  if (!input.collegeExists) return exception("unknown_college");
  const served = input.counselors.some(({profile, auth}) =>
    Array.isArray(profile.assignedCollegeIds) && profile.assignedCollegeIds.includes(collegeId) && isEligibleCounselor(profile, auth));
  if (!served) return exception("no_eligible_counselor", collegeId);
  return {scope: "college", collegeId, reason: null};
}

/**
 * Who may act on an appointment with the given scope. The actor has already
 * passed the clinical staff gate (approved, active, verified counselor/admin).
 */
export function decideApprovalAuthority(input: {
  actor: {role: string; isSuperAdmin: boolean; assignedCollegeIds: unknown};
  scope: ApprovalScope;
  exceptionReason?: unknown;
}): ApprovalAuthority {
  const {actor, scope} = input;
  if (actor.role === "counselor") {
    if (scope.scope === "exception") {
      throw new ApprovalError("needs_triage", "This appointment needs administrative review because its college cannot be confirmed or has no assigned counselor.");
    }
    const serves = Array.isArray(actor.assignedCollegeIds) && actor.assignedCollegeIds.includes(scope.collegeId);
    if (!serves) throw new ApprovalError("wrong_college", "Only counselors assigned to this student's college can act on this appointment.");
    return {mode: "college", collegeId: scope.collegeId, scopeReason: null, exceptionReason: null};
  }
  if (actor.role === "admin") {
    throw new ApprovalError(
      "admin_read_only",
      "Administrators have read-only access to appointments. Only assigned counselors can modify appointments.",
    );
  }
  throw new ApprovalError("operational_staff", "Counselor access is required for clinical appointment actions.");
}
