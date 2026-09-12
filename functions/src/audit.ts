import {FieldValue, Transaction} from "firebase-admin/firestore";

export const AUDIT_CATEGORIES = {
  authentication: "AUTHENTICATION",
  userManagement: "USER_MANAGEMENT",
  profiling: "PROFILING",
  appointments: "APPOINTMENTS",
  schedule: "SCHEDULE",
  inquiries: "INQUIRIES",
  reports: "REPORTS",
  system: "SYSTEM",
  security: "SECURITY",
} as const;

export type AuditCategory = typeof AUDIT_CATEGORIES[keyof typeof AUDIT_CATEGORIES];

export type AuditWrite = {
  actorId: string;
  actorNameSnapshot: string;
  actorRoleSnapshot: string;
  action: string;
  category: AuditCategory;
  targetType?: string;
  targetId?: string;
  metadata?: Record<string, unknown>;
};

export const AUDIT_ACTIONS = [
  "STAFF_SIGNED_IN", "STAFF_SIGNED_OUT", "PASSWORD_CHANGED", "SESSION_REVOKED",
  "STAFF_ACCOUNT_VIEWED", "STAFF_ROLE_CHANGED", "STAFF_ACCESS_REVOKED",
  "STAFF_ACCOUNT_SUSPENDED", "STAFF_ACCOUNT_REACTIVATED", "STAFF_REGISTRATION_APPROVED",
  "STAFF_REGISTRATION_REJECTED", "STAFF_ACCESS_REQUEST_SUBMITTED", "STAFF_ACCESS_REQUEST_VIEWED",
  "STAFF_ACCESS_REQUEST_MORE_INFO_REQUIRED", "STAFF_ACCESS_REQUEST_APPROVED", "STAFF_ROLE_ASSIGNED",
  "STAFF_ACCOUNT_ACTIVATED", "STUDENT_PROFILE_VIEWED", "ASSESSMENT_SUMMARY_VIEWED",
  "ASSESSMENT_HISTORY_VIEWED", "COUNSELING_HISTORY_VIEWED", "APPOINTMENT_VIEWED", "APPOINTMENT_ADJUSTMENT_REQUESTED",
  "APPOINTMENT_CONFIRMED", "APPOINTMENT_RESCHEDULED", "APPOINTMENT_COMPLETED",
  "APPOINTMENT_MARKED_NO_SHOW", "APPOINTMENT_CANCELLED", "SCHEDULE_CREATED",
  "SCHEDULE_UPDATED", "SCHEDULE_SLOT_CREATED", "SCHEDULE_SLOT_UPDATED",
  "SCHEDULE_SLOT_REMOVED", "COUNSELOR_AVAILABILITY_CHANGED", "INQUIRY_VIEWED",
  "INQUIRY_RESPONDED", "INQUIRY_STATUS_CHANGED", "INQUIRY_RESOLVED", "REPORT_VIEWED",
  "REPORT_GENERATED", "REPORT_EXPORTED_PDF", "REPORT_EXPORTED_CSV", "REPORT_EXPORTED_XLSX",
  "ACADEMIC_YEAR_CREATED", "ACADEMIC_YEAR_CLOSED", "ACADEMIC_YEAR_CHANGED",
  "POPULATION_SNAPSHOT_CREATED", "POPULATION_SNAPSHOT_UPDATED",
] as const;

export type AuditAction = typeof AUDIT_ACTIONS[number];

/** Server-authoritative, append-only audit record writer. Never accept actor data from clients. */
export function writeAudit(transaction: Transaction, db: FirebaseFirestore.Firestore, event: AuditWrite): void {
  const ref = db.collection("admin_audit_logs").doc();
  transaction.create(ref, {
    actorId: event.actorId,
    actorNameSnapshot: event.actorNameSnapshot,
    actorRoleSnapshot: event.actorRoleSnapshot,
    action: event.action,
    category: event.category,
    targetType: event.targetType ?? null,
    targetId: event.targetId ?? null,
    metadata: event.metadata ?? {},
    sessionId: null,
    timestamp: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    targetUserId: event.targetType === "staff" ? event.targetId : null,
  });
}

export function actorName(data: FirebaseFirestore.DocumentData): string {
  const name = String(data.name ?? `${data.firstName ?? ""} ${data.lastName ?? ""}`).trim();
  return name || String(data.email ?? "Administrator");
}
