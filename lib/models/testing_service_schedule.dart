import 'dart:typed_data';

import '../core/utils/firestore_mapper.dart';
import 'appointment_model.dart';
import 'pacc_availability_model.dart';
import 'profile_roles.dart';
import 'user_model.dart';

const String testingServiceFormType = 'testing_service';
const String testingServiceDefaultLocation = 'PACC Testing Room';
const int testingServiceMaxReschedules = 1;
const int testingDocumentMaxBytes = 5 * 1024 * 1024;
const int testingDocumentMaxAdmissionFiles = 3;

const Map<String, String> _testingDocumentMimeByExt = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'pdf': 'application/pdf',
};

String? testingDocumentMimeType(String fileName) {
  final period = fileName.lastIndexOf('.');
  if (period < 1) return null;
  final ext = fileName.substring(period + 1).toLowerCase();
  return _testingDocumentMimeByExt[ext];
}

/// Canonical display and download filename for Testing Service uploads so raw
/// device camera/temp filenames never appear in student or PACC views.
String standardizedTestingDocumentFileName(
  TestingDocumentKind kind,
  String rawName, {
  int? admissionIndex,
}) {
  final period = rawName.lastIndexOf('.');
  final candidateExt = period >= 0
      ? rawName.substring(period + 1).trim().toLowerCase()
      : '';
  final ext = _testingDocumentMimeByExt.containsKey(candidateExt)
      ? candidateExt
      : 'png';
  return switch (kind) {
    TestingDocumentKind.endorsementLetter => 'Endorsement_Letter.$ext',
    TestingDocumentKind.officialReceipt => 'Official_Receipt_PHP250.$ext',
    TestingDocumentKind.admissionRequirement =>
      admissionIndex != null && admissionIndex > 0
          ? 'Admission_Requirement_$admissionIndex.$ext'
          : 'Admission_Requirement.$ext',
  };
}

enum TestingServiceClientType {
  ucuEmployee,
  studentForOjt;

  String get label => switch (this) {
    TestingServiceClientType.ucuEmployee => 'UCU Employee',
    TestingServiceClientType.studentForOjt => 'Student for OJT',
  };
}

enum TestingDocumentKind {
  endorsementLetter,
  officialReceipt,
  admissionRequirement;

  String get wireValue => switch (this) {
    TestingDocumentKind.endorsementLetter => 'endorsement_letter',
    TestingDocumentKind.officialReceipt => 'official_receipt',
    TestingDocumentKind.admissionRequirement => 'admission_requirement',
  };

  String get label => switch (this) {
    TestingDocumentKind.endorsementLetter => 'Endorsement Letter',
    TestingDocumentKind.officialReceipt => 'Official Receipt (PHP 250.00)',
    TestingDocumentKind.admissionRequirement => 'Admission Requirements',
  };

  static TestingDocumentKind fromValue(Object? raw) =>
      switch (raw?.toString().trim()) {
        'official_receipt' => TestingDocumentKind.officialReceipt,
        'admission_requirement' => TestingDocumentKind.admissionRequirement,
        _ => TestingDocumentKind.endorsementLetter,
      };
}

class TestingServiceDocumentRef {
  const TestingServiceDocumentRef({
    required this.path,
    required this.name,
    required this.contentType,
    required this.size,
    required this.kind,
  });

  final String path;
  final String name;
  final String contentType;
  final int size;
  final TestingDocumentKind kind;

  bool get isImage => contentType.startsWith('image/');
  bool get isPdf => contentType == 'application/pdf';

  String displayFileName({int? admissionIndex}) =>
      standardizedTestingDocumentFileName(
        kind,
        name,
        admissionIndex: admissionIndex,
      );

  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    'contentType': contentType,
    'size': size,
    'kind': kind.wireValue,
  };

  static TestingServiceDocumentRef? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final path = json['path']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final contentType = json['contentType']?.toString().trim() ?? '';
    final size = json['size'] is num ? (json['size'] as num).toInt() : 0;
    if (path.isEmpty || name.isEmpty || size <= 0) return null;
    return TestingServiceDocumentRef(
      path: path,
      name: name,
      contentType: contentType,
      size: size,
      kind: TestingDocumentKind.fromValue(json['kind']),
    );
  }
}

class TestingServiceDocuments {
  const TestingServiceDocuments({
    this.endorsementLetter,
    this.officialReceipt,
    this.admissionRequirements = const [],
  });

  final TestingServiceDocumentRef? endorsementLetter;
  final TestingServiceDocumentRef? officialReceipt;
  final List<TestingServiceDocumentRef> admissionRequirements;

  List<TestingServiceDocumentRef> get all => [
    ?endorsementLetter,
    ?officialReceipt,
    ...admissionRequirements,
  ];

  bool get isEmpty => all.isEmpty;

  static TestingServiceDocuments? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final endorsement = TestingServiceDocumentRef.tryFromJson(
      json['endorsementLetter'],
    );
    final receipt = TestingServiceDocumentRef.tryFromJson(
      json['officialReceipt'],
    );
    final rawAdmission = json['admissionRequirements'];
    final admissions = rawAdmission is List
        ? rawAdmission
              .map(TestingServiceDocumentRef.tryFromJson)
              .whereType<TestingServiceDocumentRef>()
              .toList(growable: false)
        : const <TestingServiceDocumentRef>[];
    if (endorsement == null && receipt == null && admissions.isEmpty) {
      return null;
    }
    return TestingServiceDocuments(
      endorsementLetter: endorsement,
      officialReceipt: receipt,
      admissionRequirements: admissions,
    );
  }
}

class PendingTestingDocument {
  const PendingTestingDocument({
    required this.name,
    required this.contentType,
    required this.bytes,
    required this.kind,
    this.uploadedRef,
  });

  final String name;
  final String contentType;
  final Uint8List bytes;
  final TestingDocumentKind kind;
  final TestingServiceDocumentRef? uploadedRef;

  int get size => bytes.length;
  bool get isImage => contentType.startsWith('image/');
  bool get isPdf => contentType == 'application/pdf';

  String displayFileName({int? admissionIndex}) =>
      standardizedTestingDocumentFileName(
        kind,
        name,
        admissionIndex: admissionIndex,
      );

  PendingTestingDocument copyWithUploaded(TestingServiceDocumentRef ref) =>
      PendingTestingDocument(
        name: name,
        contentType: contentType,
        bytes: bytes,
        kind: kind,
        uploadedRef: ref,
      );
}

class PersonalDataSheetInput {
  const PersonalDataSheetInput({
    required this.fullName,
    required this.email,
    this.idNumber = '',
    this.officeOrCollege = '',
    this.courseOrPosition = '',
  });

  final String fullName;
  final String email;
  final String idNumber;
  final String officeOrCollege;
  final String courseOrPosition;

  Map<String, Object?> toJson() => {
    'fullName': fullName.trim(),
    'email': email.trim(),
    'idNumber': idNumber.trim(),
    'officeOrCollege': officeOrCollege.trim(),
    'courseOrPosition': courseOrPosition.trim(),
  };
}

enum TestingScheduleStatus {
  awaitingSchedule,
  proposed,
  rescheduleRequested,
  confirmed,
  completed,
  cancelled;

  String get storedValue => switch (this) {
    TestingScheduleStatus.awaitingSchedule => 'awaiting_schedule',
    TestingScheduleStatus.proposed => 'proposed',
    TestingScheduleStatus.rescheduleRequested => 'reschedule_requested',
    TestingScheduleStatus.confirmed => 'confirmed',
    TestingScheduleStatus.completed => 'completed',
    TestingScheduleStatus.cancelled => 'cancelled',
  };

  String get label => switch (this) {
    TestingScheduleStatus.awaitingSchedule => 'Awaiting Schedule',
    TestingScheduleStatus.proposed => 'Schedule Proposed',
    TestingScheduleStatus.rescheduleRequested => 'Reschedule Requested',
    TestingScheduleStatus.confirmed => 'Schedule Confirmed',
    TestingScheduleStatus.completed => 'Completed',
    TestingScheduleStatus.cancelled => 'Cancelled',
  };

  static TestingScheduleStatus fromValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase().replaceAll(
      '-',
      '_',
    );
    return switch (normalized) {
      'proposed' => TestingScheduleStatus.proposed,
      'reschedule_requested' => TestingScheduleStatus.rescheduleRequested,
      'confirmed' => TestingScheduleStatus.confirmed,
      'completed' => TestingScheduleStatus.completed,
      'cancelled' || 'canceled' => TestingScheduleStatus.cancelled,
      _ => TestingScheduleStatus.awaitingSchedule,
    };
  }
}

class TestingServiceClientEligibility {
  const TestingServiceClientEligibility({
    required this.isEligible,
    required this.requiresOjtConfirmation,
    required this.requesterLabel,
    this.ineligibleReason,
  });

  final bool isEligible;
  final bool requiresOjtConfirmation;
  final String requesterLabel;
  final String? ineligibleReason;
}

TestingServiceClientEligibility evaluateTestingServiceClientEligibility(
  UserModel? user,
) {
  if (user == null) {
    return const TestingServiceClientEligibility(
      isEligible: false,
      requiresOjtConfirmation: false,
      requesterLabel: '',
      ineligibleReason:
          'Please sign in with an eligible MindMate account (Student for OJT, Teaching employee, or Non-Teaching employee).',
    );
  }
  final accountStatus = (user.accountStatus ?? 'active').trim().toLowerCase();
  if (user.accessRole != AccessRole.appUser ||
      user.staffAccountStatus != null ||
      accountStatus != 'active') {
    return const TestingServiceClientEligibility(
      isEligible: false,
      requiresOjtConfirmation: false,
      requesterLabel: '',
      ineligibleReason:
          'Testing Service requests are available only to Students for OJT, Teaching employees, and Non-Teaching employees.',
    );
  }
  return switch (user.effectivePopulationRole) {
    PopulationRole.student => const TestingServiceClientEligibility(
      isEligible: true,
      requiresOjtConfirmation: true,
      requesterLabel: 'Student (OJT)',
    ),
    PopulationRole.teaching => const TestingServiceClientEligibility(
      isEligible: true,
      requiresOjtConfirmation: false,
      requesterLabel: 'Teaching Employee',
    ),
    PopulationRole.nonTeaching => const TestingServiceClientEligibility(
      isEligible: true,
      requiresOjtConfirmation: false,
      requesterLabel: 'Non-Teaching Employee',
    ),
    null => const TestingServiceClientEligibility(
      isEligible: false,
      requiresOjtConfirmation: false,
      requesterLabel: '',
      ineligibleReason:
          'Your profile role must be Student (for OJT), Teaching, or Non-Teaching to request Testing Service.',
    ),
  };
}

/// Checks whether a Manila wall-clock [DateTime] falls within Testing Service
/// hours: Monday through Saturday, 8:00 AM to 5:00 PM inclusive.
bool isWithinTestingServiceAvailability(DateTime manilaWallClock) {
  if (manilaWallClock.weekday == DateTime.sunday) return false;
  final totalMinutes = manilaWallClock.hour * 60 + manilaWallClock.minute;
  return totalMinutes >= 8 * 60 && totalMinutes <= 17 * 60;
}

/// Converts a Manila wall-clock date + hour/minute into the UTC-backed [DateTime]
/// representing that exact Asia/Manila instant.
DateTime testingServiceInstantFromManila({
  required int year,
  required int month,
  required int day,
  required int hour,
  int minute = 0,
}) => DateTime.utc(year, month, day, hour, minute).subtract(
  const Duration(hours: 8),
);

String formatTestingServiceTime(DateTime wallClock) {
  final hour = wallClock.hour % 12 == 0 ? 12 : wallClock.hour % 12;
  final minute = wallClock.minute.toString().padLeft(2, '0');
  final period = wallClock.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

const List<int> testingServiceSlotHours = [
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
];

class TestingServiceSlot {
  const TestingServiceSlot({
    required this.instant,
    required this.label,
    required this.available,
    this.closureReason,
  });

  final DateTime instant;
  final String label;
  final bool available;
  final String? closureReason;
}

/// Resolves selectable hourly Testing Service slots for a Manila calendar date
/// from Admin PACC Availability (`pacc_availability/current`), falling back to
/// Mon-Sat 8:00 AM-5:00 PM PHT when availability has not loaded.
List<TestingServiceSlot> testingServiceSlotsForDate(
  DateTime localDate, {
  PaccAvailabilityModel? availability,
  DateTime? now,
}) {
  final cutoff = now ?? DateTime.now();
  if (availability == null) {
    return [
      for (final hour in testingServiceSlotHours)
        () {
          final wallClock = DateTime(
            localDate.year,
            localDate.month,
            localDate.day,
            hour,
          );
          final instant = testingServiceInstantFromManila(
            year: localDate.year,
            month: localDate.month,
            day: localDate.day,
            hour: hour,
          );
          final available =
              isWithinTestingServiceAvailability(wallClock) &&
              instant.isAfter(cutoff);
          return TestingServiceSlot(
            instant: instant,
            label: formatTestingServiceTime(wallClock),
            available: available,
          );
        }(),
    ];
  }

  final slots = <TestingServiceSlot>[];
  for (var hour = 6; hour <= 20; hour++) {
    final wallClock = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
      hour,
    );
    final instant = testingServiceInstantFromManila(
      year: localDate.year,
      month: localDate.month,
      day: localDate.day,
      hour: hour,
    );
    final resolved = availability.resolveScheduleAt(instant);
    final openMinutes = _parseHhMmMinutes(resolved.schedule.opensAt);
    final closeMinutes = _parseHhMmMinutes(resolved.schedule.closesAt);
    final slotMinutes = hour * 60;
    if (slotMinutes < openMinutes || slotMinutes >= closeMinutes) {
      continue;
    }
    final available = resolved.canBookAppointments && instant.isAfter(cutoff);
    slots.add(
      TestingServiceSlot(
        instant: instant,
        label: formatTestingServiceTime(wallClock),
        available: available,
        closureReason: resolved.closureReason,
      ),
    );
  }
  return slots;
}

int _parseHhMmMinutes(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return 0;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts[1]) ?? 0;
  return hour * 60 + minute;
}

bool isTestingServiceDateSelectable(
  DateTime localDate, {
  PaccAvailabilityModel? availability,
  DateTime? now,
}) => testingServiceSlotsForDate(
  localDate,
  availability: availability,
  now: now,
).any((slot) => slot.available);

DateTime nextSelectableTestingServiceDate({
  DateTime? startingFrom,
  PaccAvailabilityModel? availability,
  int maxDays = 60,
}) {
  final now = DateTime.now();
  final base = startingFrom ?? now;
  final startDay = DateTime(base.year, base.month, base.day);
  for (var offset = 0; offset <= maxDays; offset++) {
    final candidate = startDay.add(Duration(days: offset));
    if (isTestingServiceDateSelectable(
      candidate,
      availability: availability,
      now: now,
    )) {
      return candidate;
    }
  }
  return startDay.add(const Duration(days: 1));
}

class TestingServiceSchedule {
  const TestingServiceSchedule({
    required this.status,
    this.scheduledAt,
    this.scheduledTime,
    this.location = testingServiceDefaultLocation,
    this.proposedBy,
    this.proposedByName,
    this.proposedAt,
    this.staffNote,
    this.rescheduleCount = 0,
    this.maxReschedules = testingServiceMaxReschedules,
    this.rescheduleReason,
    this.rescheduleRequestedAt,
    this.confirmedAt,
    this.confirmedBy,
    this.completedAt,
    this.completedBy,
    this.completedByName,
    this.completionNote,
    this.cancelReason,
    this.cancelledByName,
    this.cancelledAt,
    this.revision = 0,
  });

  final TestingScheduleStatus status;
  final DateTime? scheduledAt;
  final String? scheduledTime;
  final String location;
  final String? proposedBy;
  final String? proposedByName;
  final DateTime? proposedAt;
  final String? staffNote;
  final int rescheduleCount;
  final int maxReschedules;
  final String? rescheduleReason;
  final DateTime? rescheduleRequestedAt;
  final DateTime? confirmedAt;
  final String? confirmedBy;
  final DateTime? completedAt;
  final String? completedBy;
  final String? completedByName;
  final String? completionNote;
  final String? cancelReason;
  final String? cancelledByName;
  final DateTime? cancelledAt;
  final int revision;

  bool get hasSchedule => scheduledAt != null;
  bool get isProposed => status == TestingScheduleStatus.proposed;
  bool get isRescheduleRequested =>
      status == TestingScheduleStatus.rescheduleRequested;
  bool get isConfirmed => status == TestingScheduleStatus.confirmed;
  bool get isCompleted => status == TestingScheduleStatus.completed;
  bool get isCancelled => status == TestingScheduleStatus.cancelled;
  bool get isActive => !isCancelled && !isCompleted;
  bool get hasUsedReschedule => rescheduleCount >= maxReschedules;
  bool get canUserAccept => isProposed && hasSchedule;
  bool get canUserRequestReschedule =>
      isProposed && hasSchedule && !hasUsedReschedule;

  DateTime? get scheduledAtManila {
    final dt = scheduledAt;
    if (dt == null) return null;
    final shifted = dt.toUtc().add(const Duration(hours: 8));
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
    );
  }

  /// Narrow display-only projection onto [AppointmentModel] so existing
  /// schedule display patterns can be reused without writing to or coupling
  /// with the counseling `appointments` collection or lifecycle.
  AppointmentModel? toDisplayAppointment({
    required String inquiryId,
    required String userId,
    required String fullName,
    required String email,
    required String concern,
    required DateTime createdAt,
  }) {
    if (isCancelled) return null;
    final manila = scheduledAtManila;
    if (manila == null) return null;
    final resolvedTime = (scheduledTime ?? '').trim().isNotEmpty
        ? scheduledTime!.trim()
        : formatTestingServiceTime(manila);
    return AppointmentModel(
      id: inquiryId,
      userId: userId,
      fullName: fullName,
      scheduledAt: manila,
      scheduledTime: resolvedTime,
      location: location.trim().isNotEmpty
          ? location.trim()
          : testingServiceDefaultLocation,
      status: isConfirmed ? 'confirmed' : 'requested',
      concern: concern,
      contactNumber: '',
      email: email,
      preferredContactMethod: 'In-app notifications',
      createdAt: createdAt,
      counselorName: proposedByName,
      assignedStaffId: proposedBy,
      staffReply: staffNote,
      reviewedAt: proposedAt,
      rescheduleReason: rescheduleReason,
    );
  }

  static TestingServiceSchedule? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final rawLocation = json['location']?.toString().trim() ?? '';
    final maxReschedules = json['maxReschedules'] is num
        ? (json['maxReschedules'] as num).toInt()
        : testingServiceMaxReschedules;
    return TestingServiceSchedule(
      status: TestingScheduleStatus.fromValue(json['status']),
      scheduledAt: dateTimeFromFirestore(json['scheduledAt']),
      scheduledTime: _optionalString(json['scheduledTime']),
      location: rawLocation.isNotEmpty
          ? rawLocation
          : testingServiceDefaultLocation,
      proposedBy: _optionalString(json['proposedBy']),
      proposedByName: _optionalString(json['proposedByName']),
      proposedAt: dateTimeFromFirestore(json['proposedAt']),
      staffNote: _optionalString(json['staffNote']),
      rescheduleCount: json['rescheduleCount'] is num
          ? (json['rescheduleCount'] as num).toInt()
          : 0,
      maxReschedules: maxReschedules > 0
          ? maxReschedules
          : testingServiceMaxReschedules,
      rescheduleReason: _optionalString(json['rescheduleReason']),
      rescheduleRequestedAt: dateTimeFromFirestore(
        json['rescheduleRequestedAt'],
      ),
      confirmedAt: dateTimeFromFirestore(json['confirmedAt']),
      confirmedBy: _optionalString(json['confirmedBy']),
      completedAt: dateTimeFromFirestore(json['completedAt']),
      completedBy: _optionalString(json['completedBy']),
      completedByName: _optionalString(json['completedByName']),
      completionNote: _optionalString(json['completionNote']),
      cancelReason: _optionalString(json['cancelReason']),
      cancelledByName: _optionalString(json['cancelledByName']),
      cancelledAt: dateTimeFromFirestore(json['cancelledAt']),
      revision: json['revision'] is num ? (json['revision'] as num).toInt() : 0,
    );
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
