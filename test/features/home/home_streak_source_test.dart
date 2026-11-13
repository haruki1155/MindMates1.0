import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/home/domain/home_streak_source.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';

void main() {
  // Noon in Manila on 2026-11-12.
  final now = DateTime.utc(2026, 11, 12, 4);

  NormalizedMoodEvent event(String dateKey, {String label = 'Okay'}) {
    final date = MoodManilaCalendar.dateForKey(dateKey);
    return NormalizedMoodEvent(
      id: 'e-$dateKey-$label',
      userId: 'u1',
      level: 4,
      dateKey: dateKey,
      occurredAt: date.add(const Duration(hours: 2)),
      source: MoodEventSource.v2,
      label: label,
    );
  }

  MoodHistoryWindow window(List<String> keys) => MoodHistoryWindow(
    events: [for (final key in keys) event(key)],
    coverage: MoodHistoryCoverage.complete,
  );

  group('resolveHomeStreak', () {
    test('V2 history wins over a stale stored counter', () {
      final snapshot = resolveHomeStreak(
        v2History: window(['2026-11-11', '2026-11-12']),
        storedStreak: 9,
        lastActivityDateKey: '2026-11-12',
        now: now,
      );
      expect(snapshot.days, 2);
      expect(snapshot.checkedInToday, isTrue);
      expect(snapshot.state, HomeStreakState.doneToday);
    });

    test('yesterday only keeps the streak but asks for today', () {
      final snapshot = resolveHomeStreak(
        v2History: window(['2026-11-10', '2026-11-11']),
        storedStreak: 0,
        now: now,
      );
      expect(snapshot.days, 2);
      expect(snapshot.checkedInToday, isFalse);
      expect(snapshot.state, HomeStreakState.activeNotToday);
    });

    test('missed day breaks the V2 streak', () {
      final snapshot = resolveHomeStreak(
        v2History: window(['2026-11-09']),
        storedStreak: 5,
        lastActivityDateKey: '2026-11-12',
        now: now,
      );
      expect(snapshot.days, 0);
      expect(snapshot.state, HomeStreakState.notStarted);
    });

    test('null history falls back to the effective stored counter', () {
      final kept = resolveHomeStreak(
        storedStreak: 3,
        lastActivityDateKey: '2026-11-11',
        activeDateKeys: const ['2026-11-10', '2026-11-11'],
        now: now,
      );
      expect(kept.days, 3);
      expect(kept.checkedInToday, isFalse);
      expect(kept.state, HomeStreakState.activeNotToday);
      expect(kept.activeDateKeys, {'2026-11-10', '2026-11-11'});

      final broken = resolveHomeStreak(
        storedStreak: 3,
        lastActivityDateKey: '2026-11-01',
        now: now,
      );
      expect(broken.days, 0);
      expect(broken.state, HomeStreakState.notStarted);
    });

    test('activeDateKeys come from V2 events', () {
      final snapshot = resolveHomeStreak(
        v2History: window(['2026-11-08', '2026-11-11', '2026-11-12']),
        storedStreak: 0,
        activeDateKeys: const ['2026-01-01'],
        now: now,
      );
      expect(snapshot.activeDateKeys, {
        '2026-11-08',
        '2026-11-11',
        '2026-11-12',
      });
    });

    test('seven consecutive days ending today is a milestone', () {
      final keys = [
        for (var day = 6; day <= 12; day++) '2026-11-${'$day'.padLeft(2, '0')}',
      ];
      final snapshot = resolveHomeStreak(
        v2History: window(keys),
        storedStreak: 0,
        now: now,
      );
      expect(snapshot.days, 7);
      expect(snapshot.state, HomeStreakState.milestone);
    });

    test('a milestone length without a check-in today is not shown yet', () {
      final keys = [
        for (var day = 5; day <= 11; day++) '2026-11-${'$day'.padLeft(2, '0')}',
      ];
      final snapshot = resolveHomeStreak(
        v2History: window(keys),
        storedStreak: 0,
        now: now,
      );
      expect(snapshot.days, 7);
      expect(snapshot.state, HomeStreakState.activeNotToday);
    });
  });

  test('isStreakMilestone', () {
    for (final days in [7, 14, 30, 60, 90]) {
      expect(isStreakMilestone(days), isTrue, reason: '$days');
    }
    for (final days in [0, 1, 6, 8, 29, 31, 45, 61]) {
      expect(isStreakMilestone(days), isFalse, reason: '$days');
    }
  });
}
