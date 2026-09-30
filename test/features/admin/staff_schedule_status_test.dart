import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/staff_operations_dashboard.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';

void main() {
  testWidgets('Staff schedule metric uses the V2 resolver for non-color-only availability wording', (tester) async {
    final now = DateTime.utc(2026, 9, 28, 2);
    final availability = PaccAvailabilityModel.v2(
      weekdays: {
        for (var day = 1; day <= 7; day++) day: day == 1 ? const PaccDaySchedule(enabled: true, opensAt: '08:00', closesAt: '17:00', presence: CounselorPresence.inOffice, appointmentsEnabled: false, acceptsWalkIns: true) : PaccDaySchedule.closed,
      },
      overrides: const [],
    );

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaccStaffScheduleMetric(width: 300, availability: availability, now: now))));

    expect(find.text('Open — appointments unavailable'), findsOneWidget);
    expect(find.text('Today\'s PACC schedule'), findsOneWidget);
  });
}
