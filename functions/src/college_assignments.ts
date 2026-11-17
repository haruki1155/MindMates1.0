// Pure validation for counselor-only college assignments. No Firebase
// imports: callables load user/college state and ownership locks, this decides.
//
// Assignments live on users/{uid}.assignedCollegeIds (the colleges a counselor
// serves). users/{uid}.collegeId is the person's own home college and is
// deliberately not touched here.

export type CollegeAssignmentErrorCode =
  | "role-mismatch"
  | "unknown-college"
  | "inactive-college"
  | "inactive-staff"
  | "stale-revision"
  | "too-many"
  | "invalid-id"
  | "college-already-assigned"
  | "college-conflict";

export class CollegeAssignmentError extends Error {
  constructor(public readonly code: CollegeAssignmentErrorCode, message: string) {
    super(message);
    this.name = "CollegeAssignmentError";
  }
}

export const MAX_ASSIGNED_COLLEGES = 20;
const COLLEGE_ID = /^[A-Za-z0-9_-]{1,128}$/;

export type CollegeAssignmentPlan = {
  changed: boolean;
  before: string[];
  next: string[];
  added: string[];
  removed: string[];
  /** The stored revision the plan was checked against. */
  revision: number;
  legacyStaffCleanup: boolean;
};

export type CounselorCollegeTransferPlan = {
  changed: boolean;
  collegeId: string;
  beforeOwnerIds: string[];
  afterOwnerIds: string[];
  conflictResolved: boolean;
  removals: Array<{
    userId: string;
    before: string[];
    next: string[];
    revision: number;
    nextRevision: number;
  }>;
  addition: {
    userId: string;
    before: string[];
    next: string[];
    revision: number;
    nextRevision: number;
  } | null;
};

export function storedAssignedCollegeIds(value: unknown): string[] {
  return Array.isArray(value)
    ? [...new Set(value.filter((id): id is string => typeof id === "string" && id.length > 0))].sort()
    : [];
}

export function storedAssignmentRevision(target: Record<string, unknown>): number {
  const revisionValue = target.collegeAssignmentRevision;
  return Number.isInteger(revisionValue) && Number(revisionValue) >= 0 ? Number(revisionValue) : 0;
}

export function lifecycleActive(target: Record<string, unknown>): boolean {
  const staffStatus = target.staffAccountStatus;
  const accountStatus = target.accountStatus;
  return (staffStatus == null || staffStatus === "approved") && (accountStatus == null || accountStatus === "active");
}

export function planCollegeAssignmentChange(input: {
  target: Record<string, unknown> | null;
  requested: unknown;
  colleges: Map<string, {active: boolean}>;
  expectedRevision: unknown;
  /** Map from collegeId -> sorted distinct UIDs of OTHER counselors already serving that college. */
  collegeOwners?: Map<string, string[]>;
}): CollegeAssignmentPlan {
  const {target, requested, colleges, expectedRevision, collegeOwners} = input;
  if (!Array.isArray(requested) || requested.some((id) => typeof id !== "string" || !COLLEGE_ID.test(id))) {
    throw new CollegeAssignmentError("invalid-id", "Provide a list of valid college IDs.");
  }
  const role = String(target?.accessRole ?? "");
  if (!target || (role !== "counselor" && role !== "portalStaff")) {
    throw new CollegeAssignmentError("role-mismatch", "Only counselor accounts can be assigned to colleges.");
  }

  const next = [...new Set(requested as string[])].sort();
  const before = storedAssignedCollegeIds(target.assignedCollegeIds);
  const added = next.filter((id) => !before.includes(id));
  const removed = before.filter((id) => !next.includes(id));

  if (role === "portalStaff") {
    if (added.length > 0 || before.length === 0) {
      throw new CollegeAssignmentError(
        "role-mismatch",
        "Only counselor accounts can be assigned to colleges. Portal staff cannot receive new college assignments.",
      );
    }
    const unknown = next.filter((id) => !colleges.has(id));
    if (unknown.length > 0) {
      throw new CollegeAssignmentError("unknown-college", `Unknown college: ${unknown.join(", ")}.`);
    }
    const revision = storedAssignmentRevision(target);
    if (!Number.isInteger(expectedRevision) || expectedRevision !== revision) {
      throw new CollegeAssignmentError("stale-revision", "These college assignments were updated by someone else. Reload and try again.");
    }
    return {changed: removed.length > 0, before, next, added: [], removed, revision, legacyStaffCleanup: true};
  }

  if (next.length > MAX_ASSIGNED_COLLEGES) {
    throw new CollegeAssignmentError("too-many", `A counselor can serve at most ${MAX_ASSIGNED_COLLEGES} colleges.`);
  }
  const unknown = next.filter((id) => !colleges.has(id));
  if (unknown.length > 0) {
    throw new CollegeAssignmentError("unknown-college", `Unknown college: ${unknown.join(", ")}.`);
  }

  const revision = storedAssignmentRevision(target);
  if (!Number.isInteger(expectedRevision) || expectedRevision !== revision) {
    throw new CollegeAssignmentError("stale-revision", "These college assignments were updated by someone else. Reload and try again.");
  }

  if (added.length > 0) {
    // Removals are always allowed so suspended counselors and archived colleges
    // can be cleaned up; only new responsibilities need an active counselor
    // account, an active college, and no existing counselor owner.
    if (!lifecycleActive(target)) {
      throw new CollegeAssignmentError("inactive-staff", "Only approved, active counselor accounts can receive new college assignments.");
    }
    const inactive = added.filter((id) => colleges.get(id)?.active !== true);
    if (inactive.length > 0) {
      throw new CollegeAssignmentError("inactive-college", `Archived colleges cannot be newly assigned: ${inactive.join(", ")}.`);
    }
    for (const id of added) {
      const owners = collegeOwners?.get(id) ?? [];
      if (owners.length > 1) {
        throw new CollegeAssignmentError(
          "college-conflict",
          "This college currently has multiple assigned counselors. Resolve the conflict through the authorized transfer process.",
        );
      }
      if (owners.length === 1) {
        throw new CollegeAssignmentError(
          "college-already-assigned",
          "This college is already assigned to another counselor. Reassign it through the authorized transfer process.",
        );
      }
    }
  }
  return {changed: added.length > 0 || removed.length > 0, before, next, added, removed, revision, legacyStaffCleanup: false};
}

export function planCollegeCounselorTransfer(input: {
  collegeId: string;
  college: {active: boolean} | null;
  currentOwners: Array<{uid: string; profile: Record<string, unknown>}>;
  targetCounselor: {uid: string; profile: Record<string, unknown>} | null;
  expectedOwnerIds: unknown;
  expectedRevisions: unknown;
}): CounselorCollegeTransferPlan {
  const {collegeId, college, currentOwners, targetCounselor, expectedOwnerIds, expectedRevisions} = input;
  if (!COLLEGE_ID.test(collegeId)) {
    throw new CollegeAssignmentError("invalid-id", "A valid college ID is required.");
  }
  if (!college) {
    throw new CollegeAssignmentError("unknown-college", `Unknown college: ${collegeId}.`);
  }
  if (!Array.isArray(expectedOwnerIds) || expectedOwnerIds.some((id) => typeof id !== "string")) {
    throw new CollegeAssignmentError("stale-revision", "College counselor ownership details are invalid. Reload and try again.");
  }
  const expectedSorted = [...new Set(expectedOwnerIds as string[])].sort();
  const actualOwners = [...new Map(currentOwners.map((o) => [o.uid, o])).values()]
    .sort((a, b) => a.uid.localeCompare(b.uid));
  const actualOwnerIds = actualOwners.map((o) => o.uid);
  if (
    expectedSorted.length !== actualOwnerIds.length ||
    expectedSorted.some((id, idx) => id !== actualOwnerIds[idx])
  ) {
    throw new CollegeAssignmentError("stale-revision", "College counselor ownership changed. Reload and try again.");
  }

  if (!expectedRevisions || typeof expectedRevisions !== "object" || Array.isArray(expectedRevisions)) {
    throw new CollegeAssignmentError("stale-revision", "Counselor revisions are out of date. Reload and try again.");
  }
  const revMap = expectedRevisions as Record<string, unknown>;
  const involved = new Map<string, Record<string, unknown>>();
  for (const owner of actualOwners) involved.set(owner.uid, owner.profile);
  if (targetCounselor) {
    involved.set(targetCounselor.uid, targetCounselor.profile);
  }
  for (const [uid, profile] of involved.entries()) {
    const storedRev = storedAssignmentRevision(profile);
    if (!Number.isInteger(revMap[uid]) || revMap[uid] !== storedRev) {
      throw new CollegeAssignmentError("stale-revision", "These counselor assignments were updated by someone else. Reload and try again.");
    }
  }

  if (targetCounselor) {
    if (String(targetCounselor.profile.accessRole ?? "") !== "counselor") {
      throw new CollegeAssignmentError("role-mismatch", "Only counselor accounts can be assigned to colleges.");
    }
    const alreadyOwner = actualOwnerIds.includes(targetCounselor.uid);
    if (!alreadyOwner) {
      if (!lifecycleActive(targetCounselor.profile)) {
        throw new CollegeAssignmentError("inactive-staff", "Only approved, active counselor accounts can receive new college assignments.");
      }
      if (!college.active) {
        throw new CollegeAssignmentError("inactive-college", `Archived colleges cannot be newly assigned: ${collegeId}.`);
      }
      const existingIds = storedAssignedCollegeIds(targetCounselor.profile.assignedCollegeIds);
      if (existingIds.length + 1 > MAX_ASSIGNED_COLLEGES) {
        throw new CollegeAssignmentError("too-many", `A counselor can serve at most ${MAX_ASSIGNED_COLLEGES} colleges.`);
      }
    }
  }

  const targetId = targetCounselor?.uid ?? null;
  const removals = actualOwners
    .filter((o) => o.uid !== targetId)
    .map((o) => {
      const before = storedAssignedCollegeIds(o.profile.assignedCollegeIds);
      const next = before.filter((id) => id !== collegeId);
      const revision = storedAssignmentRevision(o.profile);
      return {userId: o.uid, before, next, revision, nextRevision: revision + 1};
    });

  const addition = targetCounselor && !actualOwnerIds.includes(targetCounselor.uid)
    ? (() => {
      const before = storedAssignedCollegeIds(targetCounselor.profile.assignedCollegeIds);
      const next = [...new Set([...before, collegeId])].sort();
      const revision = storedAssignmentRevision(targetCounselor.profile);
      return {userId: targetCounselor.uid, before, next, revision, nextRevision: revision + 1};
    })()
    : null;

  const afterOwnerIds = targetId ? [targetId] : [];
  return {
    changed: removals.length > 0 || addition != null,
    collegeId,
    beforeOwnerIds: actualOwnerIds,
    afterOwnerIds,
    conflictResolved: actualOwnerIds.length > 1 && afterOwnerIds.length <= 1,
    removals,
    addition,
  };
}
