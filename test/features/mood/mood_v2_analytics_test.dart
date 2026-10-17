import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/models/mood_model.dart';

void main() {
  NormalizedMoodEvent event(
    String id,
    DateTime occurredAt, {
    int level = 3,
    MoodEventSource source = MoodEventSource.v2,
  }) => NormalizedMoodEvent(
    id: id,
    userId: 'user_1',
    level: level,
    dateKey: MoodManilaCalendar.dateKeyForInstant(occurredAt),
    occurredAt: occurredAt,
    source: source,
    clientRequestId: source == MoodEventSource.v2 ? id : null,
  );

  MoodHistoryWindow window(
    List<NormalizedMoodEvent> events, {
    MoodHistoryCoverage coverage = MoodHistoryCoverage.complete,
  }) => MoodHistoryWindow(events: events, coverage: coverage);

  group('Mood V2 analytics', () {
    test('three same-day events are three entries and one active day', () {
      final snapshot = MoodAnalytics.summarize(
        window([
          event('a', DateTime.utc(2026, 7, 7, 16), level: 2),
          event('b', DateTime.utc(2026, 7, 7, 17), level: 3),
          event('c', DateTime.utc(2026, 7, 7, 18), level: 5),
        ]),
        referenceInstant: DateTime.utc(2026, 7, 7, 18),
      );

      expect(snapshot.eventCount, 3);
      expect(snapshot.activeDayCount, 1);
      expect(snapshot.daily.single.distribution[2], 1);
      expect(snapshot.daily.single.distribution[3], 1);
      expect(snapshot.daily.single.distribution[5], 1);
    });

    test('uses Manila rollover rather than the host time zone', () {
      expect(
        MoodManilaCalendar.dateKeyForInstant(DateTime.utc(2026, 7, 7, 15, 59)),
        '2026-07-07',
      );
      expect(
        MoodManilaCalendar.dateKeyForInstant(DateTime.utc(2026, 7, 7, 16)),
        '2026-07-08',
      );
    });

    test('continues current streak through today or yesterday only', () {
      final events = [
        event('one', DateTime.utc(2026, 7, 7, 16)),
        event('two', DateTime.utc(2026, 7, 8, 16)),
      ];
      expect(
        MoodAnalytics.streak(
          window(events),
          referenceInstant: DateTime.utc(2026, 7, 8, 18),
        ).currentDays,
        2,
      );
      expect(
        MoodAnalytics.streak(
          window(events),
          referenceInstant: DateTime.utc(2026, 7, 9, 18),
        ).currentDays,
        2,
      );
    });

    test('resets current streak after a missed Manila day', () {
      final result = MoodAnalytics.streak(
        window([event('one', DateTime.utc(2026, 7, 7, 16))]),
        referenceInstant: DateTime.utc(2026, 7, 9, 18),
      );
      expect(result.currentDays, 0);
      expect(result.longestDays, 1);
    });

    test('normalizes legacy-only, V2-only, and mixed history', () {
      final legacy = NormalizedMoodEvent.fromLegacy(
        MoodModel(
          id: 'daily_user_1_20260708',
          userId: 'user_1',
          level: 4,
          createdAt: DateTime.utc(2026, 7, 7, 16),
        ),
      );
      expect(MoodAnalytics.summarize(window([legacy]), referenceInstant: DateTime.utc(2026, 7, 7, 18)).eventCount, 1);
      expect(MoodAnalytics.summarize(window([event('v2', DateTime.utc(2026, 7, 7, 17))]), referenceInstant: DateTime.utc(2026, 7, 7, 18)).eventCount, 1);
      expect(MoodAnalytics.summarize(window([legacy, event('v2', DateTime.utc(2026, 7, 8, 17))]), referenceInstant: DateTime.utc(2026, 7, 8, 18)).activeDayCount, 2);
    });

    test('deduplicates stable event identities and sorts out-of-order input', () {
      final snapshot = MoodAnalytics.summarize(
        window([
          event('later', DateTime.utc(2026, 7, 8, 16)),
          event('first', DateTime.utc(2026, 7, 7, 16)),
          event('later', DateTime.utc(2026, 7, 8, 16)),
        ]),
        referenceInstant: DateTime.utc(2026, 7, 8, 18),
      );
      expect(snapshot.eventCount, 2);
      expect(snapshot.streak.currentDays, 2);
    });

    test('empty and partial history are explicit', () {
      final empty = MoodAnalytics.summarize(
        window(const [], coverage: MoodHistoryCoverage.partial),
        referenceInstant: DateTime.utc(2026, 7, 7, 16),
      );
      expect(empty.eventCount, 0);
      expect(empty.streak.longestDays, 0);
      expect(empty.streak.isLongestWindowed, isTrue);
    });

    test('calculates the longest distinct-date run', () {
      final result = MoodAnalytics.streak(
        window([
          event('one', DateTime.utc(2026, 7, 1, 16)),
          event('two', DateTime.utc(2026, 7, 2, 16)),
          event('three', DateTime.utc(2026, 7, 4, 16)),
          event('four', DateTime.utc(2026, 7, 5, 16)),
          event('five', DateTime.utc(2026, 7, 6, 16)),
        ]),
        referenceInstant: DateTime.utc(2026, 7, 6, 18),
      );
      expect(result.longestDays, 3);
      expect(result.currentDays, 3);
    });

    test('uses Monday-to-Monday weekly bounds and separate counts', () {
      final snapshot = MoodAnalytics.summarize(
        window([
          event('monday-a', DateTime.utc(2026, 7, 5, 16)),
          event('monday-b', DateTime.utc(2026, 7, 5, 17)),
          event('sunday', DateTime.utc(2026, 7, 11, 16)),
          event('next-monday', DateTime.utc(2026, 7, 12, 16)),
        ]),
        referenceInstant: DateTime.utc(2026, 7, 8, 16),
      );
      expect(snapshot.weekly.range.startDateKey, '2026-07-06');
      expect(snapshot.weekly.range.endExclusiveDateKey, '2026-07-13');
      expect(snapshot.weekly.entryCount, 3);
      expect(snapshot.weekly.activeDayCount, 2);
    });
  });
}
