import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/features/mood/widgets/mood_v2_history_panel.dart';
import 'package:mind_mates/features/mood/screens/mood_journey_screen.dart';
import 'package:mind_mates/features/mood/widgets/mood_journey_summary.dart';
import 'package:mind_mates/routes/route_names.dart';

void main() {
  testWidgets(
    'streak is a white card with yellow edge and readable dark text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodJourneySummary(
                history: const MoodHistoryWindow(
                  events: [],
                  coverage: MoodHistoryCoverage.complete,
                ),
                now: DateTime.utc(2026, 11, 12),
              ),
            ),
          ),
        ),
      );
      final card = tester.widget<Container>(
        find.byKey(const Key('mood-streak-card')),
      );
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, Colors.white);
      expect((decoration.border! as Border).top.color, const Color(0xFFFFC414));
      expect(decoration.boxShadow, isNotEmpty);
      expect(find.text('Mood Streak'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting a past date shows only its day detail, updates selected-week summary, and keeps monthly overview separate',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: _JourneyAuth()),
            ChangeNotifierProvider<MoodProvider>.value(value: _PeriodMood()),
          ],
          child: MaterialApp(
            home: MoodJourneyScreen(
              nowProvider: () => DateTime.utc(2026, 11, 12),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default selected date is Nov 11/12 week; Nov 11 is in week Nov 9-15 (1 check-in),
      // while November at a glance has 3 check-ins across 2 mood-active days (Nov 1 has 2, Nov 11 has 1).
      expect(
        find.descendant(
          of: find.byKey(const Key('mood-selected-week-card')),
          matching: find.text('1 check-in · 1 mood-active day'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('mood-month-overview-card')),
          matching: find.text('2 mood-active days · 3 check-ins'),
        ),
        findsOneWidget,
      );
      // Nov 1 is Sunday; before selecting Nov 1, Sunday's day card is not shown.
      expect(find.text('Sunday'), findsNothing);

      // Select Sunday Nov 1 on the calendar.
      await tester.tap(find.byKey(const Key('mood-calendar-day-2026-11-01')));
      await tester.pumpAndSettle();

      // Now Sunday Nov 1's detail is shown and the selected week (Oct 26 - Nov 1) has 2 check-ins.
      expect(find.text('Sunday'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('mood-selected-week-card')),
          matching: find.text('2 check-ins · 1 mood-active day'),
        ),
        findsOneWidget,
      );
      // Monthly overview remains 2 mood-active days · 3 check-ins.
      expect(
        find.descendant(
          of: find.byKey(const Key('mood-month-overview-card')),
          matching: find.text('2 mood-active days · 3 check-ins'),
        ),
        findsOneWidget,
      );
      // Selecting an empty historical day does not open any mood logger.
      await tester.tap(find.byKey(const Key('mood-calendar-day-2026-11-05')));
      await tester.pumpAndSettle();
      expect(find.text('No mood check-ins on this date.'), findsOneWidget);
      expect(find.text('Save mood entry'), findsNothing);
    },
  );

  testWidgets(
    'journey hides the previous account history after an account switch',
    (tester) async {
      final auth = _JourneyAuth();
      final mood = _JourneyMood();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<MoodProvider>.value(value: mood),
          ],
          child: MaterialApp(
            home: MoodJourneyScreen(
              nowProvider: () => DateTime.utc(2026, 11, 11, 2),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('mood-v2-history-list')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Okay').first);
      await tester.pumpAndSettle();
      expect(find.text('Private account A note'), findsOneWidget);
      auth.switchTo('account-b');
      await tester.pump();
      expect(find.text('Private account A note'), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
    },
  );

  testWidgets('journey summary counts events and active days separately', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 11, 3);
    final history = MoodHistoryWindow(
      coverage: MoodHistoryCoverage.partial,
      events: [
        NormalizedMoodEvent(
          id: '1',
          userId: 'synthetic',
          level: 3,
          dateKey: '2026-11-11',
          occurredAt: now,
          source: MoodEventSource.v2,
          label: 'Okay',
        ),
        NormalizedMoodEvent(
          id: '2',
          userId: 'synthetic',
          level: 3,
          dateKey: '2026-11-11',
          occurredAt: now,
          source: MoodEventSource.v2,
          label: 'Okay',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MoodJourneySummary(history: history, now: now),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('mood-selected-week-card')), findsOneWidget);
    expect(find.byKey(const Key('mood-month-overview-card')), findsOneWidget);
    expect(find.text('2 check-ins · 1 mood-active day'), findsOneWidget);
    expect(find.text('1 mood-active day · 2 check-ins'), findsOneWidget);
    expect(find.textContaining('Most logged mood'), findsOneWidget);
    expect(find.textContaining('Top logged mood'), findsOneWidget);
    expect(find.textContaining('Okay'), findsWidgets);
    expect(find.text('Based on loaded entries'), findsWidgets);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets(
      'journey summary and calendar fit without overflow at $width with large text',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final now = DateTime.utc(2026, 11, 11);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: _JourneyAuth()),
              ChangeNotifierProvider<MoodProvider>.value(value: _PeriodMood()),
            ],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1200),
                  textScaler: const TextScaler.linear(1.8),
                ),
                child: MoodJourneyScreen(nowProvider: () => now),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mood-journey-calendar')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('journey week and month summaries report tied moods accurately', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 11);
    final events = [
      for (final (id, day, label) in [
        ('1', 11, 'Okay'),
        ('2', 11, 'Great'),
        ('3', 1, 'Great'),
      ])
        NormalizedMoodEvent(
          id: id,
          userId: 'synthetic',
          level: 4,
          dateKey: '2026-11-${day.toString().padLeft(2, '0')}',
          occurredAt: DateTime.utc(2026, 11, day),
          source: MoodEventSource.v2,
          label: label,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MoodJourneySummary(
              history: MoodHistoryWindow(
                events: events,
                coverage: MoodHistoryCoverage.partial,
              ),
              now: now,
              selectedDateKey: '2026-11-11',
              displayedMonth: DateTime.utc(2026, 11, 1),
            ),
          ),
        ),
      ),
    );
    expect(
      find.textContaining('Most logged moods are tied: Great, Okay'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('mood-selected-week-card')),
        matching: find.text('2 check-ins · 1 mood-active day'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('mood-month-overview-card')),
        matching: find.text('2 mood-active days · 3 check-ins'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('mood-month-overview-card')),
        matching: find.textContaining('Great'),
      ),
      findsWidgets,
    );
    expect(find.text('Based on loaded entries'), findsWidgets);
  });

  group('item 38 recap', () {
    Future<void> pumpJourney(WidgetTester tester, {int? milestoneDays}) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: _JourneyAuth()),
            ChangeNotifierProvider<MoodProvider>.value(value: _RecapMood()),
          ],
          child: MaterialApp(
            routes: {
              RouteNames.mindfulBreathing: (_) =>
                  const Scaffold(body: Text('Breathing target')),
            },
            home: MoodJourneyScreen(
              nowProvider: () => DateTime.utc(2026, 11, 12, 4),
              milestoneDays: milestoneDays,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('milestone banner only when opened from View recap', (
      tester,
    ) async {
      await pumpJourney(tester, milestoneDays: 7);
      expect(
        find.text("🔥 7-day streak · Here's your week in moods"),
        findsOneWidget,
      );
      await pumpJourney(tester);
      expect(find.textContaining('-day streak · '), findsNothing);
    });

    testWidgets('mood streak card shows the colored flame', (tester) async {
      await pumpJourney(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('mood-streak-card')),
          matching: find.byKey(const Key('streak-flame')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('selected week shows best day, a tip and the support note', (
      tester,
    ) async {
      await pumpJourney(tester, milestoneDays: 7);
      expect(find.text('Best day'), findsOneWidget);
      expect(find.text('Tuesday · Great'), findsOneWidget);
      expect(find.text('Notice what made it a good day.'), findsOneWidget);
      expect(find.text('A gentle tip'), findsOneWidget);
      expect(
        find.text(
          'Stress showed up a few times this week. A 2-minute breathing '
          'session can help you reset.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "This reflects your own check-ins. It is not a diagnosis. If you'd "
          'like to talk to someone, PACC is here for you.',
        ),
        findsOneWidget,
      );
      expect(find.text('Book a PACC appointment'), findsOneWidget);

      await tester.ensureVisible(find.text('Try breathing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try breathing'));
      await tester.pumpAndSettle();
      expect(find.text('Breathing target'), findsOneWidget);
    });

    testWidgets(
      'selecting a week with no good-enough check-in hides Best day',
      (tester) async {
        await pumpJourney(tester);
        // Select Nov 2 (earlier week with no entries).
        await tester.tap(find.byKey(const Key('mood-calendar-day-2026-11-02')));
        await tester.pumpAndSettle();
        expect(find.text('Best day'), findsNothing);
        expect(find.text('A gentle tip'), findsOneWidget);
      },
    );
  });

  testWidgets('journey has a clear title and an empty state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MoodJourneyScreen()));
    expect(find.text('My Mood Journey'), findsOneWidget);
    expect(find.textContaining('Sign in'), findsOneWidget);
  });

  testWidgets('personal journey shows each same-day mood and its note', (
    tester,
  ) async {
    final time = DateTime.utc(2026, 11, 11, 1);
    final history = MoodHistoryWindow(
      coverage: MoodHistoryCoverage.partial,
      events: [
        NormalizedMoodEvent(
          id: 'one',
          userId: 'synthetic',
          level: 3,
          dateKey: '2026-11-11',
          occurredAt: time,
          source: MoodEventSource.v2,
          label: 'Okay',
          note: 'A private note',
        ),
        NormalizedMoodEvent(
          id: 'two',
          userId: 'synthetic',
          level: 3,
          dateKey: '2026-11-11',
          occurredAt: time.add(const Duration(hours: 1)),
          source: MoodEventSource.v2,
          label: 'Okay',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MoodV2HistoryPanel(
              history: history,
              showPersonalDetails: true,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('2 check-ins'), findsOneWidget);
    expect(find.textContaining('Okay'), findsNothing);
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Okay'), findsNWidgets(2));
    await tester.tap(find.byType(ExpansionTile).last);
    await tester.pumpAndSettle();
    expect(find.text('A private note'), findsOneWidget);
    expect(find.text('Based on loaded entries'), findsOneWidget);
  });
}

class _JourneyAuth extends ChangeNotifier implements AuthProvider {
  String uid = 'account-a';
  @override
  String? get authenticatedUserId => uid;
  void switchTo(String value) {
    uid = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _JourneyMood extends ChangeNotifier implements MoodProvider {
  @override
  Map<String, String?> get v2PersonalNotes => const {
    'v2:one': 'Private account A note',
  };
  @override
  Set<String> get v2NoteLoadingDays => const {};
  @override
  Set<String> get v2NoteErrorDays => const {};
  @override
  Future<void> loadMoodV2DayNotes(String uid, String day) async {}
  @override
  bool get isMoodV2ReadEnabled => true;
  @override
  MoodHistoryWindow? get v2History => MoodHistoryWindow(
    coverage: MoodHistoryCoverage.complete,
    events: [
      NormalizedMoodEvent(
        id: 'one',
        userId: 'account-a',
        level: 3,
        dateKey: '2026-11-11',
        occurredAt: DateTime.utc(2026, 11, 11),
        source: MoodEventSource.v2,
        label: 'Okay',
        note: 'Private account A note',
      ),
    ],
  );
  @override
  MoodHistoryWindow? get moodCalendarHistory => v2History;
  @override
  bool get isLoadingMoodCalendarRange => false;
  @override
  String? get moodCalendarRangeError => null;
  @override
  String? get loadedMoodCalendarStartKey => '2026-10-26';
  @override
  String? get loadedMoodCalendarEndExclusiveKey => '2026-12-07';
  @override
  Future<void> loadMoodCalendarRange(
    String userId, {
    required String startDateKey,
    required String endExclusiveDateKey,
  }) async {}
  @override
  bool get isLoadingV2History => false;
  @override
  bool get isLoadingMoreV2History => false;
  @override
  bool get canLoadMoreMoodV2History => false;
  @override
  String? get v2HistoryErrorMessage => null;
  @override
  String? get v2PaginationErrorMessage => null;
  @override
  Future<void> loadMoodV2History(String userId, {DateTime? now}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PeriodMood extends _JourneyMood {
  @override
  MoodHistoryWindow get v2History => MoodHistoryWindow(
    coverage: MoodHistoryCoverage.complete,
    events: [
      NormalizedMoodEvent(
        id: '1-a',
        userId: 'account-a',
        level: 3,
        dateKey: '2026-11-01',
        occurredAt: DateTime.utc(2026, 11, 1, 1),
        source: MoodEventSource.v2,
        label: 'Okay',
      ),
      NormalizedMoodEvent(
        id: '1-b',
        userId: 'account-a',
        level: 4,
        dateKey: '2026-11-01',
        occurredAt: DateTime.utc(2026, 11, 1, 3),
        source: MoodEventSource.v2,
        label: 'Great',
      ),
      NormalizedMoodEvent(
        id: '11',
        userId: 'account-a',
        level: 3,
        dateKey: '2026-11-11',
        occurredAt: DateTime.utc(2026, 11, 11, 2),
        source: MoodEventSource.v2,
        label: 'Okay',
      ),
    ],
  );
}

class _RecapMood extends _JourneyMood {
  NormalizedMoodEvent _event(String id, int day, int level, String label) =>
      NormalizedMoodEvent(
        id: id,
        userId: 'account-a',
        level: level,
        dateKey: '2026-11-${day.toString().padLeft(2, '0')}',
        occurredAt: DateTime.utc(2026, 11, day, 2),
        source: MoodEventSource.v2,
        label: label,
      );

  @override
  MoodHistoryWindow get v2History => MoodHistoryWindow(
    coverage: MoodHistoryCoverage.complete,
    events: [
      _event('tue', 10, 5, 'Great'),
      _event('wed-1', 11, 2, 'Stressed'),
      _event('wed-2', 11, 2, 'Stressed'),
      _event('thu', 12, 4, 'Okay'),
    ],
  );
}
