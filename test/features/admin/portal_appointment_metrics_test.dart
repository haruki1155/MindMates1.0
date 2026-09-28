import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/portal_appointment_metrics.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/appointment_queue_item.dart';

void main() {
  final now = DateTime(2026, 9, 28, 12);
  final records = [
    _appointment('requested', now),
    _appointment('confirmed', now),
    _appointment('confirmed', now.add(const Duration(days: 2))),
    _appointment('completed', now),
    _appointment('completed', now, archived: true),
    _appointment('cancelled', now),
  ];

  test('canonical and staff projection use identical portal counts', () {
    final canonical = PortalAppointmentMetrics.fromAppointments(records, now);
    final projection = PortalAppointmentMetrics.fromQueue(
      records
          .map(
            (item) => AppointmentQueueItem(
              id: item.id,
              studentDisplayName: item.fullName,
              scheduledAt: item.scheduledAt,
              scheduledTime: item.scheduledTime,
              status: item.status,
              isArchived: item.isArchived,
            ),
          )
          .toList(),
      now,
    );

    expect(canonical.needsAction, 2);
    expect(canonical.today, 1);
    expect(canonical.upcoming, 1);
    expect(canonical.completed, 2);
    expect(projection.needsAction, canonical.needsAction);
    expect(projection.today, canonical.today);
    expect(projection.upcoming, canonical.upcoming);
    expect(projection.completed, canonical.completed);
  });
}

AppointmentModel _appointment(
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
  createdAt: scheduledAt,
  archivedAt: archived ? scheduledAt : null,
);
