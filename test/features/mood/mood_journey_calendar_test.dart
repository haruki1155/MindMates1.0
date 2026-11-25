import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/features/mood/widgets/mood_journey_calendar.dart';

void main() {
  testWidgets(
    'renders November 2026 Monday-first grid, navigates months and Today shortcut',
    (tester) async {
      DateTime? changedMonth;
      var todayPressed = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodJourneyCalendar(
                displayedMonth: DateTime.utc(2026, 11, 1),
                selectedDateKey: '2026-11-18',
                todayDateKey: '2026-11-18',
                history: const MoodHistoryWindow(
                  events: [],
                  coverage: MoodHistoryCoverage.complete,
                ),
                onMonthChanged: (month) => changedMonth = month,
                onDaySelected: (_) {},
                onTodayPressed: () => todayPressed++,
              ),
            ),
          ),
        ),
      );

      expect(find.text('November 2026'), findsOneWidget);
      for (final weekday in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        expect(find.text(weekday), findsOneWidget);
      }
      // Nov 2026 grid starts Mon Oct 26 and ends Sun Dec 6.
      expect(
        find.byKey(const Key('mood-calendar-day-2026-10-26')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mood-calendar-day-2026-11-01')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mood-calendar-day-2026-11-30')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mood-calendar-day-2026-12-06')),
        findsOneWidget,
      );

      // Monday Oct 26 should be to the left of Sunday Nov 1 in the first row.
      final oct26Pos = tester.getTopLeft(
        find.byKey(const Key('mood-calendar-day-2026-10-26')),
      );
      final nov1Pos = tester.getTopLeft(
        find.byKey(const Key('mood-calendar-day-2026-11-01')),
      );
      expect(oct26Pos.dy, equals(nov1Pos.dy));
      expect(oct26Pos.dx, lessThan(nov1Pos.dx));

      await tester.tap(find.byKey(const Key('mood-calendar-prev-month')));
      expect(changedMonth, DateTime.utc(2026, 10, 1));

      await tester.tap(find.byKey(const Key('mood-calendar-next-month')));
      expect(changedMonth, DateTime.utc(2026, 12, 1));

      await tester.tap(find.byKey(const Key('mood-calendar-today-button')));
      expect(todayPressed, 1);
    },
  );

  testWidgets(
    'displays single and multiple mood check-ins (+N badge), announces semantics, and blocks future date selection',
    (tester) async {
      String? selectedKey;
      final history = MoodHistoryWindow(
        coverage: MoodHistoryCoverage.complete,
        events: [
          _event('1', '2026-11-16', 4, 'Okay', hour: 1),
          _event('2', '2026-11-18', 2, 'Stressed', hour: 1),
          _event('3', '2026-11-18', 3, 'Tired', hour: 3),
          _event('4', '2026-11-18', 5, 'Great', hour: 5),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodJourneyCalendar(
                displayedMonth: DateTime.utc(2026, 11, 1),
                selectedDateKey: '2026-11-18',
                todayDateKey: '2026-11-20',
                history: history,
                onMonthChanged: (_) {},
                onDaySelected: (key) => selectedKey = key,
                onTodayPressed: () {},
              ),
            ),
          ),
        ),
      );

      // Nov 18 has 3 entries -> shows latest glyph + "+2" badge.
      expect(find.text('+2'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Nov 18.*3 check-ins.*selected')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Nov 16.*1 check-in')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'Nov 20.*today')), findsOneWidget);

      // Tapping Nov 16 selects it.
      await tester.tap(find.byKey(const Key('mood-calendar-day-2026-11-16')));
      expect(selectedKey, '2026-11-16');

      // Tapping future date Nov 25 does NOT select it.
      await tester.tap(find.byKey(const Key('mood-calendar-day-2026-11-25')));
      expect(selectedKey, '2026-11-16');
    },
  );

  testWidgets(
    'distinguishes loading/unknown state, error retry, and partial history notice',
    (tester) async {
      var retried = 0;

      // 1. Loading with null history -> shows loading indicator and does not claim 0 check-ins.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodJourneyCalendar(
                displayedMonth: DateTime.utc(2026, 11, 1),
                selectedDateKey: '2026-11-18',
                todayDateKey: '2026-11-18',
                history: null,
                isLoading: true,
                onMonthChanged: (_) {},
                onDaySelected: (_) {},
                onTodayPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('mood-calendar-loading')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Nov 18.*loading check-ins')),
        findsOneWidget,
      );

      // 1b. Unloaded with null history and isLoading=false -> still announces loading check-ins, never 'no check-ins'.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodJourneyCalendar(
                displayedMonth: DateTime.utc(2026, 11, 1),
                selectedDateKey: '2026-11-18',
                todayDateKey: '2026-11-18',
                history: null,
                isLoading: false,
                onMonthChanged: (_) {},
                onDaySelected: (_) {},
                onTodayPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Nov 18.*loading check-ins')),
        findsOneWidget,
      );

      // 2. Error state -> shows error message and retry action.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodJourneyCalendar(
                displayedMonth: DateTime.utc(2026, 11, 1),
                selectedDateKey: '2026-11-18',
                todayDateKey: '2026-11-18',
                history: null,
                errorMessage: 'Unable to load mood history for this month.',
                onRetry: () => retried++,
                onMonthChanged: (_) {},
                onDaySelected: (_) {},
                onTodayPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('mood-calendar-error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('mood-calendar-retry')));
      expect(retried, 1);

      // 3. Partial coverage -> shows "Based on loaded entries".
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodJourneyCalendar(
                displayedMonth: DateTime.utc(2026, 11, 1),
                selectedDateKey: '2026-11-18',
                todayDateKey: '2026-11-18',
                history: const MoodHistoryWindow(
                  events: [],
                  coverage: MoodHistoryCoverage.partial,
                ),
                onRetry: () => retried++,
                onMonthChanged: (_) {},
                onDaySelected: (_) {},
                onTodayPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Based on loaded entries'), findsOneWidget);
    },
  );

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets(
      'fits without overflow at width $width and text scale 1.8 with >= 40dp targets',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final history = MoodHistoryWindow(
          coverage: MoodHistoryCoverage.complete,
          events: [
            _event('1', '2026-11-18', 2, 'Stressed', hour: 1),
            _event('2', '2026-11-18', 4, 'Okay', hour: 2),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1000),
                textScaler: const TextScaler.linear(1.8),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: MoodJourneyCalendar(
                    displayedMonth: DateTime.utc(2026, 11, 1),
                    selectedDateKey: '2026-11-18',
                    todayDateKey: '2026-11-18',
                    history: history,
                    onMonthChanged: (_) {},
                    onDaySelected: (_) {},
                    onTodayPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        final cellSize = tester.getSize(
          find.byKey(const Key('mood-calendar-day-2026-11-18')),
        );
        expect(cellSize.width, greaterThanOrEqualTo(40.0));
        expect(cellSize.height, greaterThanOrEqualTo(40.0));
      },
    );
  }

  testWidgets(
    'collapsed to a week, it shows only the selected day row and a calendar button',
    (tester) async {
      var expandTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodJourneyCalendar(
                displayedMonth: DateTime.utc(2026, 11, 1),
                selectedDateKey: '2026-11-18',
                todayDateKey: '2026-11-18',
                history: const MoodHistoryWindow(
                  events: [],
                  coverage: MoodHistoryCoverage.complete,
                ),
                collapsedToWeek: true,
                onExpand: () => expandTaps++,
                onMonthChanged: (_) {},
                onDaySelected: (_) {},
                onTodayPressed: () {},
              ),
            ),
          ),
        ),
      );

      // Week of Wed Nov 18: Mon Nov 16 to Sun Nov 22, nothing else.
      for (var day = 16; day <= 22; day++) {
        expect(
          find.byKey(Key('mood-calendar-day-2026-11-$day')),
          findsOneWidget,
          reason: 'Nov $day',
        );
      }
      for (final key in [
        '2026-10-26',
        '2026-11-15',
        '2026-11-23',
        '2026-12-06',
      ]) {
        expect(
          find.byKey(Key('mood-calendar-day-$key')),
          findsNothing,
          reason: key,
        );
      }
      expect(find.byTooltip('Expand mood calendar'), findsNothing);
      await tester.tap(find.byTooltip('Open full calendar'));
      expect(expandTaps, 1);
      expect(
        find.descendant(
          of: find.byTooltip('Open full calendar'),
          matching: find.byIcon(Icons.calendar_month),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'collapsed to a week outside the selected month, it shows the first week',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodJourneyCalendar(
                displayedMonth: DateTime.utc(2026, 12, 1),
                selectedDateKey: '2026-11-18',
                todayDateKey: '2026-11-18',
                history: const MoodHistoryWindow(
                  events: [],
                  coverage: MoodHistoryCoverage.complete,
                ),
                collapsedToWeek: true,
                onMonthChanged: (_) {},
                onDaySelected: (_) {},
                onTodayPressed: () {},
              ),
            ),
          ),
        ),
      );
      // December 2026 grid starts Mon Nov 30.
      expect(
        find.byKey(const Key('mood-calendar-day-2026-11-30')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mood-calendar-day-2026-12-06')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mood-calendar-day-2026-12-07')),
        findsNothing,
      );
    },
  );

  Future<List<String>> pumpWeek(
    WidgetTester tester, {
    required String selected,
    required String today,
  }) async {
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MoodJourneyCalendar(
              displayedMonth: DateTime.utc(2026, 11, 1),
              selectedDateKey: selected,
              todayDateKey: today,
              history: const MoodHistoryWindow(
                events: [],
                coverage: MoodHistoryCoverage.complete,
              ),
              collapsedToWeek: true,
              onMonthChanged: (_) => fail('week arrows must not change month'),
              onDaySelected: picked.add,
              onTodayPressed: () {},
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('in week view the arrows step one week at a time', (
    tester,
  ) async {
    final picked = await pumpWeek(
      tester,
      selected: '2026-11-18',
      today: '2026-11-30',
    );
    expect(find.byTooltip('Previous week'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mood-calendar-prev-month')));
    await tester.tap(find.byKey(const Key('mood-calendar-next-month')));
    expect(picked, ['2026-11-11', '2026-11-25']);
  });

  testWidgets('in week view next stops at the current week', (tester) async {
    var picked = await pumpWeek(
      tester,
      selected: '2026-11-18',
      today: '2026-11-23',
    );
    await tester.tap(find.byKey(const Key('mood-calendar-next-month')));
    expect(picked, ['2026-11-23'], reason: 'lands on today, never the future');

    picked = await pumpWeek(
      tester,
      selected: '2026-11-18',
      today: '2026-11-20',
    );
    await tester.tap(find.byKey(const Key('mood-calendar-next-month')));
    expect(picked, isEmpty, reason: 'already in the current week');
  });
}

NormalizedMoodEvent _event(
  String id,
  String dateKey,
  int level,
  String label, {
  int hour = 1,
}) {
  final date = MoodManilaCalendar.dateForKey(dateKey);
  return NormalizedMoodEvent(
    id: id,
    userId: 'student-1',
    level: level,
    dateKey: dateKey,
    occurredAt: date.add(Duration(hours: hour)),
    source: MoodEventSource.v2,
    label: label,
  );
}
