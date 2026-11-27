import '../core/utils/firestore_mapper.dart';
import 'testing_service_schedule.dart';

enum StudentInquiryStatus {
  pending,
  inProgress,
  resolved;

  String get label => switch (this) {
    StudentInquiryStatus.pending => 'Pending',
    StudentInquiryStatus.inProgress => 'In Progress',
    StudentInquiryStatus.resolved => 'Resolved',
  };

  static StudentInquiryStatus fromValue(Object? value) =>
      switch (value?.toString().toLowerCase().replaceAll(' ', '_')) {
        'resolved' => StudentInquiryStatus.resolved,
        'in_progress' || 'inprogress' => StudentInquiryStatus.inProgress,
        _ => StudentInquiryStatus.pending,
      };
}

/// Read-only view of a student's own inquiry in `inquiries/{inquiryId}`.
class StudentInquiryRecord {
  const StudentInquiryRecord({
    required this.id,
    required this.userId,
    required this.subject,
    required this.message,
    required this.category,
    required this.status,
    required this.createdAt,
    this.formType,
    this.formData = const {},
    this.testingSchedule,
    this.testingDocuments,
    this.contactNumber,
    this.preferredScheduleAt,
    this.preferredScheduleTime,
    this.acknowledgedAt,
    this.firstResponseAt,
    this.lastResponseAt,
    this.responseCount = 0,
    this.assigneeIds = const [],
    this.assigneeLabels = const {},
    this.ownerId,
    this.lastResponseByName,
    this.lastResponseRole,
    this.takeoverByName,
  });

  final String id;
  final String userId;
  final String subject;
  final String message;
  final String category;
  final String? formType;
  final Map<String, dynamic> formData;
  final TestingServiceSchedule? testingSchedule;
  final TestingServiceDocuments? testingDocuments;
  final String? contactNumber;
  final DateTime? preferredScheduleAt;
  final String? preferredScheduleTime;
  final StudentInquiryStatus status;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;
  final DateTime? firstResponseAt;
  final DateTime? lastResponseAt;
  final int responseCount;
  final List<String> assigneeIds;
  final Map<String, String> assigneeLabels;
  final String? ownerId;
  final String? lastResponseByName;
  final String? lastResponseRole;
  final String? takeoverByName;

  bool get isTestingService => formType == testingServiceFormType;

  bool get isActiveTestingService {
    if (!isTestingService) return false;
    final sched = testingSchedule;
    if (sched != null) {
      return sched.isActive && status != StudentInquiryStatus.resolved;
    }
    return status != StudentInquiryStatus.resolved;
  }

  /// Human-readable name of the counselor/administrator processing this inquiry,
  /// so the applicant knows who to approach at the PACC office.
  String? get processingCounselorName {
    final completed = testingSchedule?.completedByName?.trim() ?? '';
    if (completed.isNotEmpty) return completed;
    final proposed = testingSchedule?.proposedByName?.trim() ?? '';
    if (proposed.isNotEmpty) return proposed;
    final cancelled = testingSchedule?.cancelledByName?.trim() ?? '';
    if (cancelled.isNotEmpty) return cancelled;
    final takeover = takeoverByName?.trim() ?? '';
    if (takeover.isNotEmpty) return takeover;
    final ownerKey = ownerId?.trim() ?? '';
    if (ownerKey.isNotEmpty) {
      final ownerLabel = assigneeLabels[ownerKey]?.trim() ?? '';
      if (ownerLabel.isNotEmpty) return ownerLabel;
    }
    for (final uid in assigneeIds) {
      final label = assigneeLabels[uid]?.trim() ?? '';
      if (label.isNotEmpty) return label;
    }
    for (final label in assigneeLabels.values) {
      final trimmed = label.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    final replier = lastResponseByName?.trim() ?? '';
    return replier.isNotEmpty ? replier : null;
  }

  String get processingCounselorRoleLabel =>
      (takeoverByName?.trim().isNotEmpty == true || lastResponseRole == 'admin')
      ? 'PACC Administrator'
      : 'PACC Counselor / Psychometrician';

  factory StudentInquiryRecord.fromJson(
    Map<String, dynamic> json, {
    String? id,
  }) {
    final rawSubject = json['subject']?.toString().trim() ?? '';
    final rawCategory = json['category']?.toString().trim() ?? '';
    final rawFormType = json['formType']?.toString().trim() ?? '';
    final rawContact = json['contactNumber']?.toString().trim() ?? '';
    final rawPreferredTime =
        json['preferredScheduleTime']?.toString().trim() ?? '';
    final rawOwnerId = json['ownerId']?.toString().trim() ?? '';
    final rawLastResponseByName =
        json['lastResponseByName']?.toString().trim() ?? '';
    final rawLastResponseRole =
        json['lastResponseRole']?.toString().trim() ?? '';
    final rawTakeover = json['takeover'];
    final rawTakeoverByName = rawTakeover is Map
        ? (rawTakeover['byName'] ?? rawTakeover['by'])?.toString().trim() ?? ''
        : '';
    return StudentInquiryRecord(
      id: (json['id'] ?? id ?? '').toString(),
      userId: json['userId']?.toString().trim() ?? '',
      subject: rawSubject.isNotEmpty ? rawSubject : 'PACC Inquiry',
      message: json['message']?.toString() ?? '',
      category: rawCategory.isNotEmpty ? rawCategory : 'General',
      formType: rawFormType.isEmpty ? null : rawFormType,
      formData: json['formData'] is Map
          ? Map<String, dynamic>.from(json['formData'] as Map)
          : const {},
      testingSchedule: TestingServiceSchedule.tryFromJson(
        json['testingSchedule'],
      ),
      testingDocuments: TestingServiceDocuments.tryFromJson(
        json['testingDocuments'],
      ),
      contactNumber: rawContact.isEmpty ? null : rawContact,
      preferredScheduleAt: dateTimeFromFirestore(json['preferredScheduleAt']),
      preferredScheduleTime: rawPreferredTime.isEmpty
          ? null
          : rawPreferredTime,
      status: StudentInquiryStatus.fromValue(json['status']),
      createdAt: dateTimeFromFirestoreOrNow(json['createdAt']),
      acknowledgedAt: dateTimeFromFirestore(json['acknowledgedAt']),
      firstResponseAt: dateTimeFromFirestore(json['firstResponseAt']),
      lastResponseAt: dateTimeFromFirestore(json['lastResponseAt']),
      responseCount: json['responseCount'] is num
          ? (json['responseCount'] as num).toInt()
          : 0,
      assigneeIds: json['assigneeIds'] is List
          ? (json['assigneeIds'] as List)
                .map((e) => e?.toString().trim() ?? '')
                .where((e) => e.isNotEmpty)
                .toList(growable: false)
          : const [],
      assigneeLabels: json['assigneeLabels'] is Map
          ? {
              for (final entry in (json['assigneeLabels'] as Map).entries)
                if ((entry.value?.toString().trim() ?? '').isNotEmpty)
                  entry.key.toString().trim(): entry.value.toString().trim(),
            }
          : const {},
      ownerId: rawOwnerId.isEmpty ? null : rawOwnerId,
      lastResponseByName:
          rawLastResponseByName.isEmpty ? null : rawLastResponseByName,
      lastResponseRole:
          rawLastResponseRole.isEmpty ? null : rawLastResponseRole,
      takeoverByName: rawTakeoverByName.isEmpty ? null : rawTakeoverByName,
    );
  }
}

/// Read-only authored counselor/administrator reply under
/// `inquiries/{inquiryId}/replies/{replyId}`.
class StudentInquiryReply {
  const StudentInquiryReply({
    required this.id,
    required this.message,
    required this.authorName,
    required this.authorRole,
    required this.createdAt,
  });

  final String id;
  final String message;
  final String authorName;
  final String authorRole;
  final DateTime? createdAt;

  bool get isAdministrator => authorRole == 'admin';

  String get roleLabel =>
      isAdministrator ? 'PACC Administrator' : 'PACC Counselor';

  factory StudentInquiryReply.fromJson(
    Map<String, dynamic> json, {
    required String id,
  }) {
    final name = json['authorName']?.toString().trim() ?? '';
    return StudentInquiryReply(
      id: id,
      message: json['message']?.toString() ?? '',
      authorName: name.isNotEmpty ? name : 'PACC staff',
      authorRole: json['authorRole']?.toString().trim() ?? '',
      createdAt: dateTimeFromFirestore(json['createdAt']),
    );
  }
}
