import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/domain/best_contact_time.dart';
import 'package:mind_mates/features/counseling/screens/pacc_counseling_screen.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('shows default contact window without a text box', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _enterCounselingStage(tester);
    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('12:00 PM'), findsOneWidget);
    expect(find.byKey(const Key('best-time-start')), findsOneWidget);
    expect(find.byKey(const Key('best-time-end')), findsOneWidget);
  });

  testWidgets('shows device 24 hour format in picker fields', (tester) async {
    await tester.pumpWidget(_app(use24Hour: true));
    await tester.pumpAndSettle();
    await _enterCounselingStage(tester);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('9:00 AM'), findsNothing);
  });

  testWidgets('selects a different contact day', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _enterCounselingStage(tester);
    final weekends = find.byKey(const Key('best-time-days-weekends'));
    await tester.ensureVisible(weekends);
    await tester.pumpAndSettle();
    await tester.tap(weekends);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(weekends).selected, isTrue);
  });

  testWidgets('time picker changes hours and cancel keeps current value', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _enterCounselingStage(tester);
    final start = find.byKey(const Key('best-time-start'));
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(TimePickerDialog),
            matching: find.byType(TextField),
          )
          .first,
      '8',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('8:00 AM'), findsOneWidget);

    await tester.tap(start);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('8:00 AM'), findsOneWidget);
  });

  testWidgets('reopening legacy free text shows safe picker defaults', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _AppointmentRepository(_legacyAppointment());

    await tester.pumpWidget(_app(repository: repository));
    await tester.pumpAndSettle();

    // Open the existing completed appointment.
    await tester.tap(find.text('Past').first);
    await tester.pumpAndSettle();

    final view = find.text('View appointment');
    await tester.ensureVisible(view);
    await tester.pumpAndSettle();
    await tester.tap(view);
    await tester.pumpAndSettle();

    // Rebook from the legacy appointment.
    await tester.tap(find.text('Book Appointment').last);
    await tester.pumpAndSettle();

    // Complete Personal Information before Counseling Details.
    await _enterCounselingStage(tester);

    // Legacy free text must fall back to safe visual defaults.
    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('12:00 PM'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('intake-concern')),
      'I need counseling',
    );

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    for (final label in ['Email', 'No']) {
      final option = find.widgetWithText(InkWell, label);
      expect(option, findsOneWidget);
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();
    }

    final continueToSchedule = find.text('Continue to Date & Time');
    await tester.ensureVisible(continueToSchedule);
    await tester.pumpAndSettle();
    await tester.tap(continueToSchedule);
    await tester.pumpAndSettle();

    // Select a server-offered date and time.
    final date = find.text('30');
    await tester.ensureVisible(date);
    await tester.pumpAndSettle();
    await tester.tap(date);
    await tester.pumpAndSettle();

    final slot = find.byKey(const Key('time-chip-10:00 AM'));
    expect(slot, findsOneWidget);
    await tester.ensureVisible(slot);
    await tester.pumpAndSettle();
    await tester.tap(slot);
    await tester.pumpAndSettle();

    final review = find.text('Continue to Confirm');
    await tester.ensureVisible(review);
    await tester.pumpAndSettle();
    await tester.tap(review);
    await tester.pumpAndSettle();

    expect(find.text('Review request'), findsOneWidget);

    final submit = find.text('Send appointment request');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    // The original legacy contact preference must be preserved.
    expect(
      repository.created?.bestTime,
      'Weekend mornings 9 AM - 12 PM',
    );
  });

  testWidgets('rejects equal and overnight contact windows', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _enterCounselingStage(tester);
    final field = tester.state<FormFieldState<BestContactTime>>(
      find.byWidgetPredicate((widget) => widget is FormField<BestContactTime>),
    );
    for (final range in [
      const BestContactTime(
        days: BestContactTimeDays.weekdays,
        start: TimeOfDay(hour: 9, minute: 0),
        end: TimeOfDay(hour: 9, minute: 0),
      ),
      const BestContactTime(
        days: BestContactTimeDays.weekdays,
        start: TimeOfDay(hour: 23, minute: 0),
        end: TimeOfDay(hour: 1, minute: 0),
      ),
    ]) {
      field.didChange(range);
      field.validate();
      await tester.pump();
      expect(
        find.text('End time must be after the start time.'),
        findsOneWidget,
      );
    }
  });
}


Future<void> _enterCounselingStage(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('intake')), findsOneWidget);

  const fields = <String, String>{
    'intake-first-name': 'Test',
    'intake-last-name': 'Student',
    'intake-age': '20',
    'intake-address': 'Urdaneta City',
    'intake-contact': '09123456789',
    'intake-email': 'user@example.com',
    'intake-facebook': 'test@example.com',
  };

  for (final entry in fields.entries) {
    await tester.enterText(
      find.byKey(ValueKey(entry.key)),
      entry.value,
    );
  }

  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();

  for (final label in ['Male', 'Fourth Year']) {
    final option = find.widgetWithText(InkWell, label);
    expect(option, findsOneWidget);
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  final next = find.text('Continue to Counseling Details');
  await tester.ensureVisible(next);
  await tester.pumpAndSettle();
  await tester.tap(next);
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey('counselingDetails')),
    findsOneWidget,
  );
}


Widget _app({bool use24Hour = false, _AppointmentRepository? repository}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => UserProvider(_UserRepository())
            ..setUser(const UserModel(id: 'user_1', email: 'user@example.com', course: 'BS Information Technology')),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AppointmentProvider(repository ?? _AppointmentRepository(null)),
        ),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(alwaysUse24HourFormat: use24Hour),
          child: PaccCounselingScreen(
            startBooking: repository?.prior == null,
            showBottomNavigation: false,
            nowProvider: () => DateTime(2026, 4, 15, 9),
          ),
        ),
      ),
    );

class _UserRepository extends UserRepository {}

AppointmentModel _legacyAppointment() => AppointmentModel(
  id: 'old_1',
  userId: 'user_1',
  fullName: 'Prior Student',
  scheduledAt: DateTime(2026, 4, 1, 9),
  scheduledTime: '9:00 AM',
  location: 'PACC',
  status: 'completed',
  concern: 'Prior concern',
  contactNumber: '09123456789',
  email: 'user@example.com',
  preferredContactMethod: 'Email',
  bestTime: 'Weekend mornings 9 AM - 12 PM',
  course: 'BS Information Technology',
  createdAt: DateTime(2026, 3, 1),
);

class _AppointmentRepository extends AppointmentRepository {
  _AppointmentRepository(this.prior);
  final AppointmentModel? prior;

  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async =>
      prior == null ? [] : [prior!];

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      Stream.value(prior == null ? [] : [prior!]);

  AppointmentModel? created;

  @override
  Future<AppointmentModel> createAppointment(
    AppointmentModel appointment, {
    String? requestId,
  }) async {
    created = appointment;
    return appointment.copyWith(id: 'created_1');
  }

  @override
  Future<List<AppointmentSlot>> getAvailableSlots(DateTime date) async => [
    AppointmentSlot(start: DateTime(2026, 4, 30, 10), label: '10:00 AM'),
  ];
}
