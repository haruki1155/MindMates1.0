import '../../../models/appointment_model.dart';

enum AppointmentQueue { needsAction, today, upcoming, completed, closed }

AppointmentQueue classifyAppointment(
  AppointmentModel appointment,
  DateTime now,
) {
  switch (appointment.lifecycleStatus) {
    case AppointmentStatus.requested:
    case AppointmentStatus.legacyRequested:
    case AppointmentStatus.rescheduleProposed:
      return AppointmentQueue.needsAction;
    case AppointmentStatus.confirmed:
      final day = DateTime(
        appointment.scheduledAt.year,
        appointment.scheduledAt.month,
        appointment.scheduledAt.day,
      );
      final today = DateTime(now.year, now.month, now.day);
      if (day.isAfter(today)) return AppointmentQueue.upcoming;
      if (day.isBefore(today)) return AppointmentQueue.needsAction;
      return AppointmentQueue.today;
    case AppointmentStatus.completed:
      return AppointmentQueue.completed;
    case AppointmentStatus.cancelled:
    case AppointmentStatus.noShow:
    case AppointmentStatus.declined:
    case AppointmentStatus.expired:
    case AppointmentStatus.unknown:
      return AppointmentQueue.closed;
  }
}

bool canReviewAppointment(AppointmentModel appointment, DateTime now) =>
    !appointment.isArchived &&
    switch (appointment.lifecycleStatus) {
      AppointmentStatus.requested ||
      AppointmentStatus.legacyRequested ||
      AppointmentStatus.rescheduleProposed => true,
      AppointmentStatus.confirmed =>
        classifyAppointment(appointment, now) != AppointmentQueue.upcoming,
      _ => false,
    };

Map<AppointmentQueue, int> appointmentQueueCounts(
  Iterable<AppointmentModel> appointments,
  DateTime now,
) {
  final counts = {for (final queue in AppointmentQueue.values) queue: 0};
  for (final appointment in appointments) {
    counts.update(classifyAppointment(appointment, now), (value) => value + 1);
  }
  return counts;
}
