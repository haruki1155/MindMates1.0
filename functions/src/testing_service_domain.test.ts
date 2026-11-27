import assert from "node:assert/strict";
import {test} from "node:test";

import {
  assertCanAcceptTestingSchedule,
  assertCanCancelTestingSchedule,
  assertCanCompleteTestingSchedule,
  assertCanProposeTestingSchedule,
  assertCanRequestTestingReschedule,
  canCounselorDecideTestingSchedule,
  isSyntheticStudentEmail,
  resolveTestingServiceEligibility,
  standardizedTestingDocumentFileName,
  TestingServiceValidationError,
  validatePhilippineMobile,
  validateTestingDocumentRef,
  validateTestingDocumentUploadPayload,
  validateTestingScheduleDateTime,
  validateTestingServiceSubmission,
  visibleContactEmail,
} from "./testing_service_domain";

const manilaInstant = (
  year: number,
  month: number,
  day: number,
  hour: number,
  minute = 0,
): number => Date.UTC(year, month - 1, day, hour - 8, minute);

function expectValidationError(fn: () => unknown, code: string) {
  assert.throws(
    fn,
    (error: unknown) =>
      error instanceof TestingServiceValidationError && error.code === code,
  );
}

const sampleNonce = "0123456789abcdef0123456789abcdef";
const sampleBytes = Buffer.from("sample-pdf-bytes");
const sampleBase64 = sampleBytes.toString("base64");

function docRef(uid: string, kind: "endorsement_letter" | "official_receipt" | "admission_requirement", ext = "pdf") {
  return {
    path: `testing_service_files/${uid}/${kind}/${sampleNonce}.${ext}`,
    name: `${kind}.${ext}`,
    contentType: ext === "pdf" ? "application/pdf" : "image/png",
    size: sampleBytes.length,
    kind,
  };
}

test("eligibility allows student for OJT, teaching, and non-teaching using trusted profile fields", () => {
  const studentOjt = resolveTestingServiceEligibility(
    {accessRole: "appUser", accountStatus: "active", populationRole: "student"},
    {isStudentForOjt: true},
  );
  assert.equal(studentOjt.requesterType, "student_ojt");

  const teaching = resolveTestingServiceEligibility(
    {accessRole: "appUser", accountStatus: "active", populationRole: "teaching"},
    {isStudentForOjt: false},
  );
  assert.equal(teaching.requesterType, "teaching");

  const nonTeaching = resolveTestingServiceEligibility(
    {accessRole: "appUser", accountStatus: "active", declaredRole: "nonTeaching"},
  );
  assert.equal(nonTeaching.requesterType, "non_teaching");
});

test("eligibility rejects student without OJT, staff/admin roles, suspended accounts, and spoofed role strings", () => {
  expectValidationError(
    () => resolveTestingServiceEligibility(
      {accessRole: "appUser", accountStatus: "active", populationRole: "student"},
      {isStudentForOjt: false},
    ),
    "failed-precondition",
  );
  for (const profile of [
    null,
    {accessRole: "portalStaff", accountStatus: "active", populationRole: "nonTeaching"},
    {accessRole: "counselor", accountStatus: "active", populationRole: "teaching"},
    {accessRole: "admin", accountStatus: "active", populationRole: "nonTeaching"},
    {accessRole: "appUser", staffAccountStatus: "pending", populationRole: "nonTeaching"},
    {accessRole: "appUser", accountStatus: "suspended", populationRole: "teaching"},
    {accessRole: "appUser", accountStatus: "active", populationRole: "alumni"},
  ]) {
    expectValidationError(
      () => resolveTestingServiceEligibility(profile, {isStudentForOjt: true}),
      "permission-denied",
    );
  }
});

test("Philippine mobile number formats and validates across 09, 9, and +63 inputs", () => {
  assert.equal(validatePhilippineMobile("09171234567"), "+63 917 123 4567");
  assert.equal(validatePhilippineMobile("9171234567"), "+63 917 123 4567");
  assert.equal(validatePhilippineMobile("+63 917-123-4567"), "+63 917 123 4567");
  expectValidationError(() => validatePhilippineMobile("12345"), "invalid-argument");
  expectValidationError(() => validatePhilippineMobile("+1 555 123 4567"), "invalid-argument");
});

test("document upload payload & reference validation enforces owner, kind, MIME, and 5 MB limit", () => {
  const uploaded = validateTestingDocumentUploadPayload(
    {
      kind: "endorsement_letter",
      name: "endorsement.pdf",
      contentType: "application/pdf",
      size: sampleBytes.length,
      dataBase64: sampleBase64,
    },
    "user-1",
    sampleNonce,
  );
  assert.equal(
    uploaded.document.path,
    `testing_service_files/user-1/endorsement_letter/${sampleNonce}.pdf`,
  );

  // Wrong MIME for extension
  expectValidationError(
    () => validateTestingDocumentUploadPayload(
      {
        kind: "endorsement_letter",
        name: "endorsement.pdf",
        contentType: "image/png",
        size: sampleBytes.length,
        dataBase64: sampleBase64,
      },
      "user-1",
      sampleNonce,
    ),
    "invalid-argument",
  );

  // Wrong owner prefix on ref
  expectValidationError(
    () => validateTestingDocumentRef(
      docRef("other-user", "endorsement_letter"),
      "user-1",
      "endorsement_letter",
    ),
    "invalid-argument",
  );
});

test("submission requires Endorsement Letter + Official Receipt uploads, mobile number, PDS, and Informed Consent; admission scans optional", () => {
  const now = manilaInstant(2026, 11, 27, 10, 0);
  const validPayload = {
    endorsementLetterConfirmed: true,
    officialReceiptConfirmed: true,
    personalDataSheetConfirmed: true,
    informedConsentConfirmed: true,
    mobileNumber: "09171234567",
    preferredScheduleAtMillis: manilaInstant(2026, 11, 28, 9, 0),
    endorsementLetter: docRef("user-1", "endorsement_letter"),
    officialReceipt: docRef("user-1", "official_receipt"),
    personalDataSheet: {
      fullName: "Juan Dela Cruz",
      email: "juan@ucu.edu.ph",
      idNumber: "2023-001",
      officeOrCollege: "CCSE",
      courseOrPosition: "BSIT",
    },
  };

  const ok = validateTestingServiceSubmission(validPayload, "user-1", now);
  assert.equal(ok.mobileNumber, "+63 917 123 4567");
  assert.equal(ok.documents.admissionRequirements.length, 0);
  assert.equal(ok.preferredSchedule?.scheduledTime, "09:00 AM");

  // With optional admission requirement scan
  const withAdmission = validateTestingServiceSubmission(
    {
      ...validPayload,
      admissionRequirements: [docRef("user-1", "admission_requirement", "png")],
    },
    "user-1",
    now,
  );
  assert.equal(withAdmission.documents.admissionRequirements.length, 1);

  // Missing official receipt upload rejected
  expectValidationError(
    () => validateTestingServiceSubmission(
      {...validPayload, officialReceipt: null},
      "user-1",
      now,
    ),
    "invalid-argument",
  );

  // Missing Informed Consent rejected
  expectValidationError(
    () => validateTestingServiceSubmission(
      {...validPayload, informedConsentConfirmed: false},
      "user-1",
      now,
    ),
    "invalid-argument",
  );
});

test("schedule availability allows Monday-Saturday 8:00 AM-5:00 PM PHT and rejects Sunday/off-hours/past", () => {
  const now = manilaInstant(2026, 11, 27, 10, 0); // Friday 10:00 AM PHT

  const satMorning = validateTestingScheduleDateTime(
    manilaInstant(2026, 11, 28, 8, 0),
    now,
  );
  assert.equal(satMorning.scheduledTime, "08:00 AM");

  const monClosing = validateTestingScheduleDateTime(
    manilaInstant(2026, 11, 30, 17, 0),
    now,
  );
  assert.equal(monClosing.scheduledTime, "05:00 PM");

  expectValidationError(
    () => validateTestingScheduleDateTime(manilaInstant(2026, 11, 29, 10, 0), now),
    "invalid-argument",
  );
  expectValidationError(
    () => validateTestingScheduleDateTime(manilaInstant(2026, 11, 28, 7, 59), now),
    "invalid-argument",
  );
  expectValidationError(
    () => validateTestingScheduleDateTime(manilaInstant(2026, 11, 30, 17, 1), now),
    "invalid-argument",
  );
  expectValidationError(
    () => validateTestingScheduleDateTime(manilaInstant(2026, 11, 27, 9, 0), now),
    "invalid-argument",
  );
});

test("state machine enforces one-time reschedule and locks confirmed schedules", () => {
  const proposed = {
    formType: "testing_service",
    userId: "user-1",
    status: "in_progress",
    testingSchedule: {
      status: "proposed",
      scheduledAt: new Date(),
      rescheduleCount: 0,
      revision: 1,
    },
  };

  assert.equal(assertCanProposeTestingSchedule(proposed).scheduleRevision, 1);
  assert.equal(assertCanAcceptTestingSchedule(proposed, "user-1").scheduleRevision, 1);
  expectValidationError(
    () => assertCanAcceptTestingSchedule(proposed, "user-2"),
    "permission-denied",
  );

  const resched = assertCanRequestTestingReschedule(proposed, "user-1", "Have a class exam");
  assert.equal(resched.rescheduleCount, 0);
  assert.equal(resched.reason, "Have a class exam");

  const secondProposed = {
    ...proposed,
    testingSchedule: {
      status: "proposed",
      scheduledAt: new Date(),
      rescheduleCount: 1,
      revision: 3,
    },
  };
  expectValidationError(
    () => assertCanRequestTestingReschedule(secondProposed, "user-1", "Another reason"),
    "failed-precondition",
  );
  assert.equal(assertCanAcceptTestingSchedule(secondProposed, "user-1").scheduleRevision, 3);

  const confirmed = {
    ...proposed,
    testingSchedule: {
      status: "confirmed",
      scheduledAt: new Date(),
      rescheduleCount: 1,
      revision: 4,
    },
  };
  expectValidationError(
    () => assertCanProposeTestingSchedule(confirmed),
    "failed-precondition",
  );
  expectValidationError(
    () => assertCanAcceptTestingSchedule(confirmed, "user-1"),
    "failed-precondition",
  );
  expectValidationError(
    () => assertCanRequestTestingReschedule(confirmed, "user-1", "Cannot change"),
    "failed-precondition",
  );

  const cancelled = {
    ...proposed,
    testingSchedule: {
      status: "cancelled",
      cancelReason: "Incomplete documents",
      revision: 5,
    },
  };
  assert.deepEqual(
    assertCanCancelTestingSchedule(confirmed, "Office emergency closure"),
    {scheduleRevision: 4, reason: "Office emergency closure"},
  );
  expectValidationError(
    () => assertCanCancelTestingSchedule(proposed, "No"),
    "invalid-argument",
  );
  expectValidationError(
    () => assertCanCancelTestingSchedule(cancelled, "Already cancelled"),
    "failed-precondition",
  );
  expectValidationError(
    () => assertCanProposeTestingSchedule(cancelled),
    "failed-precondition",
  );
  expectValidationError(
    () => assertCanAcceptTestingSchedule(cancelled, "user-1"),
    "failed-precondition",
  );
  expectValidationError(
    () => assertCanRequestTestingReschedule(cancelled, "user-1", "Need slot"),
    "failed-precondition",
  );
  expectValidationError(
    () => assertCanCompleteTestingSchedule(cancelled, "Done"),
    "failed-precondition",
  );
  expectValidationError(
    () => assertCanCompleteTestingSchedule(proposed, "Done"),
    "failed-precondition",
  );
  expectValidationError(
    () => assertCanCompleteTestingSchedule({
      ...proposed,
      testingSchedule: {status: "awaiting_schedule", revision: 0},
    }, "Done"),
    "failed-precondition",
  );

  const completedState = assertCanCompleteTestingSchedule(confirmed, "Testing session finished.");
  assert.deepEqual(completedState, {
    scheduleRevision: 4,
    reason: "Testing session finished.",
  });

  const completed = {
    ...proposed,
    status: "resolved",
    testingSchedule: {
      status: "completed",
      revision: 6,
    },
  };
  expectValidationError(
    () => assertCanCompleteTestingSchedule(completed, "Again"),
    "failed-precondition",
  );
  expectValidationError(
    () => assertCanProposeTestingSchedule(completed),
    "failed-precondition",
  );
  expectValidationError(
    () => assertCanCancelTestingSchedule(completed, "Too late"),
    "failed-precondition",
  );
});

test("standardized document filenames, synthetic email hiding, and PACC availability sync", () => {
  assert.equal(
    standardizedTestingDocumentFileName("endorsement_letter", "phone_verified_after_fix.png"),
    "Endorsement_Letter.png",
  );
  assert.equal(
    standardizedTestingDocumentFileName("official_receipt", "IMG_20261127.jpeg"),
    "Official_Receipt_PHP250.jpeg",
  );
  assert.equal(
    standardizedTestingDocumentFileName("admission_requirement", "scan.pdf", 2),
    "Admission_Requirement_2.pdf",
  );

  assert.equal(isSyntheticStudentEmail("20220367@students.mindmate.local"), true);
  assert.equal(isSyntheticStudentEmail("20220367@student.mindmate.local"), true);
  assert.equal(isSyntheticStudentEmail("20220367@mindmate.local"), true);
  assert.equal(visibleContactEmail("20220367@students.mindmate.local"), "");
  assert.equal(visibleContactEmail("student@ucu.edu.ph"), "student@ucu.edu.ph");

  const now = manilaInstant(2026, 11, 27, 8, 0);
  const weekday = {
    enabled: true,
    opensAt: "09:00",
    closesAt: "16:00",
    presence: "in_office",
    appointmentsEnabled: true,
    acceptsWalkIns: true,
  };
  const closed = {
    enabled: false,
    opensAt: "08:00",
    closesAt: "17:00",
    presence: "out_of_office",
    appointmentsEnabled: false,
    acceptsWalkIns: false,
  };
  const availability = {
    schemaVersion: 2,
    timezone: "Asia/Manila",
    weekdays: {
      1: weekday,
      2: weekday,
      3: weekday,
      4: weekday,
      5: weekday,
      6: closed,
      7: closed,
    },
    overrides: [],
    notice: "",
  };

  assert.equal(
    validateTestingScheduleDateTime(manilaInstant(2026, 11, 30, 10, 0), now, availability).scheduledTime,
    "10:00 AM",
  );
  expectValidationError(
    () => validateTestingScheduleDateTime(manilaInstant(2026, 11, 30, 8, 0), now, availability),
    "invalid-argument",
  );
  expectValidationError(
    () => validateTestingScheduleDateTime(manilaInstant(2026, 11, 28, 10, 0), now, availability),
    "invalid-argument",
  );
});

test("canCounselorDecideTestingSchedule restricts Testing Service decisions to assigned counselors and keeps Admin read-only", () => {
  const inquiry = {
    formType: "testing_service",
    assigneeIds: ["coun-1", "admin-1"],
    takeover: false,
  };

  // Assigned counselor can manage schedule
  assert.equal(
    canCounselorDecideTestingSchedule({uid: "coun-1", role: "counselor", isSuperAdmin: false}, inquiry),
    true,
  );

  // Admin / Super Admin is strictly supervising/monitoring only (even if UID is in assigneeIds)
  assert.equal(
    canCounselorDecideTestingSchedule({uid: "admin-1", role: "admin", isSuperAdmin: true}, inquiry),
    false,
  );
  assert.equal(
    canCounselorDecideTestingSchedule({uid: "admin-2", role: "admin", isSuperAdmin: false}, inquiry),
    false,
  );
  assert.equal(
    canCounselorDecideTestingSchedule({uid: "coun-1", role: "counselor", isSuperAdmin: true}, inquiry),
    false,
  );

  // Unassigned counselor, operational staff, and taken-over inquiries are denied
  assert.equal(
    canCounselorDecideTestingSchedule({uid: "coun-2", role: "counselor", isSuperAdmin: false}, inquiry),
    false,
  );
  assert.equal(
    canCounselorDecideTestingSchedule({uid: "staff-1", role: "portalStaff", isSuperAdmin: false}, inquiry),
    false,
  );
  assert.equal(
    canCounselorDecideTestingSchedule(
      {uid: "coun-1", role: "counselor", isSuperAdmin: false},
      {...inquiry, takeover: true},
    ),
    false,
  );
});
