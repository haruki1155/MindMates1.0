import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/app_notification_model.dart';

void main() {
  group('AppNotificationModel', () {
    test('parses a portal inquiry notification and unread state', () {
      final notification = AppNotificationModel.fromJson({
        'userId': 'counselor-1',
        'title': 'New inquiry',
        'body': 'A new inquiry is ready for review.',
        'type': 'inquiry',
        'inquiryId': 'inquiry-1',
        'audience': 'portal',
        'createdAt': '2026-09-10T08:00:00.000Z',
      }, id: 'notification-1');

      expect(notification.id, 'notification-1');
      expect(notification.inquiryId, 'inquiry-1');
      expect(notification.appointmentId, isNull);
      expect(notification.audience, 'portal');
      expect(notification.isRead, isFalse);
    });

    test('treats a populated readAt timestamp as read', () {
      final notification = AppNotificationModel.fromJson({
        'id': 'notification-2',
        'userId': 'admin-1',
        'type': 'appointment',
        'appointmentId': 'appointment-1',
        'createdAt': '2026-09-10T08:00:00.000Z',
        'readAt': '2026-09-10T08:05:00.000Z',
      });

      expect(notification.appointmentId, 'appointment-1');
      expect(notification.isRead, isTrue);
    });

    test('parses archived and expiry lifecycle timestamps', () {
      final notification = AppNotificationModel.fromJson({
        'id': 'notification-3',
        'userId': 'admin-1',
        'type': 'inquiry',
        'createdAt': '2026-09-10T08:00:00.000Z',
        'resolvedAt': '2026-09-11T08:00:00.000Z',
        'archivedAt': '2026-09-11T08:00:00.000Z',
        'expiresAt': '2026-12-10T08:00:00.000Z',
      });

      expect(notification.isArchived, isTrue);
      expect(notification.resolvedAt, isNotNull);
      expect(notification.expiresAt, isNotNull);
    });
  });
}
