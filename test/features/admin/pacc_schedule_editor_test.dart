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

PaccAvailabilityModel _schedule({
  int revision = 4,
  List<PaccDateOverride> overrides = const [],
}) => PaccAvailabilityModel.v2(
  weekdays: {for (var day = 1; day <= 7; day++) day: _openDay},
  overrides: overrides,
  revision: revision,
);

Widget _editor({
  PaccAvailabilityModel? availability,
  bool readOnly = false,
  PaccScheduleEditorController? controller,
  Future<PaccAvailabilitySaveResult> Function(PaccAvailabilityModel, {bool confirmConflicts})? onSave,
}) => MaterialApp(home: Scaffold(body: PaccScheduleEditor(
  availability: availability ?? _schedule(),
  readOnly: readOnly,
  controller: controller,
  onSave: onSave ?? (_, {confirmConflicts = false}) async => const PaccAvailabilitySaveResult(revision: 5, conflicts: []),
)));

void main() {
  Future<void> makeDirty(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('edit-day-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('day-1-opens')), '10:00');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
  }

  testWidgets('dirty navigation offers close, discard, and save through the normal editor flow', (tester) async {
    final controller = PaccScheduleEditorController();
    PaccAvailabilityModel? saved;
    await tester.pumpWidget(_editor(controller: controller, onSave: (value, {confirmConflicts = false}) async {
      saved = value;
      return const PaccAvailabilitySaveResult(revision: 5, conflicts: []);
    }));
    await makeDirty(tester);
    final leave = controller.confirmLeave(tester.element(find.byType(PaccScheduleEditor)));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved schedule changes'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(await leave, isFalse);
    expect(saved, isNull);

    final saveLeave = controller.confirmLeave(tester.element(find.byType(PaccScheduleEditor)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(await saveLeave, isTrue);
    expect(saved, isNotNull);
  });

  testWidgets('discard leaves without saving and failed or conflicted saves stay', (tester) async {
    final discardController = PaccScheduleEditorController();
    var calls = 0;
    await tester.pumpWidget(_editor(controller: discardController, onSave: (_, {confirmConflicts = false}) async { calls++; return const PaccAvailabilitySaveResult(revision: 5, conflicts: []); }));
    await makeDirty(tester);
    final discard = discardController.confirmLeave(tester.element(find.byType(PaccScheduleEditor)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes').last);
    await tester.pumpAndSettle();
    expect(await discard, isTrue);
    expect(calls, 0);

    final failedController = PaccScheduleEditorController();
    await tester.pumpWidget(_editor(controller: failedController, onSave: (_, {confirmConflicts = false}) => Future.error(StateError('stale'))));
    await makeDirty(tester);
    final failed = failedController.confirmLeave(tester.element(find.byType(PaccScheduleEditor)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(await failed, isFalse);
    expect(find.text('Save failed. Your changes are still available.'), findsOneWidget);
  });

  testWidgets('clean navigation does not show a guard', (tester) async {
    final controller = PaccScheduleEditorController();
    await tester.pumpWidget(_editor(controller: controller));
    expect(await controller.confirmLeave(tester.element(find.byType(PaccScheduleEditor))), isTrue);
    expect(find.text('Unsaved schedule changes'), findsNothing);
  });

  testWidgets('unresolved conflict during navigation save keeps the draft and page', (tester) async {
    final controller = PaccScheduleEditorController();
    await tester.pumpWidget(_editor(controller: controller, onSave: (_, {confirmConflicts = false}) async => const PaccAvailabilitySaveResult(revision: 4, conflicts: [PaccScheduleConflict(appointmentId: 'a', status: 'confirmed', timestamp: 1, reason: 'Office is closed.')])));
    await makeDirty(tester);
    final leave = controller.confirmLeave(tester.element(find.byType(PaccScheduleEditor)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule conflicts'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await leave, isFalse);
    expect(find.text('Conflict detected'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsNothing);
  });

  testWidgets('custom special-date apply and removal remain local until Save schedule', (tester) async {
    const override = PaccDateOverride(
      date: '2099-01-01',
      closedAllDay: false,
      reason: 'Future custom hours',
      schedule: _openDay,
    );
    var calls = 0;
    PaccAvailabilityModel? saved;
    await tester.pumpWidget(_editor(
      availability: _schedule(overrides: const [override]),
      onSave: (value, {confirmConflicts = false}) async {
        calls++;
        saved = value;
        return const PaccAvailabilitySaveResult(revision: 5, conflicts: []);
      },
    ));

    expect(find.textContaining('Future custom hours'), findsOneWidget);
    await tester.ensureVisible(find.text('2099-01-01'));
    await tester.tap(find.text('2099-01-01'));
    await tester.pumpAndSettle();
    expect(find.text('Edit special date'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('override-opens')), '10:00');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('Special date updated.'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Remove 2099-01-01'));
    await tester.tap(find.byTooltip('Remove 2099-01-01'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('2099-01-01'), findsNothing);
    expect(find.textContaining('Special date removed.'), findsOneWidget);

    await tester.ensureVisible(find.text('Save schedule'));
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(saved!.overrides, isEmpty);
  });

  testWidgets('duplicate special date is rejected without changing the existing override', (tester) async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final existing = PaccDateOverride(date: today, closedAllDay: true, reason: 'Already set');
    var calls = 0;
    await tester.pumpWidget(_editor(
      availability: _schedule(overrides: [existing]),
      onSave: (_, {confirmConflicts = false}) async {
        calls++;
        return const PaccAvailabilitySaveResult(revision: 5, conflicts: []);
      },
    ));

    await tester.ensureVisible(find.text('Add special date'));
    await tester.tap(find.text('Add special date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('A special date already exists for $today.'), findsOneWidget);
    expect(find.text(today), findsOneWidget);
    expect(find.textContaining('Already set'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('an existing historical special date remains visible', (tester) async {
    const historical = PaccDateOverride(
      date: '2020-01-01',
      closedAllDay: true,
      reason: 'Historical closure',
    );
    await tester.pumpWidget(_editor(availability: _schedule(overrides: const [historical])));
    await tester.ensureVisible(find.text('2020-01-01'));
    expect(find.text('2020-01-01'), findsOneWidget);
    expect(find.textContaining('Historical closure'), findsOneWidget);
  });

  testWidgets('presents aligned weekday and special-date summaries', (tester) async {
    const custom = PaccDateOverride(
      date: '2099-09-30',
      closedAllDay: false,
      reason: 'University event schedule',
      schedule: PaccDaySchedule(
        enabled: true,
        opensAt: '10:00',
        closesAt: '14:00',
        presence: CounselorPresence.inOffice,
        appointmentsEnabled: true,
        acceptsWalkIns: false,
      ),
    );
    await tester.pumpWidget(_editor(availability: _schedule(overrides: const [custom])));

    expect(find.text('Weekly Schedule'), findsOneWidget);
    expect(find.text('Set multiple days'), findsOneWidget);
    // The scroll view reserves 25px; the button must align with the section's
    // padded right edge rather than following the heading text.
    expect(tester.getRect(find.text('Set multiple days')).right, closeTo(755, 1));
    expect(find.text('Special Dates'), findsOneWidget);
    expect(find.text('09:00 AM – 05:00 PM'), findsNWidgets(5));
    expect(find.text('In office'), findsWidgets);
    expect(find.text('Appointments on'), findsWidgets);
    expect(find.text('Walk-ins off'), findsOneWidget);
    expect(find.text('10:00 AM – 02:00 PM'), findsOneWidget);
    expect(find.text('Custom schedule'), findsOneWidget);
    expect(find.byTooltip('Edit 2099-09-30'), findsOneWidget);
    expect(find.byTooltip('Remove 2099-09-30'), findsOneWidget);
    expect(find.text('Revision 4'), findsNothing);
  });

  testWidgets('shows a concise empty special-date state and stays responsive', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_editor());

    expect(find.text('No special dates yet'), findsOneWidget);
    expect(find.textContaining('Add an override for holidays'), findsOneWidget);
    expect(find.text('Add special date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
    await tester.ensureVisible(find.text('Save schedule'));
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();

    expect(saved!.weekdays[1]!.opensAt, '10:00');
    expect(saved!.weekdays[2]!.opensAt, '09:00');
    expect(saved!.weekdays[6]!.enabled, isFalse);
    expect(find.text('Schedule saved successfully'), findsOneWidget);
  });

  testWidgets('supports counselor and service controls per weekday', (tester) async {
    PaccAvailabilityModel? saved;
    await tester.pumpWidget(_editor(onSave: (value, {confirmConflicts = false}) async {
      saved = value;
      return const PaccAvailabilitySaveResult(revision: 5, conflicts: []);
    }));
    await tester.ensureVisible(find.byKey(const Key('edit-day-4')));
    await tester.tap(find.byKey(const Key('edit-day-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Out of office'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save schedule'));
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

    expect(find.text('Save failed. Your changes are still available.'), findsOneWidget);
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

  testWidgets('refreshes a clean editor when Firestore supplies a newer revision', (tester) async {
    await tester.pumpWidget(_editor(availability: _schedule(revision: 4)));
    await tester.pumpWidget(_editor(availability: PaccAvailabilityModel.v2(
      weekdays: {
        for (var day = 1; day <= 7; day++)
          day: day == 1 ? _openDay.copyWith(opensAt: '10:00') : _openDay,
      },
      overrides: const [],
      revision: 5,
    )));

    expect(find.textContaining('10:00 AM – 05:00 PM'), findsOneWidget);
    expect(find.text('Revision 5'), findsNothing);
  });

  testWidgets('applies one shared draft to Monday through Wednesday only', (tester) async {
    PaccAvailabilityModel? saved;
    await tester.pumpWidget(_editor(onSave: (value, {confirmConflicts = false}) async {
      saved = value;
      return const PaccAvailabilitySaveResult(revision: 5, conflicts: []);
    }));
    await tester.tap(find.text('Set multiple days'));
    await tester.pumpAndSettle();
    for (final day in [1, 2, 3]) {
      await tester.tap(find.byKey(Key('bulk-day-$day')));
    }
    await tester.enterText(find.byKey(const Key('bulk-opens')), '10:00');
    await tester.enterText(find.byKey(const Key('bulk-closes')), '16:00');
    await tester.tap(find.text('Apply to 3 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();

    for (final day in [1, 2, 3]) {
      expect(saved!.weekdays[day]!.opensAt, '10:00');
      expect(saved!.weekdays[day]!.closesAt, '16:00');
    }
    expect(saved!.weekdays[4]!.opensAt, '09:00');
    expect(saved!.weekdays[6]!.enabled, isFalse);
    expect(saved!.weekdays[7]!.enabled, isFalse);
  });
}
