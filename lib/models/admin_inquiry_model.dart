import '../core/utils/firestore_mapper.dart';

enum InquiryStatus {
  pending,
  inProgress,
  resolved;

  String get storedValue => switch (this) {
    InquiryStatus.pending => 'pending',
    InquiryStatus.inProgress => 'in_progress',
    InquiryStatus.resolved => 'resolved',
  };

  String get label => switch (this) {
    InquiryStatus.pending => 'Pending',
    InquiryStatus.inProgress => 'In Progress',
    InquiryStatus.resolved => 'Resolved',
  };

  static InquiryStatus fromValue(Object? value) =>
      switch (value?.toString().toLowerCase().replaceAll(' ', '_')) {
        'resolved' => InquiryStatus.resolved,
        'in_progress' || 'inprogress' => InquiryStatus.inProgress,
        _ => InquiryStatus.pending,
      };
}

/// Server-side college routing state (functions/src/inquiry_routing_service.ts).
enum InquiryRoutingStatus {
  unrouted,
  routed,
  needsTriage;

  String get label => switch (this) {
    InquiryRoutingStatus.unrouted => 'Not yet routed',
    InquiryRoutingStatus.routed => 'Routed',
    InquiryRoutingStatus.needsTriage => 'Needs triage',
  };

  static InquiryRoutingStatus fromValue(Object? value) => switch (value) {
    'routed' => InquiryRoutingStatus.routed,
    'needs_triage' => InquiryRoutingStatus.needsTriage,
    _ => InquiryRoutingStatus.unrouted,
  };
}

/// Result of the super-administrator backfill for unrouted inquiries.
class InquiryRoutingBackfillResult {
  const InquiryRoutingBackfillResult({
    required this.routed,
    required this.needsTriage,
    required this.remaining,
  });
  final int routed;
  final int needsTriage;
  final int remaining;
}

class AdminInquiryModel {
  const AdminInquiryModel({
    required this.id,
    required this.userId,
    required this.subject,
    required this.message,
    required this.category,
    required this.email,
    required this.createdAt,
    required this.status,
    this.name,
    this.role,
    this.formType,
    this.formData = const {},
    this.acknowledgedAt,
    this.assignedStaffId,
    this.collegeId = '',
    this.routingStatus = InquiryRoutingStatus.unrouted,
    this.routingReason,
    this.routingMode,
    this.routingRevision = 0,
    this.assigneeIds = const [],
    this.assigneeLabels = const {},
    this.ownerId,
    this.escalationStatus,
    this.escalationReason,
  });

  final String id;
  final String userId;
  final String subject;
  final String message;
  final String category;
  final String email;
  final DateTime createdAt;
  final InquiryStatus status;
  final String? name;
  final String? role;
  final String? formType;
  final Map<String, dynamic> formData;
  final DateTime? acknowledgedAt;

  /// Portal account that owns this inquiry, when one has been recorded.
  /// Not written by any server flow yet; `null` means unassigned.
  final String? assignedStaffId;

  /// Routing fields are written only by Cloud Functions.
  final String collegeId;
  final InquiryRoutingStatus routingStatus;
  final String? routingReason;
  final String? routingMode;
  final int routingRevision;
  final List<String> assigneeIds;
  final Map<String, String> assigneeLabels;
  final String? ownerId;
  final String? escalationStatus;
  final String? escalationReason;

  bool get isManuallyRouted => routingMode == 'manual';
  bool get isEscalated => escalationStatus == 'requested';

  bool get isFormSubmission => formType != null && formType!.isNotEmpty;
  bool get isAcknowledged => acknowledgedAt != null;

  String get typeLabel {
    final rawType = (formType ?? '').trim();
    if (rawType.isNotEmpty) return _label(rawType);
    final rawCategory = category.trim();
    if (rawCategory.isNotEmpty) return _label(rawCategory);
    return 'General Inquiry';
  }

  String get displayName =>
      (name ?? '').trim().isNotEmpty ? name!.trim() : email;

  factory AdminInquiryModel.fromJson(Map<String, dynamic> json, {String? id}) {
    return AdminInquiryModel(
      id: (json['id'] ?? id ?? '').toString(),
      userId: json['userId']?.toString() ?? '',
      subject: json['subject']?.toString() ?? 'Untitled inquiry',
      message: json['message']?.toString() ?? '',
      category: json['category']?.toString() ?? 'General',
      email: json['email']?.toString() ?? '',
      name: _optional(json['name']),
      role: _optional(json['role']),
      formType: _optional(json['formType']),
      formData: json['formData'] is Map
          ? Map<String, dynamic>.from(json['formData'] as Map)
          : const {},
      acknowledgedAt: dateTimeFromFirestore(json['acknowledgedAt']),
      assignedStaffId: _optional(json['assignedStaffId']),
      collegeId: json['collegeId']?.toString() ?? '',
      routingStatus: InquiryRoutingStatus.fromValue(json['routingStatus']),
      routingReason: _optional(json['routingReason']),
      routingMode: _optional(json['routingMode']),
      routingRevision: json['routingRevision'] is num
          ? (json['routingRevision'] as num).toInt()
          : 0,
      assigneeIds: json['assigneeIds'] is List
          ? (json['assigneeIds'] as List).whereType<String>().toList()
          : const [],
      assigneeLabels: json['assigneeLabels'] is Map
          ? {
              for (final entry in (json['assigneeLabels'] as Map).entries)
                entry.key.toString(): entry.value?.toString() ?? '',
            }
          : const {},
      ownerId: _optional(json['ownerId']),
      escalationStatus: json['escalation'] is Map
          ? _optional((json['escalation'] as Map)['status'])
          : null,
      escalationReason: json['escalation'] is Map
          ? _optional((json['escalation'] as Map)['reason'])
          : null,
      createdAt: dateTimeFromFirestoreOrNow(json['createdAt']),
      status: InquiryStatus.fromValue(json['status']),
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'subject': subject,
    'message': message,
    'category': category,
    'email': email,
    'name': name ?? '',
    'role': role ?? '',
    'formType': formType ?? '',
    'formData': formData,
    'status': status.storedValue,
    'createdAt': createdAt,
  };

  static String? _optional(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static String _label(String value) => value
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}
