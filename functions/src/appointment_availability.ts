import {APPOINTMENT_TIME_ZONE} from "./appointment_scheduling";

export class AppointmentAvailabilityValidationError extends Error {}
export type CounselorPresence = "in_office" | "out_of_office" | "on_leave";
export type PaccDaySchedule = {enabled: boolean; opensAt: string; closesAt: string; presence: CounselorPresence; appointmentsEnabled: boolean; acceptsWalkIns: boolean};
export type PaccDateOverride = {date: string; closedAllDay: boolean; schedule?: PaccDaySchedule; reason: string};
export type PaccAvailabilityConfig = {schemaVersion: 2; timezone: typeof APPOINTMENT_TIME_ZONE; weekdays: Record<number, PaccDaySchedule>; overrides: PaccDateOverride[]; notice: string};
export type ResolvedPaccSchedule = PaccDaySchedule & {date: string; weekday: number; source: "weekly" | "override"; isOfficeOpen: boolean; canBookAppointments: boolean; acceptsWalkInsNow: boolean; closureReason?: string};

const WEEKDAY_NUMBERS: Record<string, number> = {Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7};
const OFFICE_TIME = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const PRESENCES = new Set<CounselorPresence>(["in_office", "out_of_office", "on_leave"]);
const V2_FIELDS = new Set(["schemaVersion", "timezone", "weekdays", "overrides", "notice"]);
const DAY_FIELDS = new Set(["enabled", "opensAt", "closesAt", "presence", "appointmentsEnabled", "acceptsWalkIns"]);
const OVERRIDE_FIELDS = new Set(["date", "closedAllDay", "schedule", "reason"]);

function isRecord(value: unknown): value is Record<string, unknown> { return !!value && typeof value === "object" && !Array.isArray(value); }
function onlyFields(value: Record<string, unknown>, fields: Set<string>): boolean { return Object.keys(value).every((key) => fields.has(key)); }
function minutes(value: string): number { const [hours, mins] = value.split(":").map(Number); return hours * 60 + mins; }
function isCalendarDate(value: string): boolean {
  if (!DATE.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}
function localParts(millis: number): {date: string; weekday: number; minutes: number} {
  const parts = new Intl.DateTimeFormat("en-US", {timeZone: APPOINTMENT_TIME_ZONE, weekday: "short", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23"}).formatToParts(new Date(millis));
  const part = (type: string) => parts.find((item) => item.type === type)?.value;
  const weekday = WEEKDAY_NUMBERS[part("weekday") ?? ""];
  const hour = Number(part("hour")); const minute = Number(part("minute"));
  const year = part("year"); const month = part("month"); const day = part("day");
  if (!weekday || !Number.isInteger(hour) || !Number.isInteger(minute) || !year || !month || !day) throw new AppointmentAvailabilityValidationError("PACC availability is not configured correctly.");
  return {date: `${year}-${month}-${day}`, weekday, minutes: hour * 60 + minute};
}
function closedDay(): PaccDaySchedule { return {enabled: false, opensAt: "08:00", closesAt: "17:00", presence: "out_of_office", appointmentsEnabled: false, acceptsWalkIns: false}; }
function validateDay(value: unknown): PaccDaySchedule {
  if (!isRecord(value) || !onlyFields(value, DAY_FIELDS) || Object.keys(value).length !== DAY_FIELDS.size) throw new AppointmentAvailabilityValidationError("PACC day schedule is not configured correctly.");
  const {enabled, opensAt, closesAt, presence, appointmentsEnabled, acceptsWalkIns} = value;
  if (typeof enabled !== "boolean" || typeof opensAt !== "string" || !OFFICE_TIME.test(opensAt) || typeof closesAt !== "string" || !OFFICE_TIME.test(closesAt) || minutes(opensAt) >= minutes(closesAt) || typeof presence !== "string" || !PRESENCES.has(presence as CounselorPresence) || typeof appointmentsEnabled !== "boolean" || typeof acceptsWalkIns !== "boolean" || (!enabled && (appointmentsEnabled || acceptsWalkIns))) throw new AppointmentAvailabilityValidationError("PACC day schedule is not configured correctly.");
  return {enabled, opensAt, closesAt, presence: presence as CounselorPresence, appointmentsEnabled, acceptsWalkIns};
}
function validateOverride(value: unknown): PaccDateOverride {
  if (!isRecord(value) || !onlyFields(value, OVERRIDE_FIELDS) || typeof value.date !== "string" || !isCalendarDate(value.date) || typeof value.closedAllDay !== "boolean" || typeof value.reason !== "string" || value.reason.trim().length > 250) throw new AppointmentAvailabilityValidationError("PACC date override is not configured correctly.");
  const hasSchedule = value.schedule !== undefined;
  if ((value.closedAllDay && hasSchedule) || (!value.closedAllDay && !hasSchedule)) throw new AppointmentAvailabilityValidationError("PACC date override is contradictory.");
  return {date: value.date, closedAllDay: value.closedAllDay, ...(hasSchedule ? {schedule: validateDay(value.schedule)} : {}), reason: value.reason.trim()};
}

/** Strict V2-only payload validation for the availability-management callable. */
export function validatePaccAvailabilityPayload(value: unknown): PaccAvailabilityConfig {
  if (!isRecord(value) || !onlyFields(value, V2_FIELDS) || value.schemaVersion !== 2 || value.timezone !== APPOINTMENT_TIME_ZONE || !isRecord(value.weekdays) || Object.keys(value.weekdays).length !== 7 || !Array.isArray(value.overrides) || value.overrides.length > 366 || typeof value.notice !== "string" || value.notice.trim().length > 500) throw new AppointmentAvailabilityValidationError("PACC availability is not configured correctly.");
  const weekdays = {} as Record<number, PaccDaySchedule>;
  for (let day = 1; day <= 7; day += 1) { if (!(String(day) in value.weekdays)) throw new AppointmentAvailabilityValidationError("PACC availability requires all weekdays."); weekdays[day] = validateDay(value.weekdays[String(day)]); }
  if (Object.keys(value.weekdays).some((key) => !/^[1-7]$/.test(key))) throw new AppointmentAvailabilityValidationError("PACC availability requires valid weekdays.");
  const overrides = value.overrides.map(validateOverride).sort((left, right) => left.date.localeCompare(right.date));
  if (new Set(overrides.map((item) => item.date)).size !== overrides.length) throw new AppointmentAvailabilityValidationError("PACC date overrides must be unique.");
  return {schemaVersion: 2, timezone: APPOINTMENT_TIME_ZONE, weekdays, overrides, notice: value.notice.trim()};
}

function normalizeLegacy(value: Record<string, unknown>): PaccAvailabilityConfig {
  const {openDays, opensAt, closesAt, presence, acceptsWalkIns} = value; const notice = value.notice ?? ""; const blackoutDates = value.blackoutDates ?? [];
  if (!Array.isArray(openDays) || openDays.length === 0 || !openDays.every((day) => Number.isInteger(day) && day >= 1 && day <= 7) || new Set(openDays).size !== openDays.length || typeof opensAt !== "string" || !OFFICE_TIME.test(opensAt) || typeof closesAt !== "string" || !OFFICE_TIME.test(closesAt) || minutes(opensAt) >= minutes(closesAt) || typeof presence !== "string" || !PRESENCES.has(presence as CounselorPresence) || typeof acceptsWalkIns !== "boolean" || typeof notice !== "string" || notice.trim().length > 500 || !Array.isArray(blackoutDates) || blackoutDates.length > 366 || !blackoutDates.every((date) => typeof date === "string" && isCalendarDate(date)) || new Set(blackoutDates).size !== blackoutDates.length) throw new AppointmentAvailabilityValidationError("PACC availability has not been published.");
  const weekdays = {} as Record<number, PaccDaySchedule>;
  for (let day = 1; day <= 7; day += 1) weekdays[day] = openDays.includes(day) ? {enabled: true, opensAt, closesAt, presence: presence as CounselorPresence, appointmentsEnabled: true, acceptsWalkIns} : closedDay();
  return {schemaVersion: 2, timezone: APPOINTMENT_TIME_ZONE, weekdays, overrides: [...blackoutDates].sort().map((date) => ({date, closedAllDay: true, reason: ""})), notice: notice.trim()};
}

/** Reads V2 documents losslessly and converts V1 only at the storage boundary. */
export function normalizePaccAvailabilityForRead(value: unknown): PaccAvailabilityConfig {
  if (!isRecord(value)) throw new AppointmentAvailabilityValidationError("PACC availability has not been published.");
  if (value.schemaVersion === 2) {
    return validatePaccAvailabilityPayload({
      schemaVersion: value.schemaVersion,
      timezone: value.timezone,
      weekdays: value.weekdays,
      overrides: value.overrides,
      notice: value.notice,
    });
  }
  return normalizeLegacy(value);
}
export function resolvePaccSchedule(scheduledMillis: number, availability: unknown): ResolvedPaccSchedule {
  if (!Number.isFinite(scheduledMillis)) throw new AppointmentAvailabilityValidationError("PACC schedule time is invalid.");
  const config = normalizePaccAvailabilityForRead(availability); const local = localParts(scheduledMillis); const override = config.overrides.find((item) => item.date === local.date); const schedule = override?.closedAllDay ? closedDay() : (override?.schedule ?? config.weekdays[local.weekday]);
  const withinHours = local.minutes >= minutes(schedule.opensAt) && local.minutes < minutes(schedule.closesAt); const isOfficeOpen = schedule.enabled && withinHours; const canBookAppointments = isOfficeOpen && schedule.presence === "in_office" && schedule.appointmentsEnabled; const acceptsWalkInsNow = isOfficeOpen && schedule.acceptsWalkIns;
  const closureReason = !schedule.enabled ? (override?.reason || "Office is closed.") : !withinHours ? "Office is closed at the selected time." : schedule.presence !== "in_office" ? "Counselor is unavailable." : !schedule.appointmentsEnabled ? "Appointments are unavailable." : undefined;
  return {...schedule, date: local.date, weekday: local.weekday, source: override ? "override" : "weekly", isOfficeOpen, canBookAppointments, acceptsWalkInsNow, ...(closureReason ? {closureReason} : {})};
}
export type PaccScheduleConflict = {appointmentId: string; status: string; timestamp: number; reason: string};
function appointmentMillis(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) return value.getTime();
  if (isRecord(value) && typeof value.toMillis === "function") {
    const millis = (value.toMillis as () => unknown)();
    return typeof millis === "number" && Number.isFinite(millis) ? millis : null;
  }
  if (isRecord(value) && typeof value._seconds === "number") return value._seconds * 1_000 + (typeof value._nanoseconds === "number" ? Math.floor(value._nanoseconds / 1_000_000) : 0);
  return null;
}
/** Finds future active appointment timestamps that a candidate schedule would invalidate. */
export function previewPaccScheduleConflicts(candidate: PaccAvailabilityConfig, appointments: Iterable<Record<string, unknown>>, nowMillis = Date.now()): PaccScheduleConflict[] {
  const conflicts: PaccScheduleConflict[] = [];
  const activeStatuses = new Set(["requested", "confirmed", "reschedule_proposed", "pending", "upcoming", "reschedule_required"]);
  for (const appointment of appointments) {
    const status = String(appointment.status ?? "");
    if (!activeStatuses.has(status)) continue;
    const timestamps = [appointmentMillis(appointment.scheduledAt)];
    if (status === "reschedule_proposed") timestamps.push(appointmentMillis(appointment.proposedScheduledAt));
    for (const timestamp of timestamps) {
      if (timestamp === null || timestamp <= nowMillis) continue;
      const resolved = resolvePaccSchedule(timestamp, candidate);
      if (!resolved.canBookAppointments) conflicts.push({appointmentId: String(appointment.id ?? ""), status, timestamp, reason: resolved.closureReason ?? "PACC is unavailable."});
    }
  }
  return conflicts.sort((left, right) => left.appointmentId.localeCompare(right.appointmentId) || left.timestamp - right.timestamp);
}
export function canManagePaccAvailability(accessRole: unknown): boolean { return accessRole === "counselor" || accessRole === "admin"; }
export function validatePaccAppointmentAvailability(scheduledMillis: number, availability: unknown): void { const resolved = resolvePaccSchedule(scheduledMillis, availability); if (!resolved.canBookAppointments) throw new AppointmentAvailabilityValidationError(resolved.closureReason ?? "PACC is not available for appointments at this time."); }
