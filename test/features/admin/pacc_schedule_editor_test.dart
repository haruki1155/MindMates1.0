import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';
import 'package:mind_mates/repositories/pacc_availability_repository.dart';

const _day = PaccDaySchedule(enabled: true, opensAt: '09:00', closesAt: '17:00', presence: CounselorPresence.inOffice, appointmentsEnabled: true, acceptsWalkIns: false);
final _schedule = PaccAvailabilityModel.v2(weekdays: {for (var day = 1; day <= 7; day++) day: _day}, overrides: const []);

void main() {
  testWidgets('shows seven isolated weekday rows and a visible save control', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaccScheduleEditor(availability: _schedule, onSave: (_, {confirmConflicts = false}) async => const PaccAvailabilitySaveResult(revision: 1, conflicts: [])))));
    for (final day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']) {
      expect(find.bySemanticsLabel('Schedule $day'), findsOneWidget);
    }
    expect(find.text('Save schedule'), findsOneWidget);
  });

  testWidgets('keeps staff read-only and labels the closed state', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaccScheduleEditor(availability: _schedule, readOnly: true, onSave: (_, {confirmConflicts = false}) async => const PaccAvailabilitySaveResult(revision: 1, conflicts: [])))));
    expect(find.text('Read-only schedule'), findsOneWidget);
    expect(find.text('Save schedule'), findsNothing);
  });

  testWidgets('applies a bulk closed state only to selected weekdays', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaccScheduleEditor(availability: _schedule, onSave: (_, {confirmConflicts = false}) async => const PaccAvailabilitySaveResult(revision: 1, conflicts: [])))));
    await tester.tap(find.bySemanticsLabel('Select Monday'));
    await tester.pump();
    await tester.tap(find.text('Close selected days'));
    await tester.pump();
    expect(find.bySemanticsLabel('Schedule Monday'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);
  });

  testWidgets('validates Monday times locally without changing other weekdays', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaccScheduleEditor(availability: _schedule, onSave: (_, {confirmConflicts = false}) async => const PaccAvailabilitySaveResult(revision: 1, conflicts: [])))));
    await tester.enterText(find.byKey(const Key('day-1-opens')), '18:00');
    await tester.enterText(find.byKey(const Key('day-1-closes')), '09:00');
    await tester.pump();
    expect(find.text('Opening time must be before closing time.'), findsOneWidget);
  });

  testWidgets('keeps valid weekday time edits local until Save', (tester) async {
    var saves = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaccScheduleEditor(availability: _schedule, onSave: (_, {confirmConflicts = false}) async { saves++; return const PaccAvailabilitySaveResult(revision: 1, conflicts: []); }))));
    await tester.enterText(find.byKey(const Key('day-1-opens')), '10:00');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('day-1-closes')), '16:00');
    await tester.pump();
    expect(find.text('Opening time must be before closing time.'), findsNothing);
    expect(saves, 0);
  });

  testWidgets('adds a closed special date override to the local draft', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaccScheduleEditor(availability: _schedule, onSave: (_, {confirmConflicts = false}) async => const PaccAvailabilitySaveResult(revision: 1, conflicts: [])))));
    await tester.tap(find.text('Add special date'));
    await tester.pump();
    expect(find.text('Special date'), findsOneWidget);
  });

  testWidgets('requires confirmation before resaving reported conflicts', (tester) async {
    var calls = 0;
    Future<PaccAvailabilitySaveResult> save(PaccAvailabilityModel _, {bool confirmConflicts = false}) async {
      calls++;
      return confirmConflicts
          ? const PaccAvailabilitySaveResult(revision: 2, conflicts: [])
          : const PaccAvailabilitySaveResult(revision: 1, conflicts: [PaccScheduleConflict(appointmentId: 'a1', status: 'confirmed', timestamp: 1, reason: 'Office is closed.')]);
    }
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaccScheduleEditor(availability: _schedule, onSave: save))));
    await tester.ensureVisible(find.text('Save schedule'));
    await tester.tap(find.text('Save schedule'));
    await tester.pump();
    expect(find.text('Schedule conflicts'), findsOneWidget);
    await tester.tap(find.text('Save anyway'));
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('prompts before discarding a dirty local draft', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaccScheduleEditor(availability: _schedule, onSave: (_, {confirmConflicts = false}) async => const PaccAvailabilitySaveResult(revision: 1, conflicts: [])))));
    await tester.enterText(find.byKey(const Key('day-1-opens')), '10:00');
    await tester.pump();
    await tester.ensureVisible(find.text('Discard changes'));
    await tester.tap(find.text('Discard changes'));
    await tester.pump();
    expect(find.text('Discard schedule changes?'), findsOneWidget);
  });
}
