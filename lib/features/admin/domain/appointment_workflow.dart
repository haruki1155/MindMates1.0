import '../../../models/appointment_model.dart';

enum AppointmentQueue { needsAction, today, upcoming, completed, cancelled }

AppointmentQueue classifyAppointment(
  AppointmentModel appointment,
  DateTime now,
) {
  if (appointment.status.trim().toLowerCase() == 'completed') {
    return AppointmentQueue.completed;
  }
  if (appointment.lifecycleStatus == AppointmentStatus.cancelled) {
    return AppointmentQueue.cancelled;
  }
  if (appointment.hasPendingScheduleChange && appointment.proposedBy == 'student') {
    return AppointmentQueue.needsAction;
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
    case AppointmentStatus.cancelled:
      return AppointmentQueue.cancelled;
    case AppointmentStatus.completed:
    case AppointmentStatus.noShow:
    case AppointmentStatus.declined:
    case AppointmentStatus.expired:
      // Retain legacy terminal values without presenting them as completed
      // counseling appointments.
      return AppointmentQueue.needsAction;
    case AppointmentStatus.unknown:
      return AppointmentQueue.needsAction;
  }
}

/// Completed and Cancelled include archived records matching their queue;
/// History remains archive-only.
List<AppointmentModel> appointmentRecordsForView(
  Iterable<AppointmentModel> appointments,
  DateTime now, {
  required bool showHistory,
  AppointmentQueue? queue,
}) => appointments.where((appointment) {
  if (showHistory) return appointment.isArchived;
  if (queue == AppointmentQueue.completed || queue == AppointmentQueue.cancelled) {
    return classifyAppointment(appointment, now) == queue;
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
      AppointmentStatus.confirmed => true,
      _ => false,
    };

Map<AppointmentQueue, int> appointmentQueueCounts(
  Iterable<AppointmentModel> appointments,
  DateTime now,
) {
  final counts = {for (final queue in AppointmentQueue.values) queue: 0};
  for (final appointment in appointments) {
    final queue = classifyAppointment(appointment, now);
    if (appointment.isArchived &&
        queue != AppointmentQueue.completed &&
        queue != AppointmentQueue.cancelled) {
      continue;
    }
    counts.update(queue, (value) => value + 1);
  }
  return counts;
}
