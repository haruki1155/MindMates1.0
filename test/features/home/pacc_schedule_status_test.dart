import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/home/screens/home_screen.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';

void main() {
  final manilaMondayMorning = DateTime.utc(2026, 9, 28, 2);

  testWidgets('Home describes an open office with appointments and walk-ins', (tester) async {
    await _pump(tester, _schedule(), manilaMondayMorning);

    expect(find.text('OPEN — APPOINTMENTS AVAILABLE'), findsOneWidget);
    expect(find.textContaining('Office is open.'), findsOneWidget);
    expect(find.textContaining('Appointments are available.'), findsOneWidget);
    expect(find.textContaining('Walk-ins are accepted.'), findsOneWidget);
  });

  testWidgets('Home gives explicit closed, appointments-disabled, override, and counselor wording', (tester) async {
    await _pump(tester, _schedule(day: _day(enabled: false)), manilaMondayMorning);
    expect(find.text('CLOSED'), findsOneWidget);
    expect(find.textContaining('Office is closed.'), findsOneWidget);

    await _pump(tester, _schedule(day: _day(appointmentsEnabled: false)), manilaMondayMorning);
    expect(find.text('OPEN — APPOINTMENTS UNAVAILABLE'), findsOneWidget);
    expect(find.textContaining('Appointments are unavailable.'), findsOneWidget);

    await _pump(tester, _schedule(overrides: const [PaccDateOverride(date: '2026-09-28', closedAllDay: true, reason: 'University holiday')]), manilaMondayMorning);
    expect(find.text('CLOSED'), findsOneWidget);
    expect(find.textContaining('University holiday'), findsOneWidget);

    await _pump(tester, _schedule(day: _day(presence: CounselorPresence.outOfOffice)), manilaMondayMorning);
    expect(find.text('OPEN — COUNSELOR UNAVAILABLE'), findsOneWidget);
    expect(find.textContaining('Counselor is unavailable'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, PaccAvailabilityModel availability, DateTime now) => tester.pumpWidget(
  MaterialApp(home: Scaffold(body: PaccHomeScheduleStatus(availability: availability, now: now, onViewMore: () {}, onViewDetail: () {}))),
);

PaccAvailabilityModel _schedule({PaccDaySchedule? day, List<PaccDateOverride> overrides = const []}) => PaccAvailabilityModel.v2(
  weekdays: {for (var index = 1; index <= 7; index++) index: index == 1 ? day ?? _day() : PaccDaySchedule.closed},
  overrides: overrides,
);

PaccDaySchedule _day({bool enabled = true, bool appointmentsEnabled = true, bool acceptsWalkIns = true, CounselorPresence presence = CounselorPresence.inOffice}) => PaccDaySchedule(
  enabled: enabled,
  opensAt: '08:00',
  closesAt: '17:00',
  presence: presence,
  appointmentsEnabled: appointmentsEnabled,
  acceptsWalkIns: acceptsWalkIns,
);
