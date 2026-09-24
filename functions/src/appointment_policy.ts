export type AppointmentBookingPolicy = {
  maxActiveAppointments: number | null;
  maxPendingAppointments: number | null;
  minimumLeadTimeMinutes: number | null;
  maximumBookingDaysAhead: number | null;
  cancellationCutoffMinutes: number | null;
  rateLimitWindowMinutes: number | null;
  rateLimitCount: number | null;
  staleRequestExpiryHours: number | null;
  requireCancellationReason: boolean;
};

export const defaultAppointmentBookingPolicy: AppointmentBookingPolicy = {
  maxActiveAppointments: null,
  maxPendingAppointments: null,
  minimumLeadTimeMinutes: null,
  maximumBookingDaysAhead: null,
  cancellationCutoffMinutes: null,
  rateLimitWindowMinutes: null,
  rateLimitCount: null,
  staleRequestExpiryHours: null,
  requireCancellationReason: false,
};

const numericFields = [
  "maxActiveAppointments", "maxPendingAppointments", "minimumLeadTimeMinutes",
  "maximumBookingDaysAhead", "cancellationCutoffMinutes", "rateLimitWindowMinutes",
  "rateLimitCount", "staleRequestExpiryHours",
] as const;

export function appointmentBookingPolicy(value: unknown): AppointmentBookingPolicy {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return {...defaultAppointmentBookingPolicy};
  }
  const source = value as Record<string, unknown>;
  const policy = numericFields.reduce((policy, field) => {
    const raw = source[field];
    policy[field] = typeof raw === "number" && Number.isInteger(raw) && raw > 0 ? raw : null;
    return policy;
  }, {...defaultAppointmentBookingPolicy});
  policy.requireCancellationReason = source.requireCancellationReason === true;
  return policy;
}

export function bookingPolicyViolation(
  policy: AppointmentBookingPolicy,
  scheduledMillis: number,
  nowMillis = Date.now(),
): string | null {
  if (policy.minimumLeadTimeMinutes !== null &&
      scheduledMillis < nowMillis + policy.minimumLeadTimeMinutes * 60_000) {
    return "Choose an appointment after the minimum booking lead time.";
  }
  if (policy.maximumBookingDaysAhead !== null &&
      scheduledMillis > nowMillis + policy.maximumBookingDaysAhead * 86_400_000) {
    return "Choose an appointment within the permitted booking window.";
  }
  return null;
}
