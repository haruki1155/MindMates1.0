import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mood/domain/mood_journey_period.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';

void main() {
  test('Manila Monday and month boundaries exclude future and prior dates', () {
    final monday = DateTime.utc(2026, 10, 4, 16);
    expect(
      includesMoodJourneyDate('2026-10-05', MoodJourneyPeriod.week, monday),
      isTrue,
    );
    expect(
      includesMoodJourneyDate('2026-10-04', MoodJourneyPeriod.week, monday),
      isFalse,
    );
    expect(
      includesMoodJourneyDate('2026-10-06', MoodJourneyPeriod.week, monday),
      isFalse,
    );
    final november = DateTime.utc(2026, 10, 31, 16);
    expect(
      includesMoodJourneyDate('2026-11-01', MoodJourneyPeriod.month, november),
      isTrue,
    );
    expect(
      includesMoodJourneyDate('2026-10-31', MoodJourneyPeriod.month, november),
      isFalse,
    );
    expect(
      includesMoodJourneyDate('2026-11-02', MoodJourneyPeriod.month, november),
      isFalse,
    );
  });

  test(
    'moodVisibleMonthRange spans Monday of first week through Monday after last Sunday',
    () {
      // Nov 1, 2026 is Sunday -> grid starts Mon Oct 26, 2026.
      // Nov 30, 2026 is Monday -> last Sunday is Dec 6 -> endExclusive is Mon Dec 7, 2026.
      final nov2026 = moodVisibleMonthRange(DateTime.utc(2026, 11, 18));
      expect(nov2026.startDateKey, '2026-10-26');
      expect(nov2026.endExclusiveDateKey, '2026-12-07');

      final novMonth = moodMonthRange(DateTime.utc(2026, 11, 18));
      expect(novMonth.startDateKey, '2026-11-01');
      expect(novMonth.endExclusiveDateKey, '2026-12-01');

      // Leap year February 2028: Feb 1 is Tuesday -> grid starts Mon Jan 31.
      // Feb 29 is Tuesday -> last Sunday is Mar 5 -> endExclusive is Mon Mar 6.
      final feb2028 = moodVisibleMonthRange(DateTime.utc(2028, 2, 1));
      expect(feb2028.startDateKey, '2028-01-31');
      expect(feb2028.endExclusiveDateKey, '2028-03-06');

      final febMonth = moodMonthRange(DateTime.utc(2028, 2, 15));
      expect(febMonth.startDateKey, '2028-02-01');
      expect(febMonth.endExclusiveDateKey, '2028-03-01');
    },
  );

  test(
    'moodWeekContainingDate resolves Monday-first week for Sunday, Monday, and cross-month dates',
    () {
      // Sunday Nov 1, 2026 belongs to week Mon Oct 26 .. Mon Nov 2 (exclusive).
      final sundayWeek = moodWeekContainingDate(DateTime.utc(2026, 11, 1));
      expect(sundayWeek.startDateKey, '2026-10-26');
      expect(sundayWeek.endExclusiveDateKey, '2026-11-02');
      expect(sundayWeek.includes('2026-10-26'), isTrue);
      expect(sundayWeek.includes('2026-11-01'), isTrue);
      expect(sundayWeek.includes('2026-11-02'), isFalse);

      // Monday Nov 2, 2026 starts a new week Mon Nov 2 .. Mon Nov 9 (exclusive).
      final mondayWeek = moodWeekContainingDateKey('2026-11-02');
      expect(mondayWeek.startDateKey, '2026-11-02');
      expect(mondayWeek.endExclusiveDateKey, '2026-11-09');

      // Around Manila midnight: 2026-11-01 15:59 UTC is 23:59 Manila Sunday Nov 1;
      // 2026-11-01 16:00 UTC is 00:00 Manila Monday Nov 2.
      final beforeMidnightKey = MoodManilaCalendar.dateKeyForInstant(
        DateTime.utc(2026, 11, 1, 15, 59),
      );
      final atMidnightKey = MoodManilaCalendar.dateKeyForInstant(
        DateTime.utc(2026, 11, 1, 16, 0),
      );
      expect(
        moodWeekContainingDateKey(beforeMidnightKey).startDateKey,
        '2026-10-26',
      );
      expect(
        moodWeekContainingDateKey(atMidnightKey).startDateKey,
        '2026-11-02',
      );
    },
  );

  test(
    'summarizeMoodRange deduplicates stableIdentity, counts same-day check-ins vs active days, and preserves partial coverage',
    () {
      final window = MoodHistoryWindow(
        coverage: MoodHistoryCoverage.partial,
        events: [
          _event('e1', '2026-11-18', 2, label: 'Stressed', hour: 2),
          // Exact duplicate stableIdentity (v2:e1) must count once.
          _event('e1', '2026-11-18', 2, label: 'Stressed', hour: 2),
          // Second distinct check-in on the same day.
          _event('e2', '2026-11-18', 4, label: 'Okay', hour: 8),
          // Another day in the same week.
          _event('e3', '2026-11-19', 2, label: 'Stressed', hour: 4),
          // Out-of-range event on next Monday (endExclusive).
          _event('e4', '2026-11-23', 5, label: 'Great', hour: 1),
        ],
      );

      final summary = summarizeMoodRange(window, '2026-11-16', '2026-11-23');
      expect(summary.checkInCount, 3);
      expect(summary.activeDayCount, 2);
      expect(summary.labeledCheckInCount, 3);
      expect(summary.unlabeledCheckInCount, 0);
      expect(summary.topLabels, ['Stressed']);
      expect(summary.topLabelCount, 2);
      expect(summary.isTiedTop, isFalse);
      expect(summary.isPartial, isTrue);
      expect(summary.labelCounts, {'Stressed': 2, 'Okay': 1});
      expect(summary.labelDistribution.first.label, 'Stressed');
      expect(summary.labelDistribution.first.count, 2);
      expect(summary.labelDistribution.first.percentage, 67);
    },
  );

  test(
    'summarizeMoodRange reports tied top moods and never invents a mood for unlabeled events',
    () {
      final tiedWindow = MoodHistoryWindow(
        coverage: MoodHistoryCoverage.complete,
        events: [
          _event('a', '2026-11-16', 4, label: 'Okay'),
          _event('b', '2026-11-17', 5, label: 'Great'),
          _event('c', '2026-11-18', 4, label: 'Okay'),
          _event('d', '2026-11-18', 5, label: 'Great', hour: 3),
          _event('e', '2026-11-19', 3, label: '   '),
        ],
      );

      final tied = summarizeMoodRange(tiedWindow, '2026-11-16', '2026-11-23');
      expect(tied.checkInCount, 5);
      expect(tied.activeDayCount, 4);
      expect(tied.labeledCheckInCount, 4);
      expect(tied.unlabeledCheckInCount, 1);
      expect(tied.isTiedTop, isTrue);
      expect(tied.topLabels, ['Great', 'Okay']);
      expect(tied.topLabelCount, 2);
      expect(tied.isPartial, isFalse);

      final unlabeledOnlyWindow = MoodHistoryWindow(
        coverage: MoodHistoryCoverage.complete,
        events: [
          _event('u1', '2026-11-16', 3, label: null),
          _event('u2', '2026-11-17', 2, label: '  '),
        ],
      );
      final unlabeled = summarizeMoodRange(
        unlabeledOnlyWindow,
        '2026-11-16',
        '2026-11-23',
      );
      expect(unlabeled.checkInCount, 2);
      expect(unlabeled.activeDayCount, 2);
      expect(unlabeled.labeledCheckInCount, 0);
      expect(unlabeled.unlabeledCheckInCount, 2);
      expect(unlabeled.topLabels, isEmpty);
      expect(unlabeled.topLabelCount, 0);
      expect(unlabeled.labelDistribution, isEmpty);
    },
  );

  test(
    'intersectMoodRanges clips week and month boundaries to academic term and handles empty overlap',
    () {
      // Week crossing Nov 30 - Dec 6 clipped to Semester 1 ending Dec 1 (exclusive).
      const crossWeek = MoodWeekRange(
        startDateKey: '2026-11-30',
        endExclusiveDateKey: '2026-12-07',
      );
      const firstSemester = MoodWeekRange(
        startDateKey: '2026-06-01',
        endExclusiveDateKey: '2026-12-01',
      );
      final clipped = intersectMoodRanges(crossWeek, firstSemester);
      expect(clipped.startDateKey, '2026-11-30');
      expect(clipped.endExclusiveDateKey, '2026-12-01');
      expect(isMoodRangeEmpty(clipped), isFalse);

      final window = MoodHistoryWindow(
        coverage: MoodHistoryCoverage.complete,
        events: [
          _event('nov30', '2026-11-30', 4, label: 'Okay'),
          _event('dec01', '2026-12-01', 2, label: 'Stressed'),
        ],
      );
      final clippedSummary = summarizeMoodRange(
        window,
        clipped.startDateKey,
        clipped.endExclusiveDateKey,
      );
      expect(clippedSummary.checkInCount, 1);
      expect(clippedSummary.topLabels, ['Okay']);

      // Disjoint ranges produce an empty intersection.
      const mayWeek = MoodWeekRange(
        startDateKey: '2026-05-18',
        endExclusiveDateKey: '2026-05-25',
      );
      final disjoint = intersectMoodRanges(mayWeek, firstSemester);
      expect(isMoodRangeEmpty(disjoint), isTrue);
      final emptySummary = summarizeMoodRange(
        window,
        disjoint.startDateKey,
        disjoint.endExclusiveDateKey,
      );
      expect(emptySummary.checkInCount, 0);
      expect(emptySummary.activeDayCount, 0);
    },
  );
}

NormalizedMoodEvent _event(
  String id,
  String dateKey,
  int level, {
  String? label,
  int hour = 1,
}) {
  final day = MoodManilaCalendar.dateForKey(dateKey);
  return NormalizedMoodEvent(
    id: id,
    userId: 'student-1',
    level: level,
    dateKey: dateKey,
    occurredAt: day.add(Duration(hours: hour)),
    source: MoodEventSource.v2,
    label: label,
  );
}
