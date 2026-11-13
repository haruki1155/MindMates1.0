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
    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('12:00 PM'), findsOneWidget);
    expect(find.byKey(const Key('best-time-start')), findsOneWidget);
    expect(find.byKey(const Key('best-time-end')), findsOneWidget);
  });

  testWidgets('shows device 24 hour format in picker fields', (tester) async {
    await tester.pumpWidget(_app(use24Hour: true));
    await tester.pumpAndSettle();
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('9:00 AM'), findsNothing);
  });

  testWidgets('selects a different contact day', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('Past').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Appointment'));
    await tester.pumpAndSettle();
    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('12:00 PM'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final fields = find.byType(TextFormField);
    for (final entry in <int, String>{
      0: 'Molar',
      1: 'Leonardo',
      3: '20',
      4: 'Urdaneta',
      5: '09123456789',
      6: 'leo@example.com',
      7: 'facebook.com/leo',
      8: 'I need counseling',
    }.entries) {
      await tester.enterText(fields.at(entry.key), entry.value);
    }
    for (final label in ['Male', 'Fourth Year', 'Email', 'No']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Continue to Date & Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10:00 AM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to Confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Appointment').last);
    await tester.pumpAndSettle();
    expect(repository.created?.bestTime, 'Weekend mornings 9 AM - 12 PM');
  });

  testWidgets('rejects equal and overnight contact windows', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
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

Widget _app({bool use24Hour = false, _AppointmentRepository? repository}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => UserProvider(_UserRepository())
            ..setUser(const UserModel(id: 'user_1', email: 'user@example.com')),
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
