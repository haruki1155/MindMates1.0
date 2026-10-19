import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/insights/models/insights_models.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';

void main() {
  test('V2 insight metrics keep entry count separate from active days', () {
    final snapshot = MoodAnalytics.summarize(
      MoodHistoryWindow(
        events: [
          _event('one', DateTime.utc(2026, 7, 7, 16), 4),
          _event('two', DateTime.utc(2026, 7, 7, 17), 5),
        ],
        coverage: MoodHistoryCoverage.complete,
      ),
      referenceInstant: DateTime.utc(2026, 7, 8),
    );

    final metrics = InsightMetricsSummary.from(
      moods: const [],
      moodV2Analytics: snapshot,
    );

    expect(metrics.usesMoodV2, isTrue);
    expect(metrics.checkIns, 2);
    expect(metrics.moodActiveDays, 1);
    expect(metrics.moodStreakDays, 1);
    expect(metrics.hasPartialMoodHistory, isFalse);
  });

  test('partial V2 history stays explicitly windowed', () {
    final snapshot = MoodAnalytics.summarize(
      MoodHistoryWindow(
        events: [_event('one', DateTime.utc(2026, 7, 7, 16), 3)],
        coverage: MoodHistoryCoverage.partial,
      ),
      referenceInstant: DateTime.utc(2026, 7, 8),
    );

    final metrics = InsightMetricsSummary.from(
      moods: const [],
      moodV2Analytics: snapshot,
    );

    expect(metrics.hasPartialMoodHistory, isTrue);
  });
}

NormalizedMoodEvent _event(String id, DateTime occurredAt, int level) =>
    NormalizedMoodEvent(
      id: id,
      userId: 'user_1',
      level: level,
      dateKey: MoodManilaCalendar.dateKeyForInstant(occurredAt),
      occurredAt: occurredAt,
      source: MoodEventSource.v2,
    );
