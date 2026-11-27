import {
  AppointmentAvailabilityValidationError,
  validatePaccAppointmentAvailability,
} from "./appointment_availability";
import {formatAppointmentTime} from "./appointment_scheduling";

export const TESTING_SERVICE_FORM_TYPE = "testing_service";
export const TESTING_SERVICE_CATEGORY = "Service Form";
export const TESTING_SERVICE_MAX_RESCHEDULES = 1;
export const TESTING_SERVICE_DEFAULT_LOCATION = "PACC Testing Room";
export const TESTING_SERVICE_TIMEZONE = "Asia/Manila";

export const TESTING_DOCUMENT_MAX_BYTES = 5 * 1024 * 1024;
export const TESTING_DOCUMENT_MAX_ADMISSION_FILES = 3;
export const TESTING_DOCUMENT_KINDS = [
  "endorsement_letter",
  "official_receipt",
  "admission_requirement",
] as const;

export type TestingDocumentKind = typeof TESTING_DOCUMENT_KINDS[number];

export const TESTING_DOCUMENT_MIME_BY_EXT: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  pdf: "application/pdf",
};

export interface TestingServiceDocumentRef {
  path: string;
  name: string;
  contentType: string;
  size: number;
  kind: TestingDocumentKind;
}

export interface TestingServiceDocuments {
  endorsementLetter: TestingServiceDocumentRef;
  officialReceipt: TestingServiceDocumentRef;
  admissionRequirements: TestingServiceDocumentRef[];
}

export interface PersonalDataSheetSummary {
  fullName: string;
  email: string;
  idNumber: string;
  officeOrCollege: string;
  courseOrPosition: string;
}

export const TESTING_SCHEDULE_STATUSES = [
  "awaiting_schedule",
  "proposed",
  "reschedule_requested",
  "confirmed",
  "completed",
  "cancelled",
] as const;

const SYNTHETIC_EMAIL_SUFFIXES = [
  "@students.mindmate.local",
  "@student.mindmate.local",
  "@mindmate.local",
];

export function isSyntheticStudentEmail(email: unknown): boolean {
  const normalized = String(email ?? "").trim().toLowerCase();
  return SYNTHETIC_EMAIL_SUFFIXES.some((suffix) => normalized.endsWith(suffix));
}

export function visibleContactEmail(email: unknown): string {
  const trimmed = String(email ?? "").trim();
  if (!trimmed || isSyntheticStudentEmail(trimmed)) {
    return "";
  }
  return trimmed;
}

export function standardizedTestingDocumentFileName(
  kind: TestingDocumentKind,
  rawName: unknown,
  admissionIndex?: number,
): string {
  const extMatch = /\.([a-z0-9]{1,8})$/i.exec(String(rawName ?? "").trim());
  const candidateExt = extMatch ? extMatch[1].toLowerCase() : "";
  const ext = TESTING_DOCUMENT_MIME_BY_EXT[candidateExt] ? candidateExt : "png";
  switch (kind) {
    case "endorsement_letter":
      return `Endorsement_Letter.${ext}`;
    case "official_receipt":
      return `Official_Receipt_PHP250.${ext}`;
    case "admission_requirement":
      return admissionIndex && admissionIndex > 0
        ? `Admission_Requirement_${admissionIndex}.${ext}`
        : `Admission_Requirement.${ext}`;
  }
}

export type TestingScheduleStatus = typeof TESTING_SCHEDULE_STATUSES[number];
export type TestingRequesterType = "student_ojt" | "teaching" | "non_teaching";

export type TestingServiceErrorCode =
  | "invalid-argument"
  | "permission-denied"
  | "failed-precondition";

export class TestingServiceValidationError extends Error {
  constructor(
    public readonly code: TestingServiceErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "TestingServiceValidationError";
  }
}

export type TestingServiceEligibility = {
  requesterType: TestingRequesterType;
  requesterLabel: string;
  populationRole: "student" | "teaching" | "nonTeaching";
};

function normalizedToken(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[\s_-]+/g, "");
}

/**
 * Resolves Testing Service eligibility purely from trusted server-side user
 * profile fields, never from a client-supplied role string.
 */
export function resolveTestingServiceEligibility(
  profile: Record<string, unknown> | null | undefined,
  input: {isStudentForOjt?: unknown} = {},
): TestingServiceEligibility {
  if (!profile) {
    throw new TestingServiceValidationError(
      "permission-denied",
      "Your MindMate profile could not be found.",
    );
  }
  const accountStatus = profile.accountStatus == null
    ? "active"
    : String(profile.accountStatus).trim().toLowerCase();
  if (accountStatus !== "active") {
    throw new TestingServiceValidationError(
      "permission-denied",
      "Your account is not active.",
    );
  }
  const rawAccessRole = normalizedToken(profile.accessRole ?? "appUser");
  const legacyRole = normalizedToken(profile.role);
  if (
    rawAccessRole !== "appuser" ||
    profile.staffAccountStatus != null ||
    ["portalstaff", "counselor", "counsellor", "admin", "staff"].includes(legacyRole)
  ) {
    throw new TestingServiceValidationError(
      "permission-denied",
      "Testing Service requests are only available to Students for OJT, Teaching employees, and Non-Teaching employees.",
    );
  }

  const rawPop = normalizedToken(
    profile.populationRole ?? profile.declaredRole ?? profile.role,
  );
  if (rawPop === "student") {
    if (input.isStudentForOjt !== true) {
      throw new TestingServiceValidationError(
        "failed-precondition",
        "Testing Service for students is available only for OJT requirements.",
      );
    }
    return {
      requesterType: "student_ojt",
      requesterLabel: "Student (OJT)",
      populationRole: "student",
    };
  }
  if (rawPop === "teaching" || rawPop === "faculty" || rawPop === "teachingpersonnel") {
    return {
      requesterType: "teaching",
      requesterLabel: "Teaching Employee",
      populationRole: "teaching",
    };
  }
  if (
    rawPop === "nonteaching" ||
    rawPop === "nonteachingpersonnel"
  ) {
    return {
      requesterType: "non_teaching",
      requesterLabel: "Non-Teaching Employee",
      populationRole: "nonTeaching",
    };
  }

  throw new TestingServiceValidationError(
    "permission-denied",
    "Testing Service is available only to Students for OJT, Teaching employees, and Non-Teaching employees.",
  );
}

/**
 * Normalizes Philippine mobile numbers (`09XXXXXXXXX`, `9XXXXXXXXX`,
 * `639XXXXXXXXX`, or `+639XXXXXXXXX`) to canonical `+63 9XX XXX XXXX`.
 */
export function validatePhilippineMobile(value: unknown): string {
  const raw = typeof value === "string" ? value.trim() : "";
  const compact = raw.replace(/[\s\-().]/g, "");
  let national = "";
  if (/^\+639\d{9}$/.test(compact)) {
    national = compact.slice(3);
  } else if (/^639\d{9}$/.test(compact)) {
    national = compact.slice(2);
  } else if (/^09\d{9}$/.test(compact)) {
    national = compact.slice(1);
  } else if (/^9\d{9}$/.test(compact)) {
    national = compact;
  } else {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Enter a valid Philippine mobile number (e.g. +63 917 123 4567).",
    );
  }
  return `+63 ${national.slice(0, 3)} ${national.slice(3, 6)} ${national.slice(6, 10)}`;
}

function validateFileNameAndExt(rawName: unknown): {name: string; extension: string} {
  const name = typeof rawName === "string" ? rawName.trim() : "";
  if (name.length === 0 || name.length > 120 || /[\\/\x00-\x1f]/.test(name)) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Invalid document file name.",
    );
  }
  const period = name.lastIndexOf(".");
  const extension = period > 0 ? name.slice(period + 1).toLowerCase() : "";
  if (!Object.hasOwn(TESTING_DOCUMENT_MIME_BY_EXT, extension)) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Upload a JPG, PNG, or PDF file.",
    );
  }
  return {name, extension};
}

export function validateTestingDocumentUploadPayload(
  data: unknown,
  uid: string,
  nonceHex: string,
): {document: TestingServiceDocumentRef; bytes: Buffer} {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Invalid document upload payload.",
    );
  }
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(uid) || !/^[a-f0-9]{32}$/.test(nonceHex)) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Invalid document upload path.",
    );
  }
  const entry = data as Record<string, unknown>;
  const kind = String(entry.kind ?? "").trim() as TestingDocumentKind;
  if (!TESTING_DOCUMENT_KINDS.includes(kind)) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Unsupported Testing Service document category.",
    );
  }
  const {name, extension} = validateFileNameAndExt(entry.name);
  const expectedMime = TESTING_DOCUMENT_MIME_BY_EXT[extension];
  const contentType = typeof entry.contentType === "string"
    ? entry.contentType.trim().toLowerCase()
    : "";
  if (contentType !== expectedMime) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Document file type does not match its extension.",
    );
  }
  const size = entry.size;
  if (
    typeof size !== "number" ||
    !Number.isSafeInteger(size) ||
    size <= 0 ||
    size > TESTING_DOCUMENT_MAX_BYTES
  ) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Documents must be 5 MB or smaller.",
    );
  }
  const encoded = entry.dataBase64;
  if (
    typeof encoded !== "string" ||
    encoded.length !== 4 * Math.ceil(size / 3)
  ) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Invalid document upload data.",
    );
  }
  const bytes = Buffer.from(encoded, "base64");
  if (bytes.length !== size || bytes.toString("base64") !== encoded) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Invalid document upload data.",
    );
  }
  const canonicalName = standardizedTestingDocumentFileName(kind, name);
  const path = `testing_service_files/${uid}/${kind}/${nonceHex}.${extension}`;
  return {
    document: {path, name: canonicalName, contentType, size, kind},
    bytes,
  };
}

export function validateTestingDocumentRef(
  raw: unknown,
  uid: string,
  expectedKind: TestingDocumentKind,
): TestingServiceDocumentRef {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Required Testing Service document upload is missing.",
    );
  }
  const entry = raw as Record<string, unknown>;
  const path = typeof entry.path === "string" ? entry.path : "";
  const {name} = validateFileNameAndExt(entry.name);
  const contentType = typeof entry.contentType === "string"
    ? entry.contentType.trim().toLowerCase()
    : "";
  const size = entry.size;
  const kind = entry.kind == null ? expectedKind : String(entry.kind).trim();
  if (kind !== expectedKind) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Document category does not match the required upload slot.",
    );
  }
  const prefix = `testing_service_files/${uid}/${expectedKind}/`;
  if (!path.startsWith(prefix)) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Document upload owner does not match the signed-in user.",
    );
  }
  const filename = path.slice(prefix.length);
  const matched = /^[a-f0-9]{32}\.(jpg|jpeg|png|pdf)$/.exec(filename);
  if (!matched || TESTING_DOCUMENT_MIME_BY_EXT[matched[1]] !== contentType) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Invalid document reference.",
    );
  }
  if (
    typeof size !== "number" ||
    !Number.isSafeInteger(size) ||
    size <= 0 ||
    size > TESTING_DOCUMENT_MAX_BYTES
  ) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Documents must be 5 MB or smaller.",
    );
  }
  return {
    path,
    name: standardizedTestingDocumentFileName(expectedKind, name),
    contentType,
    size,
    kind: expectedKind,
  };
}

function validatePersonalDataSheet(raw: unknown): PersonalDataSheetSummary {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Personal Data Sheet details are required.",
    );
  }
  const entry = raw as Record<string, unknown>;
  const fullName = typeof entry.fullName === "string" ? entry.fullName.trim() : "";
  if (fullName.length < 1 || fullName.length > 120) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Full name on the Personal Data Sheet must be 1-120 characters.",
    );
  }
  const rawEmail = typeof entry.email === "string" ? entry.email.trim() : "";
  if (isSyntheticStudentEmail(rawEmail)) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Enter a personal or institutional email address on the Personal Data Sheet instead of an internal login alias.",
    );
  }
  if (rawEmail && (rawEmail.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(rawEmail))) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Enter a valid email address on the Personal Data Sheet.",
    );
  }
  const cleanOptional = (value: unknown, label: string, max: number): string => {
    const text = typeof value === "string" ? value.trim() : "";
    if (text.length > max) {
      throw new TestingServiceValidationError(
        "invalid-argument",
        `${label} must be at most ${max} characters.`,
      );
    }
    return text;
  };
  return {
    fullName,
    email: rawEmail,
    idNumber: cleanOptional(entry.idNumber, "ID number", 60),
    officeOrCollege: cleanOptional(entry.officeOrCollege, "Office / College", 120),
    courseOrPosition: cleanOptional(entry.courseOrPosition, "Course / Position", 120),
  };
}

export function validateTestingServiceSubmission(
  input: {
    endorsementLetterConfirmed?: unknown;
    officialReceiptConfirmed?: unknown;
    personalDataSheetConfirmed?: unknown;
    informedConsentConfirmed?: unknown;
    mobileNumber?: unknown;
    preferredScheduleAtMillis?: unknown;
    endorsementLetter?: unknown;
    officialReceipt?: unknown;
    admissionRequirements?: unknown;
    personalDataSheet?: unknown;
    message?: unknown;
    preferredScheduleNote?: unknown;
  },
  uid: string,
  nowMillis = Date.now(),
  availability?: unknown,
): {
  message: string;
  preferredScheduleNote: string | null;
  mobileNumber: string;
  preferredSchedule: {millis: number; scheduledTime: string} | null;
  documents: TestingServiceDocuments;
  personalDataSheet: PersonalDataSheetSummary;
} {
  if (input.endorsementLetterConfirmed !== true || input.officialReceiptConfirmed !== true) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Please confirm both required documents: Endorsement Letter and Official Receipt (PHP 250.00).",
    );
  }
  if (input.personalDataSheetConfirmed !== true || input.informedConsentConfirmed !== true) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Please complete and agree to both the Personal Data Sheet and Informed Consent.",
    );
  }
  const mobileNumber = validatePhilippineMobile(input.mobileNumber);
  const endorsementLetterBase = validateTestingDocumentRef(
    input.endorsementLetter,
    uid,
    "endorsement_letter",
  );
  const officialReceiptBase = validateTestingDocumentRef(
    input.officialReceipt,
    uid,
    "official_receipt",
  );

  const rawAdmission = input.admissionRequirements ?? [];
  if (!Array.isArray(rawAdmission)) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Admission requirement uploads must be a list.",
    );
  }
  if (rawAdmission.length > TESTING_DOCUMENT_MAX_ADMISSION_FILES) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      `Upload at most ${TESTING_DOCUMENT_MAX_ADMISSION_FILES} admission requirement files.`,
    );
  }
  const endorsementLetter = {
    ...endorsementLetterBase,
    name: standardizedTestingDocumentFileName("endorsement_letter", endorsementLetterBase.name),
  };
  const officialReceipt = {
    ...officialReceiptBase,
    name: standardizedTestingDocumentFileName("official_receipt", officialReceiptBase.name),
  };
  const seenPaths = new Set<string>([endorsementLetter.path, officialReceipt.path]);
  const admissionRequirements = rawAdmission.map((entry, index) => {
    const doc = validateTestingDocumentRef(entry, uid, "admission_requirement");
    if (seenPaths.has(doc.path)) {
      throw new TestingServiceValidationError(
        "invalid-argument",
        "Duplicate document upload path.",
      );
    }
    seenPaths.add(doc.path);
    return {
      ...doc,
      name: standardizedTestingDocumentFileName("admission_requirement", doc.name, index + 1),
    };
  });

  const preferredSchedule = input.preferredScheduleAtMillis != null
    ? validateTestingScheduleDateTime(input.preferredScheduleAtMillis, nowMillis, availability)
    : null;

  const personalDataSheet = validatePersonalDataSheet(input.personalDataSheet);

  const rawMessage = typeof input.message === "string" ? input.message.trim() : "";
  if (rawMessage.length > 2000) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Inquiry message must be at most 2000 characters.",
    );
  }
  const message = rawMessage.length > 0
    ? rawMessage
    : "Requesting a Testing Service schedule.";

  const rawNote = typeof input.preferredScheduleNote === "string"
    ? input.preferredScheduleNote.trim()
    : "";
  if (rawNote.length > 300) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Preferred schedule note must be at most 300 characters.",
    );
  }
  return {
    message,
    preferredScheduleNote: rawNote.length > 0 ? rawNote : null,
    mobileNumber,
    preferredSchedule,
    documents: {
      endorsementLetter,
      officialReceipt,
      admissionRequirements,
    },
    personalDataSheet,
  };
}

const VALID_WEEKDAYS = new Set(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]);

function manilaParts(millis: number): {weekday: string; hour: number; minute: number} {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: TESTING_SERVICE_TIMEZONE,
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(millis));
  const lookup = (type: string) => parts.find((part) => part.type === type)?.value ?? "";
  return {
    weekday: lookup("weekday"),
    hour: Number(lookup("hour")),
    minute: Number(lookup("minute")),
  };
}

/**
 * Validates that [scheduledAtMillis] is in the future and falls within
 * Testing Service operating hours: Monday-Saturday, 8:00 AM-5:00 PM (Asia/Manila).
 */
export function validateTestingScheduleDateTime(
  scheduledAtMillis: unknown,
  nowMillis = Date.now(),
  availability?: unknown,
): {millis: number; scheduledTime: string} {
  if (
    typeof scheduledAtMillis !== "number" ||
    !Number.isSafeInteger(scheduledAtMillis) ||
    scheduledAtMillis <= 0 ||
    Number.isNaN(new Date(scheduledAtMillis).getTime())
  ) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Choose a valid Testing Service date and time.",
    );
  }
  if (scheduledAtMillis <= nowMillis) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Choose a future Testing Service date and time.",
    );
  }
  if (availability !== undefined && availability !== null) {
    try {
      validatePaccAppointmentAvailability(scheduledAtMillis, availability);
    } catch (error) {
      if (error instanceof AppointmentAvailabilityValidationError) {
        throw new TestingServiceValidationError("invalid-argument", error.message);
      }
      throw error;
    }
    return {
      millis: scheduledAtMillis,
      scheduledTime: formatAppointmentTime(scheduledAtMillis),
    };
  }
  const {weekday, hour, minute} = manilaParts(scheduledAtMillis);
  const totalMinutes = hour * 60 + minute;
  if (!VALID_WEEKDAYS.has(weekday) || totalMinutes < 8 * 60 || totalMinutes > 17 * 60) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Testing Service schedules must be Monday through Saturday, 8:00 AM to 5:00 PM (PHT).",
    );
  }
  return {
    millis: scheduledAtMillis,
    scheduledTime: formatAppointmentTime(scheduledAtMillis),
  };
}

function testingScheduleRecord(
  inquiryData: Record<string, unknown>,
): Record<string, unknown> {
  const raw = inquiryData.testingSchedule;
  return raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw as Record<string, unknown>
    : {};
}

export function assertCanProposeTestingSchedule(
  inquiryData: Record<string, unknown>,
): {scheduleRevision: number; rescheduleCount: number} {
  if (inquiryData.formType !== TESTING_SERVICE_FORM_TYPE) {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Only Testing Service inquiries support testing schedules.",
    );
  }
  if (String(inquiryData.status ?? "").trim().toLowerCase() === "resolved") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Resolved inquiries cannot be scheduled.",
    );
  }
  const schedule = testingScheduleRecord(inquiryData);
  const status = String(schedule.status ?? "");
  if (status === "cancelled") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "This Testing Service schedule has been cancelled.",
    );
  }
  if (status === "completed") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "This Testing Service request is already marked as completed.",
    );
  }
  if (status === "confirmed") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "This Testing Service schedule is already confirmed and locked.",
    );
  }
  const scheduleRevision = Number.isInteger(schedule.revision) && Number(schedule.revision) >= 0
    ? Number(schedule.revision)
    : 0;
  const rescheduleCount = Number.isInteger(schedule.rescheduleCount) && Number(schedule.rescheduleCount) >= 0
    ? Number(schedule.rescheduleCount)
    : 0;
  return {scheduleRevision, rescheduleCount};
}

export function assertCanCancelTestingSchedule(
  inquiryData: Record<string, unknown>,
  rawReason: unknown,
): {scheduleRevision: number; reason: string} {
  if (inquiryData.formType !== TESTING_SERVICE_FORM_TYPE) {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Only Testing Service inquiries support testing schedules.",
    );
  }
  if (String(inquiryData.status ?? "").trim().toLowerCase() === "resolved") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Resolved inquiries cannot be cancelled.",
    );
  }
  const schedule = testingScheduleRecord(inquiryData);
  const status = String(schedule.status ?? "");
  if (status === "cancelled") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "This Testing Service schedule has already been cancelled.",
    );
  }
  if (status === "completed") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Completed Testing Service requests cannot be cancelled.",
    );
  }
  const reason = typeof rawReason === "string" ? rawReason.trim() : "";
  if (reason.length < 3 || reason.length > 500) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Provide a cancellation reason of 3-500 characters.",
    );
  }
  const scheduleRevision = Number.isInteger(schedule.revision) && Number(schedule.revision) >= 0
    ? Number(schedule.revision)
    : 0;
  return {scheduleRevision, reason};
}

export function assertCanAcceptTestingSchedule(
  inquiryData: Record<string, unknown>,
  uid: string,
): {scheduleRevision: number} {
  if (inquiryData.formType !== TESTING_SERVICE_FORM_TYPE) {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Only Testing Service inquiries support testing schedules.",
    );
  }
  if (String(inquiryData.userId ?? "").trim() !== uid) {
    throw new TestingServiceValidationError(
      "permission-denied",
      "Only the inquiry owner can accept this schedule.",
    );
  }
  const schedule = testingScheduleRecord(inquiryData);
  const scheduleStatus = String(schedule.status ?? "");
  if (scheduleStatus === "cancelled") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "This Testing Service schedule has been cancelled.",
    );
  }
  if (scheduleStatus === "completed") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "This Testing Service request is already marked as completed.",
    );
  }
  if (scheduleStatus !== "proposed" || schedule.scheduledAt == null) {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "There is no proposed schedule awaiting your acceptance.",
    );
  }
  const scheduleRevision = Number.isInteger(schedule.revision) && Number(schedule.revision) >= 0
    ? Number(schedule.revision)
    : 0;
  return {scheduleRevision};
}

export function assertCanRequestTestingReschedule(
  inquiryData: Record<string, unknown>,
  uid: string,
  rawReason: unknown,
): {scheduleRevision: number; rescheduleCount: number; reason: string} {
  if (inquiryData.formType !== TESTING_SERVICE_FORM_TYPE) {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Only Testing Service inquiries support testing schedules.",
    );
  }
  if (String(inquiryData.userId ?? "").trim() !== uid) {
    throw new TestingServiceValidationError(
      "permission-denied",
      "Only the inquiry owner can request a reschedule.",
    );
  }
  const schedule = testingScheduleRecord(inquiryData);
  const status = String(schedule.status ?? "");
  if (status === "cancelled") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "This Testing Service schedule has been cancelled.",
    );
  }
  if (status === "completed") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "This Testing Service request is already marked as completed.",
    );
  }
  if (status === "confirmed") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Confirmed Testing Service schedules cannot be rescheduled or cancelled.",
    );
  }
  const rescheduleCount = Number.isInteger(schedule.rescheduleCount) && Number(schedule.rescheduleCount) >= 0
    ? Number(schedule.rescheduleCount)
    : 0;
  if (rescheduleCount >= TESTING_SERVICE_MAX_RESCHEDULES) {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "You have already used your one allowed reschedule request.",
    );
  }
  if (status !== "proposed" || schedule.scheduledAt == null) {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Wait for PACC to propose a schedule before requesting a reschedule.",
    );
  }
  const reason = typeof rawReason === "string" ? rawReason.trim() : "";
  if (reason.length < 3 || reason.length > 500) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Provide a reschedule reason of 3-500 characters.",
    );
  }
  const scheduleRevision = Number.isInteger(schedule.revision) && Number(schedule.revision) >= 0
    ? Number(schedule.revision)
    : 0;
  return {scheduleRevision, rescheduleCount, reason};
}

export function assertCanCompleteTestingSchedule(
  inquiryData: Record<string, unknown>,
  rawReason: unknown,
): {scheduleRevision: number; reason: string} {
  if (inquiryData.formType !== TESTING_SERVICE_FORM_TYPE) {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Only Testing Service inquiries support testing schedules.",
    );
  }
  const schedule = testingScheduleRecord(inquiryData);
  const status = String(schedule.status ?? "");
  if (status === "cancelled") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Cancelled Testing Service schedules cannot be marked as completed.",
    );
  }
  if (status === "completed") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "This Testing Service request is already marked as completed.",
    );
  }
  if (status !== "confirmed") {
    throw new TestingServiceValidationError(
      "failed-precondition",
      "Only confirmed Testing Service schedules can be marked as completed.",
    );
  }
  const reason = typeof rawReason === "string" ? rawReason.trim() : "";
  if (reason.length > 500) {
    throw new TestingServiceValidationError(
      "invalid-argument",
      "Completion note must be at most 500 characters.",
    );
  }
  const scheduleRevision = Number.isInteger(schedule.revision) && Number(schedule.revision) >= 0
    ? Number(schedule.revision)
    : 0;
  return {scheduleRevision, reason};
}

/**
 * Only assigned counselors may propose, reschedule, cancel, or complete
 * Testing Service schedules. Administrators and super-administrators retain
 * read-only supervising and monitoring access only.
 */
export function canCounselorDecideTestingSchedule(
  actor: {uid: string; role: string; isSuperAdmin: boolean},
  inquiry: Record<string, unknown>,
): boolean {
  if (actor.isSuperAdmin || actor.role === "admin") return false;
  if (inquiry.takeover) return false;
  const assignees = Array.isArray(inquiry.assigneeIds) ? inquiry.assigneeIds : [];
  return actor.role === "counselor" && assignees.includes(actor.uid);
}
