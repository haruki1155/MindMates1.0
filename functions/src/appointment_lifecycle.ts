export type AppointmentActor = "student" | "staff";

export const APPOINTMENT_ACTIVE_STATUSES = new Set([
  "requested",
  "confirmed",
  "reschedule_proposed",
]);

export const APPOINTMENT_TERMINAL_STATUSES = new Set([
  "cancelled",
  "canceled",
  "completed",
  "no_show",
  "noshow",
  "declined",
  "expired",
]);

export function canonicalAppointmentStatus(value: unknown): string {
  const status = String(value ?? "").trim().toLowerCase();
  return ["pending", "upcoming", "reschedule_required"].includes(status)
    ? "requested"
    : status;
}

const transitions: Record<AppointmentActor, Record<string, readonly string[]>> = {
  student: {
    reschedule_proposed: ["confirmed"],
  },
  staff: {
    requested: ["confirmed", "reschedule_proposed"],
    confirmed: ["completed", "no_show", "reschedule_proposed"],
    reschedule_proposed: ["reschedule_proposed"],
  },
};

export function canTransitionAppointment(
  status: unknown,
  actor: AppointmentActor,
  nextStatus: string,
): boolean {
  const current = canonicalAppointmentStatus(status);
  return transitions[actor][current]?.includes(nextStatus) ?? false;
}

export function appointmentActionsFor(
  status: unknown,
  actor: AppointmentActor,
): readonly string[] {
  return transitions[actor][canonicalAppointmentStatus(status)] ?? [];
}
