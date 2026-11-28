import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/notifications/screens/notifications_screen.dart';
import 'package:mind_mates/models/app_notification_model.dart';
import 'package:mind_mates/models/student_inquiry_model.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';
import 'package:mind_mates/repositories/inquiry_repository.dart';
import 'package:mind_mates/repositories/notification_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:provider/provider.dart';

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
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Mark all read')).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('notification-unread'))).height,
      greaterThanOrEqualTo(48),
    );
    semantics.dispose();
  });

  testWidgets(
    'tapping inquiry notification marks read and opens StudentInquiryDetailScreen',
    (tester) async {
      final repository = _MemoryNotificationsRepository([
        AppNotificationModel(
          id: 'notif-inq-1',
          userId: 'user_1',
          title: 'PACC replied to your inquiry',
          body: 'Open MindMate to view the reply.',
          type: 'inquiry',
          inquiryId: 'inq_1',
          createdAt: DateTime(2026, 11, 15, 9),
        ),
      ]);
      final inquiryRepository = _TestInquiryRepository(
        inquiry: StudentInquiryRecord(
          id: 'inq_1',
          userId: 'user_1',
          subject: 'Intake Follow-up',
          message: 'When is my next check-in?',
          category: 'Service Form',
          status: StudentInquiryStatus.inProgress,
          createdAt: DateTime(2026, 11, 15, 8),
          responseCount: 1,
        ),
        replies: [
          StudentInquiryReply(
            id: 'rep-1',
            message: 'Your counselor scheduled Friday at 10 AM.',
            authorName: 'Counselor Santos',
            authorRole: 'counselor',
            createdAt: DateTime(2026, 11, 15, 9),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            userId: 'user_1',
            repository: repository,
            inquiryRepository: inquiryRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('PACC replied to your inquiry'));
      await tester.pumpAndSettle();

      expect(repository.markedIds, ['notif-inq-1']);
      expect(find.text('Inquiry Details'), findsOneWidget);
      expect(find.text('Intake Follow-up'), findsOneWidget);
      expect(
        find.text('Your counselor scheduled Friday at 10 AM.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping appointment notification preserves appointment lookup behavior',
    (tester) async {
      final repository = _MemoryNotificationsRepository([
        AppNotificationModel(
          id: 'notif-appt-1',
          userId: 'user_1',
          title: 'Appointment confirmed',
          body: 'Your PACC appointment has been updated.',
          type: 'appointment_confirmed',
          appointmentId: 'appt_missing',
          createdAt: DateTime(2026, 11, 15, 10),
        ),
      ]);
      final provider = AppointmentProvider(_TestAppointmentRepository());

      await tester.pumpWidget(
        ChangeNotifierProvider<AppointmentProvider>.value(
          value: provider,
          child: MaterialApp(
            home: NotificationsScreen(userId: 'user_1', repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Appointment confirmed'));
      await tester.pumpAndSettle();

      expect(repository.markedIds, ['notif-appt-1']);
      expect(
        find.text('This appointment is no longer available.'),
        findsOneWidget,
      );
    },
  );

  for (final (type, route, target) in [
    ('mood_reminder', RouteNames.logMood, 'Mood logger target'),
    ('breathing_reminder', RouteNames.mindfulBreathing, 'Breathing target'),
  ]) {
    testWidgets('$type notification marks read and opens its destination', (
      tester,
    ) async {
      final repository = _MemoryNotificationsRepository([
        AppNotificationModel(
          id: 'reminder-1',
          userId: 'user_1',
          title: 'MindMate Reminder',
          body: 'A gentle reminder.',
          type: type,
          createdAt: DateTime(2026, 11, 15, 10),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(userId: 'user_1', repository: repository),
          routes: {route: (_) => Scaffold(body: Text(target))},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('MindMate Reminder'));
      await tester.pumpAndSettle();

      expect(repository.markedIds, ['reminder-1']);
      expect(find.text(target), findsOneWidget);
    });
  }
}

Widget _app(_MemoryNotificationsRepository repository, {double scale = 1}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
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

class _TestInquiryRepository extends InquiryRepository {
  _TestInquiryRepository({required this.inquiry, required this.replies})
    : super(currentUserIdProvider: () => inquiry.userId);

  final StudentInquiryRecord inquiry;
  final List<StudentInquiryReply> replies;

  @override
  Stream<StudentInquiryRecord?> watchMyInquiry(
    String inquiryId, {
    required String userId,
  }) => Stream.value(inquiryId == inquiry.id ? inquiry : null);

  @override
  Stream<List<StudentInquiryReply>> watchMyInquiryReplies(String inquiryId) =>
      Stream.value(inquiryId == inquiry.id ? replies : const []);
}

class _TestAppointmentRepository implements AppointmentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
