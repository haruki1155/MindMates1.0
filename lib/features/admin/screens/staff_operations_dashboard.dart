import 'package:flutter/material.dart';

import '../../../models/appointment_queue_item.dart';
import '../../../models/pacc_availability_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../theme/admin_theme.dart';
import '../widgets/staff_schedule_calendar.dart';
import '../widgets/staff_queue_refresh_button.dart';
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
            // Always render the calendar shell. Connectivity or permission
            // errors must be visible, not mistaken for an empty schedule.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: StaffQueueRefreshButton(repository: repository),
                ),
                const SizedBox(height: 12),
                if (snapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: _ScheduleNotice(
                      'Live appointments could not be loaded. '
                      'Calendar counts are unavailable; check access or network.',
                    ),
                  )
                else if (!snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: _ScheduleNotice(
                      'Loading the staff appointment schedule…',
                    ),
                  ),
                _DashboardContent(
                  appointments: snapshot.hasError
                      ? const <AppointmentQueueItem>[]
                      : snapshot.data ?? const <AppointmentQueueItem>[],
                  availability: repository.watchPaccAvailability(),
                  onNavigate: onNavigate,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _ScheduleNotice extends StatelessWidget {
  const _ScheduleNotice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AdminColors.accentFaint,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AdminColors.border),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
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

const _box = BoxDecoration(
  color: AdminColors.surface,
  borderRadius: BorderRadius.all(Radius.circular(12)),
  border: Border.fromBorderSide(BorderSide(color: AdminColors.border)),
);
