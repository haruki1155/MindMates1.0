import {canonicalAppointmentStatus} from "./appointment_lifecycle";

// A proposed replacement does not supersede the original appointment until it
// is accepted. Reminders therefore remain anchored to `scheduledAt`.
export const REMINDER_ELIGIBLE_APPOINTMENT_STATUSES = [
  "confirmed",
  "reschedule_proposed",
] as const;

const eligibleStatuses = new Set<string>(REMINDER_ELIGIBLE_APPOINTMENT_STATUSES);

export function isReminderEligibleAppointmentStatus(status: unknown): boolean {
  return eligibleStatuses.has(canonicalAppointmentStatus(status));
}

export function isAppointmentReminderEnabled(
  preferences: Record<string, unknown> | null | undefined,
  stage: "twentyFourHour" | "oneHour",
): boolean {
  const field = stage === "twentyFourHour"
    ? "appointment24HourEnabled"
    : "appointment1HourEnabled";
  return preferences?.[field] !== false;
}
