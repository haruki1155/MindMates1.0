import '../core/utils/firestore_mapper.dart';

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
    this.acknowledgedAt,
    this.firstResponseAt,
    this.lastResponseAt,
    this.responseCount = 0,
  });

  final String id;
  final String userId;
  final String subject;
  final String message;
  final String category;
  final String? formType;
  final StudentInquiryStatus status;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;
  final DateTime? firstResponseAt;
  final DateTime? lastResponseAt;
  final int responseCount;

  factory StudentInquiryRecord.fromJson(
    Map<String, dynamic> json, {
    String? id,
  }) {
    final rawSubject = json['subject']?.toString().trim() ?? '';
    final rawCategory = json['category']?.toString().trim() ?? '';
    final rawFormType = json['formType']?.toString().trim() ?? '';
    return StudentInquiryRecord(
      id: (json['id'] ?? id ?? '').toString(),
      userId: json['userId']?.toString().trim() ?? '',
      subject: rawSubject.isNotEmpty ? rawSubject : 'PACC Inquiry',
      message: json['message']?.toString() ?? '',
      category: rawCategory.isNotEmpty ? rawCategory : 'General',
      formType: rawFormType.isEmpty ? null : rawFormType,
      status: StudentInquiryStatus.fromValue(json['status']),
      createdAt: dateTimeFromFirestoreOrNow(json['createdAt']),
      acknowledgedAt: dateTimeFromFirestore(json['acknowledgedAt']),
      firstResponseAt: dateTimeFromFirestore(json['firstResponseAt']),
      lastResponseAt: dateTimeFromFirestore(json['lastResponseAt']),
      responseCount: json['responseCount'] is num
          ? (json['responseCount'] as num).toInt()
          : 0,
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
