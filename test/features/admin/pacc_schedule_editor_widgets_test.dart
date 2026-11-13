import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/widgets/pacc_schedule_editor_widgets.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';

void main() {
  test('time picker serializes 24-hour values', () {
    expect(paccTimeOfDayValue(const TimeOfDay(hour: 16, minute: 5)), '16:05');
    expect(paccParseTimeOfDay('09:30').hour, 9);
    expect(paccParseTimeOfDay('25:99').hour, 8);
  });

  testWidgets('office hours uses a dropdown, not a toggle', (tester) async {
    bool? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaccOfficeHoursSelector(
            value: true,
            onChanged: (v) => selected = v,
          ),
        ),
      ),
    );
    expect(find.text('Office Hours'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.byType(DropdownButton<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Closed').last);
    await tester.pumpAndSettle();
    expect(selected, false);
  });

  testWidgets('weekly table shows required columns and edits correct day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    int? edited;
    final schedule = PaccDaySchedule(
      enabled: true,
      opensAt: '08:00',
      closesAt: '17:00',
      presence: CounselorPresence.inOffice,
      appointmentsEnabled: true,
      acceptsWalkIns: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaccWeeklyScheduleTable(
            days: {for (var day = 1; day <= 5; day++) day: schedule},
            readOnly: false,
            onEditDay: (day) => edited = day,
          ),
        ),
      ),
    );
    for (final heading in [
      'Day',
      'Opening Time',
      'Closing Time',
      'Office Status',
      'Action',
    ]) {
      expect(find.text(heading), findsOneWidget);
    }
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('8:00 AM'), findsNWidgets(5));
    await tester.tap(find.byKey(const Key('edit-day-1')));
    expect(edited, 1);
  });

  testWidgets('narrow schedule table scrolls horizontally', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaccWeeklyScheduleTable(
            days: const {},
            readOnly: true,
            onEditDay: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('Office Status'), findsOneWidget);
  });
}
