import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/appointment_workflow.dart';
import 'package:mind_mates/models/appointment_model.dart';

void main() {
  final now = DateTime(2026, 9, 25, 12);

  AppointmentModel appointment(
    String status,
    DateTime scheduledAt, {
    bool archived = false,
  }) => AppointmentModel(
    id: status,
    userId: 'student',
    fullName: 'Student',
    scheduledAt: scheduledAt,
    scheduledTime: '10:00 AM',
    location: 'PACC',
    status: status,
    concern: '',
    contactNumber: '',
    email: '',
    preferredContactMethod: '',
    createdAt: now,
    archivedAt: archived ? now : null,
  );

  test('classifies only exact completed status as Completed', () {
    final cases = <String, AppointmentQueue>{
      'requested': AppointmentQueue.needsAction,
      'pending': AppointmentQueue.needsAction,
      'reschedule_proposed': AppointmentQueue.needsAction,
      'completed': AppointmentQueue.completed,
      'not_attended': AppointmentQueue.needsAction,
      'no_show': AppointmentQueue.needsAction,
      'cancelled': AppointmentQueue.needsAction,
      'declined': AppointmentQueue.needsAction,
      'expired': AppointmentQueue.needsAction,
      'unrecognized': AppointmentQueue.needsAction,
    };
    for (final entry in cases.entries) {
      expect(
        classifyAppointment(appointment(entry.key, now), now),
        entry.value,
        reason: entry.key,
      );
    }
    expect(
      classifyAppointment(
        appointment('confirmed', now.add(const Duration(days: 1))),
        now,
      ),
      AppointmentQueue.upcoming,
    );
    expect(
      classifyAppointment(appointment('confirmed', now), now),
      AppointmentQueue.today,
    );
    expect(
      classifyAppointment(
        appointment('confirmed', now.subtract(const Duration(days: 1))),
        now,
      ),
      AppointmentQueue.needsAction,
    );
  });

  test('review is restricted to active records requiring a decision', () {
    expect(canReviewAppointment(appointment('requested', now), now), isTrue);
    expect(
      canReviewAppointment(appointment('reschedule_proposed', now), now),
      isTrue,
    );
    expect(canReviewAppointment(appointment('confirmed', now), now), isTrue);
    expect(
      canReviewAppointment(
        appointment('confirmed', now.subtract(const Duration(days: 1))),
        now,
      ),
      isTrue,
    );
    expect(
      canReviewAppointment(
        appointment('confirmed', now.add(const Duration(days: 1))),
        now,
      ),
      isFalse,
    );
    expect(canReviewAppointment(appointment('completed', now), now), isFalse);
    expect(
      canReviewAppointment(appointment('requested', now, archived: true), now),
      isFalse,
    );
  });

  test('Completed counts archived finished records outside All active', () {
    final records = [
      appointment('requested', now),
      appointment('confirmed', now.add(const Duration(days: 8))),
      appointment('confirmed', now.add(const Duration(days: 9))),
      appointment('completed', now),
      appointment('no_show', now),
      for (var index = 0; index < 89; index++)
        appointment('completed', now, archived: true),
    ];
    final counts = appointmentQueueCounts(records, now);
    expect(counts.values.reduce((a, b) => a + b), records.length);
    expect(counts[AppointmentQueue.completed], 90);
    expect(
      appointmentRecordsForView(records, now, showHistory: false).length,
      5,
    );
    expect(
      appointmentRecordsForView(
        records,
        now,
        showHistory: false,
        queue: AppointmentQueue.completed,
      ).length,
      90,
    );
    expect(
      appointmentRecordsForView(records, now, showHistory: true).length,
      89,
    );
  });

  test(
    'legacy terminal statuses retain their stored values but are not completed',
    () {
      for (final status in [
        'completed',
        'not_attended',
        'no_show',
        'cancelled',
        'declined',
        'expired',
      ]) {
        final record = appointment(status, now);
        expect(
          classifyAppointment(record, now),
          status == 'completed'
              ? AppointmentQueue.completed
              : AppointmentQueue.needsAction,
        );
        expect(record.status, status);
      }
    },
  );

  test('History contains archived records only', () {
    final active = appointment('completed', now);
    final archived = appointment('declined', now, archived: true);
    expect(
      appointmentRecordsForView([active, archived], now, showHistory: true),
      [archived],
    );
  });
}
