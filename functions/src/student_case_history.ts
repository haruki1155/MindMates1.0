// Pure rules for a student's case history (evaluator requirement #9). No
// Firebase reads: the callable loads the profiles and appointments, this
// decides who may see them, in what order, and which fields leave the server.
import {Timestamp} from "firebase-admin/firestore";

import {canonicalAppointmentStatus} from "./appointment_lifecycle";

type Doc = Record<string, unknown>;

export type CaseHistoryErrorCode = "permission-denied" | "not-found" | "failed-precondition" | "invalid-argument";
export class CaseHistoryError extends Error {
  constructor(public readonly code: CaseHistoryErrorCode, message: string) {
    super(message);
    this.name = "CaseHistoryError";
  }
}

export type CaseHistoryBasis = "super_admin" | "college" | "assigned";

export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 50;
/** Upper bound on one student's appointments read per call. */
export const MAX_HISTORY_RECORDS = 500;

const STAFF_ROLES = new Set(["portalStaff", "counselor", "admin"]);
const NOT_AUTHORIZED = "You are not authorized to view this student's case history.";

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/** A staff account (by accessRole or the legacy role) is never a case-history subject. */
function isStaffAccount(profile: Doc): boolean {
  return STAFF_ROLES.has(text(profile.accessRole)) || ["admin", "counselor"].includes(text(profile.role).toLowerCase());
}

/**
 * Who may read a student's history. `actor` has already passed requireClinical
 * (approved, active, email-verified counselor or admin).
 */
export function decideCaseHistoryAccess(input: {
  actorId: string;
  actor: Doc;
  superAdminUid: string;
  target: Doc | null;
  /** Whether any of the student's appointments has assignedStaffId == actorId. */
  assignedToActor: boolean;
}): CaseHistoryBasis {
  const {actorId, actor, superAdminUid, target, assignedToActor} = input;
  const isSuperAdmin = superAdminUid !== "" && actorId === superAdminUid && text(actor.accessRole) === "admin";
  if (isSuperAdmin) {
    if (!target) throw new CaseHistoryError("not-found", "Student not found.");
    if (isStaffAccount(target)) throw new CaseHistoryError("failed-precondition", "That account is not a student.");
    return "super_admin";
  }
  // Counselors get one answer for unknown, staff and out-of-scope targets so
  // the callable cannot be used to discover accounts.
  if (text(actor.accessRole) !== "counselor" || !target || isStaffAccount(target)) {
    throw new CaseHistoryError("permission-denied", NOT_AUTHORIZED);
  }
  const collegeId = text(target.collegeId);
  const served = Array.isArray(actor.assignedCollegeIds) ? actor.assignedCollegeIds : [];
  if (target.verificationStatus === "verified" && collegeId !== "" && served.includes(collegeId)) return "college";
  if (assignedToActor) return "assigned";
  throw new CaseHistoryError("permission-denied", NOT_AUTHORIZED);
}

function millisOf(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

/** scheduledAt, else createdAt, else null (sorted last). */
export function sortMillis(data: Doc): number | null {
  return millisOf(data.scheduledAt) ?? millisOf(data.createdAt);
}

type Keyed = {id: string; data: Doc};

function compare(a: {millis: number | null; id: string}, b: {millis: number | null; id: string}): number {
  if (a.millis !== b.millis) {
    if (a.millis == null) return 1;
    if (b.millis == null) return -1;
    return b.millis - a.millis;
  }
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

/** Newest first; records without a timestamp last; document ID breaks ties. */
export function sortCaseHistory<T extends Keyed>(docs: T[]): T[] {
  return [...docs].sort((a, b) => compare({millis: sortMillis(a.data), id: a.id}, {millis: sortMillis(b.data), id: b.id}));
}

export function encodeCursor(millis: number | null, id: string): string {
  return `${millis == null ? "none" : millis}|${id}`;
}

export function decodeCursor(value: unknown): {millis: number | null; id: string} {
  const raw = typeof value === "string" ? value : "";
  const split = raw.indexOf("|");
  const head = split > 0 ? raw.slice(0, split) : "";
  const id = split > 0 ? raw.slice(split + 1) : "";
  if (!id || (head !== "none" && !/^-?\d{1,16}$/.test(head))) {
    throw new CaseHistoryError("invalid-argument", "The history page cursor is invalid. Reload the history.");
  }
  return {millis: head === "none" ? null : Number(head), id};
}

export function pageSizeOf(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return DEFAULT_PAGE_SIZE;
  return Math.min(MAX_PAGE_SIZE, Math.max(1, Math.floor(value)));
}

/** The page that starts strictly after `cursor` in `sorted` order. */
export function pageCaseHistory<T extends Keyed>(sorted: T[], cursor: string | null, pageSize: number): {items: T[]; nextCursor: string | null} {
  const after = cursor == null ? null : decodeCursor(cursor);
  const start = after == null ? 0 : sorted.findIndex((doc) => compare({millis: sortMillis(doc.data), id: doc.id}, after) > 0);
  const items = start < 0 ? [] : sorted.slice(start, start + pageSize);
  const last = items[items.length - 1];
  const more = start >= 0 && start + pageSize < sorted.length;
  return {items, nextCursor: more && last ? encodeCursor(sortMillis(last.data), last.id) : null};
}

function iso(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}

/**
 * The fields of one appointment that may leave the server in a history.
 * Contact details, staff-only notes and the clinical_notes / history
 * subcollections are never included.
 */
export function caseHistoryEntry(id: string, data: Doc) {
  return {
    id,
    status: canonicalAppointmentStatus(data.status),
    scheduledAt: iso(data.scheduledAt),
    scheduledTime: text(data.scheduledTime),
    createdAt: iso(data.createdAt),
    completedAt: iso(data.completedAt),
    archived: data.archivedAt != null,
    archivedAt: iso(data.archivedAt),
    counselorName: text(data.counselorName) || text(data.actionByName),
    location: text(data.location),
    concern: text(data.concern),
    followUpStatus: text(data.followUpStatus),
    hasSchedule: data.scheduledAt instanceof Timestamp,
  };
}

export type CaseHistoryEntry = ReturnType<typeof caseHistoryEntry>;

/** Display name from the student's profile, never from appointment text. */
export function studentDisplayName(profile: Doc): string {
  const full = text(profile.fullName) || text(profile.name) || `${text(profile.firstName)} ${text(profile.lastName)}`.trim();
  return full || "Student";
}
