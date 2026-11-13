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

Widget _app({bool use24Hour = false}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) =>
          UserProvider(_UserRepository())
            ..setUser(const UserModel(id: 'user_1', email: 'user@example.com')),
    ),
    ChangeNotifierProvider(
      create: (_) => AppointmentProvider(_AppointmentRepository()),
    ),
  ],
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(alwaysUse24HourFormat: use24Hour),
      child: const PaccCounselingScreen(
        startBooking: true,
        showBottomNavigation: false,
      ),
    ),
  ),
);

class _UserRepository extends UserRepository {}

class _AppointmentRepository extends AppointmentRepository {
  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async => [];

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      const Stream.empty();
}
