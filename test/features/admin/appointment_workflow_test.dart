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

  test('classifies the hardened lifecycle without losing terminal states', () {
    final cases = <String, AppointmentQueue>{
      'requested': AppointmentQueue.needsAction,
      'pending': AppointmentQueue.needsAction,
      'reschedule_proposed': AppointmentQueue.needsAction,
      'completed': AppointmentQueue.completed,
      'no_show': AppointmentQueue.closed,
      'cancelled': AppointmentQueue.closed,
      'declined': AppointmentQueue.closed,
      'expired': AppointmentQueue.closed,
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

  test('queue counts are a complete partition', () {
    final records = [
      appointment('requested', now),
      appointment('confirmed', now),
      appointment('confirmed', now.add(const Duration(days: 8))),
      appointment('completed', now),
      appointment('expired', now),
    ];
    final counts = appointmentQueueCounts(records, now);
    expect(counts.values.reduce((a, b) => a + b), records.length);
    expect(counts[AppointmentQueue.upcoming], 1);
    expect(counts[AppointmentQueue.closed], 1);
  });
}
