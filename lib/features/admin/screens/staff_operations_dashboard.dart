import 'package:flutter/material.dart';

import '../../../models/appointment_queue_item.dart';
import '../../../models/pacc_availability_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../theme/admin_theme.dart';
import 'admin_portal.dart';

/// Operational dashboard for PAACC Staff. It deliberately does not query
/// users, assessments, reports, or counseling notes.
class StaffOperationsDashboardPage extends StatelessWidget {
  const StaffOperationsDashboardPage({
    super.key,
    required this.repository,
    required this.onNavigate,
  });

  final AdminPortalRepository repository;
  final ValueChanged<AdminPortalPage> onNavigate;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: StreamBuilder<List<AppointmentQueueItem>>(
          stream: repository.watchPortalAppointmentQueue(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _StateCard(
                title: "Unable to load today's appointments",
                message: 'Please try again.',
                action: 'Retry',
                onPressed: () {},
              );
            }
            if (!snapshot.hasData) return const _StaffDashboardSkeleton();
            return _DashboardContent(
              appointments: snapshot.data!,
              availability: repository.watchPaccAvailability(),
              onNavigate: onNavigate,
            );
          },
        ),
      ),
    ),
  );
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.appointments,
    required this.availability,
    required this.onNavigate,
  });
  final List<AppointmentQueueItem> appointments;
  final Stream<PaccAvailabilityModel?> availability;
  final ValueChanged<AdminPortalPage> onNavigate;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today =
        appointments.where((a) => _sameDay(a.scheduledAt, now)).toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final upcoming = appointments.where((a) {
      final day = a.scheduledAt;
      return day.isAfter(now) && day.isBefore(now.add(const Duration(days: 8)));
    }).length;
    final needsAction = appointments.where((a) {
      final status = a.status.toLowerCase().trim();
      return status == 'pending' || status == 'reschedule_required';
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dashboard',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        const Text(
          "Overview of today's PAACC operations.",
          style: TextStyle(color: AdminColors.muted),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 900
                ? 4
                : box.maxWidth >= 560
                ? 2
                : 1;
            final width = (box.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Metric(
                  width: width,
                  label: "Today's appointments",
                  value: '${today.length}',
                  note:
                      '${today.where((a) => !_closed(a.status)).length} remaining',
                  icon: Icons.calendar_today_outlined,
                ),
                _Metric(
                  width: width,
                  label: 'Upcoming',
                  value: '$upcoming',
                  note: 'Next 7 days',
                  icon: Icons.event_available_outlined,
                ),
                _Metric(
                  width: width,
                  label: 'Needs attention',
                  value: '$needsAction',
                  note: 'Requires review',
                  icon: Icons.priority_high_rounded,
                ),
                SizedBox(
                  width: width,
                  child: StreamBuilder<PaccAvailabilityModel?>(
                    stream: availability,
                    builder: (context, state) {
                      final available = state.data?.isOpenAt(now) == true;
                      return _Metric(
                        width: width,
                        label: 'Schedule',
                        value: state.hasData
                            ? (available ? 'Available' : 'Closed')
                            : '—',
                        note: "Today's PAACC schedule",
                        icon: Icons.schedule_outlined,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        _Panel(
          title: "Today's appointments",
          action: TextButton(
            onPressed: () => onNavigate(AdminPortalPage.dashboard),
            child: const Text('View all →'),
          ),
          child: today.isEmpty
              ? _StateCard(
                  title: 'No appointments today',
                  message:
                      'There are currently no counseling appointments scheduled for today.',
                  action: 'Open schedule',
                  onPressed: () => onNavigate(AdminPortalPage.availability),
                )
              : Column(
                  children: today
                      .take(8)
                      .map((a) => _AppointmentRow(appointment: a))
                      .toList(),
                ),
        ),
        const SizedBox(height: 20),
        _Panel(
          title: 'Quick actions',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => onNavigate(AdminPortalPage.dashboard),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('View appointments'),
              ),
              OutlinedButton.icon(
                onPressed: () => onNavigate(AdminPortalPage.availability),
                icon: const Icon(Icons.schedule_outlined),
                label: const Text('Open schedule'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
  });
  final double width;
  final String label, value, note;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: 118),
    padding: const EdgeInsets.all(18),
    decoration: _box,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AdminColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                note,
                style: const TextStyle(fontSize: 12, color: AdminColors.muted),
              ),
            ],
          ),
        ),
        Icon(icon, color: AdminColors.accentStrong),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: _box,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({required this.appointment});
  final AppointmentQueueItem appointment;
  @override
  Widget build(BuildContext context) {
    final suffix = appointment.studentDisplayName.isEmpty
        ? ''
        : appointment.studentDisplayName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              appointment.scheduledTime.isEmpty
                  ? _time(appointment.scheduledAt)
                  : appointment.scheduledTime,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text('Student ••••$suffix')),
          _Status(text: _statusLabel(appointment.status)),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AdminColors.accentSoft,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
    ),
  );
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.title,
    required this.message,
    required this.action,
    required this.onPressed,
  });
  final String title, message, action;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(message, style: const TextStyle(color: AdminColors.muted)),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: onPressed, child: Text(action)),
    ],
  );
}

class _StaffDashboardSkeleton extends StatelessWidget {
  const _StaffDashboardSkeleton();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SkeletonLine(width: 230, height: 30),
      const SizedBox(height: 10),
      const _SkeletonLine(width: 300, height: 16),
      const SizedBox(height: 24),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: List.generate(
          4,
          (_) =>
              const SizedBox(width: 245, height: 118, child: _SkeletonBlock()),
        ),
      ),
      const SizedBox(height: 20),
      const SizedBox(height: 250, child: _SkeletonBlock()),
    ],
  );
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFE9E8E4),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminColors.border),
    ),
  );
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width, required this.height});
  final double width, height;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: width, height: height, child: const _SkeletonBlock());
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
bool _closed(String status) => const {
  'completed',
  'complete',
  'cancelled',
  'canceled',
}.contains(status.toLowerCase().trim());
String _time(DateTime date) {
  final hour = date.hour == 0
      ? 12
      : date.hour > 12
      ? date.hour - 12
      : date.hour;
  return '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
}

String _statusLabel(String status) => switch (status.toLowerCase().trim()) {
  'reschedule_required' => 'Schedule adjustment',
  'pending' => 'Pending review',
  'confirmed' => 'Confirmed',
  'completed' || 'complete' => 'Completed',
  _ => status.isEmpty ? 'Scheduled' : status,
};
const _box = BoxDecoration(
  color: AdminColors.surface,
  borderRadius: BorderRadius.all(Radius.circular(12)),
  border: Border.fromBorderSide(BorderSide(color: AdminColors.border)),
);
