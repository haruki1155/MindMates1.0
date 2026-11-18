// Pure routing decisions and staff-safe operational projection for student
// inquiries. No Firebase imports.
//
// Automatic clinical routing uses ONLY eligible counselor college assignments
// (users/{uid}.assignedCollegeIds where accessRole == "counselor"), matching
// PR #63's counselor-only college ownership. Operational portalStaff do not
// hold college ownership and never receive automatic clinical assignments;
// operational monitoring uses explicit server-authorized monitoringStaffIds on
// the sanitized status projection instead.

export type RoutingReason = "missing_college" | "unverified_profile" | "unknown_college" | "no_eligible_staff";

export type RoutingDecision = {
  routingStatus: "routed" | "needs_triage";
  routingReason: RoutingReason | null;
  collegeId: string;
  assigneeIds: string[];
  assigneeLabels: Record<string, string>;
  monitoringStaffIds: string[];
  monitoringStaffLabels: Record<string, string>;
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
const ALLOWED_CATEGORIES = new Set(["Service Form", "General", "Academic", "Counseling", "Feedback"]);
const ALLOWED_FORM_LABELS: Record<string, string> = {
  client_feedback: "Client Feedback Form",
  guidance_satisfaction_survey: "Student Satisfaction Survey",
};
const VALID_STATUSES = new Set(["pending", "in_progress", "resolved"]);
const VALID_ROUTING_STATUSES = new Set(["unrouted", "routed", "needs_triage"]);
const VALID_ROUTING_REASONS = new Set(["missing_college", "unverified_profile", "unknown_college", "no_eligible_staff"]);
const VALID_ROUTING_MODES = new Set(["automatic", "manual"]);

function staffLifecycleActive(profile: Record<string, unknown>, auth: AuthState): boolean {
  if (!auth || auth.disabled || !auth.emailVerified) return false;
  const staffStatus = profile.staffAccountStatus;
  const accountStatus = profile.accountStatus;
  return (staffStatus == null || staffStatus === "approved") && (accountStatus == null || accountStatus === "active");
}

/** Active, approved, verified counselor eligible for clinical inquiry handling. */
export function isEligibleCounselorAssignee(profile: Record<string, unknown>, auth: AuthState): boolean {
  return String(profile.accessRole ?? "") === "counselor" && staffLifecycleActive(profile, auth);
}

/** Active, approved, verified operational staff eligible for monitoring assignment only. */
export function isEligibleMonitoringStaff(profile: Record<string, unknown>, auth: AuthState): boolean {
  return String(profile.accessRole ?? "") === "portalStaff" && staffLifecycleActive(profile, auth);
}

/** Backwards-compatible alias: clinical routing eligibility requires counselor role. */
export function isEligibleAssignee(profile: Record<string, unknown>, auth: AuthState): boolean {
  return isEligibleCounselorAssignee(profile, auth);
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
    ({
      routingStatus: "needs_triage",
      routingReason,
      collegeId,
      assigneeIds: [],
      assigneeLabels: {},
      monitoringStaffIds: [],
      monitoringStaffLabels: {},
    });
  const {student} = input;
  const rawCollege = typeof student?.collegeId === "string" ? student.collegeId.trim() : "";
  if (!student || !ID.test(rawCollege)) return triage("missing_college");
  if (student.verificationStatus !== "verified") return triage("unverified_profile");
  if (!input.collegeExists) return triage("unknown_college");

  const eligible = input.candidates
    .filter((c) => ID.test(c.uid) && serves(c.profile, rawCollege) && isEligibleCounselorAssignee(c.profile, c.auth))
    .sort((a, b) => a.uid.localeCompare(b.uid));
  if (eligible.length === 0) return triage("no_eligible_staff", rawCollege);
  return {
    routingStatus: "routed",
    routingReason: null,
    collegeId: rawCollege,
    assigneeIds: eligible.map((c) => c.uid),
    assigneeLabels: Object.fromEntries(eligible.map((c) => [c.uid, c.label])),
    monitoringStaffIds: [],
    monitoringStaffLabels: {},
  };
}

export type ReassignmentPlan = {
  assigneeIds: string[];
  assigneeLabels: Record<string, string>;
  monitoringStaffIds: string[];
  monitoringStaffLabels: Record<string, string>;
  added: string[];
  removed: string[];
  /** Clinical counselor assignees who do not serve the inquiry's college (allowed, recorded in audit). */
  outOfCollege: string[];
  ownerId: string | null;
  revision: number;
};

function sanitizeIdList(raw: unknown): string[] {
  if (!Array.isArray(raw) || raw.some((id) => typeof id !== "string" || !ID.test(id))) {
    throw new InquiryRoutingError("invalid-assignees", "Choose valid staff accounts.");
  }
  return [...new Set(raw as string[])].sort();
}

export function planReassignment(input: {
  inquiry: Record<string, unknown>;
  requested: unknown;
  requestedMonitoring?: unknown;
  candidates: Map<string, {label: string; profile: Record<string, unknown>; auth: AuthState}>;
  expectedRevision: unknown;
}): ReassignmentPlan {
  const {inquiry, requested, requestedMonitoring, candidates} = input;
  const next = sanitizeIdList(requested);
  const existingMonitors = Array.isArray(inquiry.monitoringStaffIds)
    ? [...new Set((inquiry.monitoringStaffIds as unknown[]).filter((v): v is string => typeof v === "string" && ID.test(v)))].sort()
    : [];
  const nextMonitors = requestedMonitoring === undefined ? existingMonitors : sanitizeIdList(requestedMonitoring);

  if (next.length > MAX_INQUIRY_ASSIGNEES || nextMonitors.length > MAX_INQUIRY_ASSIGNEES) {
    throw new InquiryRoutingError("invalid-assignees", `Choose at most ${MAX_INQUIRY_ASSIGNEES} accounts per role.`);
  }
  if (requestedMonitoring === undefined && next.length < 1) {
    throw new InquiryRoutingError("invalid-assignees", `Choose between 1 and ${MAX_INQUIRY_ASSIGNEES} counselor accounts.`);
  }
  if (next.length + nextMonitors.length < 1) {
    throw new InquiryRoutingError("invalid-assignees", "Choose at least 1 counselor or monitoring staff account.");
  }

  const storedRevision = Number.isInteger(inquiry.routingRevision) ? Number(inquiry.routingRevision) : 0;
  if (!Number.isInteger(input.expectedRevision) || input.expectedRevision !== storedRevision) {
    throw new InquiryRoutingError("stale-revision", "This inquiry was updated by someone else. Reload and try again.");
  }
  const ineligibleCounselors = next.filter((uid) => {
    const c = candidates.get(uid);
    return !c || !isEligibleCounselorAssignee(c.profile, c.auth);
  });
  if (ineligibleCounselors.length > 0) {
    throw new InquiryRoutingError("ineligible-assignee", "Only approved, active counselor accounts can handle clinical inquiries.");
  }
  if (requestedMonitoring !== undefined) {
    const ineligibleMonitors = nextMonitors.filter((uid) => {
      const c = candidates.get(uid);
      return !c || !isEligibleMonitoringStaff(c.profile, c.auth);
    });
    if (ineligibleMonitors.length > 0) {
      throw new InquiryRoutingError("ineligible-assignee", "Only approved, active operational staff accounts can monitor inquiry status.");
    }
  }

  const beforeAssignees = Array.isArray(inquiry.assigneeIds)
    ? (inquiry.assigneeIds as unknown[]).filter((v): v is string => typeof v === "string")
    : [];
  const beforeAll = new Set([...beforeAssignees, ...existingMonitors]);
  const nextAll = new Set([...next, ...nextMonitors]);

  const existingLabels = (inquiry.monitoringStaffLabels && typeof inquiry.monitoringStaffLabels === "object")
    ? inquiry.monitoringStaffLabels as Record<string, unknown>
    : {};
  const monitoringStaffLabels = requestedMonitoring === undefined
    ? Object.fromEntries(nextMonitors.map((uid) => [uid, String(existingLabels[uid] ?? candidates.get(uid)?.label ?? "PACC staff")]))
    : Object.fromEntries(nextMonitors.map((uid) => [uid, candidates.get(uid)!.label]));

  const collegeId = typeof inquiry.collegeId === "string" ? inquiry.collegeId : "";
  const owner = typeof inquiry.ownerId === "string" ? inquiry.ownerId : null;
  return {
    assigneeIds: next,
    assigneeLabels: Object.fromEntries(next.map((uid) => [uid, candidates.get(uid)!.label])),
    monitoringStaffIds: nextMonitors,
    monitoringStaffLabels,
    added: [...nextAll].filter((uid) => !beforeAll.has(uid)).sort(),
    removed: [...beforeAll].filter((uid) => !nextAll.has(uid)).sort(),
    outOfCollege: next.filter((uid) => !collegeId || !serves(candidates.get(uid)!.profile, collegeId)),
    ownerId: owner && next.includes(owner) ? owner : null,
    revision: storedRevision + 1,
  };
}

export type InquiryStatusProjection = {
  inquiryId: string;
  collegeId: string;
  category: string;
  formType: string | null;
  operationalLabel: string;
  status: string;
  routingStatus: string;
  routingReason: string | null;
  routingMode: string | null;
  routingRevision: number;
  assigneeIds: string[];
  assigneeLabels: Record<string, string>;
  monitoringStaffIds: string[];
  monitoringStaffLabels: Record<string, string>;
  ownerId: string | null;
  escalationStatus: "requested" | "handled" | null;
  createdAt: unknown;
  acknowledgedAt: unknown;
  resolvedAt: unknown;
  sourceUpdatedAt: unknown;
};

function sanitizeLabels(ids: string[], rawLabels: unknown): Record<string, string> {
  const map = rawLabels && typeof rawLabels === "object" && !Array.isArray(rawLabels)
    ? rawLabels as Record<string, unknown>
    : {};
  const out: Record<string, string> = {};
  for (const uid of ids) {
    const labelText = typeof map[uid] === "string" ? map[uid].trim().slice(0, 80) : "";
    if (labelText) out[uid] = labelText;
  }
  return out;
}

function sanitizeIdArray(raw: unknown): string[] {
  return Array.isArray(raw)
    ? [...new Set(raw.filter((v): v is string => typeof v === "string" && ID.test(v)))].sort()
    : [];
}

/**
 * Builds the sanitized, staff-safe inquiry status projection from a canonical
 * inquiry document. Never includes user-authored `subject`, `message`,
 * `formData`, `email`, `name`, `userId`, `role`, clinical notes/transcripts,
 * or free-text `escalation.reason`.
 */
export function buildInquiryStatusProjection(
  inquiryId: string,
  inquiry: Record<string, unknown>,
  options: {counselorAssigneeIds?: string[]; monitoringStaffIds?: string[]} = {},
): InquiryStatusProjection {
  const rawCategory = typeof inquiry.category === "string" ? inquiry.category.trim() : "";
  const category = ALLOWED_CATEGORIES.has(rawCategory) ? rawCategory : "General";

  const rawFormType = typeof inquiry.formType === "string" ? inquiry.formType.trim() : "";
  const formType = Object.prototype.hasOwnProperty.call(ALLOWED_FORM_LABELS, rawFormType) ? rawFormType : null;
  const operationalLabel = formType
    ? ALLOWED_FORM_LABELS[formType]
    : category === "Service Form"
      ? "Service Form"
      : `${category} Inquiry`;

  const rawStatus = typeof inquiry.status === "string" ? inquiry.status.trim().toLowerCase() : "";
  const status = VALID_STATUSES.has(rawStatus) ? rawStatus : "pending";

  const rawRoutingStatus = typeof inquiry.routingStatus === "string" ? inquiry.routingStatus.trim() : "";
  const routingStatus = VALID_ROUTING_STATUSES.has(rawRoutingStatus) ? rawRoutingStatus : "unrouted";

  const rawReason = typeof inquiry.routingReason === "string" ? inquiry.routingReason.trim() : "";
  const routingReason = VALID_ROUTING_REASONS.has(rawReason) ? rawReason : null;

  const rawMode = typeof inquiry.routingMode === "string" ? inquiry.routingMode.trim() : "";
  const routingMode = VALID_ROUTING_MODES.has(rawMode) ? rawMode : null;

  const routingRevision = Number.isInteger(inquiry.routingRevision) && Number(inquiry.routingRevision) >= 0
    ? Number(inquiry.routingRevision)
    : 0;

  const rawCollegeId = typeof inquiry.collegeId === "string" ? inquiry.collegeId.trim() : "";
  const collegeId = ID.test(rawCollegeId) ? rawCollegeId : "";

  const assigneeIds = options.counselorAssigneeIds
    ? [...new Set(options.counselorAssigneeIds.filter((id) => ID.test(id)))].sort()
    : sanitizeIdArray(inquiry.assigneeIds);
  const monitoringStaffIds = options.monitoringStaffIds
    ? [...new Set(options.monitoringStaffIds.filter((id) => ID.test(id)))].sort()
    : sanitizeIdArray(inquiry.monitoringStaffIds);

  const rawOwnerId = typeof inquiry.ownerId === "string" ? inquiry.ownerId.trim() : "";
  const ownerId = ID.test(rawOwnerId) && assigneeIds.includes(rawOwnerId) ? rawOwnerId : null;

  const escalation = inquiry.escalation && typeof inquiry.escalation === "object" && !Array.isArray(inquiry.escalation)
    ? inquiry.escalation as Record<string, unknown>
    : null;
  const rawEscStatus = typeof escalation?.status === "string" ? escalation.status : "";
  const escalationStatus = rawEscStatus === "requested" || rawEscStatus === "handled" ? rawEscStatus : null;

  return {
    inquiryId,
    collegeId,
    category,
    formType,
    operationalLabel,
    status,
    routingStatus,
    routingReason,
    routingMode,
    routingRevision,
    assigneeIds,
    assigneeLabels: sanitizeLabels(assigneeIds, inquiry.assigneeLabels),
    monitoringStaffIds,
    monitoringStaffLabels: sanitizeLabels(monitoringStaffIds, inquiry.monitoringStaffLabels),
    ownerId,
    escalationStatus,
    createdAt: inquiry.createdAt ?? null,
    acknowledgedAt: inquiry.acknowledgedAt ?? null,
    resolvedAt: inquiry.resolvedAt ?? null,
    sourceUpdatedAt: inquiry.updatedAt ?? inquiry.routedAt ?? inquiry.createdAt ?? null,
  };
}

/**
 * Prevents delayed or out-of-order trigger runs from overwriting a newer
 * projection revision with stale visibility/routing state.
 */
export function shouldWriteInquiryProjection(
  existing: Record<string, unknown> | null | undefined,
  next: InquiryStatusProjection,
): boolean {
  if (!existing) return true;
  const existingRevision = Number.isInteger(existing.routingRevision) && Number(existing.routingRevision) >= 0
    ? Number(existing.routingRevision)
    : 0;
  if (next.routingRevision < existingRevision) return false;
  if (next.routingRevision > existingRevision) return true;
  const serialize = (doc: Record<string, unknown>) => JSON.stringify({
    collegeId: doc.collegeId ?? "",
    category: doc.category ?? "General",
    formType: doc.formType ?? null,
    operationalLabel: doc.operationalLabel ?? "",
    status: doc.status ?? "pending",
    routingStatus: doc.routingStatus ?? "unrouted",
    routingReason: doc.routingReason ?? null,
    routingMode: doc.routingMode ?? null,
    routingRevision: Number.isInteger(doc.routingRevision) ? doc.routingRevision : 0,
    assigneeIds: sanitizeIdArray(doc.assigneeIds),
    monitoringStaffIds: sanitizeIdArray(doc.monitoringStaffIds),
    ownerId: doc.ownerId ?? null,
    escalationStatus: doc.escalationStatus ?? null,
    acknowledged: doc.acknowledgedAt != null,
    resolved: doc.resolvedAt != null,
  });
  return serialize(existing) !== serialize(next as unknown as Record<string, unknown>);
}

export const assigneeNotificationId = (inquiryId: string, uid: string): string => `portal_inquiry_${inquiryId}_${uid}`;
export const triageNotificationId = (inquiryId: string): string => `portal_inquiry_triage_${inquiryId}`;
export const escalationNotificationId = (inquiryId: string, revision: number): string =>
  `portal_inquiry_escalation_${inquiryId}_${revision}`;
