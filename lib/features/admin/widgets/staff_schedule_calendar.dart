import 'package:flutter/material.dart';

import '../../../models/appointment_queue_item.dart';
import '../theme/admin_theme.dart';

/// Only staff-safe scheduling metadata; no concerns or clinical notes.
enum StaffScheduleKind { counseling, testing }

class StaffScheduleEntry {
  const StaffScheduleEntry({
    required this.id,
    required this.scheduledAt,
    required this.kind,
    required this.timeLabel,
    required this.assignedCounselor,
    required this.status,
  });

  final String id;
  final DateTime scheduledAt;
  final StaffScheduleKind kind;
  final String timeLabel;
  final String assignedCounselor;
  final String status;

  factory StaffScheduleEntry.fromCounseling(AppointmentQueueItem item) =>
      StaffScheduleEntry(
        id: item.id,
        scheduledAt: item.scheduledAt,
        kind: StaffScheduleKind.counseling,
        timeLabel: item.scheduledTime,
        assignedCounselor: item.assignedCounselor ?? 'Unassigned',
        status: item.status,
      );
}

/// Plots verified counseling appointments. Testing may be plotted only when
/// a trusted source supplies entries and explicitly sets connected=true.
class StaffScheduleCalendar extends StatefulWidget {
  const StaffScheduleCalendar({
    super.key,
    required this.counselingAppointments,
    this.testingAppointments = const [],
    this.testingSchedulesConnected = false,
    this.initialMonth,
  });

  final List<AppointmentQueueItem> counselingAppointments;
  final List<StaffScheduleEntry> testingAppointments;
  final bool testingSchedulesConnected;
  final DateTime? initialMonth;

  @override
  State<StaffScheduleCalendar> createState() => _StaffScheduleCalendarState();
}

class _StaffScheduleCalendarState extends State<StaffScheduleCalendar> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth ?? DateTime.now();
    _month = DateTime(initial.year, initial.month);
    _selected = DateTime(initial.year, initial.month, initial.day);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<StaffScheduleEntry> get _entries {
    final counseling = widget.counselingAppointments.where((item) {
      if (item.isArchived) return false;
      // Display pending requests separately, never as confirmed bookings.
      return const {
        'confirmed', 'completed', 'complete',
        'requested', 'pending', 'upcoming', 'reschedule_proposed',
      }.contains(item.status.trim().toLowerCase());
    }).map(StaffScheduleEntry.fromCounseling);
    final entries = <StaffScheduleEntry>[
      ...counseling,
      if (widget.testingSchedulesConnected)
        ...widget.testingAppointments.where(
          (entry) => entry.kind == StaffScheduleKind.testing,
        ),
    ];
    entries.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return entries;
  }

  void _moveMonth(int offset) {
    final next = DateTime(_month.year, _month.month + offset);
    setState(() {
      _month = next;
      _selected = next;
    });
  }

  String _time(BuildContext context, StaffScheduleEntry entry) =>
      entry.timeLabel.trim().isNotEmpty
          ? entry.timeLabel.trim()
          : TimeOfDay.fromDateTime(entry.scheduledAt).format(context);

  String _detail(BuildContext context, StaffScheduleEntry entry) {
    final status = entry.status.trim().toLowerCase();
    final pending = const {
      'requested', 'pending', 'upcoming', 'reschedule_proposed',
    }.contains(status);
    return '${_time(context, entry)} · '
        '${entry.kind == StaffScheduleKind.counseling ? 'Counseling' : 'Testing'}'
        ' · ${entry.assignedCounselor}'
        '${pending ? ' · Pending (unconfirmed)' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final first = DateTime(_month.year, _month.month);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final selected = entries.where((item) => _sameDay(item.scheduledAt, _selected));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(
            MaterialLocalizations.of(context).formatMonthYear(_month),
            style: Theme.of(context).textTheme.titleLarge,
          )),
          TextButton(
            onPressed: () => setState(() {
              final now = DateTime.now();
              _month = DateTime(now.year, now.month);
              _selected = DateTime(now.year, now.month, now.day);
            }),
            child: const Text('Today'),
          ),
          IconButton(
            tooltip: 'Previous month',
            onPressed: () => _moveMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: () => _moveMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          widget.testingSchedulesConnected
              ? 'Counseling and testing schedules'
              : 'Counseling schedules and pending requests · Testing schedules not yet connected',
          style: const TextStyle(color: AdminColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final width = constraints.maxWidth / 7;
          return Column(children: [
            Row(children: [
              for (final weekday in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                SizedBox(
                  width: width,
                  child: Center(child: Text(weekday, style: TextStyle(
                    fontSize: compact ? 10 : 12,
                    fontWeight: FontWeight.w700,
                  ))),
                ),
            ]),
            const SizedBox(height: 8),
            for (var week = 0; week < 6; week++)
              Row(children: [
                for (var day = 0; day < 7; day++)
                  _buildDay(
                    context,
                    gridStart.add(Duration(days: week * 7 + day)),
                    entries,
                    width,
                    compact,
                  ),
              ]),
          ]);
        }),
        const SizedBox(height: 18),
        Text(
          'Schedule details · ${MaterialLocalizations.of(context).formatMediumDate(_selected)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (selected.isEmpty)
          const Text('No confirmed counseling appointments on this date.',
              style: TextStyle(color: AdminColors.muted))
        else
          for (final item in selected)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(item.kind == StaffScheduleKind.counseling
                  ? Icons.forum_outlined : Icons.fact_check_outlined),
              title: Text(_detail(context, item)),
              subtitle: Text(item.status),
            ),
        if (!widget.testingSchedulesConnected) ...[
          const SizedBox(height: 10),
          const Text(
            'Testing dates are currently arranged outside MindMate. '
            'They will be plotted after PACC connects an official testing schedule source.',
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
        ],
      ],
    );
  }

  Widget _buildDay(
    BuildContext context,
    DateTime date,
    List<StaffScheduleEntry> all,
    double width,
    bool compact,
  ) {
    final daily = all.where((item) => _sameDay(item.scheduledAt, date)).toList();
    final counseling = daily.where((item) =>
        item.kind == StaffScheduleKind.counseling &&
        const {'confirmed', 'completed', 'complete'}
            .contains(item.status.trim().toLowerCase())).length;
    final pending = daily.where((item) =>
        item.kind == StaffScheduleKind.counseling &&
        const {'requested', 'pending', 'upcoming', 'reschedule_proposed'}
            .contains(item.status.trim().toLowerCase())).length;
    final testing = daily.where((item) => item.kind == StaffScheduleKind.testing).length;
    final active = _sameDay(date, _selected);
    final inMonth = date.month == _month.month && date.year == _month.year;
    final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final hoverText = daily.isEmpty
        ? 'No scheduled appointments'
        : daily.map((item) => _detail(context, item)).join('\n');
    return SizedBox(
      width: width,
      height: compact ? 70 : 100,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Tooltip(
          message: hoverText,
          child: Material(
            color: active ? AdminColors.accentSoft : inMonth
                ? AdminColors.surface : AdminColors.canvas,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: active
                  ? AdminColors.accentStrong : AdminColors.border),
            ),
            child: InkWell(
              key: Key('staff-day-$dateKey'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _selected = date),
              child: Padding(
                padding: EdgeInsets.all(compact ? 3 : 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${date.day}', style: TextStyle(
                      color: inMonth ? AdminColors.ink : AdminColors.muted,
                      fontSize: compact ? 11 : 13,
                      fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                    )),
                    if (counseling > 0)
                      Text(compact ? '$counseling C' : '$counseling counseling',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: compact ? 10 : 11)),
                    if (pending > 0)
                      Text(compact ? '$pending P' : '$pending pending',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: compact ? 10 : 11)),
                    if (widget.testingSchedulesConnected && testing > 0)
                      Text(compact ? '$testing T' : '$testing testing',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: compact ? 10 : 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
