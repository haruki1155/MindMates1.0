import '../core/utils/firestore_mapper.dart';

/// The only lifecycle values written by the current appointment backend.
/// [legacyRequested] is read-only compatibility for old `pending`/`upcoming`
/// records; newly created appointments are always [requested].
enum AppointmentStatus {
  requested,
  confirmed,
  rescheduleProposed,
  cancelled,
  completed,
  noShow,
  declined,
  expired,
  legacyRequested,
  unknown;

  static AppointmentStatus parse(Object? value) =>
      switch (value?.toString().trim().toLowerCase()) {
        'requested' => requested,
        'confirmed' => confirmed,
        'reschedule_proposed' => rescheduleProposed,
        'cancelled' || 'canceled' => cancelled,
        'completed' || 'complete' => completed,
        'no_show' || 'noshow' || 'no-show' => noShow,
        'declined' => declined,
        'expired' => expired,
        'pending' || 'upcoming' || 'reschedule_required' => legacyRequested,
        _ => unknown,
      };

  String get value => switch (this) {
    requested || legacyRequested => 'requested',
    confirmed => 'confirmed',
    rescheduleProposed => 'reschedule_proposed',
    cancelled => 'cancelled',
    completed => 'completed',
    noShow => 'no_show',
    declined => 'declined',
    expired => 'expired',
    unknown => 'requested',
  };

  String get label => switch (this) {
    requested || legacyRequested => 'REQUESTED',
    confirmed => 'CONFIRMED',
    rescheduleProposed => 'SCHEDULE CHANGE',
    cancelled => 'CANCELLED',
    completed => 'COMPLETED',
    noShow => 'DID NOT ATTEND',
    declined => 'DECLINED',
    expired => 'EXPIRED',
    unknown => 'REQUESTED',
  };

  bool get isTerminal => switch (this) {
    cancelled || completed || noShow || declined || expired => true,
    _ => false,
  };
}

class AppointmentModel {
  const AppointmentModel({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.scheduledAt,
    required this.scheduledTime,
    required this.location,
    required this.status,
    required this.concern,
    required this.contactNumber,
    required this.email,
    required this.preferredContactMethod,
    required this.createdAt,
    this.age,
    this.address,
    this.facebook,
    this.sex,
    this.course,
    this.yearLevel,
    this.therapyBefore,
    this.bestTime,
    this.counselorName,
    this.updatedAt,
    this.assignedStaffId,
    this.staffReply,
    this.reviewedAt,
    this.proposedScheduledAt,
    this.proposedScheduledTime,
    this.proposedBy,
    this.proposalStatus,
    this.department,
    this.academicYearId,
    this.archivedAt,
    this.parentAppointmentId,
    this.rescheduleReason,
    this.followUpRecommended = false,
    this.followUpMessage,
    this.followUpStatus = 'none',
    this.followUpAppointmentId,
  });

  final String id;
  final String userId;
  final String fullName;
  final int? age;
  final String? address;
  final String contactNumber;
  final String email;
  final String? facebook;
  final String? sex;
  final String? course;
  final String? yearLevel;
  final String preferredContactMethod;
  final String? therapyBefore;
  final String concern;
  final String? bestTime;
  final DateTime scheduledAt;
  final String scheduledTime;
  final String location;
  final String status;
  final String? counselorName;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? assignedStaffId;
  final String? staffReply;
  final DateTime? reviewedAt;
  final DateTime? proposedScheduledAt;
  final String? proposedScheduledTime;
  final String? proposedBy;
  final String? proposalStatus;
  final String? department;
  final String? academicYearId;
  final DateTime? archivedAt;
  final String? parentAppointmentId;
  final String? rescheduleReason;
  final bool followUpRecommended;
  final String? followUpMessage;
  final String followUpStatus;
  final String? followUpAppointmentId;

  bool get isArchived => archivedAt != null;
  AppointmentStatus get lifecycleStatus => AppointmentStatus.parse(status);

  bool get isFinalized => const {
    'completed',
    'complete',
    'declined',
    'cancelled',
    'canceled',
    'no_show',
    'noshow',
    'expired',
  }.contains(status.toLowerCase().trim());

  bool get isActive => switch (lifecycleStatus) {
    AppointmentStatus.requested ||
    AppointmentStatus.legacyRequested ||
    AppointmentStatus.confirmed ||
    AppointmentStatus.rescheduleProposed => true,
    _ => false,
  };

  bool get hasAvailableFollowUpOffer =>
      lifecycleStatus == AppointmentStatus.completed &&
      followUpRecommended &&
      followUpStatus.trim().toLowerCase() == 'offered';

  factory AppointmentModel.fromJson(Map<String, dynamic> json, {String? id}) {
    return AppointmentModel(
      id: (json['id'] ?? id ?? '').toString(),
      userId: json['userId']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      age: _optionalInt(json['age']),
      address: _optionalString(json['address']),
      contactNumber: json['contactNumber']?.toString().trim() ?? '',
      email: json['email']?.toString().trim() ?? '',
      facebook: _optionalString(json['facebook']),
      sex: _optionalString(json['sex']),
      course: _optionalString(json['course']),
      yearLevel: _optionalString(json['yearLevel']),
      preferredContactMethod:
          json['preferredContactMethod']?.toString().trim() ?? '',
      therapyBefore: _optionalString(json['therapyBefore']),
      concern: json['concern']?.toString() ?? '',
      bestTime: _optionalString(json['bestTime']),
      scheduledAt: dateTimeFromFirestoreOrNow(json['scheduledAt']),
      scheduledTime: json['scheduledTime']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Upcoming',
      counselorName: _optionalString(json['counselorName']),
      createdAt: dateTimeFromFirestoreOrNow(json['createdAt']),
      updatedAt: dateTimeFromFirestore(json['updatedAt']),
      assignedStaffId: _optionalString(json['assignedStaffId']),
      staffReply: _optionalString(json['staffReply']),
      reviewedAt: dateTimeFromFirestore(json['reviewedAt']),
      proposedScheduledAt: dateTimeFromFirestore(json['proposedScheduledAt']),
      proposedScheduledTime: _optionalString(json['proposedScheduledTime']),
      proposedBy: _optionalString(json['proposedBy']),
      proposalStatus: _optionalString(json['proposalStatus']),
      department: _optionalString(json['department']),
      academicYearId: _optionalString(json['academicYearId']),
      archivedAt: dateTimeFromFirestore(json['archivedAt']),
      parentAppointmentId: _optionalString(json['parentAppointmentId']),
      rescheduleReason: _optionalString(json['rescheduleReason']),
      followUpRecommended: json['followUpRecommended'] == true,
      followUpMessage: _optionalString(json['followUpMessage']),
      followUpStatus: _optionalString(json['followUpStatus']) ?? 'none',
      followUpAppointmentId: _optionalString(json['followUpAppointmentId']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'fullName': fullName,
      'age': age,
      'address': address ?? '',
      'contactNumber': contactNumber,
      'email': email,
      'facebook': facebook ?? '',
      'sex': sex ?? '',
      'course': course ?? '',
      'yearLevel': yearLevel ?? '',
      'preferredContactMethod': preferredContactMethod,
      'therapyBefore': therapyBefore ?? '',
      'concern': concern,
      'bestTime': bestTime ?? '',
      'scheduledAt': scheduledAt,
      'scheduledTime': scheduledTime,
      'location': location,
      'status': status,
      'counselorName': counselorName ?? '',
      'assignedStaffId': assignedStaffId ?? '',
      'staffReply': staffReply ?? '',
      'reviewedAt': reviewedAt,
      'proposedScheduledAt': proposedScheduledAt,
      'proposedScheduledTime': proposedScheduledTime ?? '',
      'proposedBy': proposedBy ?? '',
      'proposalStatus': proposalStatus ?? '',
      'department': department ?? '',
      'academicYearId': academicYearId ?? '',
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'parentAppointmentId': parentAppointmentId ?? '',
      'rescheduleReason': rescheduleReason ?? '',
      'followUpRecommended': followUpRecommended,
      'followUpMessage': followUpMessage ?? '',
      'followUpStatus': followUpStatus,
      'followUpAppointmentId': followUpAppointmentId ?? '',
    };
  }

  AppointmentModel copyWith({
    String? id,
    String? userId,
    String? fullName,
    int? age,
    String? address,
    String? contactNumber,
    String? email,
    String? facebook,
    String? sex,
    String? course,
    String? yearLevel,
    String? preferredContactMethod,
    String? therapyBefore,
    String? concern,
    String? bestTime,
    DateTime? scheduledAt,
    String? scheduledTime,
    String? location,
    String? status,
    String? counselorName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? assignedStaffId,
    String? staffReply,
    DateTime? reviewedAt,
    DateTime? proposedScheduledAt,
    String? proposedScheduledTime,
    String? proposedBy,
    String? proposalStatus,
    String? department,
    String? academicYearId,
    DateTime? archivedAt,
    String? parentAppointmentId,
    String? rescheduleReason,
    bool? followUpRecommended,
    String? followUpMessage,
    String? followUpStatus,
    String? followUpAppointmentId,
  }) {
    return AppointmentModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      age: age ?? this.age,
      address: address ?? this.address,
      contactNumber: contactNumber ?? this.contactNumber,
      email: email ?? this.email,
      facebook: facebook ?? this.facebook,
      sex: sex ?? this.sex,
      course: course ?? this.course,
      yearLevel: yearLevel ?? this.yearLevel,
      preferredContactMethod:
          preferredContactMethod ?? this.preferredContactMethod,
      therapyBefore: therapyBefore ?? this.therapyBefore,
      concern: concern ?? this.concern,
      bestTime: bestTime ?? this.bestTime,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      location: location ?? this.location,
      status: status ?? this.status,
      counselorName: counselorName ?? this.counselorName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      assignedStaffId: assignedStaffId ?? this.assignedStaffId,
      staffReply: staffReply ?? this.staffReply,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      proposedScheduledAt: proposedScheduledAt ?? this.proposedScheduledAt,
      proposedScheduledTime:
          proposedScheduledTime ?? this.proposedScheduledTime,
      proposedBy: proposedBy ?? this.proposedBy,
      proposalStatus: proposalStatus ?? this.proposalStatus,
      department: department ?? this.department,
      academicYearId: academicYearId ?? this.academicYearId,
      archivedAt: archivedAt ?? this.archivedAt,
      parentAppointmentId: parentAppointmentId ?? this.parentAppointmentId,
      rescheduleReason: rescheduleReason ?? this.rescheduleReason,
      followUpRecommended: followUpRecommended ?? this.followUpRecommended,
      followUpMessage: followUpMessage ?? this.followUpMessage,
      followUpStatus: followUpStatus ?? this.followUpStatus,
      followUpAppointmentId:
          followUpAppointmentId ?? this.followUpAppointmentId,
    );
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int? _optionalInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
