import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/profile_roles.dart';

enum StaffAccountStatus {
  pending,
  approved,
  rejected,
  disabled;

  String get label => switch (this) {
    pending => 'Pending',
    approved => 'Approved',
    rejected => 'Rejected',
    disabled => 'Disabled',
  };

  static StaffAccountStatus? parse(Object? value) =>
      switch (value?.toString()) {
        'pending' => pending,
        'approved' => approved,
        'rejected' => rejected,
        'disabled' => disabled,
        _ => null,
      };
}

class StaffRegistration {
  const StaffRegistration({
    required this.userId,
    required this.email,
    required this.employeeId,
    required this.status,
  });
  final String userId;
  final String email;
  final String employeeId;
  final StaffAccountStatus status;
}

class PublicAppUserRecord {
  const PublicAppUserRecord({
    required this.userId,
    required this.publicUserId,
    required this.populationRole,
    required this.department,
    this.createdAt,
  });

  final String userId;
  final String publicUserId;
  final PopulationRole populationRole;
  final String department;
  final DateTime? createdAt;

  factory PublicAppUserRecord.fromJson(Map<String, dynamic> json) =>
      PublicAppUserRecord(
        userId: '${json['userId'] ?? ''}',
        publicUserId: '${json['publicUserId'] ?? ''}',
        populationRole:
            PopulationRole.parse(json['populationRole']) ??
            PopulationRole.student,
        department: '${json['department'] ?? ''}'.trim(),
        createdAt: _publicUserDate(json['createdAt']),
      );
}

DateTime? _publicUserDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

class OrganizationRecord {
  const OrganizationRecord({
    required this.id,
    required this.name,
    required this.code,
    required this.active,
  });
  final String id;
  final String name;
  final String code;
  final bool active;
  String get status => active ? 'ACTIVE' : 'INACTIVE';
}

class College extends OrganizationRecord {
  const College({
    required super.id,
    required super.name,
    required super.code,
    required super.active,
  });
  factory College.fromJson(Map<String, dynamic> json) => College(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}',
    code: '${json['code'] ?? ''}',
    active: json['active'] == true,
  );
}

class Department extends OrganizationRecord {
  const Department({
    required super.id,
    required super.name,
    required super.code,
    required super.active,
    this.collegeId = '',
  });
  final String collegeId;
  factory Department.fromJson(Map<String, dynamic> json) => Department(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}',
    code: '${json['code'] ?? ''}',
    active: json['active'] == true,
    collegeId: '${json['collegeId'] ?? ''}',
  );
}

class Course extends OrganizationRecord {
  const Course({
    required super.id,
    required super.name,
    required super.code,
    required super.active,
    required this.collegeId,
    this.departmentId = '',
  });
  final String collegeId;
  final String departmentId;
  factory Course.fromJson(Map<String, dynamic> json) => Course(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}',
    code: '${json['code'] ?? ''}',
    active: json['active'] == true,
    collegeId: '${json['collegeId'] ?? ''}',
    departmentId: '${json['departmentId'] ?? ''}',
  );
}

class AdminAuditEvent {
  const AdminAuditEvent({
    required this.id,
    required this.action,
    required this.actorId,
    required this.targetUserId,
    required this.reason,
    this.category = '',
    this.actorNameSnapshot = '',
    this.actorRoleSnapshot = '',
    this.targetType,
    this.targetId,
    this.metadata = const {},
    this.createdAt,
  });
  final String id;
  final String action;
  final String actorId;
  final String targetUserId;
  final String reason;
  final String category;
  final String actorNameSnapshot;
  final String actorRoleSnapshot;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  factory AdminAuditEvent.fromJson(
    Map<String, dynamic> json,
  ) => AdminAuditEvent(
    id: '${json['id'] ?? ''}',
    action: '${json['action'] ?? ''}',
    actorId: '${json['actorId'] ?? ''}',
    targetUserId: '${json['targetUserId'] ?? ''}',
    reason:
        '${json['reason'] ?? (json['metadata'] is Map ? (json['metadata'] as Map)['reason'] : '') ?? ''}',
    category: '${json['category'] ?? ''}',
    actorNameSnapshot: '${json['actorNameSnapshot'] ?? ''}',
    actorRoleSnapshot:
        '${json['actorRoleSnapshot'] ?? json['actorAccessRole'] ?? ''}',
    targetType: json['targetType']?.toString(),
    targetId: json['targetId']?.toString(),
    metadata: json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : const {},
    createdAt: json['createdAt'] is Timestamp
        ? (json['createdAt'] as Timestamp).toDate()
        : json['timestamp'] is Timestamp
        ? (json['timestamp'] as Timestamp).toDate()
        : DateTime.tryParse('${json['createdAt'] ?? json['timestamp'] ?? ''}'),
  );
}
