import 'package:flutter/material.dart';

import '../../../models/appointment_model.dart';

enum AppointmentDisplayStatus {
  requested,
  pending,
  upcoming,
  confirmed,
  rescheduleProposed,
  declined,
  completed,
  cancelled,
  other,
}

AppointmentDisplayStatus appointmentDisplayStatus(String value) {
  return switch (value.trim().toLowerCase()) {
    'requested' => AppointmentDisplayStatus.requested,
    'pending' => AppointmentDisplayStatus.requested,
    'upcoming' => AppointmentDisplayStatus.upcoming,
    'confirmed' => AppointmentDisplayStatus.confirmed,
    'reschedule_proposed' => AppointmentDisplayStatus.rescheduleProposed,
    'declined' => AppointmentDisplayStatus.declined,
    'completed' => AppointmentDisplayStatus.completed,
    'cancelled' || 'canceled' => AppointmentDisplayStatus.cancelled,
    _ => AppointmentDisplayStatus.other,
  };
}

bool isSameAppointmentDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String formatAppointmentDate(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

Color appointmentStatusColor(AppointmentDisplayStatus status) =>
    switch (status) {
      AppointmentDisplayStatus.requested => const Color(0xFFF0A400),
      AppointmentDisplayStatus.pending => const Color(0xFFF0A400),
      AppointmentDisplayStatus.upcoming => const Color(0xFFE5AC00),
      AppointmentDisplayStatus.confirmed => const Color(0xFF3D8B68),
      AppointmentDisplayStatus.rescheduleProposed => const Color(0xFF61738A),
      AppointmentDisplayStatus.declined => const Color(0xFFB54A4A),
      AppointmentDisplayStatus.completed => const Color(0xFF3D8B68),
      AppointmentDisplayStatus.cancelled => const Color(0xFF8A8173),
      AppointmentDisplayStatus.other => const Color(0xFF61738A),
    };

Future<void> showAppointmentDetailsSheet(
  BuildContext context,
  AppointmentModel appointment, {
  VoidCallback? onBookAppointment,
}) {
  final contactSummary = [
    appointment.preferredContactMethod.trim(),
    appointment.contactNumber.trim(),
  ].where((value) => value.isNotEmpty).join(' | ');
  final details = <({IconData icon, String text})>[
    (
      icon: Icons.calendar_today_outlined,
      text: formatAppointmentDate(appointment.scheduledAt),
    ),
    (icon: Icons.schedule, text: appointment.scheduledTime),
    (icon: Icons.place_outlined, text: appointment.location),
    if (appointment.status.trim().isNotEmpty)
      (
        icon: Icons.info_outline,
        text: _friendlyStatus(appointment.lifecycleStatus),
      ),
    (icon: Icons.badge_outlined, text: _counselorText(appointment)),
    if (appointment.proposedScheduledAt != null)
      (
        icon: Icons.event_repeat_outlined,
        text:
            'Proposed schedule: ${formatAppointmentDate(appointment.proposedScheduledAt!)} ${appointment.proposedScheduledTime ?? ''}${appointment.proposedBy == null ? '' : ' (${appointment.proposedBy})'}',
      ),
    if (contactSummary.isNotEmpty)
      (icon: Icons.contact_phone_outlined, text: contactSummary),
    if ((appointment.bestTime ?? '').trim().isNotEmpty)
      (
        icon: Icons.access_time,
        text: 'Best contact time: ${appointment.bestTime!.trim()}',
      ),
  ];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFFFFBF0),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Appointment Details',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              for (final detail in details)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        detail.icon,
                        size: 20,
                        color: const Color(0xFF8A6500),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          detail.text,
                          style: const TextStyle(height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              if (appointment.concern.trim().isNotEmpty) ...[
                const Divider(height: 26),
                const Text(
                  'Concern',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  appointment.concern.trim(),
                  style: const TextStyle(height: 1.45),
                ),
              ],
              if ((appointment.staffReply ?? '').trim().isNotEmpty) ...[
                const Divider(height: 26),
                const Text(
                  'Appointment Activity',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  appointment.staffReply!.trim(),
                  style: const TextStyle(height: 1.45),
                ),
              ],
              if (onBookAppointment != null &&
                  (appointment.lifecycleStatus == AppointmentStatus.cancelled ||
                      appointment.lifecycleStatus ==
                          AppointmentStatus.completed ||
                      appointment.lifecycleStatus == AppointmentStatus.noShow ||
                      appointment.lifecycleStatus == AppointmentStatus.notAttended ||
                      appointment.lifecycleStatus ==
                          AppointmentStatus.declined)) ...[
                const Divider(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onBookAppointment();
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(
                      appointment.lifecycleStatus == AppointmentStatus.completed
                          ? 'Book Follow-up'
                          : 'Book Appointment',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

String _friendlyStatus(AppointmentStatus status) => switch (status) {
  AppointmentStatus.requested ||
  AppointmentStatus.legacyRequested => 'Awaiting Confirmation',
  AppointmentStatus.confirmed => 'Confirmed',
  AppointmentStatus.rescheduleProposed => 'Action Required',
  AppointmentStatus.completed => 'Completed',
  AppointmentStatus.cancelled => 'Cancelled',
  AppointmentStatus.declined => 'Request Declined',
  AppointmentStatus.noShow || AppointmentStatus.notAttended => 'Missed Appointment',
  AppointmentStatus.unknown => 'Awaiting Confirmation',
};

String _counselorText(AppointmentModel appointment) {
  final name = appointment.counselorName?.trim() ?? '';
  if (name.isEmpty || name.toLowerCase() == 'admin') {
    return 'PACC Counseling Staff';
  }
  return name;
}
