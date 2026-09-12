import '../core/utils/firestore_mapper.dart';

class AppNotificationModel {
  const AppNotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.appointmentId,
    this.inquiryId,
    this.audience,
    this.readAt,
    this.resolvedAt,
    this.archiveEligibleAt,
    this.archivedAt,
    this.expiresAt,
  });

  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;
  final String? appointmentId;
  final String? inquiryId;
  final String? audience;
  final DateTime? readAt;
  final DateTime? resolvedAt;
  final DateTime? archiveEligibleAt;
  final DateTime? archivedAt;
  final DateTime? expiresAt;

  bool get isRead => readAt != null;
  bool get isArchived => archivedAt != null;

  factory AppNotificationModel.fromJson(
    Map<String, dynamic> json, {
    String? id,
  }) => AppNotificationModel(
    id: (json['id'] ?? id ?? '').toString(),
    userId: json['userId']?.toString() ?? '',
    title: json['title']?.toString() ?? 'MindMate update',
    body: json['body']?.toString() ?? '',
    type: json['type']?.toString() ?? 'general',
    appointmentId: _text(json['appointmentId']),
    inquiryId: _text(json['inquiryId']),
    audience: _text(json['audience']),
    createdAt: dateTimeFromFirestoreOrNow(json['createdAt']),
    readAt: dateTimeFromFirestore(json['readAt']),
    resolvedAt: dateTimeFromFirestore(json['resolvedAt']),
    archiveEligibleAt: dateTimeFromFirestore(json['archiveEligibleAt']),
    archivedAt: dateTimeFromFirestore(json['archivedAt']),
    expiresAt: dateTimeFromFirestore(json['expiresAt']),
  );

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
