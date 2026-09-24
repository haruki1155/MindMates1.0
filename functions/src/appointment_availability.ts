import {APPOINTMENT_TIME_ZONE} from "./appointment_scheduling";

export class AppointmentAvailabilityValidationError extends Error {}

export type PaccAvailabilityConfig = {
  openDays: number[];
  opensAt: string;
  closesAt: string;
  presence: "in_office" | "out_of_office" | "on_leave";
  acceptsWalkIns: boolean;
  notice: string;
};

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
const AVAILABILITY_FIELDS = new Set([
  "openDays",
  "opensAt",
  "closesAt",
  "presence",
  "acceptsWalkIns",
  "notice",
]);
const PRESENCE_VALUES = new Set<PaccAvailabilityConfig["presence"]>([
  "in_office",
  "out_of_office",
  "on_leave",
]);

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

function normalizeAvailability(value: unknown, {allowMissingNotice}: {allowMissingNotice: boolean}): PaccAvailabilityConfig {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new AppointmentAvailabilityValidationError("PACC availability is not configured correctly.");
  }
  const data = value as Record<string, unknown>;
  if (!allowMissingNotice && Object.keys(data).some((key) => !AVAILABILITY_FIELDS.has(key))) {
    throw new AppointmentAvailabilityValidationError("PACC availability contains unsupported fields.");
  }
  const openDays = data.openDays;
  const opensAt = data.opensAt;
  const closesAt = data.closesAt;
  const presence = data.presence;
  const acceptsWalkIns = data.acceptsWalkIns;
  const notice = data.notice ?? "";
  if (!Array.isArray(openDays) || openDays.length === 0 ||
      !openDays.every((day) => Number.isInteger(day) && day >= 1 && day <= 7) ||
      new Set(openDays).size !== openDays.length ||
      typeof opensAt !== "string" || !OFFICE_TIME.test(opensAt) ||
      typeof closesAt !== "string" || !OFFICE_TIME.test(closesAt) ||
      minutesSinceMidnight(opensAt) >= minutesSinceMidnight(closesAt) ||
      typeof acceptsWalkIns !== "boolean" ||
      typeof presence !== "string" || !PRESENCE_VALUES.has(presence as PaccAvailabilityConfig["presence"]) ||
      typeof notice !== "string" || notice.trim().length > 500) {
    throw new AppointmentAvailabilityValidationError("PACC availability is not configured correctly.");
  }
  return {
    openDays: [...openDays].sort((a, b) => a - b),
    opensAt,
    closesAt,
    presence: presence as PaccAvailabilityConfig["presence"],
    acceptsWalkIns,
    notice: notice.trim(),
  };
}

/** Strict payload validation for the availability-management callable. */
export function validatePaccAvailabilityPayload(value: unknown): PaccAvailabilityConfig {
  return normalizeAvailability(value, {allowMissingNotice: false});
}

/** Existing documents may predate the optional notice field and carry server metadata. */
function normalizeStoredAvailability(value: unknown): PaccAvailabilityConfig {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new AppointmentAvailabilityValidationError("PACC availability has not been published.");
  }
  const data = value as Record<string, unknown>;
  return normalizeAvailability({
    openDays: data.openDays,
    opensAt: data.opensAt,
    closesAt: data.closesAt,
    presence: data.presence,
    acceptsWalkIns: data.acceptsWalkIns,
    notice: data.notice ?? "",
  }, {allowMissingNotice: true});
}

export function canManagePaccAvailability(accessRole: unknown): boolean {
  return accessRole === "counselor" || accessRole === "admin";
}

export function validatePaccAppointmentAvailability(
  scheduledMillis: number,
  availability: unknown,
): void {
  if (!availability || typeof availability !== "object") {
    throw new AppointmentAvailabilityValidationError("PACC appointment availability has not been published.");
  }
  const config = normalizeStoredAvailability(availability);
  if (config.presence !== "in_office") {
    throw new AppointmentAvailabilityValidationError("PACC is not available for appointments at this time.");
  }
  const local = appointmentLocalTime(scheduledMillis);
  if (!config.openDays.includes(local.weekday)) {
    throw new AppointmentAvailabilityValidationError("PACC is closed on the selected day.");
  }
  if (local.minutes < minutesSinceMidnight(config.opensAt) || local.minutes >= minutesSinceMidnight(config.closesAt)) {
    throw new AppointmentAvailabilityValidationError("PACC is closed at the selected time.");
  }
}
