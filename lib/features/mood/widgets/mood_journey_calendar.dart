import 'package:flutter/material.dart';

import '../../home/widgets/home_dashboard_widgets.dart';
import '../domain/mood_journey_period.dart';
import '../domain/mood_v2_analytics.dart';
import 'mood_glyph.dart';

class MoodJourneyCalendar extends StatelessWidget {
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

  static const List<String> _monthNames = [
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
    if (permittedRange == null) return true;
    final currentMonthStart = MoodManilaCalendar.dateKeyForDate(
      DateTime.utc(displayedMonth.year, displayedMonth.month, 1),
    );
    return currentMonthStart.compareTo(permittedRange!.startDateKey) > 0;
  }

  bool get _canGoNext {
    final nextMonthStart = MoodManilaCalendar.dateKeyForDate(
      DateTime.utc(displayedMonth.year, displayedMonth.month + 1, 1),
    );
    if (permittedRange != null &&
        nextMonthStart.compareTo(permittedRange!.endExclusiveDateKey) >= 0) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final visibleRange = moodVisibleMonthRange(displayedMonth);
    final start = MoodManilaCalendar.dateForKey(visibleRange.startDateKey);
    final endExclusive = MoodManilaCalendar.dateForKey(
      visibleRange.endExclusiveDateKey,
    );
    final totalDays = endExclusive.difference(start).inDays;
    final rowCount = totalDays ~/ 7;

    final aggregatesByDay = <String, MoodDailyAggregate>{};
    if (history != null) {
      for (final day in MoodAnalytics.dailyAggregates(history!.uniqueEvents)) {
        if (permittedRange == null || permittedRange!.includes(day.dateKey)) {
          aggregatesByDay[day.dateKey] = day;
        }
      }
    }

    final monthTitle =
        '${_monthNames[displayedMonth.month - 1]} ${displayedMonth.year}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTightWidth = constraints.maxWidth < 310;
        final horizontalPad = isTightWidth ? 2.0 : 8.0;
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;

        return Container(
          key: const Key('mood-journey-calendar'),
          decoration: HomeDecor.card(radius: HomeMetrics.radiusLarge),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPad,
            vertical: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(
                context,
                monthTitle: monthTitle,
                stackToday: isTightWidth && largeText,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final label in _weekdayHeaders)
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
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
              const SizedBox(height: 4),
              for (var row = 0; row < rowCount; row++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: _buildDayCell(
                          context,
                          day: start.add(Duration(days: row * 7 + col)),
                          aggregatesByDay: aggregatesByDay,
                        ),
                      ),
                  ],
                ),
              if (isLoading) ...[
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
              if (errorMessage != null) ...[
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
                        errorMessage!,
                        style: const TextStyle(
                          color: HomePalette.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (onRetry != null)
                        TextButton.icon(
                          key: const Key('mood-calendar-retry'),
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              ],
              if (history != null &&
                  history!.coverage == MoodHistoryCoverage.partial) ...[
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
                    if (onRetry != null && errorMessage == null)
                      TextButton(
                        key: const Key('mood-calendar-partial-retry'),
                        onPressed: onRetry,
                        child: const Text('Retry full month'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              _buildLegend(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required String monthTitle,
    required bool stackToday,
  }) {
    final prevButton = IconButton(
      key: const Key('mood-calendar-prev-month'),
      tooltip: 'Previous month',
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.chevron_left),
      color: HomePalette.text,
      onPressed: _canGoPrevious
          ? () => onMonthChanged(
              DateTime.utc(displayedMonth.year, displayedMonth.month - 1, 1),
            )
          : null,
    );

    final nextButton = IconButton(
      key: const Key('mood-calendar-next-month'),
      tooltip: 'Next month',
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.chevron_right),
      color: HomePalette.text,
      onPressed: _canGoNext
          ? () => onMonthChanged(
              DateTime.utc(displayedMonth.year, displayedMonth.month + 1, 1),
            )
          : null,
    );

    final todayButton = TextButton(
      key: const Key('mood-calendar-today-button'),
      onPressed: onTodayPressed,
      style: TextButton.styleFrom(
        foregroundColor: HomePalette.text,
        backgroundColor: HomePalette.surfaceWarm,
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

    if (stackToday) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              prevButton,
              Expanded(
                child: Text(
                  monthTitle,
                  key: const Key('mood-calendar-month-title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: HomePalette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              nextButton,
            ],
          ),
          Align(alignment: Alignment.centerRight, child: todayButton),
        ],
      );
    }

    return Row(
      children: [
        prevButton,
        Expanded(
          child: Text(
            monthTitle,
            key: const Key('mood-calendar-month-title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HomePalette.text,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        nextButton,
        const SizedBox(width: 4),
        todayButton,
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
        day.year == displayedMonth.year && day.month == displayedMonth.month;
    final isSelected = dateKey == selectedDateKey;
    final isToday = dateKey == todayDateKey;
    final isFuture = dateKey.compareTo(todayDateKey) > 0;
    final isOutOfPermittedRange =
        permittedRange != null && !permittedRange!.includes(dateKey);
    final isInteractive = !isFuture && !isOutOfPermittedRange;

    final aggregate = aggregatesByDay[dateKey];
    final checkInCount = aggregate?.entryCount ?? 0;
    final latestEvent = aggregate?.latestEvent;
    final isUnknownState =
        history == null && (isLoading || errorMessage != null);

    final semanticParts = <String>[
      '${_fullWeekdayNames[day.weekday - 1]}, ${_shortMonthNames[day.month - 1]} ${day.day}, ${day.year}',
      if (isToday) 'today',
      if (!isInDisplayedMonth) 'outside current month',
      if (isFuture)
        'future date'
      else if (isOutOfPermittedRange)
        'outside selected academic period'
      else if (isUnknownState)
        isLoading ? 'loading check-ins' : 'check-ins unavailable'
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
      backgroundColor = HomePalette.softGold.withValues(alpha: 0.36);
    } else if (isToday) {
      backgroundColor = HomePalette.surfaceWarm;
    } else if (checkInCount > 0 && isInDisplayedMonth) {
      backgroundColor = HomePalette.surfaceWarm.withValues(alpha: 0.7);
    } else {
      backgroundColor = Colors.transparent;
    }

    final BoxBorder? border;
    if (isSelected) {
      border = Border.all(color: HomePalette.sun, width: 2.0);
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

    return Semantics(
      container: true,
      button: isInteractive,
      selected: isSelected,
      enabled: isInteractive,
      label: semanticParts.join(', '),
      child: ExcludeSemantics(
        child: GestureDetector(
          key: Key('mood-calendar-day-$dateKey'),
          behavior: HitTestBehavior.opaque,
          onTap: isInteractive
              ? () {
                  if (!isInDisplayedMonth) {
                    onMonthChanged(DateTime.utc(day.year, day.month, 1));
                  }
                  onDaySelected(dateKey);
                }
              : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 48),
            child: AnimatedContainer(
              duration: HomeMotion.duration(context, 140),
              margin: const EdgeInsets.all(1.5),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
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
                        fontSize: 13,
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
                  if (checkInCount > 0)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MoodGlyphIcon(label: latestEvent?.label, size: 16),
                          if (checkInCount > 1) ...[
                            const SizedBox(width: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: HomePalette.sun.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '+${checkInCount - 1}',
                                style: const TextStyle(
                                  color: HomePalette.text,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    const SizedBox(height: 16),
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
              color: HomePalette.softGold.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: HomePalette.sun, width: 1.8),
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
          label: 'Today',
        ),
        _legendItem(
          marker: const Icon(Icons.circle, size: 10, color: HomePalette.gold),
          label: 'Logged mood',
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
        Text(
          label,
          style: const TextStyle(
            color: HomePalette.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
