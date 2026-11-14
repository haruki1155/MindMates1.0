import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/screens/pacc_counseling_screen.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('saves the selected day and canonical contact window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _AppointmentRepository();
    await tester.pumpWidget(_app(repository: repository, use24Hour: true));
    await tester.pumpAndSettle();
    await _enterCounseling(tester);

    final weekends = find.byKey(
      const Key('best-time-days-weekends'),
    );
    await tester.ensureVisible(weekends);
    await tester.pumpAndSettle();
    await tester.tap(weekends);
    await tester.pumpAndSettle();
    for (final entry in <String, String>{'best-time-start': '8'}.entries) {
      await tester.tap(find.byKey(Key(entry.key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(TimePickerDialog),
              matching: find.byType(TextField),
            )
            .first,
        entry.value,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
    await _goToTime(tester, fromCounseling: true);
    await tester.tap(find.byKey(const Key('time-chip-10:00 AM')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to Confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send appointment request'));
    await tester.pumpAndSettle();
    expect(repository.created?.bestTime, 'Weekends, 8:00 AM – 12:00 PM');
  });

  testWidgets('shows compact offered hours and selects one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await _goToTime(tester);
    for (final time in ['9:00 AM', '10:00 AM', '11:00 AM']) {
      expect(find.byKey(Key('time-chip-$time')), findsOneWidget);
    }
    expect(find.text('Available'), findsNothing);
    final chip = find.byKey(const Key('time-chip-10:00 AM'));
    await tester.tap(chip);
    await tester.pump();
    expect(
      tester
          .widget<InkWell>(
            find.descendant(of: chip, matching: find.byType(InkWell)),
          )
          .onTap,
      isNotNull,
    );
    await tester.tap(find.text('Continue to Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Review request'), findsOneWidget);
    expect(find.text('Send appointment request'), findsOneWidget);
  });

  testWidgets('chips wrap at 360 px with large text and 44 px targets', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
        child: _app(),
      ),
    );
    await _goToTime(tester);
    await tester.binding.setSurfaceSize(const Size(360, 900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final time in ['9:00 AM', '10:00 AM', '11:00 AM']) {
      expect(
        tester.getSize(find.byKey(Key('time-chip-$time'))).height,
        greaterThanOrEqualTo(44),
      );
    }
  });
}

Future<void> _enterCounseling(WidgetTester tester) async {
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey('intake')),
    findsOneWidget,
  );

  const fields = <String, String>{
    'intake-first-name': 'Leonardo',
    'intake-last-name': 'Molar',
    'intake-age': '20',
    'intake-address': 'Urdaneta City',
    'intake-contact': '09123456789',
    'intake-email': 'leo@example.com',
    'intake-facebook': 'facebook.com/leo',
  };

  for (final field in fields.entries) {
    await tester.enterText(
      find.byKey(ValueKey(field.key)),
      field.value,
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

Future<void> _goToTime(
  WidgetTester tester, {
  bool fromCounseling = false,
}) async {
  if (!fromCounseling) {
    await _enterCounseling(tester);
  }

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

  final next = find.text('Continue to Date & Time');
  await tester.ensureVisible(next);
  await tester.pumpAndSettle();
  await tester.tap(next);
  await tester.pumpAndSettle();

  expect(find.text('Appointment Schedule'), findsOneWidget);

  final date = find.text('30');
  await tester.ensureVisible(date);
  await tester.pumpAndSettle();
  await tester.tap(date);
  await tester.pumpAndSettle();

  expect(
    find.byKey(const Key('time-chip-10:00 AM')),
    findsOneWidget,
  );
}

Widget _app({_AppointmentRepository? repository, bool use24Hour = false}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => UserProvider(_UserRepository())
            ..setUser(
              const UserModel(
                id: 'user_1',
                email: 'leo@example.com',
                course: 'BS Information Technology',
              ),
            ),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AppointmentProvider(repository ?? _AppointmentRepository()),
        ),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(alwaysUse24HourFormat: use24Hour),
          child: PaccCounselingScreen(
            startBooking: true,
            showBottomNavigation: false,
            nowProvider: () => DateTime(2026, 4, 15, 9),
          ),
        ),
      ),
    );

class _UserRepository extends UserRepository {}

class _AppointmentRepository extends AppointmentRepository {
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
  Future<List<AppointmentModel>> fetchAppointments(String userId) async => [];
  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      const Stream.empty();
  @override
  Future<List<AppointmentSlot>> getAvailableSlots(DateTime date) async => [
    for (final hour in [9, 10, 11])
      AppointmentSlot(
        start: DateTime(date.year, date.month, date.day, hour),
        label: '${hour > 12 ? hour - 12 : hour}:00 AM',
      ),
  ];
}
