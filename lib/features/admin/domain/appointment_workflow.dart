import '../../../models/appointment_model.dart';

enum AppointmentQueue { needsAction, today, upcoming, completed, closed }

AppointmentQueue classifyAppointment(AppointmentModel appointment, DateTime now) {
  switch (appointment.lifecycleStatus) {
    case AppointmentStatus.requested:
    case AppointmentStatus.legacyRequested:
    case AppointmentStatus.rescheduleProposed:
      return AppointmentQueue.needsAction;
    case AppointmentStatus.confirmed:
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(appointment.scheduledAt.year,
          appointment.scheduledAt.month, appointment.scheduledAt.day);
      if (day.isAfter(today)) return AppointmentQueue.upcoming;
      if (day.isBefore(today)) return AppointmentQueue.needsAction;
      return AppointmentQueue.today;
    case AppointmentStatus.completed:
    case AppointmentStatus.notAttended:
    case AppointmentStatus.noShow:
      return AppointmentQueue.completed;
    case AppointmentStatus.cancelled:
    case AppointmentStatus.declined:
    case AppointmentStatus.unknown:
      return AppointmentQueue.closed;
  }
}

bool canTakeOutcomeAction(AppointmentModel appointment, DateTime now) =>
    appointment.lifecycleStatus == AppointmentStatus.confirmed &&
    !DateTime(appointment.scheduledAt.year, appointment.scheduledAt.month,
            appointment.scheduledAt.day)
        .isAfter(DateTime(now.year, now.month, now.day)) &&
    !appointment.isArchived;

Map<AppointmentQueue, int> appointmentQueueCounts(
    Iterable<AppointmentModel> appointments, DateTime now) {
  final counts = {for (final queue in AppointmentQueue.values) queue: 0};
  for (final appointment in appointments) {
    counts.update(classifyAppointment(appointment, now), (value) => value + 1);
  }
  return counts;
}
