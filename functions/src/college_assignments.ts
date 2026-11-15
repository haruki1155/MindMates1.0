// Pure validation for college-based PACC staff assignments. No Firebase
// imports: the callable reads the target and colleges, this decides.
//
// Assignments live on users/{uid}.assignedCollegeIds (the colleges a staff
// member serves). users/{uid}.collegeId is the staff member's own home college
// and is deliberately not touched here.

export type CollegeAssignmentErrorCode =
  | "role-mismatch"
  | "unknown-college"
  | "inactive-college"
  | "inactive-staff"
  | "stale-revision"
  | "too-many"
  | "invalid-id";

export class CollegeAssignmentError extends Error {
  constructor(public readonly code: CollegeAssignmentErrorCode, message: string) {
    super(message);
    this.name = "CollegeAssignmentError";
  }
}

export const MAX_ASSIGNED_COLLEGES = 20;
const COLLEGE_ID = /^[A-Za-z0-9_-]{1,128}$/;
const ASSIGNABLE_ROLES = new Set(["portalStaff", "counselor"]);

export type CollegeAssignmentPlan = {
  changed: boolean;
  before: string[];
  next: string[];
  added: string[];
  removed: string[];
  /** The stored revision the plan was checked against. */
  revision: number;
};

function storedIds(value: unknown): string[] {
  return Array.isArray(value) ? [...new Set(value.filter((id): id is string => typeof id === "string" && id.length > 0))].sort() : [];
}

function lifecycleActive(target: Record<string, unknown>): boolean {
  const staffStatus = target.staffAccountStatus;
  const accountStatus = target.accountStatus;
  return (staffStatus == null || staffStatus === "approved") && (accountStatus == null || accountStatus === "active");
}

export function planCollegeAssignmentChange(input: {
  target: Record<string, unknown> | null;
  requested: unknown;
  colleges: Map<string, {active: boolean}>;
  expectedRevision: unknown;
}): CollegeAssignmentPlan {
  const {target, requested, colleges, expectedRevision} = input;
  if (!target || !ASSIGNABLE_ROLES.has(String(target.accessRole ?? ""))) {
    throw new CollegeAssignmentError("role-mismatch", "Only PACC staff and counselor accounts can be assigned to colleges.");
  }
  if (!Array.isArray(requested) || requested.some((id) => typeof id !== "string" || !COLLEGE_ID.test(id))) {
    throw new CollegeAssignmentError("invalid-id", "Provide a list of valid college IDs.");
  }
  const next = [...new Set(requested as string[])].sort();
  if (next.length > MAX_ASSIGNED_COLLEGES) {
    throw new CollegeAssignmentError("too-many", `A staff member can serve at most ${MAX_ASSIGNED_COLLEGES} colleges.`);
  }
  const unknown = next.filter((id) => !colleges.has(id));
  if (unknown.length > 0) {
    throw new CollegeAssignmentError("unknown-college", `Unknown college: ${unknown.join(", ")}.`);
  }

  const revisionValue = target.collegeAssignmentRevision;
  const revision = Number.isInteger(revisionValue) && Number(revisionValue) >= 0 ? Number(revisionValue) : 0;
  if (!Number.isInteger(expectedRevision) || expectedRevision !== revision) {
    throw new CollegeAssignmentError("stale-revision", "These college assignments were updated by someone else. Reload and try again.");
  }

  const before = storedIds(target.assignedCollegeIds);
  const added = next.filter((id) => !before.includes(id));
  const removed = before.filter((id) => !next.includes(id));
  if (added.length > 0) {
    // Removals are always allowed so suspended accounts and archived colleges
    // can be cleaned up; only new responsibilities need an active account and
    // an active college.
    if (!lifecycleActive(target)) {
      throw new CollegeAssignmentError("inactive-staff", "Only approved, active staff accounts can receive new college assignments.");
    }
    const inactive = added.filter((id) => colleges.get(id)?.active !== true);
    if (inactive.length > 0) {
      throw new CollegeAssignmentError("inactive-college", `Archived colleges cannot be newly assigned: ${inactive.join(", ")}.`);
    }
  }
  return {changed: added.length > 0 || removed.length > 0, before, next, added, removed, revision};
}
