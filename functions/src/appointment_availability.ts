import {APPOINTMENT_TIME_ZONE} from "./appointment_scheduling";

export class AppointmentAvailabilityValidationError extends Error {}

const WEEKDAY_NUMBERS: Record<string, number> = {
  Mon: 1,
  Tue: 2,
  Wed: 3,
  Thu: 4,
  Fri: 5,
  Sat: 6,
  Sun: 7,
};
const OFFICE_TIME = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

function minutesSinceMidnight(value: string): number {
  const [hours, minutes] = value.split(":").map(Number);
  return hours * 60 + minutes;
}

function appointmentLocalTime(millis: number): {weekday: number; minutes: number} {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: APPOINTMENT_TIME_ZONE,
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(millis));
  const part = (type: string) => parts.find((item) => item.type === type)?.value;
  const weekday = WEEKDAY_NUMBERS[part("weekday") ?? ""];
  const hours = Number(part("hour"));
  const minutes = Number(part("minute"));
  if (!weekday || !Number.isInteger(hours) || !Number.isInteger(minutes)) {
    throw new AppointmentAvailabilityValidationError("PACC availability is not configured correctly.");
  }
  return {weekday, minutes: hours * 60 + minutes};
}

export function validatePaccAppointmentAvailability(
  scheduledMillis: number,
  availability: unknown,
): void {
  if (!availability || typeof availability !== "object") {
    throw new AppointmentAvailabilityValidationError("PACC appointment availability has not been published.");
  }
  const data = availability as Record<string, unknown>;
  const openDays = data.openDays;
  const opensAt = data.opensAt;
  const closesAt = data.closesAt;
  const presence = data.presence;
  const acceptsWalkIns = data.acceptsWalkIns;
  if (!Array.isArray(openDays) || openDays.length === 0 || !openDays.every((day) => Number.isInteger(day) && day >= 1 && day <= 7) ||
      typeof opensAt !== "string" || !OFFICE_TIME.test(opensAt) ||
      typeof closesAt !== "string" || !OFFICE_TIME.test(closesAt) ||
      minutesSinceMidnight(opensAt) >= minutesSinceMidnight(closesAt) ||
      typeof acceptsWalkIns !== "boolean" ||
      !["in_office", "out_of_office", "on_leave"].includes(String(presence))) {
    throw new AppointmentAvailabilityValidationError("PACC availability is not configured correctly.");
  }
  if (presence !== "in_office") {
    throw new AppointmentAvailabilityValidationError("PACC is not available for appointments at this time.");
  }
  const local = appointmentLocalTime(scheduledMillis);
  if (!openDays.includes(local.weekday)) {
    throw new AppointmentAvailabilityValidationError("PACC is closed on the selected day.");
  }
  if (local.minutes < minutesSinceMidnight(opensAt) || local.minutes >= minutesSinceMidnight(closesAt)) {
    throw new AppointmentAvailabilityValidationError("PACC is closed at the selected time.");
  }
}
