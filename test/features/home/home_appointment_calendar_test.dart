import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/home/screens/home_appointment_calendar_screen.dart';
import 'package:mind_mates/features/home/screens/home_screen.dart';
import 'package:mind_mates/features/counseling/screens/pacc_counseling_screen.dart';
import 'package:mind_mates/features/counseling/widgets/appointment_details_sheet.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';
import 'package:mind_mates/repositories/mood_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:provider/provider.dart';

void main() {
  final now = DateTime(2026, 4, 10, 9);

  test('appointment statuses are normalized for calendar styling', () {
    expect(
      appointmentDisplayStatus('UPCOMING'),
      AppointmentDisplayStatus.upcoming,
    );
    expect(
      appointmentDisplayStatus('completed'),
      AppointmentDisplayStatus.completed,
    );
    expect(
      appointmentDisplayStatus('Canceled'),
      AppointmentDisplayStatus.cancelled,
    );
    expect(
      appointmentDisplayStatus('Rescheduled'),
      AppointmentDisplayStatus.other,
    );
  });

  test('next active appointment ignores past and inactive records', () {
    final result = nextActiveAppointment([
      _appointment('past', DateTime(2026, 4, 9, 9)),
      _appointment('cancelled', DateTime(2026, 4, 11, 9), status: 'Cancelled'),
      _appointment('later', DateTime(2026, 5, 1, 9), status: 'Confirmed'),
      _appointment('next', DateTime(2026, 4, 20, 9), status: 'Pending'),
    ], now: now);

    expect(result?.id, 'next');
  });

  testWidgets('Home shows earliest future upcoming appointment', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appointments = [
      _appointment('past', DateTime(2026, 4, 8, 9)),
      _appointment('cancelled', DateTime(2026, 4, 11, 9), status: 'Cancelled'),
      _appointment('later', DateTime(2026, 4, 20, 14), time: '02:00 PM'),
      _appointment('next', DateTime(2026, 4, 15, 10), time: '10:00 AM'),
    ];
    final provider = AppointmentProvider(
      _FakeAppointmentRepository(appointments),
    );

    await tester.pumpWidget(_app(provider, HomeScreen(nowProvider: () => now)));
    await tester.pumpAndSettle();

    expect(find.text('Next appointment'), findsOneWidget);
    expect(find.textContaining('10:00 AM'), findsOneWidget);
    expect(find.textContaining('02:00 PM'), findsNothing);
  });

  testWidgets('Home calendar icon opens month calendar', (tester) async {
    final provider = AppointmentProvider(
      _FakeAppointmentRepository([
        _appointment('one', DateTime(2026, 4, 15, 10), time: '10:00 AM'),
      ]),
    );
    await tester.pumpWidget(_app(provider, HomeScreen(nowProvider: () => now)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Calendar'));
    await tester.pumpAndSettle();

    expect(find.byType(PaccCounselingScreen), findsOneWidget);
    expect(find.text('My Appointments'), findsOneWidget);
  });

  testWidgets('empty Home preview opens PACC booking flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = AppointmentProvider(_FakeAppointmentRepository(const []));
    await tester.pumpWidget(_app(provider, HomeScreen(nowProvider: () => now)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Appoint a Session'));
    await tester.pumpAndSettle();

    expect(find.byType(PaccCounselingScreen), findsOneWidget);
    expect(find.text('Appointment Schedule'), findsOneWidget);
  });

  testWidgets('selected calendar date shows ordered appointments and details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = AppointmentProvider(
      _FakeAppointmentRepository([
        _appointment('later', DateTime(2026, 4, 15, 14), time: '02:00 PM'),
        _appointment('first', DateTime(2026, 4, 15, 9), time: '09:00 AM'),
      ]),
    );
    await provider.loadAppointments('user_1');

    await tester.pumpWidget(
      _app(
        provider,
        HomeAppointmentCalendarScreen(
          initialDate: DateTime(2026, 4, 15),
          nowProvider: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('April 15, 2026'), findsOneWidget);
    final first = tester.getTopLeft(find.text('09:00 AM')).dy;
    final later = tester.getTopLeft(find.text('02:00 PM')).dy;
    expect(first, lessThan(later));

    await tester.tap(find.text('09:00 AM'));
    await tester.pumpAndSettle();
    expect(find.text('Appointment Details'), findsOneWidget);
    expect(find.text('I would like support.'), findsOneWidget);
  });

  testWidgets(
    'calendar auto-focuses next active appointment and dates are read-only',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final provider = AppointmentProvider(
        _FakeAppointmentRepository([
          _appointment(
            'cancelled',
            DateTime(2026, 4, 12, 9),
            status: 'Cancelled',
          ),
          _appointment('next', DateTime(2026, 5, 6, 10), status: 'Confirmed'),
          _appointment('later', DateTime(2026, 5, 20, 10), status: 'Upcoming'),
        ]),
      );
      await provider.loadAppointments('user_1');

      await tester.pumpWidget(
        _app(provider, HomeAppointmentCalendarScreen(nowProvider: () => now)),
      );
      await tester.pumpAndSettle();

      expect(find.text('May 2026'), findsOneWidget);
      expect(find.text('Highlighted appointment'), findsOneWidget);
      expect(find.text('May 6, 2026'), findsOneWidget);
      expect(find.text('Confirmed'), findsWidgets);
      final day = find.byKey(
        const ValueKey('appointment-calendar-day-2026-5-20'),
      );
      expect(day, findsOneWidget);
      expect(
        find.ancestor(of: day, matching: find.byType(InkWell)),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('April 2026'), findsOneWidget);
      expect(find.text('May 6, 2026'), findsOneWidget);
    },
  );

  testWidgets('explicit initial date takes precedence over automatic focus', (
    tester,
  ) async {
    final provider = AppointmentProvider(
      _FakeAppointmentRepository([
        _appointment('next', DateTime(2026, 4, 15, 9)),
        _appointment('chosen', DateTime(2026, 6, 3, 9), status: 'Completed'),
      ]),
    );
    await provider.loadAppointments('user_1');

    await tester.pumpWidget(
      _app(
        provider,
        HomeAppointmentCalendarScreen(
          initialDate: DateTime(2026, 6, 3),
          nowProvider: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('June 2026'), findsOneWidget);
    expect(find.text('June 3, 2026'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
  });
}

Widget _app(AppointmentProvider appointments, Widget home) {
  final users = UserProvider(_FakeUserRepository())
    ..setUser(const UserModel(id: 'user_1', email: 'user@example.com'));
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: users),
      ChangeNotifierProvider<AppointmentProvider>.value(value: appointments),
      ChangeNotifierProvider(
        create: (_) => MoodProvider(_FakeMoodRepository()),
      ),
      ChangeNotifierProvider(
        create: (_) => AssessmentProvider(AssessmentRepository()),
      ),
    ],
    child: MaterialApp(home: home),
  );
}

AppointmentModel _appointment(
  String id,
  DateTime scheduledAt, {
  String status = 'Upcoming',
  String time = '09:00 AM',
}) {
  return AppointmentModel(
    id: id,
    userId: 'user_1',
    fullName: 'Test User',
    scheduledAt: scheduledAt,
    scheduledTime: time,
    location: 'PACC Office',
    status: status,
    concern: 'I would like support.',
    contactNumber: '09123456789',
    email: 'user@example.com',
    preferredContactMethod: 'Email',
    createdAt: DateTime(2026, 4, 1),
  );
}

class _FakeAppointmentRepository extends AppointmentRepository {
  _FakeAppointmentRepository(this.items);
  final List<AppointmentModel> items;

  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async {
    return items.where((item) => item.userId == userId).toList();
  }

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      Stream.value(items.where((item) => item.userId == userId).toList());
}

class _FakeUserRepository extends UserRepository {}

class _FakeMoodRepository extends MoodRepository {
  @override
  Future<List<MoodModel>> fetchRecentMoods(
    String userId, {
    int limit = 14,
  }) async => const [];
}
