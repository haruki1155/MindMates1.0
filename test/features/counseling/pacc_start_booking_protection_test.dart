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
  testWidgets('startBooking preserves the active appointment protection', (
    tester,
  ) async {
    final appointments = _ActiveAppointmentRepository();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => UserProvider(_FakeUserRepository())
              ..setUser(
                const UserModel(id: 'user_1', email: 'user@example.com'),
              ),
          ),
          ChangeNotifierProvider(
            create: (_) => AppointmentProvider(appointments),
          ),
        ],
        child: const MaterialApp(
          home: PaccCounselingScreen(startBooking: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('You already have an active appointment'),
      findsOneWidget,
    );
    expect(appointments.createCalls, 0);
  });
}

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
