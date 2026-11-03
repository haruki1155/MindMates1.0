import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_compatibility.dart';

void main() {
  NormalizedMoodEvent event(
    String id,
    DateTime at,
    int level,
    MoodEventSource source,
  ) => NormalizedMoodEvent(
    id: id,
    userId: 'owner',
    level: level,
    dateKey: MoodManilaCalendar.dateKeyForInstant(at),
    occurredAt: at,
    source: source,
  );

  test('Reports counts events separately from unique Manila-active days', () {
    final history = MoodHistoryWindow(
      events: [
        event(
          'legacy',
          DateTime.utc(2026, 8, 1, 16),
          4,
          MoodEventSource.legacy,
        ),
        event('v2-one', DateTime.utc(2026, 8, 1, 17), 2, MoodEventSource.v2),
        event('v2-two', DateTime.utc(2026, 8, 2, 16), 5, MoodEventSource.v2),
      ],
      coverage: MoodHistoryCoverage.complete,
    );
    final summary = MoodReportsCompatibility.summarize(history);
    expect(summary.entryCount, 3);
    expect(summary.activeDayCount, 2);
    expect(summary.latestLevel, 5);
    expect(summary.positiveEntryCount, 2);
    expect(summary.coverage, MoodHistoryCoverage.complete);
  });

  test(
    'MindAid projection omits sensitive fields and preserves partial coverage',
    () {
      final snapshot = MindAidMoodCompatibility.summarize(
        MoodHistoryWindow(
          events: [
            event('old', DateTime.utc(2026, 8, 1), 2, MoodEventSource.legacy),
            event('latest', DateTime.utc(2026, 8, 2), 4, MoodEventSource.v2),
          ],
          coverage: MoodHistoryCoverage.partial,
        ),
      );
      expect(snapshot.latestLevel, 4);
      expect(snapshot.recentAverage, 3);
      expect(snapshot.coverage, MoodHistoryCoverage.partial);
      expect(MoodV2ReadCompatibilityFlag.reportsEnabled, isFalse);
      expect(MoodV2ReadCompatibilityFlag.mindAidEnabled, isFalse);
    },
  );
}
