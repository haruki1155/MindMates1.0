export function allowedAppointmentActions(status: string): string[] {
  switch (status) {
  case "confirmed": return ["completed", "not_attended"];
  case "reschedule_proposed": return ["confirmed", "reschedule_proposed"];
  case "requested": return ["confirmed", "declined", "reschedule_proposed"];
  default: return [];
  }
}

export function appointmentDateHasArrived(scheduledAt: Date, now: Date): boolean {
  const manilaOffset = 8 * 60 * 60 * 1000;
  return new Date(scheduledAt.getTime() + manilaOffset).toISOString().slice(0, 10) <=
    new Date(now.getTime() + manilaOffset).toISOString().slice(0, 10);
}
