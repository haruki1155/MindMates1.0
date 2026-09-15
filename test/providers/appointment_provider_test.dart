import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';

void main() {
  test('loads appointments for the requested user', () async {
    final repository = _FakeAppointmentRepository([
      _appointment('a1', 'user_1'),
      _appointment('a2', 'user_2'),
    ])..returnAllUsers = true;
    final provider = AppointmentProvider(repository);

    await provider.loadAppointments('user_1');

    expect(provider.appointments.map((item) => item.id), ['a1']);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
  });

  test(
    'load failure preserves existing appointments and exposes an error',
    () async {
      final repository = _FakeAppointmentRepository([
        _appointment('a1', 'user_1'),
      ]);
      final provider = AppointmentProvider(repository);
      await provider.loadAppointments('user_1');

      repository.shouldFail = true;
      await provider.loadAppointments('user_1');

      expect(provider.appointments.single.id, 'a1');
      expect(provider.errorMessage, 'Unable to load appointments.');
    },
  );

  test('save failure does not add an appointment', () async {
    final repository = _FakeAppointmentRepository([])..shouldFail = true;
    final provider = AppointmentProvider(repository);

    final saved = await provider.createAppointment(
      _appointment('new', 'user_1'),
    );

    expect(saved, isFalse);
    expect(provider.appointments, isEmpty);
    expect(provider.errorMessage, 'Unable to save appointment. Please try again.');
    expect(provider.isSaving, isFalse);
  });

  test(
    'switching users clears the previous user appointments immediately',
    () async {
      final repository = _FakeAppointmentRepository([
        _appointment('a1', 'user_1'),
        _appointment('a2', 'user_2'),
      ]);
      final provider = AppointmentProvider(repository);
      await provider.loadAppointments('user_1');

      final loading = provider.loadAppointments('user_2');

      expect(provider.appointments, isEmpty);
      await loading;
      expect(provider.appointments.single.id, 'a2');
    },
  );

  test('duplicate save attempts produce only one repository write', () async {
    final repository = _FakeAppointmentRepository([])
      ..saveCompleter = Completer<AppointmentModel>();
    final provider = AppointmentProvider(repository);
    final appointment = _appointment('new', 'user_1');

    final first = provider.createAppointment(appointment);
    final second = await provider.createAppointment(appointment);

    expect(second, isFalse);
    expect(repository.createCalls, 1);
    repository.saveCompleter!.complete(appointment.copyWith(id: 'created_1'));
    expect(await first, isTrue);
    expect(provider.appointments, hasLength(1));
  });
}

AppointmentModel _appointment(String id, String userId) {
  return AppointmentModel(
    id: id,
    userId: userId,
    fullName: 'Test User',
    concern: 'Needs support.',
    scheduledAt: DateTime(2026, 4, 30, 11),
    scheduledTime: '11:00 AM',
    location: 'PACC Office',
    status: 'Upcoming',
    contactNumber: '123',
    email: 'test@example.com',
    preferredContactMethod: 'Email',
    createdAt: DateTime(2026, 4, 1),
  );
}

class _FakeAppointmentRepository extends AppointmentRepository {
  _FakeAppointmentRepository(this.items);

  final List<AppointmentModel> items;
  bool shouldFail = false;
  bool returnAllUsers = false;
  int createCalls = 0;
  Completer<AppointmentModel>? saveCompleter;

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      const Stream<List<AppointmentModel>>.empty();

  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async {
    if (shouldFail) throw StateError('load failed');
    if (returnAllUsers) return List.of(items);
    return items.where((item) => item.userId == userId).toList();
  }

  @override
  Future<AppointmentModel> createAppointment(
    AppointmentModel appointment,
  ) async {
    createCalls += 1;
    if (shouldFail) throw StateError('save failed');
    if (saveCompleter != null) return saveCompleter!.future;
    return appointment.copyWith(id: 'created_1');
  }
}
