import 'package:flutter/material.dart';

import '../../../models/appointment_model.dart';

enum AppointmentSection { upcoming, past, cancelled }

class AppointmentUiState {
  const AppointmentUiState(this.label, this.description, this.icon, this.color);
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  static AppointmentUiState from(AppointmentStatus status) => switch (status) {
    AppointmentStatus.requested ||
    AppointmentStatus.legacyRequested => const AppointmentUiState(
      'Awaiting Confirmation',
      'PACC Counseling is reviewing your appointment request.',
      Icons.hourglass_top_rounded,
      Color(0xFF55718C),
    ),
    AppointmentStatus.confirmed => const AppointmentUiState(
      'Confirmed',
      'Your appointment is confirmed.',
      Icons.check_circle_outline,
      Color(0xFF287953),
    ),
    AppointmentStatus.rescheduleProposed => const AppointmentUiState(
      'Action Required',
      'A new schedule has been proposed.',
      Icons.event_repeat_outlined,
      Color(0xFFAD6700),
    ),
    AppointmentStatus.completed => const AppointmentUiState(
      'Completed',
      '',
      Icons.task_alt_outlined,
      Color(0xFF527565),
    ),
    AppointmentStatus.cancelled => const AppointmentUiState(
      'Cancelled',
      'This appointment has been cancelled.',
      Icons.cancel_outlined,
      Color(0xFFAA4B4B),
    ),
    AppointmentStatus.declined => const AppointmentUiState(
      'Request Declined',
      'Your requested schedule could not be confirmed.',
      Icons.info_outline,
      Color(0xFFAA5842),
    ),
    AppointmentStatus.noShow || AppointmentStatus.notAttended => const AppointmentUiState(
      'Missed Appointment',
      '',
      Icons.event_busy_outlined,
      Color(0xFF6C6C6C),
    ),
    AppointmentStatus.unknown => const AppointmentUiState(
      'Awaiting Confirmation',
      '',
      Icons.hourglass_top_rounded,
      Color(0xFF55718C),
    ),
  };

  static AppointmentSection sectionFor(AppointmentStatus status) =>
      switch (status) {
        AppointmentStatus.completed ||
        AppointmentStatus.noShow || AppointmentStatus.notAttended => AppointmentSection.past,
        AppointmentStatus.cancelled ||
        AppointmentStatus.declined => AppointmentSection.cancelled,
        _ => AppointmentSection.upcoming,
      };
}

class AppointmentListView extends StatefulWidget {
  const AppointmentListView({
    super.key,
    required this.appointments,
    required this.onBook,
    required this.onView,
    required this.onCalendar,
    required this.onCancel,
    required this.onAccept,
    required this.onReschedule,
    this.isSaving = false,
  });
  final List<AppointmentModel> appointments;
  final VoidCallback onBook;
  final ValueChanged<AppointmentModel> onView;
  final ValueChanged<AppointmentModel> onCalendar;
  final ValueChanged<AppointmentModel> onCancel;
  final ValueChanged<AppointmentModel> onAccept;
  final ValueChanged<AppointmentModel> onReschedule;
  final bool isSaving;
  @override
  State<AppointmentListView> createState() => _AppointmentListViewState();
}

class _AppointmentListViewState extends State<AppointmentListView> {
  AppointmentSection _section = AppointmentSection.upcoming;
  @override
  Widget build(BuildContext context) {
    final items =
        widget.appointments
            .where(
              (a) =>
                  AppointmentUiState.sectionFor(a.lifecycleStatus) == _section,
            )
            .toList()
          ..sort(
            (a, b) => _section == AppointmentSection.upcoming
                ? a.scheduledAt.compareTo(b.scheduledAt)
                : b.scheduledAt.compareTo(a.scheduledAt),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'My Appointments',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: widget.onBook,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Book Appointment'),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                foregroundColor: const Color(0xFF6A4C00),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'Appointment categories',
          child: Row(
            children: AppointmentSection.values
                .map(
                  (section) => Expanded(
                    child: _SectionTab(
                      label: switch (section) {
                        AppointmentSection.upcoming => 'Upcoming',
                        AppointmentSection.past => 'Past',
                        AppointmentSection.cancelled => 'Cancelled',
                      },
                      selected: _section == section,
                      onTap: () => setState(() => _section = section),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 20),
        if (items.isEmpty)
          _EmptyState(section: _section, onBook: widget.onBook)
        else
          ...items.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppointmentCard(
                appointment: a,
                compact: _section != AppointmentSection.upcoming,
                isSaving: widget.isSaving,
                onView: () => widget.onView(a),
                onBook: widget.onBook,
                onCalendar: () => widget.onCalendar(a),
                onCancel: () => widget.onCancel(a),
                onAccept: () => widget.onAccept(a),
                onReschedule: () => widget.onReschedule(a),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _CrisisCard(),
      ],
    );
  }
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label appointments',
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected
                  ? const Color(0xFFFFB800)
                  : const Color(0xFFE4DED3),
              width: selected ? 3 : 1,
            ),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFF3D2C00) : const Color(0xFF6D675F),
          ),
        ),
      ),
    ),
  );
}

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.compact,
    required this.isSaving,
    required this.onView,
    required this.onBook,
    required this.onCalendar,
    required this.onCancel,
    required this.onAccept,
    required this.onReschedule,
  });
  final AppointmentModel appointment;
  final bool compact;
  final bool isSaving;
  final VoidCallback onView,
      onBook,
      onCalendar,
      onCancel,
      onAccept,
      onReschedule;
  @override
  Widget build(BuildContext context) {
    final ui = AppointmentUiState.from(appointment.lifecycleStatus);
    final proposed = appointment.proposedScheduledAt;
    return Semantics(
      container: true,
      label:
          '${ui.label}: ${formatAppointmentWeekdayDate(appointment.scheduledAt)} at ${appointment.scheduledTime}',
      child: Card(
        elevation: 1,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE9E2D6)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusBadge(ui: ui),
              const SizedBox(height: 12),
              Text(
                formatAppointmentWeekdayDate(appointment.scheduledAt),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              Text(
                appointment.scheduledTime,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: ui.color,
                ),
              ),
              const SizedBox(height: 10),
              _Info(icon: Icons.place_outlined, text: appointment.location),
              _Info(
                icon: Icons.badge_outlined,
                text: (appointment.counselorName ?? '').trim().isEmpty
                    ? 'Counselor: Not yet assigned'
                    : 'Counselor: ${appointment.counselorName}',
              ),
              if (!compact && appointment.concern.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Concern',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  appointment.concern,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (appointment.lifecycleStatus ==
                      AppointmentStatus.rescheduleProposed &&
                  proposed != null) ...[
                const Divider(height: 24),
                const Text(
                  'Schedule change proposed',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Current: ${formatAppointmentShortDate(appointment.scheduledAt)} · ${appointment.scheduledTime}',
                ),
                Text(
                  'Proposed: ${formatAppointmentShortDate(proposed)} · ${appointment.proposedScheduledTime ?? ''}',
                ),
              ] else if (ui.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  ui.description,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 14),
              _actions(context, ui),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, AppointmentUiState ui) {
    final status = appointment.lifecycleStatus;
    if ({
      AppointmentStatus.requested,
      AppointmentStatus.confirmed,
    }.contains(status)) {
      return Row(
        children: [
          _OutlineAction(label: 'View Details', onPressed: onView),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: isSaving ? null : () => _showManage(context),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFFFFB800),
                foregroundColor: Colors.black,
              ),
              child: const Text('Manage'),
            ),
          ),
        ],
      );
    }
    if (status == AppointmentStatus.rescheduleProposed) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: isSaving ? null : () => _showProposal(context),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: const Color(0xFFFFB800),
            foregroundColor: Colors.black,
          ),
          child: Text(isSaving ? 'Updating...' : 'Review New Schedule'),
        ),
      );
    }
    final book = status == AppointmentStatus.completed
        ? 'Book Follow-up'
        : status == AppointmentStatus.noShow || status == AppointmentStatus.notAttended
        ? 'Book Another Appointment'
        : status == AppointmentStatus.declined
        ? 'Book Appointment'
        : 'Book Again';
    if ({
      AppointmentStatus.completed,
      AppointmentStatus.cancelled,
      AppointmentStatus.declined,
      AppointmentStatus.noShow,
      AppointmentStatus.notAttended,
    }.contains(status)) {
      return Row(
        children: [
          _OutlineAction(label: 'View Details', onPressed: onView),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: onBook,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFFFFB800),
                foregroundColor: Colors.black,
              ),
              child: Text(book),
            ),
          ),
        ],
      );
    }
    return _OutlineAction(label: 'View Details', onPressed: onView);
  }

  void _showManage(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Add to Calendar'),
            onTap: () {
              Navigator.pop(context);
              onCalendar();
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('Request Reschedule'),
            onTap: () {
              Navigator.pop(context);
              onReschedule();
            },
          ),
        ],
      ),
    ),
  );
  void _showProposal(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Schedule Change',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'Current appointment\n${formatAppointmentWeekdayDate(appointment.scheduledAt)} · ${appointment.scheduledTime}',
            ),
            const SizedBox(height: 12),
            Text(
              'Proposed appointment\n${appointment.proposedScheduledAt == null ? '' : formatAppointmentWeekdayDate(appointment.proposedScheduledAt!)} · ${appointment.proposedScheduledTime ?? ''}',
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isSaving
                    ? null
                    : () {
                        Navigator.pop(context);
                        onAccept();
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: const Color(0xFFFFB800),
                  foregroundColor: Colors.black,
                ),
                child: const Text('Accept New Schedule'),
              ),
            ),
            TextButton(
              onPressed: isSaving
                  ? null
                  : () {
                      Navigator.pop(context);
                      onReschedule();
                    },
              child: const Text('Request Another Time'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.ui});
  final AppointmentUiState ui;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: ui.color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ui.icon, size: 16, color: ui.color),
        const SizedBox(width: 4),
        Text(
          ui.label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: ui.color,
          ),
        ),
      ],
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(minimumSize: const Size(110, 48)),
    child: Text(label),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.section, required this.onBook});
  final AppointmentSection section;
  final VoidCallback onBook;
  @override
  Widget build(BuildContext context) {
    final upcoming = section == AppointmentSection.upcoming;
    final text = upcoming
        ? 'No upcoming appointments'
        : section == AppointmentSection.past
        ? 'No past appointments yet.'
        : 'No cancelled appointments.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            Icon(
              upcoming
                  ? Icons.calendar_month_outlined
                  : Icons.event_note_outlined,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              text,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            if (upcoming) ...[
              const SizedBox(height: 6),
              const Text('Book a session when you’re ready.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onBook,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB800),
                  foregroundColor: Colors.black,
                ),
                child: const Text('Book Appointment'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CrisisCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF4CD),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.phone_in_talk_outlined),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need immediate help?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text('PACC Crisis Hotline · Available 24/7'),
              ],
            ),
          ),
          TextButton(onPressed: () {}, child: const Text('Call')),
          TextButton(onPressed: () {}, child: const Text('Email')),
        ],
      ),
    ),
  );
}

String formatAppointmentWeekdayDate(DateTime date) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
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
  return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
}

String formatAppointmentShortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}
