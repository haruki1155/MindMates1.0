export const APPOINTMENT_TIME_ZONE = "Asia/Manila";

// The student booking flow currently exposes hourly starts. Keep that existing
// behavior explicit and server-enforced until PACC approves another interval.
export const appointmentSchedulingPolicy = {
  slotIntervalMinutes: 60,
  maximumBookingDaysAhead: null as number | null,
} as const;

export class AppointmentSchedulingValidationError extends Error {}

type TimestampLike = {toMillis: () => number};
type SecondsLike = {_seconds?: unknown; _nanoseconds?: unknown};

function millisFromValue(value: unknown): number {
  if (typeof value === "number") return value;
  if (value instanceof Date) return value.getTime();
  if (value && typeof value === "object" && "toMillis" in value && typeof (value as TimestampLike).toMillis === "function") {
    return (value as TimestampLike).toMillis();
  }
  if (value && typeof value === "object" && "_seconds" in value) {
    const seconds = Number((value as SecondsLike)._seconds);
    const nanos = Number((value as SecondsLike)._nanoseconds ?? 0);
    return Number.isFinite(seconds) && Number.isFinite(nanos)
      ? seconds * 1000 + Math.floor(nanos / 1000000)
      : Number.NaN;
  }
  return Number.NaN;
}

export function formatAppointmentTime(millis: number): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: APPOINTMENT_TIME_ZONE,
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(new Date(millis));
}

export function validateAppointmentTimestamp(
  value: unknown,
  nowMillis = Date.now(),
  policy = appointmentSchedulingPolicy,
): {millis: number; scheduledTime: string} {
  const millis = millisFromValue(value);
  if (!Number.isSafeInteger(millis) || millis <= 0 || Number.isNaN(new Date(millis).getTime())) {
    throw new AppointmentSchedulingValidationError("Choose a valid appointment time.");
  }
  if (millis <= nowMillis) {
    throw new AppointmentSchedulingValidationError("Choose a future appointment time.");
  }
  const slotMillis = policy.slotIntervalMinutes * 60 * 1000;
  if (!Number.isInteger(policy.slotIntervalMinutes) || policy.slotIntervalMinutes <= 0 || millis % slotMillis !== 0) {
    throw new AppointmentSchedulingValidationError("Choose a supported appointment time slot.");
  }
  if (policy.maximumBookingDaysAhead !== null && millis > nowMillis + policy.maximumBookingDaysAhead * 24 * 60 * 60 * 1000) {
    throw new AppointmentSchedulingValidationError("Choose an appointment within the permitted booking window.");
  }
  return {millis, scheduledTime: formatAppointmentTime(millis)};
}
