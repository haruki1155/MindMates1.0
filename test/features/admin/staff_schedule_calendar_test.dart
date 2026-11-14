import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/widgets/staff_schedule_calendar.dart';
import 'package:mind_mates/models/appointment_queue_item.dart';

AppointmentQueueItem _counseling({
  required String id,
  required String status,
}) => AppointmentQueueItem(
  id: id,
  studentDisplayName: 'Student test record',
  scheduledAt: DateTime(2026, 11, 16, 9),
  scheduledTime: '9:00 AM',
  status: status,
  isArchived: false,
  assignedCounselor: 'Counselor Rivera',
);

void main() {
  testWidgets('calendar plots confirmed counseling count with counselor hover details', (tester) async {
    tester.view.physicalSize = const Size(1280, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: StaffScheduleCalendar(
        counselingAppointments: [
          _counseling(id: 'first', status: 'confirmed'),
          _counseling(id: 'second', status: 'completed'),
          _counseling(id: 'cancelled', status: 'cancelled'),
        ],
        initialMonth: DateTime(2026, 11, 1),
      )),
    )));
    await tester.pumpAndSettle();

    final day = find.byKey(const Key('staff-day-2026-11-16'));
    expect(day, findsOneWidget);
    expect(find.text('2 counseling'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.ancestor(
      of: day,
      matching: find.byType(Tooltip),
    ));
    expect(tooltip.message, contains('9:00 AM · Counseling · Counselor Rivera'));
    expect(tooltip.message!.split('Counselor Rivera').length - 1, 2);

    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(find.text('9:00 AM · Counseling · Counselor Rivera'), findsNWidgets(2));
    expect(find.textContaining('Testing schedules not yet connected'), findsOneWidget);
    expect(find.textContaining('Testing dates are currently arranged outside MindMate'), findsOneWidget);
  });

  testWidgets('calendar accepts verified testing entries when a trusted source is connected', (tester) async {
    tester.view.physicalSize = const Size(1280, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: StaffScheduleCalendar(
        counselingAppointments: [_counseling(id: 'first', status: 'confirmed')],
        testingSchedulesConnected: true,
        testingAppointments: [
          StaffScheduleEntry(
            id: 'testing-1',
            scheduledAt: DateTime(2026, 11, 16, 11),
            kind: StaffScheduleKind.testing,
            timeLabel: '11:00 AM',
            assignedCounselor: 'Counselor Silva',
            status: 'confirmed',
          ),
        ],
        initialMonth: DateTime(2026, 11, 1),
      )),
    )));
    await tester.pumpAndSettle();
    expect(find.text('1 counseling'), findsOneWidget);
    expect(find.text('1 testing'), findsOneWidget);
    final day = find.byKey(const Key('staff-day-2026-11-16'));
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(find.text('11:00 AM · Testing · Counselor Silva'), findsOneWidget);
    expect(find.textContaining('Testing dates are currently arranged outside MindMate'), findsNothing);
  });

  testWidgets('calendar changes months and scrolls on a short viewport without overflow', (tester) async {
    // StaffOperationsDashboardPage hosts the reusable calendar inside
    // SingleChildScrollView. Match that production layout on the default
    // 800x600 test viewport rather than constraining a tall Column directly.
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(
        child: StaffScheduleCalendar(
          counselingAppointments: const [],
          initialMonth: DateTime(2026, 11, 1),
        ),
      ),
    )));
    expect(find.text('November 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('December 2026'), findsOneWidget);
    final emptyDay = find.text('No confirmed counseling appointments on this date.');
    await tester.ensureVisible(emptyDay);
    await tester.pumpAndSettle();
    expect(emptyDay, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
