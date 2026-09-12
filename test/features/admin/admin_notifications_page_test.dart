import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_notifications_page.dart';
import 'package:mind_mates/models/app_notification_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _Repository extends AdminPortalRepository {
  _Repository(this.notificationStream);

  final Stream<List<AppNotificationModel>> notificationStream;
  int watchCalls = 0;

  @override
  Stream<List<AppNotificationModel>> watchPortalNotifications() {
    watchCalls += 1;
    return notificationStream;
  }
}

void main() {
  testWidgets('shows an immediate empty state and then live notifications', (
    tester,
  ) async {
    final notifications = StreamController<List<AppNotificationModel>>();
    final repository = _Repository(notifications.stream);
    addTearDown(notifications.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminNotificationsPage(
            repository: repository,
            onOpenAppointments: () {},
            onOpenInquiries: () {},
          ),
        ),
      ),
    );

    expect(repository.watchCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No notifications match this filter.'), findsOneWidget);

    notifications.add([
      AppNotificationModel(
        id: 'notification-1',
        userId: 'counselor-1',
        title: 'New counseling appointment',
        body: 'A new counseling appointment is ready for review.',
        type: 'appointment',
        audience: 'portal',
        appointmentId: 'appointment-1',
        createdAt: DateTime(2026, 9, 10),
      ),
    ]);
    await tester.pump();

    expect(find.text('New counseling appointment'), findsOneWidget);
    expect(find.text('No notifications match this filter.'), findsNothing);
  });
}
