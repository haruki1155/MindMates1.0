import 'package:flutter/material.dart';

import '../../../models/appointment_model.dart';
import 'appointment_presentation.dart';

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
      'Awaiting confirmation',
      'PACC Counseling is reviewing your appointment request.',
      Icons.hourglass_top_rounded,
      Color(0xFF91600B),
    ),
    AppointmentStatus.confirmed => const AppointmentUiState(
      'Confirmed',
      'Your appointment is confirmed.',
      Icons.check_circle_outline,
      Color(0xFF287953),
    ),
    AppointmentStatus.rescheduleProposed => const AppointmentUiState(
      'Schedule Update Pending',
      'PACC is finalizing your appointment schedule.',
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
    AppointmentStatus.expired => const AppointmentUiState(
      'Request Expired',
      'This request was not reviewed in time. Please book a new appointment.',
      Icons.timer_off_outlined,
      Color(0xFF6C6C6C),
    ),
    AppointmentStatus.noShow => const AppointmentUiState(
      'Did Not Attend',
      '',
      Icons.event_busy_outlined,
      Color(0xFF6C6C6C),
    ),
    AppointmentStatus.unknown => const AppointmentUiState(
      'Status unavailable',
      '',
      Icons.hourglass_top_rounded,
      Color(0xFF91600B),
    ),
  };

  static AppointmentSection sectionFor(AppointmentStatus status) =>
      switch (status) {
        AppointmentStatus.completed ||
        AppointmentStatus.noShow => AppointmentSection.past,
        AppointmentStatus.cancelled ||
        AppointmentStatus.declined ||
        AppointmentStatus.expired => AppointmentSection.cancelled,
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
    this.isSaving = false,
  });
  final List<AppointmentModel> appointments;
  final ValueChanged<AppointmentModel?> onBook;
  final ValueChanged<AppointmentModel> onView;
  final ValueChanged<AppointmentModel> onCalendar;
  final bool isSaving;
  @override
  State<AppointmentListView> createState() => _AppointmentListViewState();
}

class _AppointmentListViewState extends State<AppointmentListView> {
  AppointmentSection _section = AppointmentSection.upcoming;
  @override
  Widget build(BuildContext context) {
    final bookingBlocked = widget.appointments.any((appointment) => appointment.isActive);
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppointmentVisuals.teal, borderRadius: BorderRadius.circular(20)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YOUR WELL-BEING MATTERS', style: TextStyle(color: Color(0xFFCEE2DA), fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
            SizedBox(height: 12),
            Text('Support begins with one conversation.', style: TextStyle(color: Colors.white, fontSize: 21, height: 1.35, fontWeight: FontWeight.w800)),
            SizedBox(height: 12),
            Text('Arrange a session with PACC at a time that works for you.', style: TextStyle(color: Color(0xFFD3E4DE), fontSize: 14, height: 1.5)),
            SizedBox(height: 16),
            Icon(Icons.favorite_border, color: Color(0xFFD3E4DE)),
          ]),
        ),
        const SizedBox(height: 16),
        Semantics(
          label: 'Appointment categories',
          child: Container(
            key: const ValueKey('appointment-category-container'),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: const Color(0xFFE9EFEB), borderRadius: BorderRadius.circular(16)),
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
          )),
        ),
        const SizedBox(height: 20),
        Text(
          '${switch (_section) {
            AppointmentSection.upcoming => 'Upcoming',
            AppointmentSection.past => 'Past',
            AppointmentSection.cancelled => 'Cancelled',
          }} Appointments (${items.length})',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _EmptyState(section: _section, onBook: () => widget.onBook(null))
        else
          ...items.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppointmentCard(
                appointment: a,
                compact: _section != AppointmentSection.upcoming,
                isSaving: widget.isSaving,
                onView: () => widget.onView(a),
                onBook: () => widget.onBook(a),
                bookingBlocked: bookingBlocked,
                onCalendar: () => widget.onCalendar(a),
              ),
            ),
          ),
        if (_section == AppointmentSection.upcoming && bookingBlocked) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFFFF9EA), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF3DEAA))),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 20, color: Color(0xFF91600B)),
              SizedBox(width: 10),
              Expanded(child: Text('You already have an active appointment. Please complete it before booking another one.', style: AppointmentVisuals.body)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        _SectionMessagePanel(section: _section),
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
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(13),

        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
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
    required this.bookingBlocked,
  });
  final AppointmentModel appointment;
  final bool compact;
  final bool isSaving;
  final bool bookingBlocked;
  final VoidCallback onView, onBook, onCalendar;
  @override
  Widget build(BuildContext context) {
    final ui = AppointmentUiState.from(appointment.lifecycleStatus);
    return Semantics(
      container: true,
      label:
          '${ui.label}: ${formatAppointmentWeekdayDate(appointment.scheduledAt)} at ${appointment.scheduledTime}',
      child: Card(
        elevation: 0,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AppointmentDateBlock(date: appointment.scheduledAt),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppointmentStatusBadge(status: appointment.lifecycleStatus),
                        const SizedBox(height: 8),
                        const Text('PACC Counseling', style: AppointmentVisuals.section),
                        const SizedBox(height: 4),
                        Text(
                          '${appointment.scheduledTime} \u00b7 Philippine Time',
                          style: const TextStyle(
                            color: AppointmentVisuals.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Info(icon: Icons.place_outlined, text: appointment.location),
              if (compact) _Info(
                icon: Icons.badge_outlined,
                text: (appointment.counselorName ?? '').trim().isEmpty
                    ? 'Counselor: Not yet assigned'
                    : 'Counselor: ${appointment.counselorName}',
              ),
              if (ui.description.isNotEmpty && appointment.lifecycleStatus != AppointmentStatus.requested && appointment.lifecycleStatus != AppointmentStatus.confirmed) ...[
                const SizedBox(height: 8),
                Text(
                  ui.description,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
              const Divider(height: 28, color: AppointmentVisuals.line),
              _actions(context, ui),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, AppointmentUiState ui) {
    final status = appointment.lifecycleStatus;
    final view = _OutlineAction(label: 'View appointment', onPressed: onView);
    Widget? secondary;
    if ({AppointmentStatus.requested, AppointmentStatus.confirmed}.contains(status)) {
      secondary = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: AppointmentVisuals.teal),
        onPressed: isSaving ? null : onCalendar,
        icon: const Icon(Icons.calendar_month_outlined, size: 18),
        label: const Text('Add to Calendar', textAlign: TextAlign.center),
      );
    } else if ({AppointmentStatus.completed, AppointmentStatus.cancelled, AppointmentStatus.declined, AppointmentStatus.expired, AppointmentStatus.noShow}.contains(status)) {
      final book = appointment.hasAvailableFollowUpOffer ? 'Book Follow-up' : status == AppointmentStatus.noShow ? 'Book Another Appointment' : status == AppointmentStatus.declined ? 'Book Appointment' : 'Book Again';
      secondary = FilledButton(onPressed: bookingBlocked || isSaving ? null : onBook, style: AppointmentVisuals.primary, child: Text(book, textAlign: TextAlign.center));
    }
    if (secondary == null) return SizedBox(width: double.infinity, child: view);
    final action = secondary;
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 300 || MediaQuery.textScalerOf(context).scale(14) > 19) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [view, const SizedBox(height: 8), action]);
      return Row(children: [Expanded(child: view), const SizedBox(width: 8), Expanded(child: action)]);
    });
  }

  // Legacy records are view-only while PACC finalizes their schedule.
  // ignore: unused_element
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
              'Schedule Update',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'Current appointment\n${formatAppointmentWeekdayDate(appointment.scheduledAt)} · ${appointment.scheduledTime}',
            ),
            const SizedBox(height: 12),
            Text(
              'PACC is finalizing the updated appointment schedule.',
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isSaving
                    ? null
                    : () {
                        Navigator.pop(context);
                        // Legacy records are read-only for students.
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: const Color(0xFFFFB800),
                  foregroundColor: Colors.black,
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppointmentDateBlock extends StatelessWidget {
  const _AppointmentDateBlock({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            months[date.month - 1],
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          Text(
            '${date.day}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
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
          child: Text(text, style: AppointmentVisuals.body.copyWith(fontSize: 12)),
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
    child: Text(label, textAlign: TextAlign.center),
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
    final category = switch (section) {
      AppointmentSection.upcoming => 'Upcoming',
      AppointmentSection.past => 'Past',
      AppointmentSection.cancelled => 'Cancelled',
    };
    return SizedBox(
      width: double.infinity,
      child: Card(
      key: ValueKey('appointment-empty-$category'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppointmentVisuals.line)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
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
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            if (upcoming) ...[
              const SizedBox(height: 6),
              const Text(textAlign: TextAlign.center, 'Book a session when you’re ready.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onBook,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB800),
                  foregroundColor: Colors.black,
                ),
                child: const Text('Book Appointment', textAlign: TextAlign.center),
              ),
            ],
          ],
        ),
      ),
    ));
  }
}

class _SectionMessagePanel extends StatelessWidget {
  const _SectionMessagePanel({required this.section});

  final AppointmentSection section;

  @override
  Widget build(BuildContext context) {
    final cancelled = section == AppointmentSection.cancelled;
    final past = section == AppointmentSection.past;
    final color = cancelled ? const Color(0xFFFFEEEB) : const Color(0xFFEAF7F1);
    final iconColor = cancelled
        ? const Color(0xFFEF5B4D)
        : const Color(0xFF22A06B);
    final message = cancelled
        ? 'This appointment was cancelled. You can book a new schedule anytime.'
        : past
        ? 'Thank you for showing up. Taking care of your mental health matters.'
        : 'You\'re all set. Taking care of your well-being is a positive step.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            cancelled ? Icons.info_outline : Icons.check_circle_outline,
            color: iconColor,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(height: 1.35))),
        ],
      ),
    );
  }
}

// Retained as an internal support surface for future non-appointment entry points.
// ignore: unused_element
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
