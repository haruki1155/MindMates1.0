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
    await tester.tap(find.byKey(const Key('best-time-days-weekends')));
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
    await _goToTime(tester);
    await tester.tap(find.byKey(const Key('time-chip-10:00 AM')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to Confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Appointment').last);
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
    expect(find.text('Confirm Appointment'), findsWidgets);
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

Future<void> _goToTime(WidgetTester tester) async {
  await tester.pumpAndSettle();
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
    final option = find.text(label);
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
  await tester.ensureVisible(find.text('30'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('30'));
  await tester.pumpAndSettle();
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
