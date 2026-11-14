import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/notifications/screens/notifications_screen.dart';
import 'package:mind_mates/models/app_notification_model.dart';
import 'package:mind_mates/repositories/notification_repository.dart';

void main() {
  testWidgets('notifications empty state is clear without any actions', (
    tester,
  ) async {
    final repository = _MemoryNotificationsRepository(const []);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('No notifications yet'), findsOneWidget);
    expect(find.text('Mark all read'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification cards preserve unread state and mark read on tap', (
    tester,
  ) async {
    final repository = _MemoryNotificationsRepository([
      _notification('unread', read: false),
      _notification('read', read: true),
    ]);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notification-unread')), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-read')), findsOneWidget);
    expect(find.textContaining('Unread'), findsOneWidget);
    expect(find.textContaining('Read'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('notification-unread')));
    await tester.pumpAndSettle();
    expect(repository.markedIds, ['unread']);
  });

  testWidgets('mark all read uses the existing repository operation', (
    tester,
  ) async {
    final repository = _MemoryNotificationsRepository([
      _notification('unread', read: false),
      _notification('read', read: true),
    ]);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    expect(repository.markedIds, ['unread']);
  });

  testWidgets('notification layout handles narrow screens and large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryNotificationsRepository([
      _notification('unread', read: false),
    ]);
    await tester.pumpWidget(_app(repository, scale: 1.4));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-unread')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('.*Mark all read.*')), findsWidgets);
    expect(tester.getSize(find.widgetWithText(TextButton, 'Mark all read')).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byKey(const ValueKey('notification-unread'))).height, greaterThanOrEqualTo(48));
    semantics.dispose();
  });
}

Widget _app(_MemoryNotificationsRepository repository, {double scale = 1}) {
  return MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: NotificationsScreen(userId: 'user_1', repository: repository),
    ),
  );
}

AppNotificationModel _notification(String id, {required bool read}) {
  return AppNotificationModel(
    id: id,
    userId: 'user_1',
    title: read ? 'Appointment confirmed' : 'Appointment request received',
    body: 'Your PACC appointment has been updated.',
    type: read ? 'appointment_confirmed' : 'appointment',
    createdAt: DateTime(2026, 11, 13, 8),
    readAt: read ? DateTime(2026, 11, 13, 9) : null,
  );
}

class _MemoryNotificationsRepository extends NotificationRepository {
  _MemoryNotificationsRepository(this.items);

  final List<AppNotificationModel> items;
  final List<String> markedIds = [];

  @override
  Stream<List<AppNotificationModel>> watchNotifications(String userId) =>
      Stream.value(items.where((item) => item.userId == userId).toList());

  @override
  Future<void> markRead(String id) async => markedIds.add(id);
}
