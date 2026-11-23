import 'package:flutter/material.dart';

import '../../home/widgets/home_dashboard_widgets.dart';
import '../../home/widgets/streak_flame.dart';
import '../domain/mood_journey_period.dart';
import '../domain/mood_v2_analytics.dart';
import '../domain/mood_week_recap.dart';
import 'mood_glyph.dart';
import 'mood_week_recap_cards.dart';

class MoodJourneySummary extends StatelessWidget {
  const MoodJourneySummary({
    super.key,
    required this.history,
    required this.now,
    this.streakHistory,
    this.selectedDateKey,
    this.displayedMonth,
    this.academicFilterRange,
    this.academicFilterLabel,
    this.showWeekRecap = false,
    this.period,
    this.onPeriodChanged,
    this.milestoneDays,
  });

  final MoodHistoryWindow history;
  final MoodHistoryWindow? streakHistory;
  final DateTime now;
  final String? selectedDateKey;
  final DateTime? displayedMonth;
  final MoodWeekRange? academicFilterRange;
  final String? academicFilterLabel;
  final bool showWeekRecap;
  final MoodJourneyPeriod? period;
  final ValueChanged<MoodJourneyPeriod>? onPeriodChanged;

  /// Set when opened from the Home milestone "View recap" (item 38).
  final int? milestoneDays;

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

  @override
  Widget build(BuildContext context) {
    final todayKey = MoodManilaCalendar.dateKeyForInstant(now);
    final effectiveSelectedKey = selectedDateKey ?? todayKey;
    final selectedDate = MoodManilaCalendar.dateForKey(effectiveSelectedKey);
    final effectiveMonth =
        displayedMonth ??
        DateTime.utc(selectedDate.year, selectedDate.month, 1);

    final rawWeekRange = moodWeekContainingDateKey(effectiveSelectedKey);
    final effectiveWeekRange = academicFilterRange == null
        ? rawWeekRange
        : intersectMoodRanges(rawWeekRange, academicFilterRange!);
    final weekSummary = summarizeMoodRange(
      history,
      effectiveWeekRange.startDateKey,
      effectiveWeekRange.endExclusiveDateKey,
    );

    final rawMonthRange = moodMonthRange(effectiveMonth);
    final effectiveMonthRange = academicFilterRange == null
        ? rawMonthRange
        : intersectMoodRanges(rawMonthRange, academicFilterRange!);
    final monthSummary = summarizeMoodRange(
      history,
      effectiveMonthRange.startDateKey,
      effectiveMonthRange.endExclusiveDateKey,
    );

    final streakSource = streakHistory ?? history;
    final streak = MoodAnalytics.streak(streakSource, referenceInstant: now);

    final weekStart = MoodManilaCalendar.dateForKey(rawWeekRange.startDateKey);
    final weekEndInclusive = MoodManilaCalendar.dateForKey(
      rawWeekRange.endExclusiveDateKey,
    ).subtract(const Duration(days: 1));
    final localizations = MaterialLocalizations.of(context);
    final weekTitle =
        'Week of ${localizations.formatShortMonthDay(weekStart)} – ${localizations.formatShortMonthDay(weekEndInclusive)}';
    final monthTitle = '${_monthNames[effectiveMonth.month - 1]} at a glance';

    final rawRecap = MoodWeekRecap.from(weekSummary.events);
    final safeRecap = weekSummary.isPartial
        ? MoodWeekRecap(bestDay: null, tip: rawRecap.tip)
        : rawRecap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (milestoneDays case final days?) ...[
          _MilestoneBanner(days: days),
          const SizedBox(height: 12),
        ],
        _SummaryPeriodCard(
          cardKey: const Key('mood-selected-week-card'),
          title: weekTitle,
          filterSubtitle: academicFilterLabel,
          summary: weekSummary,
          emptyLabel: 'Your feelings, at your pace',
          isMonthOverview: false,
        ),
        const SizedBox(height: 12),
        _SummaryPeriodCard(
          cardKey: const Key('mood-month-overview-card'),
          title: monthTitle,
          filterSubtitle: academicFilterLabel,
          summary: monthSummary,
          emptyLabel: 'No mood check-ins recorded in this month yet.',
          isMonthOverview: true,
        ),
        const SizedBox(height: 12),
        Container(
          key: const Key('mood-streak-card'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: HomePalette.sun, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: HomePalette.sun.withValues(alpha: .24),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              StreakFlame(days: streak.currentDays, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mood Streak',
                      style: TextStyle(
                        fontSize: 16,
                        color: HomePalette.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${streak.currentDays} ${streak.currentDays == 1 ? 'day' : 'days'}',
                      style: const TextStyle(
                        fontSize: 26,
                        color: HomePalette.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showWeekRecap) MoodWeekRecapCards(recap: safeRecap),
      ],
    );
  }
}

class _SummaryPeriodCard extends StatelessWidget {
  const _SummaryPeriodCard({
    required this.cardKey,
    required this.title,
    required this.summary,
    required this.emptyLabel,
    required this.isMonthOverview,
    this.filterSubtitle,
  });

  final Key cardKey;
  final String title;
  final String? filterSubtitle;
  final MoodJourneyRangeSummary summary;
  final String emptyLabel;
  final bool isMonthOverview;

  String _countsText() {
    final checkIns =
        '${summary.checkInCount} check-in${summary.checkInCount == 1 ? '' : 's'}';
    final activeDays =
        '${summary.activeDayCount} mood-active day${summary.activeDayCount == 1 ? '' : 's'}';
    return isMonthOverview
        ? '$activeDays · $checkIns'
        : '$checkIns · $activeDays';
  }

  String _headlineText() {
    if (summary.topLabels.isEmpty) {
      if (summary.checkInCount > 0 && summary.labeledCheckInCount == 0) {
        return 'No mood labels recorded for these check-ins.';
      }
      return emptyLabel;
    }
    final partialQualifier = summary.isPartial ? ' (loaded entries)' : '';
    final prefix = isMonthOverview ? 'Top logged mood' : 'Most logged mood';
    if (summary.isTiedTop) {
      return '${prefix}s are tied: ${summary.topLabels.join(', ')}$partialQualifier';
    }
    return '$prefix$partialQualifier: ${summary.topLabels.single}';
  }

  void _showPercentageGuide(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How percentages work'),
        content: const Text(
          'Each mood’s share compares its check-ins with all check-ins with a mood label in this week or month. Multiple check-ins on the same day count separately.\n\n'
          'For example, if 2 of 5 labeled check-ins were Okay, the row shows 2 (40%). Percentages are rounded to whole numbers. If some history is missing, only loaded check-ins are used.',
        ),
        scrollable: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final distributions = summary.labelDistribution.take(4).toList();
    return Container(
      key: cardKey,
      decoration: HomeDecor.card(shadowColor: const Color(0x090F0B05)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: HomePalette.surfaceWarm,
                  borderRadius: BorderRadius.circular(HomeMetrics.radiusSmall),
                ),
                child: Icon(
                  isMonthOverview
                      ? Icons.calendar_month_outlined
                      : Icons.view_week_outlined,
                  color: HomePalette.text,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: HomePalette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (distributions.isNotEmpty)
                IconButton(
                  tooltip: 'How mood percentages are calculated',
                  onPressed: () => _showPercentageGuide(context),
                  icon: const Icon(
                    Icons.info_outline,
                    color: HomePalette.muted,
                  ),
                ),
            ],
          ),
          if (filterSubtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              filterSubtitle!,
              style: const TextStyle(
                color: HomePalette.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.event_available_outlined,
                color: HomePalette.gold,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _countsText(),
                  style: const TextStyle(
                    color: HomePalette.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _headlineText(),
            style: const TextStyle(
              color: HomePalette.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (distributions.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final item in distributions) ...[
              _MoodDistributionRow(item: item),
              const SizedBox(height: 6),
            ],
          ],
          if (summary.isPartial)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Based on loaded entries',
                style: TextStyle(
                  color: HomePalette.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoodDistributionRow extends StatelessWidget {
  const _MoodDistributionRow({required this.item});

  final MoodLabelFrequency item;

  @override
  Widget build(BuildContext context) {
    final accent = MoodGlyphIcon.accentForLabel(item.label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 2,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoodGlyphIcon(label: item.label, size: 18),
                const SizedBox(width: 6),
                Text(
                  item.label,
                  style: const TextStyle(
                    color: HomePalette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Text(
              '${item.count} (${item.percentage}%)',
              style: const TextStyle(
                color: HomePalette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: item.fraction.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: HomePalette.surfaceWarm,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
      ],
    );
  }
}

class _MilestoneBanner extends StatelessWidget {
  const _MilestoneBanner({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [HomePalette.softGold, HomePalette.sun],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0x269A7000)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        "🔥 $days-day streak · Here's your week in moods",
        style: const TextStyle(
          color: HomePalette.text,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
