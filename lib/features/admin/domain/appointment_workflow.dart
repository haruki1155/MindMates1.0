import '../../../models/appointment_model.dart';

enum AppointmentQueue { needsAction, today, upcoming, completed }

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
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(
        appointment.scheduledAt.year,
        appointment.scheduledAt.month,
        appointment.scheduledAt.day,
      );
      if (day.isAfter(today)) return AppointmentQueue.upcoming;
      if (day.isBefore(today)) return AppointmentQueue.needsAction;
      return AppointmentQueue.today;
    case AppointmentStatus.completed:
    case AppointmentStatus.notAttended:
    case AppointmentStatus.noShow:
    case AppointmentStatus.cancelled:
    case AppointmentStatus.declined:
      return AppointmentQueue.completed;
    case AppointmentStatus.unknown:
      return AppointmentQueue.needsAction;
  }
}

/// Archived records remain visible in Completed; History is the archive-only
/// view. Other active queues never include archived records.
List<AppointmentModel> appointmentRecordsForView(
  Iterable<AppointmentModel> appointments,
  DateTime now, {
  required bool showHistory,
  AppointmentQueue? queue,
}) => appointments.where((appointment) {
  if (showHistory) return appointment.isArchived;
  if (queue == AppointmentQueue.completed) {
    return classifyAppointment(appointment, now) == AppointmentQueue.completed;
  }
  return !appointment.isArchived &&
      (queue == null || classifyAppointment(appointment, now) == queue);
}).toList();

bool canTakeOutcomeAction(AppointmentModel appointment, DateTime now) =>
    appointment.lifecycleStatus == AppointmentStatus.confirmed &&
    !DateTime(
      appointment.scheduledAt.year,
      appointment.scheduledAt.month,
      appointment.scheduledAt.day,
    ).isAfter(DateTime(now.year, now.month, now.day)) &&
    !appointment.isArchived;

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
