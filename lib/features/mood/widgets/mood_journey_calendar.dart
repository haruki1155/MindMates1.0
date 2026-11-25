import 'package:flutter/material.dart';

import '../../home/widgets/home_dashboard_widgets.dart';
import '../domain/mood_journey_period.dart';
import '../domain/mood_v2_analytics.dart';
import 'mood_glyph.dart';

class MoodJourneyCalendar extends StatefulWidget {
  const MoodJourneyCalendar({
    super.key,
    required this.displayedMonth,
    required this.selectedDateKey,
    required this.todayDateKey,
    required this.history,
    required this.onMonthChanged,
    required this.onDaySelected,
    required this.onTodayPressed,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.permittedRange,
    this.filters,
    this.expanded = false,
    this.onExpand,
    this.collapsedToWeek = false,
  });

  final DateTime displayedMonth;
  final String selectedDateKey;
  final String todayDateKey;
  final MoodHistoryWindow? history;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<String> onDaySelected;
  final VoidCallback onTodayPressed;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final MoodWeekRange? permittedRange;
  final Widget? filters;
  final bool expanded;
  final VoidCallback? onExpand;

  /// Shows only the week row holding the selected day (or the month's first
  /// week when that day is outside the displayed month).
  final bool collapsedToWeek;

  @override
  State<MoodJourneyCalendar> createState() => _MoodJourneyCalendarState();
}

class _MoodJourneyCalendarState extends State<MoodJourneyCalendar> {
  String? _pulseDateKey;
  int _pulseVersion = 0;

  static const List<String> _shortMonthNames = [
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

  static const List<String> _weekdayHeaders = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> _fullWeekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  bool get _canGoPrevious {
    if (widget.permittedRange == null) return true;
    final currentMonthStart = MoodManilaCalendar.dateKeyForDate(
      DateTime.utc(widget.displayedMonth.year, widget.displayedMonth.month, 1),
    );
    return currentMonthStart.compareTo(widget.permittedRange!.startDateKey) > 0;
  }

  bool get _canGoNext {
    final nextMonthStart = MoodManilaCalendar.dateKeyForDate(
      DateTime.utc(
        widget.displayedMonth.year,
        widget.displayedMonth.month + 1,
        1,
      ),
    );
    if (widget.permittedRange != null &&
        nextMonthStart.compareTo(widget.permittedRange!.endExclusiveDateKey) >=
            0) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final visibleRange = moodVisibleMonthRange(widget.displayedMonth);
    final start = MoodManilaCalendar.dateForKey(visibleRange.startDateKey);
    final endExclusive = MoodManilaCalendar.dateForKey(
      visibleRange.endExclusiveDateKey,
    );
    final totalDays = endExclusive.difference(start).inDays;
    final rowCount = totalDays ~/ 7;
    final selectedOffset = MoodManilaCalendar.dateForKey(
      widget.selectedDateKey,
    ).difference(start).inDays;
    final weekRow = selectedOffset >= 0 && selectedOffset < totalDays
        ? selectedOffset ~/ 7
        : 0;
    final visibleRows = widget.collapsedToWeek
        ? [weekRow]
        : [for (var row = 0; row < rowCount; row++) row];

    final aggregatesByDay = <String, MoodDailyAggregate>{};
    if (widget.history != null) {
      for (final day in MoodAnalytics.dailyAggregates(
        widget.history!.uniqueEvents,
      )) {
        if (widget.permittedRange == null ||
            widget.permittedRange!.includes(day.dateKey)) {
          aggregatesByDay[day.dateKey] = day;
        }
      }
    }

    final monthTitle = MaterialLocalizations.of(
      context,
    ).formatMonthYear(widget.displayedMonth);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTightWidth = constraints.maxWidth < 310;
        final horizontalPad = isTightWidth ? 2.0 : 8.0;
        final scaler = MediaQuery.textScalerOf(context);
        final dayHeight = (scaler.scale(14) + scaler.scale(10) + 14).clamp(
          widget.expanded ? 52.0 : 44.0,
          double.infinity,
        );

        return Container(
          key: const Key('mood-journey-calendar'),
          decoration: HomeDecor.card(
            radius: HomeMetrics.radiusLarge,
            shadowColor: const Color(0x090F0B05),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPad,
            vertical: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: HomePalette.surfaceWarm,
                  borderRadius: BorderRadius.circular(HomeMetrics.radiusSmall),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildHeader(monthTitle),
                ),
              ),
              const Divider(height: 16, color: HomePalette.outline),
              Row(
                children: [
                  for (final label in _weekdayHeaders)
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: HomePalette.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              for (final row in visibleRows)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: SizedBox(
                          height: dayHeight,
                          child: _buildDayCell(
                            context,
                            day: start.add(Duration(days: row * 7 + col)),
                            aggregatesByDay: aggregatesByDay,
                          ),
                        ),
                      ),
                  ],
                ),
              if (widget.isLoading) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    key: const Key('mood-calendar-loading'),
                    children: const [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Loading month check-ins…',
                          style: TextStyle(
                            color: HomePalette.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: const Key('mood-calendar-error'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: HomePalette.surfaceWarm,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: HomePalette.outlineStrong),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.errorMessage!,
                        style: const TextStyle(
                          color: HomePalette.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (widget.onRetry != null)
                        TextButton.icon(
                          key: const Key('mood-calendar-retry'),
                          onPressed: widget.onRetry,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              ],
              if (widget.history != null &&
                  widget.history!.coverage == MoodHistoryCoverage.partial) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Based on loaded entries',
                      key: Key('mood-calendar-partial-notice'),
                      style: TextStyle(
                        color: HomePalette.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.onRetry != null && widget.errorMessage == null)
                      TextButton(
                        key: const Key('mood-calendar-partial-retry'),
                        onPressed: widget.onRetry,
                        child: const Text('Retry full month'),
                      ),
                  ],
                ),
              ],
              const Divider(height: 16, color: HomePalette.outline),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildLegend(),
              ),
              if (widget.filters != null) ...[
                const Divider(height: 16, color: HomePalette.outline),
                widget.filters!,
              ],
            ],
          ),
        );
      },
    );
  }

  /// Week view: the same weekday one week earlier, if allowed.
  String? get _previousWeekKey {
    final key = MoodManilaCalendar.dateKeyForDate(
      MoodManilaCalendar.dateForKey(
        widget.selectedDateKey,
      ).subtract(const Duration(days: 7)),
    );
    final range = widget.permittedRange;
    return range == null || key.compareTo(range.startDateKey) >= 0 ? key : null;
  }

  /// Week view: one week later, or today when that week is the current one;
  /// null once the current week is shown.
  String? get _nextWeekKey {
    final selected = MoodManilaCalendar.dateForKey(widget.selectedDateKey);
    final today = MoodManilaCalendar.dateForKey(widget.todayDateKey);
    DateTime weekStart(DateTime d) =>
        d.subtract(Duration(days: d.weekday - DateTime.monday));
    if (!weekStart(today).isAfter(weekStart(selected))) return null;
    final next = selected.add(const Duration(days: 7));
    final key = MoodManilaCalendar.dateKeyForDate(
      next.isAfter(today) ? today : next,
    );
    final range = widget.permittedRange;
    return range == null || key.compareTo(range.endExclusiveDateKey) < 0
        ? key
        : null;
  }

  Widget _buildHeader(String monthTitle) {
    final weekView = widget.collapsedToWeek;
    final previousWeek = weekView ? _previousWeekKey : null;
    final nextWeek = weekView ? _nextWeekKey : null;
    final prevButton = IconButton(
      key: const Key('mood-calendar-prev-month'),
      tooltip: weekView ? 'Previous week' : 'Previous month',
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.chevron_left),
      color: HomePalette.text,
      onPressed: weekView
          ? (previousWeek == null
                ? null
                : () => widget.onDaySelected(previousWeek))
          : _canGoPrevious
          ? () => widget.onMonthChanged(
              DateTime.utc(
                widget.displayedMonth.year,
                widget.displayedMonth.month - 1,
                1,
              ),
            )
          : null,
    );

    final nextButton = IconButton(
      key: const Key('mood-calendar-next-month'),
      tooltip: weekView ? 'Next week' : 'Next month',
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.chevron_right),
      color: HomePalette.text,
      onPressed: weekView
          ? (nextWeek == null ? null : () => widget.onDaySelected(nextWeek))
          : _canGoNext
          ? () => widget.onMonthChanged(
              DateTime.utc(
                widget.displayedMonth.year,
                widget.displayedMonth.month + 1,
                1,
              ),
            )
          : null,
    );

    final todayButton = TextButton(
      key: const Key('mood-calendar-today-button'),
      onPressed: widget.onTodayPressed,
      style: TextButton.styleFrom(
        foregroundColor: HomePalette.text,
        backgroundColor: HomePalette.surface,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(44, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: HomePalette.outlineStrong),
        ),
      ),
      child: const Text(
        'Today',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            prevButton,
            Expanded(
              child: Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  monthTitle,
                  key: const Key('mood-calendar-month-title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: HomePalette.text,
                    fontSize: 19,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            nextButton,
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 4, 3),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Tap a date to see your check-ins.',
                  style: TextStyle(color: HomePalette.muted, fontSize: 12),
                ),
              ),
              if (widget.onExpand != null)
                IconButton(
                  tooltip: 'Open full calendar',
                  icon: const Icon(Icons.calendar_month, size: 20),
                  onPressed: widget.onExpand,
                ),
              todayButton,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayCell(
    BuildContext context, {
    required DateTime day,
    required Map<String, MoodDailyAggregate> aggregatesByDay,
  }) {
    final dateKey = MoodManilaCalendar.dateKeyForDate(day);
    final isInDisplayedMonth =
        day.year == widget.displayedMonth.year &&
        day.month == widget.displayedMonth.month;
    final isSelected = dateKey == widget.selectedDateKey;
    final isToday = dateKey == widget.todayDateKey;
    final isFuture = dateKey.compareTo(widget.todayDateKey) > 0;
    final isOutOfPermittedRange =
        widget.permittedRange != null &&
        !widget.permittedRange!.includes(dateKey);
    final isInteractive = !isFuture && !isOutOfPermittedRange;

    final aggregate = aggregatesByDay[dateKey];
    final checkInCount = aggregate?.entryCount ?? 0;
    final latestEvent = aggregate?.latestEvent;
    final isUnknownState = widget.history == null;

    final semanticParts = <String>[
      '${_fullWeekdayNames[day.weekday - 1]}, ${_shortMonthNames[day.month - 1]} ${day.day}, ${day.year}',
      if (isToday) 'today',
      if (!isInDisplayedMonth) 'outside current month',
      if (isFuture)
        'future date'
      else if (isOutOfPermittedRange)
        'outside selected academic period'
      else if (isUnknownState)
        widget.errorMessage != null
            ? 'check-ins unavailable'
            : 'loading check-ins'
      else if (checkInCount == 0)
        'no check-ins'
      else if (checkInCount == 1)
        '1 check-in${latestEvent?.label?.trim().isNotEmpty == true ? ' (${latestEvent!.label!.trim()})' : ''}'
      else
        '$checkInCount check-ins${latestEvent?.label?.trim().isNotEmpty == true ? ', latest ${latestEvent!.label!.trim()}' : ''}',
      if (isSelected) 'selected',
    ];

    final Color backgroundColor;
    if (isSelected) {
      backgroundColor = HomePalette.softGold;
    } else if (isToday) {
      backgroundColor = HomePalette.surfaceWarm;
    } else if (checkInCount > 0 && isInDisplayedMonth) {
      backgroundColor = HomePalette.surfaceWarm.withValues(alpha: 0.7);
    } else {
      backgroundColor = Colors.transparent;
    }

    final BoxBorder? border;
    if (isSelected) {
      border = Border.all(color: HomePalette.mutedGold);
    } else if (isToday) {
      border = Border.all(color: HomePalette.outlineStrong, width: 1.5);
    } else if (checkInCount > 0 && isInDisplayedMonth) {
      border = Border.all(color: HomePalette.outline);
    } else {
      border = null;
    }

    final Color textColor;
    if (!isInteractive) {
      textColor = HomePalette.muted.withValues(alpha: 0.42);
    } else if (!isInDisplayedMonth) {
      textColor = HomePalette.muted.withValues(alpha: 0.65);
    } else {
      textColor = HomePalette.text;
    }

    final pulseDuration = HomeMotion.duration(context, 260);
    final moodGlyph = MoodGlyphIcon(label: latestEvent?.label, size: 14);
    void selectDay() {
      if (checkInCount > 0 && pulseDuration != Duration.zero) {
        setState(() {
          _pulseDateKey = dateKey;
          _pulseVersion++;
        });
      }
      if (!isInDisplayedMonth) {
        widget.onMonthChanged(DateTime.utc(day.year, day.month, 1));
      }
      widget.onDaySelected(dateKey);
    }

    return Semantics(
      container: true,
      button: isInteractive,
      onTap: isInteractive ? selectDay : null,
      selected: isSelected,
      enabled: isInteractive,
      label: semanticParts.join(', '),
      child: ExcludeSemantics(
        child: InkWell(
          key: Key('mood-calendar-day-$dateKey'),
          borderRadius: BorderRadius.circular(10),
          onTap: isInteractive ? selectDay : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            child: AnimatedContainer(
              duration: HomeMotion.duration(context, 140),
              margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: border,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        height: 1.1,
                        fontWeight: isSelected || isToday || checkInCount > 0
                            ? FontWeight.w900
                            : FontWeight.w600,
                        decoration: isToday && !isSelected
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: MediaQuery.textScalerOf(
                      context,
                    ).scale(10).clamp(14.0, double.infinity),
                    child: checkInCount == 0
                        ? null
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_pulseDateKey == dateKey)
                                  TweenAnimationBuilder<double>(
                                    key: ValueKey(_pulseVersion),
                                    tween: Tween(begin: 0.7, end: 1.0),
                                    duration: pulseDuration,
                                    curve: Curves.easeOutBack,
                                    child: moodGlyph,
                                    builder: (_, scale, child) =>
                                        Transform.scale(
                                          scale: scale,
                                          child: child,
                                        ),
                                  )
                                else
                                  moodGlyph,
                                if (checkInCount > 1) ...[
                                  const SizedBox(width: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 0.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: HomePalette.sun.withValues(
                                        alpha: 0.45,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '+${checkInCount - 1}',
                                      style: const TextStyle(
                                        color: HomePalette.text,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _legendItem(
          marker: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: HomePalette.softGold,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: HomePalette.mutedGold),
            ),
          ),
          label: 'Selected day',
        ),
        _legendItem(
          marker: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: HomePalette.surfaceWarm,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: HomePalette.outlineStrong, width: 1.4),
            ),
          ),
          label: 'Current date',
        ),
        _legendItem(
          marker: const MoodGlyphIcon(label: 'Okay', size: 14),
          label: 'Mood check-in',
        ),
      ],
    );
  }

  Widget _legendItem({required Widget marker, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        marker,
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: HomePalette.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
