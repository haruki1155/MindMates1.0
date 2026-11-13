import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';

void main() {
  test('agreement preserves both revisions, optional reason and stale account safety', () async {
    final repository = _FakeAppointmentRepository([])..agreementCompleter = Completer<void>();
    final provider = AppointmentProvider(repository);
    await provider.loadAppointments('user_1');
    final item = _appointment('a1', 'user_1').copyWith(hasScheduleRevision: true, scheduleRevision: 4, proposalRevision: 6);
    final pending = provider.changeAgreement(item, 'cancel', 'stable_cancel_request', reason: '');
    expect(provider.isSaving, isTrue);
    expect(await provider.changeAgreement(item, 'cancel', 'duplicate_cancel_request'), isFalse);
    expect(repository.agreementCalls, 1);
    expect(repository.agreementItem!.proposalRevision, 6);
    expect(repository.agreementItem!.scheduleRevision, 4);
    expect(repository.agreementReason, '');
    await provider.loadAppointments('user_2');
    repository.agreementCompleter!.complete();
    expect(await pending, isFalse);
    expect(provider.errorMessage, isNull);
  });

  test('internal availability failures give a useful recovery message', () async {
    final repository = _AvailabilityRepository()..internal = true;
    final provider = AppointmentProvider(repository);
    await provider.getAvailableSlots(DateTime(2026, 11, 16));
    expect(provider.slotAvailabilityMessage, contains('ask PACC to check the published schedule'));
    expect(provider.slotAvailabilityMessage, isNot('INTERNAL'));
  });

  test('availability exposes actionable errors and clears them after retry', () async {
    final repository = _AvailabilityRepository();
    final provider = AppointmentProvider(repository);
    expect(await provider.getAvailableSlots(DateTime(2026, 11, 16)), isEmpty);
    expect(provider.slotAvailabilityMessage, 'PACC availability has not been published.');
    repository.fail = false;
    expect(await provider.getAvailableSlots(DateTime(2026, 11, 16)), hasLength(1));
    expect(provider.errorMessage, isNull);
    expect(provider.slotAvailabilityMessage, isNull);
  });

  test('edit forwards opened revision and request identity and rejects stale account result', () async {
    final repository = _FakeAppointmentRepository([])..editCompleter = Completer<void>();
    final provider = AppointmentProvider(repository);
    await provider.loadAppointments('user_1');
    final opened = _appointment('a1', 'user_1').copyWith(scheduleRevision: 7, hasScheduleRevision: true);
    final future = provider.rescheduleAppointment(opened, DateTime(2026, 5, 1), 'stable_request');
    expect(provider.isSaving, isTrue);
    expect(repository.editRevision, 7);
    expect(repository.editOriginal, opened.scheduledAt);
    expect(repository.editRequestId, 'stable_request');
    await provider.loadAppointments('user_2');
    repository.editCompleter!.complete();
    expect(await future, isFalse);
    expect(provider.isSaving, isFalse);
  });
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
    expect(
      provider.errorMessage,
      'Unable to save appointment. Please try again.',
    );
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

  test('passes a stable booking request ID to the repository', () async {
    final repository = _FakeAppointmentRepository([]);
    final provider = AppointmentProvider(repository);

    final saved = await provider.createAppointment(
      _appointment('new', 'user_1'),
      requestId: 'booking_retry_safe_01',
    );

    expect(saved, isTrue);
    expect(repository.lastRequestId, 'booking_retry_safe_01');
  });

  test(
    'idempotent booking replay does not duplicate the local appointment',
    () async {
      final repository = _FakeAppointmentRepository([]);
      final provider = AppointmentProvider(repository);
      final appointment = _appointment('new', 'user_1');

      expect(
        await provider.createAppointment(
          appointment,
          requestId: 'booking_retry_safe_01',
        ),
        isTrue,
      );
      expect(
        await provider.createAppointment(
          appointment,
          requestId: 'booking_retry_safe_01',
        ),
        isTrue,
      );

      expect(provider.appointments.map((item) => item.id), ['created_1']);
    },
  );
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
  int agreementCalls = 0;
  AppointmentModel? agreementItem;
  String? agreementReason;
  Completer<void>? agreementCompleter;
  @override
  Future<void> changeAgreement({required AppointmentModel appointment, required String action, required String requestId, String? reason}) async { agreementCalls++; agreementItem = appointment; agreementReason = reason; if (agreementCompleter != null) await agreementCompleter!.future; }
  String? lastRequestId;
  Completer<AppointmentModel>? saveCompleter;
  Completer<void>? editCompleter;
  int? editRevision;
  DateTime? editOriginal;
  String? editRequestId;

  @override
  Future<void> rescheduleAppointment({required String appointmentId, required DateTime expectedScheduledAt, required int expectedScheduleRevision, int expectedProposalRevision = 0, required DateTime scheduledAt, required String requestId}) async {
    editRevision = expectedScheduleRevision;
    editOriginal = expectedScheduledAt;
    editRequestId = requestId;
    if (editCompleter != null) await editCompleter!.future;
  }

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
    AppointmentModel appointment, {
    String? requestId,
  }) async {
    createCalls += 1;
    lastRequestId = requestId;
    if (shouldFail) throw StateError('save failed');
    if (saveCompleter != null) return saveCompleter!.future;
    return appointment.copyWith(id: 'created_1');
  }
}

class _AvailabilityRepository extends _FakeAppointmentRepository {
  _AvailabilityRepository() : super([]);
  bool fail = true;
  bool internal = false;
  @override
  Future<List<AppointmentSlot>> getAvailableSlots(DateTime date) async {
    if (internal) throw FirebaseFunctionsException(code: 'internal', message: 'INTERNAL');
    if (fail) throw FirebaseFunctionsException(code: 'failed-precondition', message: 'PACC availability has not been published.');
    return [AppointmentSlot(start: DateTime(2026, 11, 16, 9), label: '9:00 AM')];
  }
}
