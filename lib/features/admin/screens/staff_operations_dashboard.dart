import 'package:flutter/material.dart';

import '../../../models/appointment_queue_item.dart';
import '../../../models/pacc_availability_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../theme/admin_theme.dart';
import '../widgets/staff_schedule_calendar.dart';
import 'admin_portal.dart';

/// Operational dashboard for PACC Staff. It deliberately does not query
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
                title: 'Unable to load staff appointments',
                message: 'The schedule could not be loaded. Open the appointment table to retry.',
                action: 'Open appointments',
                onPressed: () => onNavigate(AdminPortalPage.appointments),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Dashboard',
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 6),
      const Text(
        'Monthly counseling and testing schedule overview.',
        style: TextStyle(color: AdminColors.muted),
      ),
      const SizedBox(height: 24),
      _Panel(
        title: 'Appointment calendar',
        action: TextButton(
          onPressed: () => onNavigate(AdminPortalPage.appointments),
          child: const Text('View appointment table'),
        ),
        child: StaffScheduleCalendar(counselingAppointments: appointments),
      ),
      const SizedBox(height: 20),
      StreamBuilder<PaccAvailabilityModel?>(
        stream: availability,
        builder: (context, state) {
          if (state.data == null) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, constraints) => PaccStaffScheduleMetric(
              width: constraints.maxWidth < 340 ? constraints.maxWidth : 340,
              availability: state.data!,
              now: DateTime.now(),
            ),
          );
        },
      ),
    ],
  );
}

class PaccStaffScheduleMetric extends StatelessWidget {
  const PaccStaffScheduleMetric({
    super.key,
    required this.width,
    required this.availability,
    required this.now,
  });

  final double width;
  final PaccAvailabilityModel availability;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final resolved = availability.resolveScheduleAt(now);
    final unavailableCounselor =
        resolved.schedule.presence != CounselorPresence.inOffice;
    final value = !resolved.isOfficeOpen
        ? 'Closed'
        : unavailableCounselor
        ? 'Open — counselor unavailable'
        : resolved.canBookAppointments
        ? 'Open — appointments available'
        : 'Open — appointments unavailable';
    return _Metric(
      width: width,
      label: 'Schedule',
      value: value,
      note: resolved.source == PaccScheduleSource.override
          ? 'Schedule override for ${resolved.date}'
          : "Today's PACC schedule",
      icon: Icons.schedule_outlined,
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

const _box = BoxDecoration(
  color: AdminColors.surface,
  borderRadius: BorderRadius.all(Radius.circular(12)),
  border: Border.fromBorderSide(BorderSide(color: AdminColors.border)),
);
