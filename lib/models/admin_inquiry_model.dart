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

enum InquiryEscalationType {
  counselorConfirmation,
  staffReasoned;

  String get storedValue => switch (this) {
    InquiryEscalationType.counselorConfirmation => 'counselor_confirmation',
    InquiryEscalationType.staffReasoned => 'staff_reasoned',
  };

  String get label => switch (this) {
    InquiryEscalationType.counselorConfirmation =>
      'Counselor requested administrator review',
    InquiryEscalationType.staffReasoned => 'Staff escalation',
  };

  static InquiryEscalationType? fromValue(Object? value) =>
      switch (value?.toString().trim()) {
        'counselor_confirmation' => InquiryEscalationType.counselorConfirmation,
        'staff_reasoned' => InquiryEscalationType.staffReasoned,
        _ => null,
      };
}

/// One bounded batch of the super-administrator backfill for unrouted
/// inquiries. When [done] is false, pass [nextCursor] to continue.
class InquiryRoutingBackfillResult {
  const InquiryRoutingBackfillResult({
    required this.routed,
    required this.needsTriage,
    required this.done,
    required this.nextCursor,
  });
  final int routed;
  final int needsTriage;
  final bool done;
  final String? nextCursor;
}

/// One authored reply on an inquiry (inquiries/{id}/replies/{requestId}).
class InquiryReply {
  const InquiryReply({
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

  factory InquiryReply.fromJson(
    Map<String, dynamic> json, {
    required String id,
  }) => InquiryReply(
    id: id,
    message: json['message']?.toString() ?? '',
    authorName: json['authorName']?.toString() ?? 'PACC staff',
    authorRole: json['authorRole']?.toString() ?? '',
    createdAt: dateTimeFromFirestore(json['createdAt']),
  );
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
    this.monitoringStaffIds = const [],
    this.monitoringStaffLabels = const {},
    this.ownerId,
    this.escalationStatus,
    this.escalationType,
    this.escalationReason,
    this.operationalLabel = '',
    this.isOperationalProjection = false,
    this.firstResponseAt,
    this.lastResponseAt,
    this.lastResponseByName,
    this.lastResponseRole,
    this.responseCount = 0,
    this.takeoverByName,
    this.takeoverReason,
    this.isTakenOverFlag = false,
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
  final List<String> monitoringStaffIds;
  final Map<String, String> monitoringStaffLabels;
  final String? ownerId;
  final String? escalationStatus;
  final InquiryEscalationType? escalationType;
  final String? escalationReason;
  final String operationalLabel;
  final bool isOperationalProjection;

  /// First and latest authored reply (not the acknowledgement receipt).
  final DateTime? firstResponseAt;
  final DateTime? lastResponseAt;
  final String? lastResponseByName;
  final String? lastResponseRole;
  final int responseCount;

  /// Set when the super-administrator has taken over the inquiry.
  final String? takeoverByName;
  final String? takeoverReason;
  final bool isTakenOverFlag;

  bool get isTakenOver => isTakenOverFlag || takeoverByName != null;
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

  AdminInquiryModel copyWith({InquiryStatus? status}) => AdminInquiryModel(
    id: id,
    userId: userId,
    subject: subject,
    message: message,
    category: category,
    email: email,
    createdAt: createdAt,
    status: status ?? this.status,
    name: name,
    role: role,
    formType: formType,
    formData: formData,
    acknowledgedAt: acknowledgedAt,
    assignedStaffId: assignedStaffId,
    collegeId: collegeId,
    routingStatus: routingStatus,
    routingReason: routingReason,
    routingMode: routingMode,
    routingRevision: routingRevision,
    assigneeIds: assigneeIds,
    assigneeLabels: assigneeLabels,
    monitoringStaffIds: monitoringStaffIds,
    monitoringStaffLabels: monitoringStaffLabels,
    ownerId: ownerId,
    escalationStatus: escalationStatus,
    escalationType: escalationType,
    escalationReason: escalationReason,
    operationalLabel: operationalLabel,
    isOperationalProjection: isOperationalProjection,
    firstResponseAt: firstResponseAt,
    lastResponseAt: lastResponseAt,
    lastResponseByName: lastResponseByName,
    lastResponseRole: lastResponseRole,
    responseCount: responseCount,
    takeoverByName: takeoverByName,
    takeoverReason: takeoverReason,
    isTakenOverFlag: isTakenOverFlag,
  );

  factory AdminInquiryModel.fromJson(Map<String, dynamic> json, {String? id}) {
    final parsedCategory = json['category']?.toString() ?? 'General';
    final parsedFormType = _optional(json['formType']);
    final fallbackOpLabel = parsedFormType != null
        ? _label(parsedFormType)
        : (parsedCategory.trim().isNotEmpty
              ? _label(parsedCategory)
              : 'General Inquiry');
    return AdminInquiryModel(
      id: (json['id'] ?? id ?? '').toString(),
      userId: json['userId']?.toString() ?? '',
      subject: json['subject']?.toString() ?? 'Untitled inquiry',
      message: json['message']?.toString() ?? '',
      category: parsedCategory,
      email: json['email']?.toString() ?? '',
      name: _optional(json['name']),
      role: _optional(json['role']),
      formType: parsedFormType,
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
      assigneeIds: _stringList(json['assigneeIds']),
      assigneeLabels: _stringMap(json['assigneeLabels']),
      monitoringStaffIds: _stringList(json['monitoringStaffIds']),
      monitoringStaffLabels: _stringMap(json['monitoringStaffLabels']),
      ownerId: _optional(json['ownerId']),
      escalationStatus: json['escalation'] is Map
          ? _optional((json['escalation'] as Map)['status'])
          : null,
      escalationType: json['escalation'] is Map
          ? InquiryEscalationType.fromValue((json['escalation'] as Map)['type'])
          : null,
      escalationReason: json['escalation'] is Map
          ? _optional((json['escalation'] as Map)['reason'])
          : null,
      firstResponseAt: dateTimeFromFirestore(json['firstResponseAt']),
      lastResponseAt: dateTimeFromFirestore(json['lastResponseAt']),
      lastResponseByName: _optional(json['lastResponseByName']),
      lastResponseRole: _optional(json['lastResponseRole']),
      responseCount: json['responseCount'] is num
          ? (json['responseCount'] as num).toInt()
          : 0,
      takeoverByName: json['takeover'] is Map
          ? (_optional((json['takeover'] as Map)['byName']) ??
                _optional((json['takeover'] as Map)['by']))
          : null,
      takeoverReason: json['takeover'] is Map
          ? _optional((json['takeover'] as Map)['reason'])
          : null,
      createdAt: dateTimeFromFirestoreOrNow(json['createdAt']),
      status: InquiryStatus.fromValue(json['status']),
      operationalLabel: _optional(json['operationalLabel']) ?? fallbackOpLabel,
      isOperationalProjection: false,
    );
  }

  /// Parses the server-managed, staff-safe `inquiry_statuses` projection.
  /// Student identifiers, message, user-authored subject, formData, and
  /// free-text escalation reasons are intentionally never read here.
  factory AdminInquiryModel.fromOperationalProjection(
    Map<String, dynamic> json, {
    String? id,
  }) {
    final parsedCategory = json['category']?.toString() ?? 'General';
    final parsedFormType = _optional(json['formType']);
    final fallbackLabel = parsedFormType != null
        ? _label(parsedFormType)
        : (parsedCategory.trim().isNotEmpty
              ? _label(parsedCategory)
              : 'General Inquiry');
    final safeLabel = _optional(json['operationalLabel']) ?? fallbackLabel;
    return AdminInquiryModel(
      id: (json['inquiryId'] ?? json['id'] ?? id ?? '').toString(),
      userId: '',
      subject: safeLabel,
      message: '',
      category: parsedCategory,
      email: '',
      name: null,
      role: null,
      formType: parsedFormType,
      formData: const {},
      acknowledgedAt: dateTimeFromFirestore(json['acknowledgedAt']),
      assignedStaffId: null,
      collegeId: json['collegeId']?.toString() ?? '',
      routingStatus: InquiryRoutingStatus.fromValue(json['routingStatus']),
      routingReason: _optional(json['routingReason']),
      routingMode: _optional(json['routingMode']),
      routingRevision: json['routingRevision'] is num
          ? (json['routingRevision'] as num).toInt()
          : 0,
      assigneeIds: _stringList(json['assigneeIds']),
      assigneeLabels: _stringMap(json['assigneeLabels']),
      monitoringStaffIds: _stringList(json['monitoringStaffIds']),
      monitoringStaffLabels: _stringMap(json['monitoringStaffLabels']),
      ownerId: _optional(json['ownerId']),
      escalationStatus: _optional(json['escalationStatus']),
      escalationType: null,
      escalationReason: null,
      firstResponseAt: dateTimeFromFirestore(json['firstResponseAt']),
      lastResponseAt: dateTimeFromFirestore(json['lastResponseAt']),
      lastResponseByName: null,
      lastResponseRole: null,
      responseCount: json['responseCount'] is num
          ? (json['responseCount'] as num).toInt()
          : 0,
      takeoverByName: null,
      takeoverReason: null,
      isTakenOverFlag: json['isTakenOver'] == true,
      createdAt: dateTimeFromFirestoreOrNow(json['createdAt']),
      status: InquiryStatus.fromValue(json['status']),
      operationalLabel: safeLabel,
      isOperationalProjection: true,
    );
  }

  static List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  static Map<String, String> _stringMap(Object? value) => value is Map
      ? {
          for (final entry in value.entries)
            entry.key.toString(): entry.value?.toString() ?? '',
        }
      : const {};

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
