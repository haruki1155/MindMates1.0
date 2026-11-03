import '../../../models/mood_model.dart';

/// All Mood V2 calendar calculations use the product's fixed Manila boundary,
/// never the host/device time zone.
class MoodManilaCalendar {
  const MoodManilaCalendar._();

  static const timezone = 'Asia/Manila';
  static const _offset = Duration(hours: 8);

  static String dateKeyForInstant(DateTime instant) {
    final manila = instant.toUtc().add(_offset);
    return '${manila.year.toString().padLeft(4, '0')}-'
        '${manila.month.toString().padLeft(2, '0')}-'
        '${manila.day.toString().padLeft(2, '0')}';
  }

  /// A UTC midnight representation of a Manila calendar date. It is only used
  /// for date ordering/arithmetic; it is not an event timestamp.
  static DateTime dateForKey(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) throw FormatException('Invalid Manila date key.');
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      throw FormatException('Invalid Manila date key.');
    }
    final value = DateTime.utc(year, month, day);
    if (dateKeyForDate(value) != dateKey) {
      throw FormatException('Invalid Manila date key.');
    }
    return value;
  }

  static String dateKeyForDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static MoodWeekRange weekContaining(DateTime referenceInstant) {
    final reference = dateForKey(dateKeyForInstant(referenceInstant));
    final monday = reference.subtract(Duration(days: reference.weekday - 1));
    return MoodWeekRange(
      startDateKey: dateKeyForDate(monday),
      endExclusiveDateKey: dateKeyForDate(monday.add(const Duration(days: 7))),
    );
  }
}

enum MoodEventSource { legacy, v2 }

enum MoodHistoryCoverage { complete, partial }

/// Immutable event returned by either the new Mood V2 reader or the legacy
/// compatibility adapter. Notes remain on the event but are never required by
/// aggregation APIs.
class NormalizedMoodEvent {
  const NormalizedMoodEvent({
    required this.id,
    required this.userId,
    required this.level,
    required this.dateKey,
    required this.occurredAt,
    required this.source,
    this.label,
    this.note,
    this.entryMethod,
    this.clientRequestId,
  }) : assert(level >= 1 && level <= 5);

  final String id;
  final String userId;
  final int level;
  final String dateKey;
  final DateTime occurredAt;
  final MoodEventSource source;
  final String? label;
  final String? note;
  final String? entryMethod;
  final String? clientRequestId;

  /// Stable across pagination and prevents only exact source/identity repeats.
  String get stableIdentity => '${source.name}:$id';

  factory NormalizedMoodEvent.fromLegacy(MoodModel mood) {
    return NormalizedMoodEvent(
      id: mood.id,
      userId: mood.userId ?? '',
      level: mood.level,
      dateKey: (mood.dateKey ?? '').trim().isEmpty
          ? MoodManilaCalendar.dateKeyForInstant(mood.createdAt)
          : mood.dateKey!.trim(),
      occurredAt: mood.createdAt,
      source: MoodEventSource.legacy,
      label: mood.label,
      note: mood.note,
      entryMethod: mood.entryMethod,
    );
  }
}

/// The immutable V2 persistence payload after a trusted server write.
class MoodV2Event {
  const MoodV2Event({
    required this.id,
    required this.userId,
    required this.level,
    required this.dateKey,
    required this.occurredAt,
    required this.clientRequestId,
    this.label,
    this.note,
    this.entryMethod,
  }) : assert(level >= 1 && level <= 5);

  final String id;
  final String userId;
  final int level;
  final String dateKey;
  final DateTime occurredAt;
  final String clientRequestId;
  final String? label;
  final String? note;
  final String? entryMethod;

  NormalizedMoodEvent toNormalized() => NormalizedMoodEvent(
    id: id,
    userId: userId,
    level: level,
    dateKey: dateKey,
    occurredAt: occurredAt,
    source: MoodEventSource.v2,
    label: label,
    note: note,
    entryMethod: entryMethod,
    clientRequestId: clientRequestId,
  );
}

class MoodHistoryWindow {
  const MoodHistoryWindow({
    required this.events,
    required this.coverage,
  });

  final List<NormalizedMoodEvent> events;
  final MoodHistoryCoverage coverage;

  List<NormalizedMoodEvent> get uniqueEvents {
    final byIdentity = <String, NormalizedMoodEvent>{};
    for (final event in events) {
      byIdentity.putIfAbsent(event.stableIdentity, () => event);
    }
    final values = byIdentity.values.toList(growable: false)
      ..sort((a, b) {
        final time = a.occurredAt.compareTo(b.occurredAt);
        return time != 0 ? time : a.stableIdentity.compareTo(b.stableIdentity);
      });
    return values;
  }
}

class MoodWeekRange {
  const MoodWeekRange({
    required this.startDateKey,
    required this.endExclusiveDateKey,
  });

  final String startDateKey;
  final String endExclusiveDateKey;

  bool includes(String dateKey) =>
      dateKey.compareTo(startDateKey) >= 0 &&
      dateKey.compareTo(endExclusiveDateKey) < 0;
}

class MoodLevelDistribution {
  const MoodLevelDistribution(this.counts);

  final Map<int, int> counts;

  int get total => counts.values.fold(0, (sum, count) => sum + count);

  int operator [](int level) => counts[level] ?? 0;
}

class MoodDailyAggregate {
  const MoodDailyAggregate({
    required this.dateKey,
    required this.events,
    required this.distribution,
  });

  final String dateKey;
  final List<NormalizedMoodEvent> events;
  final MoodLevelDistribution distribution;

  int get entryCount => events.length;
  bool get isMoodActiveDay => events.isNotEmpty;
  NormalizedMoodEvent? get latestEvent => events.isEmpty ? null : events.last;
}

class MoodWeeklyAggregate {
  const MoodWeeklyAggregate({
    required this.range,
    required this.daily,
    required this.distribution,
    required this.coverage,
  });

  final MoodWeekRange range;
  final List<MoodDailyAggregate> daily;
  final MoodLevelDistribution distribution;
  final MoodHistoryCoverage coverage;

  int get entryCount => daily.fold(0, (sum, day) => sum + day.entryCount);
  int get activeDayCount => daily.where((day) => day.isMoodActiveDay).length;
}

class MoodStreakSummary {
  const MoodStreakSummary({
    required this.currentDays,
    required this.longestDays,
    required this.coverage,
  });

  final int currentDays;
  final int longestDays;
  final MoodHistoryCoverage coverage;

  bool get isLongestWindowed => coverage == MoodHistoryCoverage.partial;
}

class MoodAnalyticsSnapshot {
  const MoodAnalyticsSnapshot({
    required this.daily,
    required this.weekly,
    required this.streak,
    required this.coverage,
  });

  final List<MoodDailyAggregate> daily;
  final MoodWeeklyAggregate weekly;
  final MoodStreakSummary streak;
  final MoodHistoryCoverage coverage;

  int get eventCount => daily.fold(0, (sum, day) => sum + day.entryCount);
  int get activeDayCount => daily.length;
}

class MoodAnalytics {
  const MoodAnalytics._();

  static MoodAnalyticsSnapshot summarize(
    MoodHistoryWindow window, {
    required DateTime referenceInstant,
  }) {
    final daily = dailyAggregates(window.uniqueEvents);
    final week = MoodManilaCalendar.weekContaining(referenceInstant);
    final weeklyEvents = window.uniqueEvents
        .where((event) => week.includes(event.dateKey))
        .toList(growable: false);
    return MoodAnalyticsSnapshot(
      daily: daily,
      weekly: MoodWeeklyAggregate(
        range: week,
        daily: dailyAggregates(weeklyEvents),
        distribution: _distribution(weeklyEvents),
        coverage: window.coverage,
      ),
      streak: streak(window, referenceInstant: referenceInstant),
      coverage: window.coverage,
    );
  }

  static List<MoodDailyAggregate> dailyAggregates(
    Iterable<NormalizedMoodEvent> events,
  ) {
    final grouped = <String, List<NormalizedMoodEvent>>{};
    for (final event in events) {
      grouped.putIfAbsent(event.dateKey, () => []).add(event);
    }
    final keys = grouped.keys.toList()..sort();
    return keys.map((key) {
      final entries = grouped[key]!..sort((a, b) {
        final time = a.occurredAt.compareTo(b.occurredAt);
        return time != 0 ? time : a.stableIdentity.compareTo(b.stableIdentity);
      });
      return MoodDailyAggregate(
        dateKey: key,
        events: List.unmodifiable(entries),
        distribution: _distribution(entries),
      );
    }).toList(growable: false);
  }

  static MoodStreakSummary streak(
    MoodHistoryWindow window, {
    required DateTime referenceInstant,
  }) {
    final keys = dailyAggregates(window.uniqueEvents)
        .map((day) => day.dateKey)
        .toList(growable: false);
    if (keys.isEmpty) {
      return MoodStreakSummary(
        currentDays: 0,
        longestDays: 0,
        coverage: window.coverage,
      );
    }

    var longest = 1;
    var run = 1;
    for (var index = 1; index < keys.length; index++) {
      final previous = MoodManilaCalendar.dateForKey(keys[index - 1]);
      final current = MoodManilaCalendar.dateForKey(keys[index]);
      if (current.difference(previous).inDays == 1) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 1;
      }
    }

    final reference = MoodManilaCalendar.dateForKey(
      MoodManilaCalendar.dateKeyForInstant(referenceInstant),
    );
    final latest = MoodManilaCalendar.dateForKey(keys.last);
    final daysSinceLatest = reference.difference(latest).inDays;
    var current = 0;
    if (daysSinceLatest == 0 || daysSinceLatest == 1) {
      current = 1;
      for (var index = keys.length - 1; index > 0; index--) {
        final newer = MoodManilaCalendar.dateForKey(keys[index]);
        final older = MoodManilaCalendar.dateForKey(keys[index - 1]);
        if (newer.difference(older).inDays != 1) break;
        current++;
      }
    }
    return MoodStreakSummary(
      currentDays: current,
      longestDays: longest,
      coverage: window.coverage,
    );
  }

  static MoodLevelDistribution _distribution(
    Iterable<NormalizedMoodEvent> events,
  ) {
    final counts = <int, int>{for (var level = 1; level <= 5; level++) level: 0};
    for (final event in events) {
      counts[event.level] = (counts[event.level] ?? 0) + 1;
    }
    return MoodLevelDistribution(Map.unmodifiable(counts));
  }
}
