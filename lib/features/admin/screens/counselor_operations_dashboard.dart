import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../models/appointment_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_dashboard_analytics.dart';
import '../domain/admin_status_presentation.dart';
import '../domain/counselor_dashboard_analytics.dart';
import '../theme/admin_theme.dart';
import '../widgets/admin_status_badge.dart';
import 'admin_portal.dart';

/// Counselor landing page with organization-wide clinical operations and a
/// separately labelled assigned caseload.
class CounselorOperationsDashboardPage extends StatelessWidget {
  const CounselorOperationsDashboardPage({
    super.key,
    required this.repository,
    required this.onNavigate,
    this.clock,
  });

  final AdminPortalRepository repository;
  final ValueChanged<AdminPortalPage> onNavigate;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => _CounselorPage(
    repository: repository,
    onNavigate: onNavigate,
    clock: clock,
  );
}

class _CounselorPage extends StatelessWidget {
  const _CounselorPage({
    required this.repository,
    required this.onNavigate,
    this.clock,
  });

  final AdminPortalRepository repository;
  final ValueChanged<AdminPortalPage> onNavigate;
  final DateTime Function()? clock;

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
          constraints: const BoxConstraints(maxWidth: 1680),
          child: StreamBuilder<List<AppointmentModel>>(
            stream: repository.watchAppointments(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final issue = snapshot.error;
                final code = issue is FirebaseException
                    ? issue.code
                    : 'unknown';
                return _Message(
                  title: 'Unable to load your counseling workspace',
                  body:
                      'Cannot read clinical appointments ($code). '
                      'Check Counselor authorization, project environment and '
                      'Firestore query permissions. Do not use Admin access as a workaround.',
                  tone: AdminSemanticTone.red,
                );
              }
              if (!snapshot.hasData) return const _Skeleton();
              return StreamBuilder<List<AppointmentModel>>(
                stream: repository.watchMyAssignedAppointments(),
                builder: (context, myCasesSnapshot) {
                  // A failed assigned-caseload query must not hide the
                  // organization-wide appointments that already loaded.
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (myCasesSnapshot.hasError)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: _Message(
                            title: 'Assigned caseload unavailable',
                            body:
                                'Your full PACC appointment overview is still '
                                'available. Check assigned-case access or query indexes.',
                            tone: AdminSemanticTone.amber,
                          ),
                        ),
                      _Content(
                        appointments: snapshot.data!,
                        myAppointments: myCasesSnapshot.hasError
                            ? const <AppointmentModel>[]
                            : myCasesSnapshot.data ??
                                  const <AppointmentModel>[],
                        caseloadLoading:
                            !myCasesSnapshot.hasData &&
                            !myCasesSnapshot.hasError,
                        caseloadUnavailable: myCasesSnapshot.hasError,
                        onNavigate: onNavigate,
                        now: (clock ?? DateTime.now)(),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.appointments,
    required this.myAppointments,
    required this.caseloadLoading,
    required this.caseloadUnavailable,
    required this.onNavigate,
    required this.now,
  });

  final List<AppointmentModel> appointments;
  final List<AppointmentModel> myAppointments;
  final bool caseloadLoading;
  final bool caseloadUnavailable;
  final ValueChanged<AdminPortalPage> onNavigate;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final analytics = CounselorDashboardAnalytics.fromAppointments(
      appointments: appointments,
      myAppointments: myAppointments,
      now: now,
    );
    final metrics = analytics.paccMetrics;
    final myMetrics = analytics.myMetrics;
    final today = analytics.todaySchedule;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PACC-wide clinical operations and your assigned caseload.',
          style: TextStyle(color: AdminColors.muted),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 1040
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
                  title: 'PACC Today',
                  value: '${metrics.today}',
                  note: '${analytics.todayRemainingCount} remaining',
                  icon: Icons.today_outlined,
                  tone: AdminSemanticTone.blue,
                  onTap: () => onNavigate(AdminPortalPage.availability),
                ),
                _Metric(
                  width: width,
                  title: 'Upcoming',
                  value: '${metrics.upcoming}',
                  note: 'Confirmed future dates',
                  icon: Icons.event_available_outlined,
                  tone: AdminSemanticTone.green,
                  onTap: () => onNavigate(AdminPortalPage.appointments),
                ),
                _Metric(
                  width: width,
                  title: 'Needs action',
                  value: '${metrics.needsAction}',
                  note: 'Follow-up required',
                  icon: Icons.priority_high_rounded,
                  tone: metrics.needsAction > 0
                      ? AdminSemanticTone.amber
                      : AdminSemanticTone.neutral,
                  onTap: () => onNavigate(AdminPortalPage.appointments),
                ),
                _Metric(
                  width: width,
                  title: 'My Assigned Active',
                  value: caseloadLoading
                      ? '…'
                      : caseloadUnavailable
                      ? '—'
                      : '${analytics.myActiveCaseloadCount}',
                  note: caseloadLoading
                      ? 'Loading assigned caseload…'
                      : caseloadUnavailable
                      ? 'Unable to load assigned cases'
                      : '${myMetrics.today} today · ${analytics.myAwaitingFollowUpOfferCount} follow-up offered',
                  icon: Icons.folder_shared_outlined,
                  tone: AdminSemanticTone.violet,
                  onTap: () => onNavigate(AdminPortalPage.cases),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        _Panel(
          title: 'My Caseload',
          subtitle:
              'Assigned counseling cases (${myMetrics.total} total records)',
          action: TextButton(
            onPressed: () => onNavigate(AdminPortalPage.cases),
            child: const Text('Open My Cases →'),
          ),
          child: caseloadLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Loading assigned caseload metrics…',
                          style: TextStyle(color: AdminColors.muted),
                        ),
                      ),
                    ],
                  ),
                )
              : Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _CaseloadStatChip(
                      label: 'Assigned ${myMetrics.total}',
                      tone: AdminSemanticTone.violet,
                      icon: Icons.assignment_ind_outlined,
                    ),
                    _CaseloadStatChip(
                      label: 'Today ${myMetrics.today}',
                      tone: AdminSemanticTone.blue,
                      icon: Icons.today_outlined,
                    ),
                    _CaseloadStatChip(
                      label: 'Upcoming ${myMetrics.upcoming}',
                      tone: AdminSemanticTone.green,
                      icon: Icons.event_available_outlined,
                    ),
                    _CaseloadStatChip(
                      label: 'Needs action ${myMetrics.needsAction}',
                      tone: myMetrics.needsAction > 0
                          ? AdminSemanticTone.amber
                          : AdminSemanticTone.neutral,
                      icon: Icons.pending_actions_outlined,
                    ),
                    if (analytics.myAwaitingFollowUpOfferCount > 0)
                      _CaseloadStatChip(
                        label:
                            'Follow-up offered ${analytics.myAwaitingFollowUpOfferCount}',
                        tone: AdminSemanticTone.amber,
                        icon: Icons.reply_outlined,
                      ),
                    _CaseloadStatChip(
                      label: 'Completed ${myMetrics.completed}',
                      tone: AdminSemanticTone.green,
                      icon: Icons.check_circle_outline,
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) {
            final twoColumns = box.maxWidth > 760;
            final cardWidth = twoColumns
                ? (box.maxWidth - AdminSpacing.md) / 2
                : box.maxWidth;
            return Wrap(
              spacing: AdminSpacing.md,
              runSpacing: AdminSpacing.md,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _ScheduleWindowChart(
                    buckets: analytics.scheduleWindowBuckets,
                    upcoming7dTotal: analytics.upcoming7dTotal,
                    upcoming7dAssignedTotal: analytics.upcoming7dAssignedTotal,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _StatusBreakdownPanel(
                    paccItems: analytics.paccStatusBreakdown,
                    paccTotal: analytics.totalPaccAppointments,
                    myItems: analytics.myStatusBreakdown,
                    myTotal: analytics.totalMyAppointments,
                    caseloadUnavailable: caseloadUnavailable,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _Panel(
          title: "Today's schedule",
          subtitle:
              'Manila local day · Excludes cancelled, declined, and expired sessions',
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
                          isAssignedToMe: analytics.assignedAppointmentIds
                              .contains(a.id.trim()),
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
              OutlinedButton.icon(
                onPressed: () => onNavigate(AdminPortalPage.cases),
                icon: const Icon(Icons.folder_shared_outlined),
                label: const Text('My Cases'),
              ),
              OutlinedButton.icon(
                onPressed: () => onNavigate(AdminPortalPage.followUps),
                icon: const Icon(Icons.task_alt_outlined),
                label: const Text('Follow-ups'),
              ),
            ],
          ),
        ),
      ],
    );
  }
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

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.title,
    required this.value,
    required this.note,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final double width;
  final String title, value, note;
  final IconData icon;
  final AdminSemanticTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _toneColors(tone);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: width,
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(14),
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
                    title,
                    style: const TextStyle(
                      color: AdminColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.muted,
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

class _CaseloadStatChip extends StatelessWidget {
  const _CaseloadStatChip({
    required this.label,
    required this.tone,
    required this.icon,
  });

  final String label;
  final AdminSemanticTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleWindowChart extends StatefulWidget {
  const _ScheduleWindowChart({
    required this.buckets,
    required this.upcoming7dTotal,
    required this.upcoming7dAssignedTotal,
  });

  final List<CounselorScheduleDayBucket> buckets;
  final int upcoming7dTotal;
  final int upcoming7dAssignedTotal;

  @override
  State<_ScheduleWindowChart> createState() => _ScheduleWindowChartState();
}

class _ScheduleWindowChartState extends State<_ScheduleWindowChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final maxCount = widget.buckets.fold<int>(
      0,
      (m, b) => b.paccCount > m ? b.paccCount : m,
    );
    final selected =
        _selectedIndex != null &&
            _selectedIndex! >= 0 &&
            _selectedIndex! < widget.buckets.length
        ? widget.buckets[_selectedIndex!]
        : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '7-day appointment schedule',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Today + next 6 days (Manila time) · ${widget.upcoming7dTotal} active PACC sessions (${widget.upcoming7dAssignedTotal} assigned to you)',
            style: const TextStyle(color: AdminColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (maxCount == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'No active sessions scheduled in the next 7 days.',
                style: TextStyle(color: AdminColors.muted),
              ),
            )
          else ...[
            const Text(
              'Scheduled sessions (count)',
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
                      child: _ScheduleDayBar(
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
                  '${_shortDate(selected.manilaDay)}: ${selected.paccCount} PACC session${selected.paccCount == 1 ? '' : 's'} '
                  '(${selected.assignedCount} assigned to you)',
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

class _ScheduleDayBar extends StatelessWidget {
  const _ScheduleDayBar({
    required this.bucket,
    required this.maxCount,
    required this.selected,
    required this.onSelect,
  });

  final CounselorScheduleDayBucket bucket;
  final int maxCount;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final tooltipMessage =
        '${_shortDate(bucket.manilaDay)} · ${bucket.paccCount} PACC session${bucket.paccCount == 1 ? '' : 's'} (${bucket.assignedCount} assigned to you)';
    final barHeight = maxCount == 0
        ? 4.0
        : (bucket.paccCount / maxCount * 88.0).clamp(4.0, 88.0);
    final hasAssigned = bucket.assignedCount > 0;

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
                '${bucket.paccCount}',
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
                  color: selected
                      ? AdminColors.blueFg
                      : hasAssigned
                      ? AdminColors.violetBorder
                      : AdminColors.blueBorder,
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

class _StatusBreakdownPanel extends StatefulWidget {
  const _StatusBreakdownPanel({
    required this.paccItems,
    required this.paccTotal,
    required this.myItems,
    required this.myTotal,
    required this.caseloadUnavailable,
  });

  final List<DashboardStatusBreakdownItem> paccItems;
  final int paccTotal;
  final List<DashboardStatusBreakdownItem> myItems;
  final int myTotal;
  final bool caseloadUnavailable;

  @override
  State<_StatusBreakdownPanel> createState() => _StatusBreakdownPanelState();
}

class _StatusBreakdownPanelState extends State<_StatusBreakdownPanel> {
  bool _showMyCaseloadOnly = false;
  String? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final items = _showMyCaseloadOnly ? widget.myItems : widget.paccItems;
    final total = _showMyCaseloadOnly ? widget.myTotal : widget.paccTotal;
    final scopeLabel = _showMyCaseloadOnly
        ? 'Assigned caseload records'
        : 'All PACC appointment records';
    final selected = items.where((i) => i.key == _selectedKey).firstOrNull;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Appointment status breakdown',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$scopeLabel ($total total)',
                    style: const TextStyle(
                      color: AdminColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: Text('PACC (${widget.paccTotal})'),
                    selected: !_showMyCaseloadOnly,
                    onSelected: (_) => setState(() {
                      _showMyCaseloadOnly = false;
                      _selectedKey = null;
                    }),
                  ),
                  ChoiceChip(
                    label: Text('My Caseload (${widget.myTotal})'),
                    selected: _showMyCaseloadOnly,
                    onSelected: widget.caseloadUnavailable
                        ? null
                        : (_) => setState(() {
                            _showMyCaseloadOnly = true;
                            _selectedKey = null;
                          }),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (total == 0 || items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                _showMyCaseloadOnly
                    ? 'No assigned caseload appointments yet.'
                    : 'No accessible appointments yet.',
                style: const TextStyle(color: AdminColors.muted),
              ),
            )
          else ...[
            for (final item in items)
              _StatusLine(
                item: item,
                total: total,
                scopeLabel: scopeLabel,
                selected: _selectedKey == item.key,
                onTap: () => setState(() {
                  _selectedKey = _selectedKey == item.key ? null : item.key;
                }),
              ),
            if (selected != null) ...[
              const SizedBox(height: 6),
              Text(
                '${selected.label}: ${selected.count} of $total '
                '(${selected.percentOf(total)}%) · $scopeLabel',
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
    required this.scopeLabel,
    required this.selected,
    required this.onTap,
  });

  final DashboardStatusBreakdownItem item;
  final int total;
  final String scopeLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _toneColors(item.tone);
    final pct = item.percentOf(total);
    final tooltipMessage =
        '${item.label}: ${item.count} of $total ($pct%) · $scopeLabel';

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

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AdminColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
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
  const _Row({
    required this.appointment,
    required this.isAssignedToMe,
    required this.onOpen,
  });

  final AppointmentModel appointment;
  final bool isAssignedToMe;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final id = appointment.userId.isEmpty ? appointment.id : appointment.userId;
    final suffix = id.length > 4 ? id.substring(id.length - 4) : id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              appointment.scheduledTime.isEmpty
                  ? _time(toManilaDateTime(appointment.scheduledAt))
                  : appointment.scheduledTime,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
            child: Text('Student ••••$suffix', overflow: TextOverflow.ellipsis),
          ),
          if (isAssignedToMe)
            const _CaseloadStatChip(
              label: 'Assigned to you',
              tone: AdminSemanticTone.violet,
              icon: Icons.person_pin_outlined,
            ),
          if ((appointment.parentAppointmentId ?? '').trim().isNotEmpty)
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
          TextButton(onPressed: onOpen, child: const Text('Open')),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body, this.tone});

  final String title, body;
  final AdminSemanticTone? tone;

  @override
  Widget build(BuildContext context) {
    final border = tone != null ? _toneColors(tone!).$3 : AdminColors.border;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
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

String _time(DateTime date) =>
    '${date.hour == 0
        ? 12
        : date.hour > 12
        ? date.hour - 12
        : date.hour}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';

final _box = BoxDecoration(
  color: AdminColors.surface,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: AdminColors.border),
);

final _skeleton = BoxDecoration(
  color: AdminColors.surfaceMuted,
  borderRadius: BorderRadius.circular(12),
);
