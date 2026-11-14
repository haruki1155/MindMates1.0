import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/widgets/appointment_list_view.dart';
import 'package:mind_mates/features/counseling/widgets/appointment_presentation.dart';
import 'package:mind_mates/models/appointment_model.dart';

void main() {
  testWidgets('all empty cards and their contents are centered', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app([]));
    await tester.pumpAndSettle();
    for (final tab in ['Upcoming', 'Past', 'Cancelled']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      final card = find.byKey(ValueKey('appointment-empty-$tab'));
      expect(card, findsOneWidget);
      expect(tester.getCenter(card).dx, closeTo(195, .5));
      final title = find.descendant(of: card, matching: find.byType(Text)).first;
      expect(tester.widget<Text>(title).textAlign, TextAlign.center);
      expect(tester.getCenter(title).dx, closeTo(195, .5));
    }
  });

  testWidgets('status uses a prominent pending pulse and confirmed icon', (tester) async {
    await tester.pumpWidget(_app([_appointment(status: 'requested')]));
    final badge = find.byKey(const ValueKey('appointment-status-requested'));
    expect(find.descendant(of: badge, matching: find.byType(AppointmentProcessingIndicator)), findsOneWidget);
    await tester.pumpWidget(_app([_appointment(status: 'confirmed')]));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byType(AppointmentProcessingIndicator), findsNothing);
  });

  testWidgets('upcoming status is an amber live-region badge with a session title', (tester) async {
    await tester.pumpWidget(_app([_appointment(status: 'requested')]));
    expect(find.text('Awaiting confirmation'), findsOneWidget);
    expect(find.text('PACC Counseling'), findsOneWidget);
    final badge = find.byKey(const ValueKey('appointment-status-requested'));
    expect(badge, findsOneWidget);
    expect(tester.widget<Semantics>(badge).properties.liveRegion, isTrue);
    await tester.pumpWidget(_app([_appointment(status: 'confirmed')]));
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Awaiting confirmation'), findsNothing);
  });

  testWidgets('upcoming card actions remain reachable with large text at320px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_app([_appointment(status: 'requested')]));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View appointment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View appointment'));
    await tester.ensureVisible(find.text('Add to Calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Calendar'));
  });

  testWidgets('overview renders the approved support and status hierarchy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/segoeui.ttf');
      if (await font.exists()) await (FontLoader('Roboto')..addFont(font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
    });
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),theme: ThemeData(fontFamily: 'Roboto'), home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: AppointmentListView(appointments: [_appointment(status: 'requested')], onView: (_) {}, onBook: (_) {}, onCalendar: (_) {})))));
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final rendered = await boundary.toImage();
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('.superpowers/sdd/MindMate_Appointment_Implementation_Plan/screenshots');
      await directory.create(recursive: true);
      await File('${directory.path}/overview-live-status.png').writeAsBytes(data!.buffer.asUint8List());
      rendered.dispose();
    });
  });

  testWidgets('category tabs share one animated segmented container', (tester) async {
    await tester.pumpWidget(_app([]));
    final group = find.byKey(const ValueKey('appointment-category-container'));
    expect(group, findsOneWidget);
    for (final label in ['Upcoming', 'Past', 'Cancelled']) {
      expect(find.descendant(of: group, matching: find.text(label)), findsOneWidget);
    }
    expect(find.descendant(of: group, matching: find.byType(AnimatedContainer)), findsNWidgets(3));
    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();
    expect(find.text('No past appointments yet.'), findsOneWidget);
  });

  testWidgets('overview presents the calm support hero', (tester) async {
    await tester.pumpWidget(_app([]));
    expect(find.text('Support begins with one conversation.'), findsOneWidget);
  });
  testWidgets('active card offers one details action and direct calendar access', (tester) async {
    var viewed = 0;
    var openedCalendar = 0;
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),home: Scaffold(body: AppointmentCard(
      appointment: _appointment(status: 'confirmed'), compact: false, isSaving: false, bookingBlocked: false,
      onView: () => viewed++, onBook: () {}, onCalendar: () => openedCalendar++,
    ))));
    expect(find.byTooltip('View appointment details'), findsNothing);
    expect(find.text('Manage'), findsNothing);
    expect(find.text('Support'), findsNothing);
    await tester.tap(find.text('View appointment'));
    await tester.tap(find.text('Add to Calendar'));
    expect(viewed, 1);
    expect(openedCalendar, 1);
  });
  testWidgets(
    'legacy schedule updates are view-only for clients',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final appointment = _appointment(
        status: 'reschedule_proposed',
        proposedScheduledAt: DateTime(2026, 10, 2, 10),
        proposedScheduledTime: '10:00 AM',
        rescheduleReason: 'Counselor schedule conflict',
      );

      await tester.pumpWidget(_app([appointment]));
      await tester.pumpAndSettle();
      expect(find.text('Schedule Update Pending'), findsOneWidget);
      expect(find.text('Accept New Schedule'), findsNothing);
      expect(find.text('PACC is finalizing your appointment schedule.'),
          findsOneWidget);
      expect(find.text('Cancel Appointment'), findsNothing);
      expect(find.text('Cancel Request'), findsNothing);
      expect(find.text('Request Reschedule'), findsNothing);
      expect(find.text('Request Another Time'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Book Appointment'), findsNothing);
      expect(
        find.textContaining('You already have an active appointment'),
        findsOneWidget,
      );
    },
  );

  testWidgets('follow-up displays only client-safe message and links booking', (
    tester,
  ) async {
    final appointment = _appointment(
      status: 'completed',
      followUpRecommended: true,
      followUpMessage: 'You may book a follow-up when ready.',
      followUpStatus: 'offered',
    );
    AppointmentModel? bookedFrom;

    await tester.pumpWidget(
      _app([appointment], onBook: (value) => bookedFrom = value),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();

    expect(find.text('Book Follow-up'), findsOneWidget);
    expect(find.text('You may book a follow-up when ready.'), findsNothing);
    await tester.tap(find.text('Book Follow-up'));
    expect(bookedFrom?.id, appointment.id);
  });

  testWidgets('a booked follow-up is not offered again', (tester) async {
    final appointment = _appointment(
      status: 'completed',
      followUpRecommended: true,
      followUpMessage: 'Already linked.',
      followUpStatus: 'booked',
    );

    await tester.pumpWidget(_app([appointment]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();

    expect(find.text('Book Follow-up'), findsNothing);
    expect(find.text('Book Again'), findsOneWidget);
  });
}

Widget _app(
  List<AppointmentModel> appointments, {
  ValueChanged<AppointmentModel?>? onBook,
}) => MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
  home: Scaffold(
    body: SingleChildScrollView(child: AppointmentListView(
      appointments: appointments,
      onBook: onBook ?? (_) {},
      onView: (_) {},
      onCalendar: (_) {},
    )),
  ),
);

AppointmentModel _appointment({
  required String status,
  DateTime? proposedScheduledAt,
  String? proposedScheduledTime,
  String? rescheduleReason,
  bool followUpRecommended = false,
  String? followUpMessage,
  String followUpStatus = 'none',
}) => AppointmentModel(
  id: 'appointment-1',
  userId: 'student-1',
  fullName: 'Student',
  scheduledAt: DateTime(2026, 10, 1, 9),
  scheduledTime: '9:00 AM',
  location: 'PACC',
  status: status,
  concern: 'Support',
  contactNumber: '09123456789',
  email: 'student@example.com',
  preferredContactMethod: 'Email',
  createdAt: DateTime(2026, 9, 1),
  proposedScheduledAt: proposedScheduledAt,
  proposedScheduledTime: proposedScheduledTime,
  rescheduleReason: rescheduleReason,
  followUpRecommended: followUpRecommended,
  followUpMessage: followUpMessage,
  followUpStatus: followUpStatus,
);
