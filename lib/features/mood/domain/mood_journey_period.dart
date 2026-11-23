import 'mood_v2_analytics.dart';

enum MoodJourneyPeriod { week, month }

DateTime moodJourneyStart(MoodJourneyPeriod period, DateTime now) {
  final today = MoodManilaCalendar.dateForKey(
    MoodManilaCalendar.dateKeyForInstant(now),
  );
  return period == MoodJourneyPeriod.month
      ? DateTime.utc(today.year, today.month)
      : today.subtract(Duration(days: today.weekday - 1));
}

bool includesMoodJourneyDate(
  String dateKey,
  MoodJourneyPeriod period,
  DateTime now,
) {
  final start = MoodManilaCalendar.dateKeyForDate(
    moodJourneyStart(period, now),
  );
  final today = MoodManilaCalendar.dateKeyForInstant(now);
  return dateKey.compareTo(start) >= 0 && dateKey.compareTo(today) <= 0;
}

/// Returns the Monday-first Manila calendar week `[startDateKey, endExclusiveDateKey)`
/// containing [calendarDate], treating its year/month/day as a Manila calendar date
/// rather than a UTC or host-timezone instant.
MoodWeekRange moodWeekContainingDate(DateTime calendarDate) {
  final normalized = DateTime.utc(
    calendarDate.year,
    calendarDate.month,
    calendarDate.day,
  );
  final monday = normalized.subtract(Duration(days: normalized.weekday - 1));
  return MoodWeekRange(
    startDateKey: MoodManilaCalendar.dateKeyForDate(monday),
    endExclusiveDateKey: MoodManilaCalendar.dateKeyForDate(
      monday.add(const Duration(days: 7)),
    ),
  );
}

/// Returns the Monday-first Manila calendar week containing [dateKey].
MoodWeekRange moodWeekContainingDateKey(String dateKey) =>
    moodWeekContainingDate(MoodManilaCalendar.dateForKey(dateKey));

/// Returns the calendar month `[YYYY-MM-01, next-month-01)` for [displayedMonth].
MoodWeekRange moodMonthRange(DateTime displayedMonth) {
  final first = DateTime.utc(displayedMonth.year, displayedMonth.month, 1);
  final nextMonth = DateTime.utc(
    displayedMonth.year,
    displayedMonth.month + 1,
    1,
  );
  return MoodWeekRange(
    startDateKey: MoodManilaCalendar.dateKeyForDate(first),
    endExclusiveDateKey: MoodManilaCalendar.dateKeyForDate(nextMonth),
  );
}

/// Returns the full Monday-first calendar grid range for [displayedMonth],
/// starting on the Monday of the row containing the 1st of the month and
/// ending exclusively on the Monday after the Sunday of the row containing the
/// last day of the month.
MoodWeekRange moodVisibleMonthRange(DateTime displayedMonth) {
  final first = DateTime.utc(displayedMonth.year, displayedMonth.month, 1);
  final gridStartMonday = first.subtract(Duration(days: first.weekday - 1));
  final last = DateTime.utc(displayedMonth.year, displayedMonth.month + 1, 0);
  final gridEndExclusiveMonday = last.add(Duration(days: 8 - last.weekday));
  return MoodWeekRange(
    startDateKey: MoodManilaCalendar.dateKeyForDate(gridStartMonday),
    endExclusiveDateKey: MoodManilaCalendar.dateKeyForDate(
      gridEndExclusiveMonday,
    ),
  );
}

/// Returns the intersection of two `[startDateKey, endExclusiveDateKey)` ranges.
/// When the ranges do not overlap, returns an empty range with
/// `startDateKey == endExclusiveDateKey`.
MoodWeekRange intersectMoodRanges(MoodWeekRange a, MoodWeekRange b) {
  final start = a.startDateKey.compareTo(b.startDateKey) >= 0
      ? a.startDateKey
      : b.startDateKey;
  final end = a.endExclusiveDateKey.compareTo(b.endExclusiveDateKey) <= 0
      ? a.endExclusiveDateKey
      : b.endExclusiveDateKey;
  if (start.compareTo(end) >= 0) {
    return MoodWeekRange(startDateKey: start, endExclusiveDateKey: start);
  }
  return MoodWeekRange(startDateKey: start, endExclusiveDateKey: end);
}

bool isMoodRangeEmpty(MoodWeekRange range) =>
    range.startDateKey.compareTo(range.endExclusiveDateKey) >= 0;

/// Picks a valid selected date when switching to [displayedMonth]:
/// today if [displayedMonth] contains [todayDateKey] (and is within [filterRange]
/// when present), otherwise the first available day in the month.
String defaultSelectedDateKeyForMonth({
  required DateTime displayedMonth,
  required String todayDateKey,
  MoodWeekRange? filterRange,
}) {
  final monthRange = moodMonthRange(displayedMonth);
  final effectiveRange = filterRange == null
      ? monthRange
      : intersectMoodRanges(monthRange, filterRange);
  if (!isMoodRangeEmpty(effectiveRange)) {
    if (effectiveRange.includes(todayDateKey)) {
      return todayDateKey;
    }
    return effectiveRange.startDateKey;
  }
  if (monthRange.includes(todayDateKey)) {
    return todayDateKey;
  }
  return monthRange.startDateKey;
}

class MoodLabelFrequency {
  const MoodLabelFrequency({
    required this.label,
    required this.count,
    required this.fraction,
    required this.percentage,
  });

  final String label;
  final int count;
  final double fraction;
  final int percentage;
}

class MoodJourneyRangeSummary {
  const MoodJourneyRangeSummary({
    required this.startInclusiveDateKey,
    required this.endExclusiveDateKey,
    required this.events,
    required this.checkInCount,
    required this.activeDayCount,
    required this.labeledCheckInCount,
    required this.unlabeledCheckInCount,
    required this.labelCounts,
    required this.labelDistribution,
    required this.topLabels,
    required this.topLabelCount,
    required this.isPartial,
  });

  final String startInclusiveDateKey;
  final String endExclusiveDateKey;
  final List<NormalizedMoodEvent> events;
  final int checkInCount;
  final int activeDayCount;
  final int labeledCheckInCount;
  final int unlabeledCheckInCount;
  final Map<String, int> labelCounts;
  final List<MoodLabelFrequency> labelDistribution;
  final List<String> topLabels;
  final int topLabelCount;
  final bool isPartial;

  bool get isTiedTop => topLabels.length > 1;

  bool get isEmptyRange =>
      startInclusiveDateKey.compareTo(endExclusiveDateKey) >= 0;

  int get topLabelPercentage => labeledCheckInCount == 0
      ? 0
      : ((topLabelCount * 100) / labeledCheckInCount).round();
}

const Map<String, String> _canonicalMoodLabels = {
  'great': 'Great',
  'okay': 'Okay',
  'stressed': 'Stressed',
  'sad': 'Sad',
  'angry': 'Angry',
  'tired': 'Tired',
  'excited': 'Excited',
};

/// Summarizes deduplicated events from [window] within
/// `[startInclusiveDateKey, endExclusiveDateKey)`.
/// Never fabricates a mood label for missing or blank labels.
MoodJourneyRangeSummary summarizeMoodRange(
  MoodHistoryWindow window,
  String startInclusiveDateKey,
  String endExclusiveDateKey,
) {
  final isPartial = window.coverage == MoodHistoryCoverage.partial;
  if (startInclusiveDateKey.compareTo(endExclusiveDateKey) >= 0) {
    return MoodJourneyRangeSummary(
      startInclusiveDateKey: startInclusiveDateKey,
      endExclusiveDateKey: endExclusiveDateKey,
      events: const [],
      checkInCount: 0,
      activeDayCount: 0,
      labeledCheckInCount: 0,
      unlabeledCheckInCount: 0,
      labelCounts: const {},
      labelDistribution: const [],
      topLabels: const [],
      topLabelCount: 0,
      isPartial: isPartial,
    );
  }

  final range = MoodWeekRange(
    startDateKey: startInclusiveDateKey,
    endExclusiveDateKey: endExclusiveDateKey,
  );
  final matching = window.uniqueEvents
      .where((event) => range.includes(event.dateKey))
      .toList(growable: false);
  final activeDays = matching.map((event) => event.dateKey).toSet().length;

  final countsByNormalizedKey = <String, int>{};
  final displayByNormalizedKey = <String, String>{};
  var labeledCount = 0;

  for (final event in matching) {
    final raw = event.label?.trim() ?? '';
    if (raw.isEmpty) continue;
    labeledCount++;
    final key = raw.toLowerCase();
    final display =
        _canonicalMoodLabels[key] ?? displayByNormalizedKey[key] ?? raw;
    displayByNormalizedKey[key] = display;
    countsByNormalizedKey[key] = (countsByNormalizedKey[key] ?? 0) + 1;
  }

  final sortedEntries =
      countsByNormalizedKey.entries
          .map((entry) {
            return MapEntry(displayByNormalizedKey[entry.key]!, entry.value);
          })
          .toList(growable: false)
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        });

  final orderedCounts = <String, int>{
    for (final entry in sortedEntries) entry.key: entry.value,
  };
  final topCount = sortedEntries.isEmpty ? 0 : sortedEntries.first.value;
  final topLabels = sortedEntries
      .where((entry) => entry.value == topCount)
      .map((entry) => entry.key)
      .toList(growable: false);
  final distribution = sortedEntries
      .map(
        (entry) => MoodLabelFrequency(
          label: entry.key,
          count: entry.value,
          fraction: labeledCount == 0 ? 0.0 : entry.value / labeledCount,
          percentage: labeledCount == 0
              ? 0
              : ((entry.value * 100) / labeledCount).round(),
        ),
      )
      .toList(growable: false);

  return MoodJourneyRangeSummary(
    startInclusiveDateKey: startInclusiveDateKey,
    endExclusiveDateKey: endExclusiveDateKey,
    events: List.unmodifiable(matching),
    checkInCount: matching.length,
    activeDayCount: activeDays,
    labeledCheckInCount: labeledCount,
    unlabeledCheckInCount: matching.length - labeledCount,
    labelCounts: Map.unmodifiable(orderedCounts),
    labelDistribution: List.unmodifiable(distribution),
    topLabels: List.unmodifiable(topLabels),
    topLabelCount: topCount,
    isPartial: isPartial,
  );
}
