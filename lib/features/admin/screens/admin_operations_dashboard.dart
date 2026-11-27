import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/admin_inquiry_model.dart';
import '../../../models/appointment_model.dart';
import '../../../models/profile_roles.dart';
import '../../../models/user_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_dashboard_analytics.dart';
import '../domain/admin_status_presentation.dart';
import '../theme/admin_theme.dart';
import '../widgets/admin_status_badge.dart';
import 'admin_portal.dart';

class AdminOperationsDashboardPage extends StatelessWidget {
  const AdminOperationsDashboardPage({
    super.key,
    required this.repository,
    required this.onNavigate,
    this.clock,
  });

  final AdminPortalRepository repository;
  final ValueChanged<AdminPortalPage> onNavigate;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => _DashboardFrame(
    title: 'Dashboard',
    subtitle: "Overview of today's MindMate activity.",
    child: StreamBuilder<List<UserModel>>(
      stream: repository.watchUsers(),
      builder: (context, usersSnapshot) => StreamBuilder<List<AdminInquiryModel>>(
        stream:
            repository.currentAccessRole == AccessRole.portalStaff &&
                !repository.isSuperAdmin
            ? repository.watchInquiryStatuses()
            : repository.watchInquiries(),
        builder: (context, inquiriesSnapshot) => StreamBuilder<List<AdminAssessmentRecord>>(
          stream: repository.watchAssessments(),
          builder: (context, assessmentsSnapshot) => StreamBuilder<List<AppointmentModel>>(
            stream: repository.watchAppointments(),
            builder: (context, appointmentsSnapshot) {
              final errors = [
                if (usersSnapshot.hasError) usersSnapshot.error,
                if (inquiriesSnapshot.hasError) inquiriesSnapshot.error,
                if (assessmentsSnapshot.hasError) assessmentsSnapshot.error,
                if (appointmentsSnapshot.hasError) appointmentsSnapshot.error,
              ];
              if (errors.isNotEmpty) {
                final isPermissionDenied = errors.any((err) {
                  final text = '$err'.toLowerCase();
                  return text.contains('permission-denied') ||
                      text.contains('permission_denied') ||
                      text.contains('unauthenticated') ||
                      text.contains('unauthorized');
                });
                return _DashboardAccessPanel(
                  isAccessDenied: isPermissionDenied,
                );
              }
              if ([
                usersSnapshot,
                inquiriesSnapshot,
                assessmentsSnapshot,
                appointmentsSnapshot,
              ].any((s) => !s.hasData)) {
                return const _DashboardLoadingPanel();
              }
              final users = usersSnapshot.data!;
              final inquiries = inquiriesSnapshot.data!;
              final assessments = assessmentsSnapshot.data!;
              final appointments = appointmentsSnapshot.data!;
              final now = (clock ?? DateTime.now)();
              final analytics = AdminDashboardAnalytics.fromRecords(
                users: users,
                appointments: appointments,
                inquiries: inquiries,
                assessments: assessments,
                now: now,
              );

              final appUserIds = users
                  .where((u) => u.isAppUser)
                  .map((u) => u.id)
                  .toSet();
              final visibleFullAssessments = assessments
                  .where(
                    (a) => a.isMainAssessment && appUserIds.contains(a.userId),
                  )
                  .toList();

              final summary =
                  'MindMate Dashboard\n'
                  'Active users (last 30 days): ${analytics.activeUsers30d}\n'
                  'Open appointments: ${analytics.openAppointments} '
                  '(Today active: ${analytics.todayActiveAppointments}, '
                  'Awaiting review: ${analytics.awaitingReviewAppointments})\n'
                  'Full assessments (last 7 days): ${analytics.fullAssessments7d}\n'
                  'Open inquiries: ${analytics.openInquiries} '
                  '(Open >= 24h: ${analytics.overdueOpenInquiries24h})';

              final activity = <_Activity>[];
              for (final a in visibleFullAssessments) {
                activity.add(
                  _Activity(
                    'Full assessment submitted',
                    a.createdAt,
                    AdminSemanticTone.violet,
                    Icons.assignment_turned_in_outlined,
                  ),
                );
              }
              for (final a in appointments) {
                activity.add(
                  _Activity(
                    'Appointment submitted',
                    a.createdAt,
                    AdminSemanticTone.blue,
                    Icons.calendar_today_outlined,
                  ),
                );
              }
              for (final i in inquiries.where(
                (i) => i.status == InquiryStatus.resolved,
              )) {
                activity.add(
                  _Activity(
                    'Inquiry resolved',
                    i.acknowledgedAt ?? i.createdAt,
                    AdminSemanticTone.green,
                    Icons.check_circle_outline,
                  ),
                );
              }
              activity.sort((a, b) => b.date.compareTo(a.date));

              final actionMetrics = <_AdminMetricSpec>[
                if (analytics.awaitingReviewAppointments > 0)
                  _AdminMetricSpec(
                    label: 'Needs action',
                    value: '${analytics.awaitingReviewAppointments}',
                    note: 'Appointments awaiting PACC review',
                    icon: Icons.priority_high_rounded,
                    tone: AdminSemanticTone.amber,
                    onTap: () => onNavigate(AdminPortalPage.appointments),
                  ),
                if (analytics.openInquiries > 0)
                  _AdminMetricSpec(
                    label: 'Open inquiries',
                    value: '${analytics.openInquiries}',
                    note:
                        '${analytics.overdueOpenInquiries24h} open ≥ 24h · ${analytics.processedInquiries} counselor-processed',
                    icon: Icons.chat_bubble_outline,
                    tone: analytics.overdueOpenInquiries24h > 0
                        ? AdminSemanticTone.amber
                        : AdminSemanticTone.green,
                    onTap: () => onNavigate(AdminPortalPage.inquiries),
                  ),
                if (analytics.openAppointments > 0)
                  _AdminMetricSpec(
                    label: 'Open appointments',
                    value: '${analytics.openAppointments}',
                    note:
                        'Today (Manila): ${analytics.todayActiveAppointments} · Awaiting review: ${analytics.awaitingReviewAppointments}',
                    icon: Icons.calendar_today_outlined,
                    tone: AdminSemanticTone.blue,
                    onTap: () => onNavigate(AdminPortalPage.appointments),
                  ),
                if (analytics.incompleteProfiles > 0)
                  _AdminMetricSpec(
                    label: 'Incomplete profiles',
                    value: '${analytics.incompleteProfiles}',
                    note: 'Student profiles awaiting completion',
                    icon: Icons.person_outline,
                    tone: AdminSemanticTone.neutral,
                    onTap: () => onNavigate(AdminPortalPage.users),
                  ),
              ];

              return Container(
                padding: const EdgeInsets.all(AdminSpacing.lg),
                decoration: _dashboardBox,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Operations overview',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _AdminQuickActionsMenu(onSelected: onNavigate),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Copy dashboard summary',
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: summary),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Dashboard summary copied.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy_all_outlined),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AdminSpacing.md),
                    if (actionMetrics.isNotEmpty)
                      LayoutBuilder(
                        builder: (context, box) {
                          final maxCols = box.maxWidth >= 900
                              ? 4
                              : box.maxWidth >= 560
                              ? 2
                              : 1;
                          final columns = actionMetrics.length < maxCols
                              ? actionMetrics.length
                              : maxCols;
                          final width =
                              (box.maxWidth - (columns - 1) * AdminSpacing.sm) /
                              columns;
                          return Wrap(
                            spacing: AdminSpacing.sm,
                            runSpacing: AdminSpacing.sm,
                            children: [
                              for (final spec in actionMetrics)
                                _Metric(
                                  width: width,
                                  label: spec.label,
                                  value: spec.value,
                                  note: spec.note,
                                  icon: spec.icon,
                                  tone: spec.tone,
                                  onTap: spec.onTap,
                                ),
                            ],
                          );
                        },
                      )
                    else
                      Container(
                        key: const ValueKey('admin-all-caught-up'),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AdminColors.greenBg.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AdminColors.greenBorder),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: AdminColors.greenFg,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'All caught up — no pending reviews, open inquiries, or open appointments.',
                                style: TextStyle(
                                  color: AdminColors.greenFg,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (analytics.overdueOpenInquiries24h > 0) ...[
                      const SizedBox(height: AdminSpacing.sm),
                      _Attention(
                        icon: Icons.hourglass_bottom_outlined,
                        tone: AdminSemanticTone.amber,
                        text:
                            '${analytics.overdueOpenInquiries24h} open inquiries are older than 24 hours',
                        actionLabel: 'Review →',
                        onAction: () => onNavigate(AdminPortalPage.inquiries),
                      ),
                    ],
                    const SizedBox(height: AdminSpacing.lg),
                    _AdminUnifiedSchedulePanel(
                      buckets: analytics.upcomingScheduleBuckets,
                      upcoming7dTotal: analytics.upcoming7dAppointments,
                      todaySchedule: analytics.todaySchedule,
                      onViewSchedule: () =>
                          onNavigate(AdminPortalPage.availability),
                    ),
                    const SizedBox(height: AdminSpacing.lg),
                    _AdminCaseloadPanel(
                      rows: analytics.activeCaseRows.take(8).toList(),
                      onViewAppointments: () =>
                          onNavigate(AdminPortalPage.appointments),
                    ),
                    const SizedBox(height: AdminSpacing.lg),
                    LayoutBuilder(
                      builder: (context, box) => Wrap(
                        spacing: AdminSpacing.lg,
                        runSpacing: AdminSpacing.lg,
                        children: [
                          SizedBox(
                            width: box.maxWidth > 700
                                ? (box.maxWidth - AdminSpacing.lg) / 2
                                : box.maxWidth,
                            child: _Trend(
                              buckets: analytics.latestActivityDayBuckets,
                              activeUsers30d: analytics.activeUsers30d,
                            ),
                          ),
                          SizedBox(
                            width: box.maxWidth > 700
                                ? (box.maxWidth - AdminSpacing.lg) / 2
                                : box.maxWidth,
                            child: _Status(
                              items: analytics.appointmentStatusBreakdown,
                              total: analytics.totalAppointments,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AdminSpacing.lg),
                    const Text(
                      'Recent Activity',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: AdminSpacing.sm),
                    if (activity.isEmpty)
                      const Text(
                        'No recent activity.',
                        style: TextStyle(color: AdminColors.muted),
                      )
                    else
                      ...activity
                          .take(5)
                          .map((a) => _Recent(activity: a, now: now)),
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
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        narrow ? 16 : 28,
        narrow ? 16 : 28,
        narrow ? 16 : 28,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: AdminSpacing.md),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardLoadingPanel extends StatelessWidget {
  const _DashboardLoadingPanel();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(32),
    decoration: _dashboardBox,
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: AdminSpacing.sm),
        Text(
          'Loading live operations overview…',
          textAlign: TextAlign.center,
          style: TextStyle(color: AdminColors.muted),
        ),
      ],
    ),
  );
}

class _DashboardAccessPanel extends StatelessWidget {
  const _DashboardAccessPanel({this.isAccessDenied = true});
  final bool isAccessDenied;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(32),
    decoration: _dashboardBox,
    child: Text(
      isAccessDenied
          ? 'Live admin data requires an authenticated staff account with the required access.'
          : 'Unable to load live dashboard data right now. Check connectivity and try again.',
      textAlign: TextAlign.center,
      style: const TextStyle(color: AdminColors.muted),
    ),
  );
}

(Color bg, Color fg, Color border) _toneColors(AdminSemanticTone tone) =>
    switch (tone) {
      AdminSemanticTone.amber => (
        AdminColors.amberBg,
        AdminColors.amberFg,
        AdminColors.amberBorder,
      ),
      AdminSemanticTone.blue => (
        AdminColors.blueBg,
        AdminColors.blueFg,
        AdminColors.blueBorder,
      ),
      AdminSemanticTone.green => (
        AdminColors.greenBg,
        AdminColors.greenFg,
        AdminColors.greenBorder,
      ),
      AdminSemanticTone.violet => (
        AdminColors.violetBg,
        AdminColors.violetFg,
        AdminColors.violetBorder,
      ),
      AdminSemanticTone.red => (
        AdminColors.redBg,
        AdminColors.redFg,
        AdminColors.redBorder,
      ),
      AdminSemanticTone.neutral => (
        AdminColors.neutralBg,
        AdminColors.neutralFg,
        AdminColors.neutralBorder,
      ),
    };

class _AdminMetricSpec {
  const _AdminMetricSpec({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final String label, value, note;
  final IconData icon;
  final AdminSemanticTone tone;
  final VoidCallback onTap;
}

class _AdminQuickActionsMenu extends StatelessWidget {
  const _AdminQuickActionsMenu({required this.onSelected});

  final ValueChanged<AdminPortalPage> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (
        page: AdminPortalPage.appointments,
        label: 'Appointments',
        icon: Icons.calendar_month_outlined,
      ),
      (
        page: AdminPortalPage.inquiries,
        label: 'Inquiries',
        icon: Icons.chat_bubble_outline,
      ),
      (
        page: AdminPortalPage.users,
        label: 'Users',
        icon: Icons.people_alt_outlined,
      ),
      (
        page: AdminPortalPage.reports,
        label: 'Reports',
        icon: Icons.assessment_outlined,
      ),
      (
        page: AdminPortalPage.availability,
        label: 'Schedule',
        icon: Icons.schedule_outlined,
      ),
      (
        page: AdminPortalPage.assessments,
        label: 'Assessments',
        icon: Icons.assignment_outlined,
      ),
    ];
    return PopupMenuButton<AdminPortalPage>(
      key: const ValueKey('admin-quick-actions-menu'),
      tooltip: 'Quick actions',
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 300),
      onSelected: onSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<AdminPortalPage>(
            value: item.page,
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: AdminColors.ink),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AdminColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_outlined, size: 17, color: AdminColors.accentStrong),
            SizedBox(width: 6),
            Text(
              'Quick actions',
              style: TextStyle(
                color: AdminColors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
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
    required this.tone,
    required this.onTap,
  });
  final double width;
  final String label, value, note;
  final IconData icon;
  final AdminSemanticTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _toneColors(tone);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.all(AdminSpacing.md),
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border.withValues(alpha: 0.65)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: fg,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
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
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: fg, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _Attention extends StatelessWidget {
  const _Attention({
    required this.icon,
    required this.tone,
    required this.text,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final AdminSemanticTone tone;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _AdminUnifiedSchedulePanel extends StatefulWidget {
  const _AdminUnifiedSchedulePanel({
    required this.buckets,
    required this.upcoming7dTotal,
    required this.todaySchedule,
    required this.onViewSchedule,
  });

  final List<DashboardActivityDayBucket> buckets;
  final int upcoming7dTotal;
  final List<AppointmentModel> todaySchedule;
  final VoidCallback onViewSchedule;

  @override
  State<_AdminUnifiedSchedulePanel> createState() =>
      _AdminUnifiedSchedulePanelState();
}

class _AdminUnifiedSchedulePanelState
    extends State<_AdminUnifiedSchedulePanel> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final maxCount = widget.buckets.fold<int>(
      0,
      (m, b) => b.count > m ? b.count : m,
    );
    final selected =
        _selectedIndex != null &&
            _selectedIndex! >= 0 &&
            _selectedIndex! < widget.buckets.length
        ? widget.buckets[_selectedIndex!]
        : null;

    final sevenDayPane = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '7-day appointment schedule',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          'Today + next 6 days (Manila) · ${widget.upcoming7dTotal} active sessions',
          style: const TextStyle(color: AdminColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (maxCount == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No active appointments in the next 7 days.',
              style: TextStyle(color: AdminColors.muted),
            ),
          )
        else ...[
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < widget.buckets.length; i++)
                  Expanded(
                    child: _AdminScheduleDayBar(
                      bucket: widget.buckets[i],
                      maxCount: maxCount,
                      selected: _selectedIndex == i,
                      onSelect: () => setState(() {
                        _selectedIndex = _selectedIndex == i ? null : i;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AdminColors.blueBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AdminColors.blueBorder.withValues(alpha: 0.6),
                ),
              ),
              child: Text(
                '${_shortDate(selected.manilaDay)}: ${selected.count} scheduled session${selected.count == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: AdminColors.blueFg,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ],
    );

    final todayPane = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's Counseling Schedule (${widget.todaySchedule.length})",
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        const Text(
          'Manila local day · Excludes cancelled, declined, and expired sessions',
          style: TextStyle(color: AdminColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (widget.todaySchedule.isEmpty)
          const Text(
            'No active appointments scheduled for today.',
            style: TextStyle(color: AdminColors.muted),
          )
        else
          ...widget.todaySchedule
              .take(6)
              .map((a) => _Schedule(appointment: a)),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AdminSpacing.md),
      decoration: BoxDecoration(
        color: AdminColors.canvas.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Schedule overview',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '7-day window and today\'s sessions combined',
                      style: TextStyle(color: AdminColors.muted, fontSize: 12),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: widget.onViewSchedule,
                  child: const Text('View schedule →'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 860) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: sevenDayPane),
                      const VerticalDivider(width: 32),
                      Expanded(flex: 6, child: todayPane),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sevenDayPane,
                  const Divider(height: 28),
                  todayPane,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AdminScheduleDayBar extends StatelessWidget {
  const _AdminScheduleDayBar({
    required this.bucket,
    required this.maxCount,
    required this.selected,
    required this.onSelect,
  });

  final DashboardActivityDayBucket bucket;
  final int maxCount;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final barHeight = maxCount == 0
        ? 4.0
        : (bucket.count / maxCount * 76.0).clamp(4.0, 76.0);
    return Tooltip(
      message:
          '${_shortDate(bucket.manilaDay)} · ${bucket.count} session${bucket.count == 1 ? '' : 's'}',
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${bucket.count}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected ? AdminColors.blueFg : AdminColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration:
                    (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                width: 22,
                height: barHeight,
                decoration: BoxDecoration(
                  color: selected ? AdminColors.blueFg : AdminColors.blueBorder,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _shortDate(bucket.manilaDay),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? AdminColors.blueFg : AdminColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminCaseloadPanel extends StatelessWidget {
  const _AdminCaseloadPanel({
    required this.rows,
    required this.onViewAppointments,
  });

  final List<DashboardCaseRow> rows;
  final VoidCallback onViewAppointments;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AdminSpacing.md),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active Cases',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Counseling caseload and next follow-up dates',
                      style: TextStyle(color: AdminColors.muted, fontSize: 12),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: onViewAppointments,
                  child: const Text('View appointments →'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Text(
              'No active counseling cases right now.',
              style: TextStyle(color: AdminColors.muted),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 720) {
                  return Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        _AdminMobileCaseItem(row: rows[i]),
                        if (i < rows.length - 1) const Divider(height: 14),
                      ],
                    ],
                  );
                }
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AdminColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Container(
                        color: AdminColors.surfaceMuted,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                'Student',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Counselor',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Status',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Next follow-up',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  rows[i].studentName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  rows[i].counselorName ?? 'Unassigned',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AdminColors.muted,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: AdminStatusBadge.fromStatus(
                                    domain: AdminStatusDomain.appointment,
                                    status: rows[i].status,
                                    compact: true,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  rows[i].nextFollowUpLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight:
                                        rows[i].hasFollowUpOffer ||
                                            rows[i].nextFollowUpDate != null
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: rows[i].hasFollowUpOffer
                                        ? AdminColors.amberFg
                                        : rows[i].nextFollowUpDate != null
                                        ? AdminColors.blueFg
                                        : AdminColors.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _AdminMobileCaseItem extends StatelessWidget {
  const _AdminMobileCaseItem({required this.row});

  final DashboardCaseRow row;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.studentName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
            AdminStatusBadge.fromStatus(
              domain: AdminStatusDomain.appointment,
              status: row.status,
              compact: true,
            ),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              'Counselor: ${row.counselorName ?? 'Unassigned'}',
              style: const TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
            Text(
              'Next follow-up: ${row.nextFollowUpLabel}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: row.hasFollowUpOffer || row.nextFollowUpDate != null
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: row.hasFollowUpOffer
                    ? AdminColors.amberFg
                    : row.nextFollowUpDate != null
                    ? AdminColors.blueFg
                    : AdminColors.muted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Schedule extends StatelessWidget {
  const _Schedule({required this.appointment});
  final AppointmentModel appointment;
  @override
  Widget build(BuildContext context) {
    final isFollowUp = (appointment.parentAppointmentId ?? '')
        .trim()
        .isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AdminSpacing.xs),
      child: Wrap(
        spacing: AdminSpacing.sm,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              appointment.scheduledTime.isEmpty
                  ? _time(toManilaDateTime(appointment.scheduledAt))
                  : appointment.scheduledTime,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 260),
            child: Text(
              appointment.fullName.isEmpty
                  ? 'Scheduled appointment'
                  : appointment.fullName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isFollowUp)
            AdminStatusBadge.fromStatus(
              domain: AdminStatusDomain.appointmentType,
              status: 'follow_up',
              compact: true,
            ),
          AdminStatusBadge.fromStatus(
            domain: AdminStatusDomain.appointment,
            status: appointment.status,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _Trend extends StatefulWidget {
  const _Trend({required this.buckets, required this.activeUsers30d});
  final List<DashboardActivityDayBucket> buckets;
  final int activeUsers30d;

  @override
  State<_Trend> createState() => _TrendState();
}

class _TrendState extends State<_Trend> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final maxCount = widget.buckets.fold<int>(
      0,
      (m, b) => b.count > m ? b.count : m,
    );
    final selected =
        _selectedIndex != null &&
            _selectedIndex! >= 0 &&
            _selectedIndex! < widget.buckets.length
        ? widget.buckets[_selectedIndex!]
        : null;

    return Container(
      padding: const EdgeInsets.all(AdminSpacing.md),
      decoration: BoxDecoration(
        color: AdminColors.canvas.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Users by most recent activity day',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Rolling 7 days (Manila time) · Count of users whose latest activity fell on each day',
            style: TextStyle(color: AdminColors.muted, fontSize: 12),
          ),
          const SizedBox(height: AdminSpacing.sm),
          if (maxCount == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'No users with recent activity in the last 7 days.',
                style: TextStyle(color: AdminColors.muted),
              ),
            )
          else ...[
            const Text(
              'Users (count)',
              style: TextStyle(
                color: AdminColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < widget.buckets.length; i++)
                    Expanded(
                      child: _TrendBar(
                        bucket: widget.buckets[i],
                        maxCount: maxCount,
                        activeUsers30d: widget.activeUsers30d,
                        selected: _selectedIndex == i,
                        onSelect: () => setState(() {
                          _selectedIndex = _selectedIndex == i ? null : i;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            if (selected != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AdminColors.blueBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AdminColors.blueBorder.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  '${_shortDate(selected.manilaDay)}: ${selected.count} user${selected.count == 1 ? '' : 's'}'
                  '${widget.activeUsers30d > 0 ? ' (${(selected.count / widget.activeUsers30d * 100).round()}% of 30-day active users)' : ''}',
                  style: const TextStyle(
                    color: AdminColors.blueFg,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.bucket,
    required this.maxCount,
    required this.activeUsers30d,
    required this.selected,
    required this.onSelect,
  });

  final DashboardActivityDayBucket bucket;
  final int maxCount;
  final int activeUsers30d;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final shareText = activeUsers30d > 0
        ? ' (${(bucket.count / activeUsers30d * 100).round()}% of 30d active)'
        : '';
    final tooltipMessage =
        '${_shortDate(bucket.manilaDay)} · ${bucket.count} user${bucket.count == 1 ? '' : 's'}$shareText\nRolling 7-day latest-seen distribution';
    final barHeight = maxCount == 0
        ? 4.0
        : (bucket.count / maxCount * 88.0).clamp(4.0, 88.0);

    return Tooltip(
      message: tooltipMessage,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${bucket.count}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected ? AdminColors.blueFg : AdminColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration:
                    (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                width: 22,
                height: barHeight,
                decoration: BoxDecoration(
                  color: selected ? AdminColors.blueFg : AdminColors.blueBorder,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _shortDate(bucket.manilaDay),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? AdminColors.blueFg : AdminColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Status extends StatefulWidget {
  const _Status({required this.items, required this.total});
  final List<DashboardStatusBreakdownItem> items;
  final int total;

  @override
  State<_Status> createState() => _StatusState();
}

class _StatusState extends State<_Status> {
  String? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final selected = widget.items
        .where((i) => i.key == _selectedKey)
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.all(AdminSpacing.md),
      decoration: BoxDecoration(
        color: AdminColors.canvas.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appointment status breakdown',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'All accessible records (${widget.total} total)',
            style: const TextStyle(color: AdminColors.muted, fontSize: 12),
          ),
          const SizedBox(height: AdminSpacing.md),
          if (widget.total == 0 || widget.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'No accessible appointments yet.',
                style: TextStyle(color: AdminColors.muted),
              ),
            )
          else ...[
            for (final item in widget.items)
              _StatusLine(
                item: item,
                total: widget.total,
                selected: _selectedKey == item.key,
                onTap: () => setState(() {
                  _selectedKey = _selectedKey == item.key ? null : item.key;
                }),
              ),
            if (selected != null) ...[
              const SizedBox(height: 6),
              Text(
                '${selected.label}: ${selected.count} of ${widget.total} '
                '(${selected.percentOf(widget.total)}%) · All accessible records',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.ink,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.item,
    required this.total,
    required this.selected,
    required this.onTap,
  });

  final DashboardStatusBreakdownItem item;
  final int total;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _toneColors(item.tone);
    final pct = item.percentOf(total);
    final tooltipMessage =
        '${item.label}: ${item.count} of $total ($pct%) · All accessible records';
    return Tooltip(
      message: tooltipMessage,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? bg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected ? Border.all(color: border) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: fg,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? fg : AdminColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${item.count} · $pct%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: item.shareOf(total),
                  minHeight: 8,
                  backgroundColor: AdminColors.surfaceMuted,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({required this.activity, required this.now});
  final _Activity activity;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final (_, fg, _) = _toneColors(activity.tone);
    return Padding(
      padding: const EdgeInsets.only(bottom: AdminSpacing.xs),
      child: Row(
        children: [
          Icon(activity.icon, size: 15, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(activity.label)),
          Text(
            _ago(activity.date, now),
            style: const TextStyle(color: AdminColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Activity {
  const _Activity(this.label, this.date, this.tone, this.icon);
  final String label;
  final DateTime date;
  final AdminSemanticTone tone;
  final IconData icon;
}

String _shortDate(DateTime d) {
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
  return '${months[d.month - 1]} ${d.day}';
}

String _time(DateTime d) {
  final h = d.hour == 0
      ? 12
      : d.hour > 12
      ? d.hour - 12
      : d.hour;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String _ago(DateTime d, DateTime now) {
  final diff = now.difference(d);
  final minutes = diff.inMinutes < 0 ? 0 : diff.inMinutes;
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
