import 'package:flutter/material.dart';

import '../../../models/appointment_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../theme/admin_theme.dart';
import 'admin_portal.dart';

/// Counselor landing page: assigned caseload and today's counseling work only.
class CounselorOperationsDashboardPage extends StatelessWidget {
  const CounselorOperationsDashboardPage({
    super.key,
    required this.repository,
    required this.onNavigate,
  });
  final AdminPortalRepository repository;
  final ValueChanged<AdminPortalPage> onNavigate;

  @override
  Widget build(BuildContext context) =>
      _CounselorPage(repository: repository, onNavigate: onNavigate);
}

class _CounselorPage extends StatelessWidget {
  const _CounselorPage({required this.repository, required this.onNavigate});
  final AdminPortalRepository repository;
  final ValueChanged<AdminPortalPage> onNavigate;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1680),
        child: StreamBuilder<List<AppointmentModel>>(
          stream: repository.watchAppointments(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _Message(
                title: 'Unable to load your counseling workspace',
                body: 'Please try again or contact an administrator.',
              );
            }
            if (!snapshot.hasData) return const _Skeleton();
            return _Content(
              appointments: snapshot.data!,
              onNavigate: onNavigate,
            );
          },
        ),
      ),
    ),
  );
}

class _Content extends StatelessWidget {
  const _Content({required this.appointments, required this.onNavigate});
  final List<AppointmentModel> appointments;
  final ValueChanged<AdminPortalPage> onNavigate;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today =
        appointments.where((a) => _sameDay(a.scheduledAt, now)).toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final upcoming = appointments
        .where(
          (a) =>
              a.scheduledAt.isAfter(now) &&
              a.scheduledAt.isBefore(now.add(const Duration(days: 8))),
        )
        .length;
    final needsAttention = appointments
        .where(
          (a) => const {
            'reschedule_required',
            'reschedule_proposed',
          }.contains(a.status.toLowerCase().trim()),
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Counselor Dashboard',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        const Text(
          'Your counseling workspace, appointments, and follow-ups.',
          style: TextStyle(color: AdminColors.muted),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 900
                ? 3
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
                  title: 'Today',
                  value: '${today.length}',
                  note:
                      '${today.where((a) => !_closed(a.status)).length} remaining',
                  icon: Icons.today_outlined,
                ),
                _Metric(
                  width: width,
                  title: 'Upcoming',
                  value: '$upcoming',
                  note: 'Next 7 days',
                  icon: Icons.event_available_outlined,
                ),
                _Metric(
                  width: width,
                  title: 'Needs attention',
                  value: '$needsAttention',
                  note: 'Follow-up required',
                  icon: Icons.priority_high_rounded,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _Panel(
          title: "Today's schedule",
          action: TextButton(
            onPressed: () => onNavigate(AdminPortalPage.availability),
            child: const Text('View schedule →'),
          ),
          child: today.isEmpty
              ? const _Message(
                  title: 'No appointments today',
                  body: 'Your assigned counseling schedule is clear today.',
                )
              : Column(
                  children: today
                      .take(10)
                      .map(
                        (a) => _Row(
                          appointment: a,
                          onOpen: () =>
                              onNavigate(AdminPortalPage.appointments),
                        ),
                      )
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
                onPressed: () => onNavigate(AdminPortalPage.appointments),
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
    required this.title,
    required this.value,
    required this.note,
    required this.icon,
  });
  final double width;
  final String title, value, note;
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
                title,
                style: const TextStyle(
                  color: AdminColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
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
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
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

class _Row extends StatelessWidget {
  const _Row({required this.appointment, required this.onOpen});
  final AppointmentModel appointment;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final id = appointment.userId.isEmpty ? appointment.id : appointment.userId;
    final suffix = id.length > 4 ? id.substring(id.length - 4) : id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              appointment.scheduledTime.isEmpty
                  ? _time(appointment.scheduledAt)
                  : appointment.scheduledTime,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text('Student ••••$suffix')),
          Text(
            _label(appointment.status),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onOpen, child: const Text('Open')),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});
  final String title, body;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: _box,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(color: AdminColors.muted)),
      ],
    ),
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(width: 300, height: 30, decoration: _skeleton),
      const SizedBox(height: 12),
      Container(width: 430, height: 16, decoration: _skeleton),
      const SizedBox(height: 24),
      Row(
        children: List.generate(
          3,
          (_) => Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(height: 118, decoration: _skeleton),
            ),
          ),
        ),
      ),
    ],
  );
}

String _label(String value) => switch (value.toLowerCase().trim()) {
  'reschedule_required' => 'Follow-up required',
  'reschedule_proposed' => 'New schedule proposed',
  'confirmed' => 'Confirmed',
  'completed' || 'complete' => 'Completed',
  _ => 'Scheduled',
};
String _time(DateTime date) =>
    '${date.hour == 0
        ? 12
        : date.hour > 12
        ? date.hour - 12
        : date.hour}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
bool _closed(String status) => const {
  'completed',
  'complete',
  'cancelled',
  'canceled',
}.contains(status.toLowerCase().trim());
final _box = BoxDecoration(
  color: AdminColors.surface,
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: AdminColors.border),
);
const _skeleton = BoxDecoration(
  color: Color(0xFFE9E8E4),
  borderRadius: BorderRadius.all(Radius.circular(12)),
);
