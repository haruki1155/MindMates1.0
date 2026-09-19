import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/appointment_workflow.dart';
import 'package:mind_mates/models/appointment_model.dart';

void main() {
  final now = DateTime(2026, 9, 19, 9);

  test('a confirmed future booking is upcoming and has no outcome action', () {
    final appointment = fixture('confirmed', DateTime(2026, 9, 22, 14));
    expect(classifyAppointment(appointment, now), AppointmentQueue.upcoming);
    expect(canTakeOutcomeAction(appointment, now), isFalse);
  });

  test('confirmed bookings scheduled today enter Today', () {
    final appointment = fixture('confirmed', DateTime(2026, 9, 19, 14));
    expect(classifyAppointment(appointment, now), AppointmentQueue.today);
    expect(canTakeOutcomeAction(appointment, now), isTrue);
  });

  test(
    'overdue confirmed bookings remain actionable without appearing as Today',
    () {
      final appointment = fixture('confirmed', DateTime(2026, 9, 18, 14));
      expect(
        classifyAppointment(appointment, now),
        AppointmentQueue.needsAction,
      );
      expect(canTakeOutcomeAction(appointment, now), isTrue);
    },
  );

  test('requests and schedule proposals need action', () {
    for (final status in [
      'requested',
      'pending',
      'upcoming',
      'reschedule_proposed',
    ]) {
      expect(
        classifyAppointment(fixture(status, now), now),
        AppointmentQueue.needsAction,
      );
    }
  });

  test('completed count includes archived appointments', () {
    final records = [
      fixture('completed', now, archivedAt: now),
      fixture('not_attended', now),
      fixture('confirmed', DateTime(2026, 9, 22)),
    ];
    expect(appointmentQueueCounts(records, now)[AppointmentQueue.completed], 2);
  });

  test(
    'finished requests share Completed without changing stored statuses',
    () {
      for (final status in [
        'completed',
        'not_attended',
        'no_show',
        'cancelled',
        'declined',
      ]) {
        final appointment = fixture(status, now);
        expect(
          classifyAppointment(appointment, now),
          AppointmentQueue.completed,
        );
        expect(appointment.status, status);
      }
      expect(
        classifyAppointment(fixture('unrecognized', now), now),
        AppointmentQueue.needsAction,
      );
    },
  );

  test(
    'Completed shows archived and active records while other queues do not',
    () {
      final records = [
        fixture('completed', now, archivedAt: now),
        fixture('declined', now),
        fixture('confirmed', DateTime(2026, 9, 22)),
      ];
      expect(
        appointmentRecordsForView(
          records,
          now,
          showHistory: false,
          queue: AppointmentQueue.completed,
        ),
        [records[0], records[1]],
      );
      expect(
        appointmentRecordsForView(
          records,
          now,
          showHistory: false,
          queue: AppointmentQueue.upcoming,
        ),
        [records[2]],
      );
      expect(appointmentRecordsForView(records, now, showHistory: true), [
        records[0],
      ]);
    },
  );
}

AppointmentModel fixture(
  String status,
  DateTime scheduledAt, {
  DateTime? archivedAt,
}) => AppointmentModel(
  id: 'a',
  userId: 'u',
  fullName: 'Student',
  scheduledAt: scheduledAt,
  scheduledTime: '2:00 PM',
  location: 'PACC',
  status: status,
  concern: 'Help',
  contactNumber: '',
  email: '',
  preferredContactMethod: '',
  createdAt: DateTime(2026, 9, 18),
  archivedAt: archivedAt,
);
