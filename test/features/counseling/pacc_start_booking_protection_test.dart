import 'dart:async';

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
  testWidgets('startBooking opens intake after an empty appointment load', (
    tester,
  ) async {
    await tester.pumpWidget(
      _paccApp(_EmptyAppointmentRepository(), showBottomNavigation: false),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intake')), findsWidgets);
  });

  testWidgets(
    'startBooking opens intake after Home has already loaded appointments',
    (tester) async {
      final repository = _EmptyAppointmentRepository();
      final appointments = AppointmentProvider(repository);
      await appointments.loadAppointments('user_1');

      await tester.pumpWidget(_paccAppWithProvider(appointments));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('intake')), findsWidgets);
    },
  );

  testWidgets(
    'startBooking does not open intake while appointment loading is pending',
    (tester) async {
      final pendingLoad = Completer<List<AppointmentModel>>();
      await tester.pumpWidget(
        _paccApp(_SequencedAppointmentRepository([() => pendingLoad.future])),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('appointmentLoading')), findsOneWidget);
      expect(find.byKey(const ValueKey('intake')), findsNothing);
    },
  );

  testWidgets(
    'startBooking shows a retryable error after appointment loading fails',
    (tester) async {
      await tester.pumpWidget(
        _paccApp(
          _SequencedAppointmentRepository([
            () => Future<List<AppointmentModel>>.error(StateError('offline')),
            () async => const [],
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('appointmentLoadError')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('intake')), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('appointmentLoadError')), findsNothing);
      expect(find.byKey(const ValueKey('intake')), findsWidgets);
    },
  );

  testWidgets('startBooking preserves the active appointment protection', (
    tester,
  ) async {
    final appointments = _ActiveAppointmentRepository();
    await tester.pumpWidget(_paccApp(appointments));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('You already have an active appointment'),
      findsOneWidget,
    );
    expect(appointments.createCalls, 0);
  });
}

Widget _paccApp(
  AppointmentRepository repository, {
  bool showBottomNavigation = true,
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) =>
          UserProvider(_FakeUserRepository())
            ..setUser(const UserModel(id: 'user_1', email: 'user@example.com')),
    ),
    ChangeNotifierProvider(create: (_) => AppointmentProvider(repository)),
  ],
  child: MaterialApp(
    home: PaccCounselingScreen(
      startBooking: true,
      showBottomNavigation: showBottomNavigation,
    ),
  ),
);

Widget _paccAppWithProvider(AppointmentProvider provider) => MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) =>
          UserProvider(_FakeUserRepository())
            ..setUser(const UserModel(id: 'user_1', email: 'user@example.com')),
    ),
    ChangeNotifierProvider<AppointmentProvider>.value(value: provider),
  ],
  child: const MaterialApp(home: PaccCounselingScreen(startBooking: true)),
);

class _FakeUserRepository extends UserRepository {}

class _ActiveAppointmentRepository extends AppointmentRepository {
  int createCalls = 0;

  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async => [
    AppointmentModel(
      id: 'active_1',
      userId: userId,
      fullName: 'Existing User',
      scheduledAt: DateTime(2026, 10, 12, 9),
      scheduledTime: '9:00 AM',
      location: 'PACC',
      status: 'requested',
      concern: 'Existing concern',
      contactNumber: '09123456789',
      email: 'user@example.com',
      preferredContactMethod: 'Email',
      createdAt: DateTime(2026, 10, 9),
    ),
  ];

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      Stream.value([]);

  @override
  Future<AppointmentModel> createAppointment(
    AppointmentModel appointment, {
    String? requestId,
  }) async {
    createCalls += 1;
    return appointment.copyWith(id: 'created_1');
  }
}

class _EmptyAppointmentRepository extends AppointmentRepository {
  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async =>
      const [];

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      const Stream<List<AppointmentModel>>.empty();
}

class _SequencedAppointmentRepository extends AppointmentRepository {
  _SequencedAppointmentRepository(this._loads);

  final List<Future<List<AppointmentModel>> Function()> _loads;
  int _loadIndex = 0;

  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) {
    final index = _loadIndex++;
    return _loads[index.clamp(0, _loads.length - 1)]();
  }

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      const Stream<List<AppointmentModel>>.empty();
}
