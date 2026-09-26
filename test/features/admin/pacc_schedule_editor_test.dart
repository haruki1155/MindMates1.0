import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';
import 'package:mind_mates/repositories/pacc_availability_repository.dart';

const _openDay = PaccDaySchedule(
  enabled: true,
  opensAt: '09:00',
  closesAt: '17:00',
  presence: CounselorPresence.inOffice,
  appointmentsEnabled: true,
  acceptsWalkIns: true,
);

PaccAvailabilityModel _schedule({int revision = 4}) => PaccAvailabilityModel.v2(
  weekdays: {for (var day = 1; day <= 7; day++) day: _openDay},
  overrides: const [],
  revision: revision,
);

Widget _editor({
  PaccAvailabilityModel? availability,
  bool readOnly = false,
  Future<PaccAvailabilitySaveResult> Function(PaccAvailabilityModel, {bool confirmConflicts})? onSave,
}) => MaterialApp(home: Scaffold(body: PaccScheduleEditor(
  availability: availability ?? _schedule(),
  readOnly: readOnly,
  onSave: onSave ?? (_, {confirmConflicts = false}) async => const PaccAvailabilitySaveResult(revision: 5, conflicts: []),
)));

void main() {
  testWidgets('shows Monday through Friday only and keeps staff read-only', (tester) async {
    await tester.pumpWidget(_editor());
    for (final day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']) {
      expect(find.text(day), findsOneWidget);
    }
    expect(find.text('Saturday'), findsNothing);
    expect(find.text('Sunday'), findsNothing);

    await tester.pumpWidget(_editor(readOnly: true));
    expect(find.text('Read-only schedule'), findsOneWidget);
    expect(find.text('Save schedule'), findsNothing);
  });

  testWidgets('edits one weekday without changing another and enforces closed weekends', (tester) async {
    PaccAvailabilityModel? saved;
    await tester.pumpWidget(_editor(onSave: (value, {confirmConflicts = false}) async {
      saved = value;
      return const PaccAvailabilitySaveResult(revision: 5, conflicts: []);
    }));
    await tester.tap(find.byKey(const Key('edit-day-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('day-1-opens')), '10:00');
    await tester.enterText(find.byKey(const Key('day-1-closes')), '16:00');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();

    expect(saved!.weekdays[1]!.opensAt, '10:00');
    expect(saved!.weekdays[2]!.opensAt, '09:00');
    expect(saved!.weekdays[6]!.enabled, isFalse);
    expect(find.text('Schedule saved'), findsOneWidget);
  });

  testWidgets('supports counselor and service controls per weekday', (tester) async {
    PaccAvailabilityModel? saved;
    await tester.pumpWidget(_editor(onSave: (value, {confirmConflicts = false}) async {
      saved = value;
      return const PaccAvailabilitySaveResult(revision: 5, conflicts: []);
    }));
    await tester.tap(find.byKey(const Key('edit-day-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Out of office'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();

    expect(saved!.weekdays[4]!.presence, CounselorPresence.outOfOffice);
    expect(saved!.weekdays[4]!.appointmentsEnabled, isFalse);
  });

  testWidgets('preserves a failed draft and gives an actionable save error', (tester) async {
    await tester.pumpWidget(_editor(onSave: (_, {confirmConflicts = false}) => Future.error(StateError('stale'))));
    await tester.tap(find.byKey(const Key('edit-day-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('day-1-opens')), '10:00');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();

    expect(find.text('Schedule could not be saved. Your changes are still available.'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('requires an ordered HH:mm range before applying a weekday', (tester) async {
    await tester.pumpWidget(_editor());
    await tester.tap(find.byKey(const Key('edit-day-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('day-1-opens')), '17:00');
    await tester.enterText(find.byKey(const Key('day-1-closes')), '09:00');
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(find.text('Opening time must be before closing time.'), findsOneWidget);
  });
}
