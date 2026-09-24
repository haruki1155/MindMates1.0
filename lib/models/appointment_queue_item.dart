import '../core/utils/firestore_mapper.dart';

/// The non-clinical scheduling projection available to PAACC portal staff.
/// It deliberately omits identity, contact, demographic, and care details.
class AppointmentQueueItem {
  const AppointmentQueueItem({
    required this.id,
    required this.studentDisplayName,
    required this.scheduledAt,
    required this.scheduledTime,
    required this.status,
    required this.isArchived,
    this.assignedCounselor,
  });

  final String id;
  final String studentDisplayName;
  final DateTime scheduledAt;
  final String scheduledTime;
  final String status;
  final bool isArchived;
  final String? assignedCounselor;

  factory AppointmentQueueItem.fromJson(
    Map<String, dynamic> json, {
    String? id,
  }) => AppointmentQueueItem(
    id: (json['appointmentId'] ?? id ?? '').toString(),
    studentDisplayName: json['studentDisplayName']?.toString().trim() ?? '',
    scheduledAt: dateTimeFromFirestoreOrNow(json['scheduledAt']),
    scheduledTime: json['scheduledTime']?.toString().trim() ?? '',
    status: json['status']?.toString().trim() ?? 'requested',
    isArchived: json['isArchived'] == true,
    assignedCounselor: _optionalString(json['assignedCounselor']),
  );

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
