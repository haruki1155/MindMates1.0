import 'mood_v2_analytics.dart';

/// Kept off until each consumer has separately adopted the read-only adapter.
class MoodV2ReadCompatibilityFlag {
  const MoodV2ReadCompatibilityFlag._();

  static const reportsEnabled = bool.fromEnvironment(
    'ENABLE_MOOD_V2_REPORTS_READ',
    defaultValue: false,
  );
  static const mindAidEnabled = bool.fromEnvironment(
    'ENABLE_MOOD_V2_MINDAID_READ',
    defaultValue: false,
  );
}

class MoodReportsCompatibilitySummary {
  const MoodReportsCompatibilitySummary({
    required this.entryCount,
    required this.activeDayCount,
    required this.averageLevel,
    required this.latestLevel,
    required this.positiveEntryCount,
    required this.coverage,
  });

  final int entryCount;
  final int activeDayCount;
  final double? averageLevel;
  final int? latestLevel;
  final int positiveEntryCount;
  final MoodHistoryCoverage coverage;
}

class MoodReportsCompatibility {
  const MoodReportsCompatibility._();

  static MoodReportsCompatibilitySummary summarize(MoodHistoryWindow history) {
    final events = history.uniqueEvents;
    final total = events.fold<int>(0, (sum, event) => sum + event.level);
    return MoodReportsCompatibilitySummary(
      entryCount: events.length,
      activeDayCount: MoodAnalytics.dailyAggregates(events).length,
      averageLevel: events.isEmpty ? null : total / events.length,
      latestLevel: events.isEmpty ? null : events.last.level,
      positiveEntryCount: events.where((event) => event.level >= 4).length,
      coverage: history.coverage,
    );
  }
}

class MindAidMoodCompatibilitySnapshot {
  const MindAidMoodCompatibilitySnapshot({
    required this.latestLevel,
    required this.recentAverage,
    required this.trend,
    required this.lastCheckInAt,
    required this.coverage,
  });

  final int? latestLevel;
  final double? recentAverage;
  final MoodV2MindAidTrend? trend;
  final DateTime? lastCheckInAt;
  final MoodHistoryCoverage coverage;
}

enum MoodV2MindAidTrend { improving, declining, steady }

/// Produces only coarse recommendation metrics. Notes, labels, entry method,
/// and expression metadata are never included in this projection.
class MindAidMoodCompatibility {
  const MindAidMoodCompatibility._();

  static MindAidMoodCompatibilitySnapshot summarize(MoodHistoryWindow history) {
    final events = history.uniqueEvents.reversed.toList(growable: false);
    final sample = events.take(7).toList(growable: false);
    final average = sample.isEmpty
        ? null
        : sample.fold<int>(0, (sum, event) => sum + event.level) /
              sample.length;
    MoodV2MindAidTrend? trend;
    if (sample.length >= 4) {
      final recent =
          sample.take(3).fold<int>(0, (sum, event) => sum + event.level) / 3;
      final olderValues = sample.skip(3).take(3).toList(growable: false);
      final older =
          olderValues.fold<int>(0, (sum, event) => sum + event.level) /
          olderValues.length;
      trend = recent - older >= .6
          ? MoodV2MindAidTrend.improving
          : recent - older <= -.6
          ? MoodV2MindAidTrend.declining
          : MoodV2MindAidTrend.steady;
    }
    return MindAidMoodCompatibilitySnapshot(
      latestLevel: events.isEmpty ? null : events.first.level,
      recentAverage: average,
      trend: trend,
      lastCheckInAt: events.isEmpty ? null : events.first.occurredAt,
      coverage: history.coverage,
    );
  }
}
