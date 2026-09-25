import '../../../models/appointment_model.dart';

enum AppointmentQueue { needsAction, today, upcoming, completed }

AppointmentQueue classifyAppointment(
  AppointmentModel appointment,
  DateTime now,
) {
  // Historical records used this outcome before the hardened no_show status.
  if (appointment.status.trim().toLowerCase() == 'not_attended') {
    return AppointmentQueue.completed;
  }
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
    case AppointmentStatus.cancelled:
    case AppointmentStatus.noShow:
    case AppointmentStatus.declined:
    case AppointmentStatus.expired:
      return AppointmentQueue.completed;
    case AppointmentStatus.unknown:
      return AppointmentQueue.needsAction;
  }
}

/// Completed includes archived finished records; History remains archive-only.
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
