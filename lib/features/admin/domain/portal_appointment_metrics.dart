import '../../../models/appointment_model.dart';
import '../../../models/appointment_queue_item.dart';
import 'appointment_workflow.dart';

/// Shared operational counts for the canonical appointment stream and the
/// privacy-safe staff projection. Completed intentionally means only the
/// exact `completed` lifecycle status, including archived completed records.
class PortalAppointmentMetrics {
  const PortalAppointmentMetrics({
    required this.total,
    required this.needsAction,
    required this.today,
    required this.upcoming,
    required this.completed,
  });

  final int total;
  final int needsAction;
  final int today;
  final int upcoming;
  final int completed;

  factory PortalAppointmentMetrics.fromAppointments(
    Iterable<AppointmentModel> appointments,
    DateTime now,
  ) {
    final counts = appointmentQueueCounts(appointments, now);
    return PortalAppointmentMetrics(
      total: appointments.length,
      needsAction: counts[AppointmentQueue.needsAction] ?? 0,
      today: counts[AppointmentQueue.today] ?? 0,
      upcoming: counts[AppointmentQueue.upcoming] ?? 0,
      completed: counts[AppointmentQueue.completed] ?? 0,
    );
  }

  factory PortalAppointmentMetrics.fromQueue(
    Iterable<AppointmentQueueItem> appointments,
    DateTime now,
  ) {
    var needsAction = 0;
    var today = 0;
    var upcoming = 0;
    var completed = 0;
    for (final appointment in appointments) {
      final status = appointment.status.trim().toLowerCase();
      if (status == 'completed') {
        completed++;
      } else if (!appointment.isArchived &&
          status == 'confirmed' &&
          _sameDay(appointment.scheduledAt, now)) {
        today++;
      } else if (!appointment.isArchived &&
          status == 'confirmed' &&
          _day(appointment.scheduledAt).isAfter(_day(now))) {
        upcoming++;
      } else if (!appointment.isArchived) {
        needsAction++;
      }
    }
    return PortalAppointmentMetrics(
      total: appointments.length,
      needsAction: needsAction,
      today: today,
      upcoming: upcoming,
      completed: completed,
    );
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static bool _sameDay(DateTime left, DateTime right) =>
      _day(left) == _day(right);
}
