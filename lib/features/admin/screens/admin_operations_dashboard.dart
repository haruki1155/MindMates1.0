import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/admin_inquiry_model.dart';
import '../../../models/appointment_model.dart';
import '../../../models/user_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../theme/admin_theme.dart';
import 'admin_portal.dart';

class AdminOperationsDashboardPage extends StatelessWidget {
  const AdminOperationsDashboardPage({
    super.key,
    required this.repository,
    required this.onNavigate,
  });

  final AdminPortalRepository repository;
  final ValueChanged<AdminPortalPage> onNavigate;

  @override
  Widget build(BuildContext context) => _DashboardFrame(
    title: 'Dashboard',
    subtitle: "Overview of today's MindMate activity.",
    child: StreamBuilder<List<UserModel>>(
      stream: repository.watchUsers(),
      builder: (context, usersSnapshot) => StreamBuilder<List<AdminInquiryModel>>(
        stream: repository.watchInquiries(),
        builder: (context, inquiriesSnapshot) => StreamBuilder<List<AdminAssessmentRecord>>(
          stream: repository.watchAssessments(),
          builder: (context, assessmentsSnapshot) => StreamBuilder<List<AppointmentModel>>(
            stream: repository.watchAppointments(),
            builder: (context, appointmentsSnapshot) {
              if ([
                usersSnapshot,
                inquiriesSnapshot,
                assessmentsSnapshot,
                appointmentsSnapshot,
              ].any((s) => s.hasError)) {
                return const _DashboardAccessPanel();
              }
              final users = (usersSnapshot.data ?? const <UserModel>[])
                  .where((u) => u.isAppUser)
                  .toList();
              final inquiries =
                  inquiriesSnapshot.data ?? const <AdminInquiryModel>[];
              final assessments =
                  (assessmentsSnapshot.data ?? const <AdminAssessmentRecord>[])
                      .where(
                        (a) =>
                            a.isMainAssessment &&
                            users.any((u) => u.id == a.userId),
                      )
                      .toList();
              final appointments =
                  appointmentsSnapshot.data ?? const <AppointmentModel>[];
              final now = DateTime.now();
              final today =
                  appointments
                      .where((a) => _sameDay(a.scheduledAt, now))
                      .toList()
                    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
              final active = users
                  .where(
                    (u) =>
                        u.lastActiveAt != null &&
                        u.lastActiveAt!.isAfter(
                          now.subtract(const Duration(days: 30)),
                        ),
                  )
                  .length;
              final weekAssessments = assessments
                  .where(
                    (a) => a.createdAt.isAfter(
                      now.subtract(const Duration(days: 7)),
                    ),
                  )
                  .length;
              final pendingAppointments = appointments
                  .where((a) => !_closed(a.status))
                  .length;
              final openInquiries = inquiries
                  .where((i) => i.status != InquiryStatus.resolved)
                  .length;
              final oldInquiries = inquiries
                  .where(
                    (i) =>
                        i.status != InquiryStatus.resolved &&
                        now.difference(i.createdAt).inHours >= 24,
                  )
                  .length;
              final incomplete = users
                  .where((u) => !u.isProfileComplete)
                  .length;
              final summary =
                  'MindMate Dashboard\nActive users: $active\nAppointments today: ${today.length}\nAssessments this week: $weekAssessments\nOpen inquiries: $openInquiries';
              final activity = <_Activity>[];
              for (final a in assessments) {
                activity.add(_Activity('Assessment completed', a.createdAt));
              }
              for (final a in appointments) {
                activity.add(_Activity('Appointment requested', a.createdAt));
              }
              for (final i in inquiries.where(
                (i) => i.status == InquiryStatus.resolved,
              )) {
                activity.add(
                  _Activity(
                    'Inquiry resolved',
                    i.acknowledgedAt ?? i.createdAt,
                  ),
                );
              }
              activity.sort((a, b) => b.date.compareTo(a.date));
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: _dashboardBox,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Operations overview',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy dashboard summary',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: summary),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Dashboard summary copied.'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_all_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, box) {
                        final columns = box.maxWidth >= 900
                            ? 4
                            : box.maxWidth >= 560
                            ? 2
                            : 1;
                        final width =
                            (box.maxWidth - (columns - 1) * 12) / columns;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _Metric(
                              width: width,
                              label: 'Active Users',
                              value: '$active',
                              note: 'Last 30 days',
                              icon: Icons.people_alt_outlined,
                              onTap: () => onNavigate(AdminPortalPage.users),
                            ),
                            _Metric(
                              width: width,
                              label: 'Appointments',
                              value: '$pendingAppointments',
                              note: 'Today: ${today.length}',
                              icon: Icons.calendar_today_outlined,
                              onTap: () =>
                                  onNavigate(AdminPortalPage.appointments),
                            ),
                            _Metric(
                              width: width,
                              label: 'Assessments',
                              value: '$weekAssessments',
                              note: 'This week',
                              icon: Icons.assignment_outlined,
                              onTap: () =>
                                  onNavigate(AdminPortalPage.assessments),
                            ),
                            _Metric(
                              width: width,
                              label: 'Open Inquiries',
                              value: '$openInquiries',
                              note: '$oldInquiries need reply',
                              icon: Icons.chat_bubble_outline,
                              onTap: () =>
                                  onNavigate(AdminPortalPage.inquiries),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 30),
                    _SectionHeader(
                      onViewAll: () => onNavigate(AdminPortalPage.inquiries),
                    ),
                    const SizedBox(height: 12),
                    if (incomplete > 0)
                      _Attention(
                        icon: Icons.warning_amber_outlined,
                        text:
                            '$incomplete profiles recommended for counselor follow-up',
                      ),
                    if (pendingAppointments > 0)
                      _Attention(
                        icon: Icons.circle,
                        text:
                            '$pendingAppointments appointment requests awaiting confirmation',
                      ),
                    if (oldInquiries > 0)
                      _Attention(
                        icon: Icons.circle,
                        text:
                            '$oldInquiries inquiries awaiting response for more than 24 hours',
                      ),
                    if (incomplete == 0 &&
                        pendingAppointments == 0 &&
                        oldInquiries == 0)
                      const Text(
                        'Everything is up to date.',
                        style: TextStyle(color: AdminColors.success),
                      ),
                    const SizedBox(height: 30),
                    const Text(
                      "Today's Counseling Schedule",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    if (today.isEmpty)
                      const Text(
                        'No appointments scheduled for today.',
                        style: TextStyle(color: AdminColors.muted),
                      )
                    else
                      ...today.take(5).map((a) => _Schedule(appointment: a)),
                    const SizedBox(height: 30),
                    LayoutBuilder(
                      builder: (context, box) => Wrap(
                        spacing: 24,
                        runSpacing: 24,
                        children: [
                          SizedBox(
                            width: box.maxWidth > 700
                                ? (box.maxWidth - 24) / 2
                                : box.maxWidth,
                            child: _Trend(users: users),
                          ),
                          SizedBox(
                            width: box.maxWidth > 700
                                ? (box.maxWidth - 24) / 2
                                : box.maxWidth,
                            child: _Status(appointments: appointments),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'Recent Activity',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    if (activity.isEmpty)
                      const Text(
                        'No recent activity.',
                        style: TextStyle(color: AdminColors.muted),
                      )
                    else
                      ...activity.take(5).map((a) => _Recent(activity: a)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _DashboardFrame extends StatelessWidget {
  const _DashboardFrame({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    ),
  );
}

class _DashboardAccessPanel extends StatelessWidget {
  const _DashboardAccessPanel();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(32),
    decoration: _dashboardBox,
    child: const Text(
      'Live admin data requires an authenticated staff account with the required access.',
      textAlign: TextAlign.center,
      style: TextStyle(color: AdminColors.muted),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.onTap,
  });
  final double width;
  final String label, value, note;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(16),
      decoration: _dashboardBox,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  note,
                  style: const TextStyle(
                    color: AdminColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: AdminColors.accentStrong),
        ],
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.onViewAll});
  final VoidCallback onViewAll;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Text(
          'Needs Attention',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      TextButton(onPressed: onViewAll, child: const Text('View all →')),
    ],
  );
}

class _Attention extends StatelessWidget {
  const _Attention({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: icon == Icons.warning_amber_outlined
              ? AdminColors.accentStrong
              : AdminColors.muted,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _Schedule extends StatelessWidget {
  const _Schedule({required this.appointment});
  final AppointmentModel appointment;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
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
        Expanded(
          child: Text(
            appointment.fullName.isEmpty
                ? 'Scheduled appointment'
                : appointment.fullName,
          ),
        ),
        SizedBox(
          width: 100,
          child: Text(
            _title(appointment.status),
            style: TextStyle(
              color: _dashboardStatusColor(appointment.status),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Trend extends StatelessWidget {
  const _Trend({required this.users});
  final List<UserModel> users;
  @override
  Widget build(BuildContext context) {
    final months = List.generate(
      6,
      (i) => DateTime(DateTime.now().year, DateTime.now().month - 5 + i),
    );
    final values = months.map((m) => _active(users, m)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Activity Trend',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 125,
          child: CustomPaint(
            painter: _Line(values.map((v) => v.toDouble()).toList()),
            child: const SizedBox.expand(),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: months
              .map(
                (m) => Text(
                  _month(m),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AdminColors.muted,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.appointments});
  final List<AppointmentModel> appointments;
  @override
  Widget build(BuildContext context) {
    final total = appointments.length;
    final completed = appointments.where((a) => _closed(a.status)).length;
    final scheduled = total - completed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Appointment Status',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        _StatusLine('Completed', completed, total),
        _StatusLine('Scheduled', scheduled, total),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(this.label, this.value, this.total);
  final String label;
  final int value, total;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : value / total,
              minHeight: 8,
              backgroundColor: AdminColors.surfaceMuted,
              color: AdminColors.accentStrong,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${total == 0 ? 0 : (value / total * 100).round()}%',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _Recent extends StatelessWidget {
  const _Recent({required this.activity});
  final _Activity activity;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(child: Text(activity.label)),
        Text(
          _ago(activity.date),
          style: const TextStyle(color: AdminColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class _Activity {
  const _Activity(this.label, this.date);
  final String label;
  final DateTime date;
}

class _Line extends CustomPainter {
  const _Line(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final grid = Paint()
      ..color = AdminColors.border
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    final max = values.fold<double>(1, (a, b) => a > b ? a : b);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(
        size.width * i / (values.length - 1),
        size.height - (values[i] / max * size.height * .85) - 4,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AdminColors.accentStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _Line oldDelegate) =>
      oldDelegate.values != values;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
bool _closed(String status) => const {
  'completed',
  'complete',
  'declined',
  'cancelled',
  'canceled',
}.contains(status.toLowerCase().trim());
int _active(List<UserModel> users, DateTime month) => users
    .where(
      (u) =>
          u.activeDateKeys.any(
            (key) => key.startsWith(
              '${month.year}-${month.month.toString().padLeft(2, '0')}-',
            ),
          ) ||
          (u.lastActiveAt?.year == month.year &&
              u.lastActiveAt?.month == month.month),
    )
    .length;
String _month(DateTime d) => const [
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
][d.month - 1];
String _time(DateTime d) {
  final h = d.hour == 0
      ? 12
      : d.hour > 12
      ? d.hour - 12
      : d.hour;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String _title(String s) => s.isEmpty
    ? 'Pending'
    : '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
String _ago(DateTime d) {
  final minutes = DateTime.now().difference(d).inMinutes;
  if (minutes < 60) return '$minutes min ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours hr ago';
  return '${hours ~/ 24} days ago';
}

final _dashboardBox = BoxDecoration(
  color: AdminColors.surface,
  borderRadius: BorderRadius.circular(10),
  border: Border.all(color: AdminColors.border),
);
Color _dashboardStatusColor(String status) =>
    _closed(status) ? AdminColors.success : AdminColors.accentStrong;
