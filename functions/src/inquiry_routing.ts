// Pure routing decisions for student inquiries. No Firebase imports.
//
// An inquiry is routed to every eligible PACC staff member or counselor whose
// users/{uid}.assignedCollegeIds contains the student's verified college
// (users/{studentUid}.collegeId). Nobody's home college is ever changed.
// Policy that PACC has not confirmed (primary/backup counselor, named
// escalation owner, automatic escalation timing) is deliberately absent.

export type RoutingReason = "missing_college" | "unverified_profile" | "unknown_college" | "no_eligible_staff";

export type RoutingDecision = {
  routingStatus: "routed" | "needs_triage";
  routingReason: RoutingReason | null;
  collegeId: string;
  assigneeIds: string[];
  assigneeLabels: Record<string, string>;
};

export type AuthState = {disabled: boolean; emailVerified: boolean} | null;

export type Candidate = {uid: string; label: string; profile: Record<string, unknown>; auth: AuthState};

export type InquiryRoutingErrorCode = "stale-revision" | "ineligible-assignee" | "invalid-assignees";

export class InquiryRoutingError extends Error {
  constructor(public readonly code: InquiryRoutingErrorCode, message: string) {
    super(message);
    this.name = "InquiryRoutingError";
  }
}

export const MAX_INQUIRY_ASSIGNEES = 10;
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const ASSIGNABLE_ROLES = new Set(["portalStaff", "counselor"]);

/** Same gates as functions/src/access.ts::requireStaff, applied to a candidate. */
export function isEligibleAssignee(profile: Record<string, unknown>, auth: AuthState): boolean {
  if (!auth || auth.disabled || !auth.emailVerified) return false;
  if (!ASSIGNABLE_ROLES.has(String(profile.accessRole ?? ""))) return false;
  const staffStatus = profile.staffAccountStatus;
  const accountStatus = profile.accountStatus;
  return (staffStatus == null || staffStatus === "approved") && (accountStatus == null || accountStatus === "active");
}

function serves(profile: Record<string, unknown>, collegeId: string): boolean {
  return Array.isArray(profile.assignedCollegeIds) && profile.assignedCollegeIds.includes(collegeId);
}

export function decideRouting(input: {
  student: Record<string, unknown> | null;
  collegeExists: boolean;
  candidates: Candidate[];
}): RoutingDecision {
  const triage = (routingReason: RoutingReason, collegeId = ""): RoutingDecision =>
    ({routingStatus: "needs_triage", routingReason, collegeId, assigneeIds: [], assigneeLabels: {}});
  const {student} = input;
  const rawCollege = typeof student?.collegeId === "string" ? student.collegeId.trim() : "";
  if (!student || !ID.test(rawCollege)) return triage("missing_college");
  if (student.verificationStatus !== "verified") return triage("unverified_profile");
  if (!input.collegeExists) return triage("unknown_college");

  const eligible = input.candidates
    .filter((c) => ID.test(c.uid) && serves(c.profile, rawCollege) && isEligibleAssignee(c.profile, c.auth))
    .sort((a, b) => a.uid.localeCompare(b.uid));
  if (eligible.length === 0) return triage("no_eligible_staff", rawCollege);
  return {
    routingStatus: "routed",
    routingReason: null,
    collegeId: rawCollege,
    assigneeIds: eligible.map((c) => c.uid),
    assigneeLabels: Object.fromEntries(eligible.map((c) => [c.uid, c.label])),
  };
}

export type ReassignmentPlan = {
  assigneeIds: string[];
  assigneeLabels: Record<string, string>;
  added: string[];
  removed: string[];
  /** Assignees who do not serve the inquiry's college (allowed, recorded in audit). */
  outOfCollege: string[];
  ownerId: string | null;
  revision: number;
};

export function planReassignment(input: {
  inquiry: Record<string, unknown>;
  requested: unknown;
  candidates: Map<string, {label: string; profile: Record<string, unknown>; auth: AuthState}>;
  expectedRevision: unknown;
}): ReassignmentPlan {
  const {inquiry, requested, candidates} = input;
  if (!Array.isArray(requested) || requested.some((id) => typeof id !== "string" || !ID.test(id))) {
    throw new InquiryRoutingError("invalid-assignees", "Choose valid staff accounts.");
  }
  const next = [...new Set(requested as string[])].sort();
  if (next.length < 1 || next.length > MAX_INQUIRY_ASSIGNEES) {
    throw new InquiryRoutingError("invalid-assignees", `Choose between 1 and ${MAX_INQUIRY_ASSIGNEES} staff accounts.`);
  }
  const storedRevision = Number.isInteger(inquiry.routingRevision) ? Number(inquiry.routingRevision) : 0;
  if (!Number.isInteger(input.expectedRevision) || input.expectedRevision !== storedRevision) {
    throw new InquiryRoutingError("stale-revision", "This inquiry was updated by someone else. Reload and try again.");
  }
  const ineligible = next.filter((uid) => {
    const c = candidates.get(uid);
    return !c || !isEligibleAssignee(c.profile, c.auth);
  });
  if (ineligible.length > 0) {
    throw new InquiryRoutingError("ineligible-assignee", "Only approved, active PACC staff or counselor accounts can be assigned.");
  }
  const before = Array.isArray(inquiry.assigneeIds) ? (inquiry.assigneeIds as unknown[]).filter((v): v is string => typeof v === "string") : [];
  const collegeId = typeof inquiry.collegeId === "string" ? inquiry.collegeId : "";
  const owner = typeof inquiry.ownerId === "string" ? inquiry.ownerId : null;
  return {
    assigneeIds: next,
    assigneeLabels: Object.fromEntries(next.map((uid) => [uid, candidates.get(uid)!.label])),
    added: next.filter((uid) => !before.includes(uid)),
    removed: before.filter((uid) => !next.includes(uid)).sort(),
    outOfCollege: next.filter((uid) => !collegeId || !serves(candidates.get(uid)!.profile, collegeId)),
    ownerId: owner && next.includes(owner) ? owner : null,
    revision: storedRevision + 1,
  };
}

export const assigneeNotificationId = (inquiryId: string, uid: string): string => `portal_inquiry_${inquiryId}_${uid}`;
export const triageNotificationId = (inquiryId: string): string => `portal_inquiry_triage_${inquiryId}`;
export const escalationNotificationId = (inquiryId: string, revision: number): string =>
  `portal_inquiry_escalation_${inquiryId}_${revision}`;
