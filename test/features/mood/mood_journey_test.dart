import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/features/mood/widgets/mood_v2_history_panel.dart';
import 'package:mind_mates/features/mood/screens/mood_journey_screen.dart';
import 'package:mind_mates/features/mood/widgets/mood_journey_summary.dart';

void main() {
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
          child: const MaterialApp(home: MoodJourneyScreen()),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Okay'));
      await tester.pumpAndSettle();
      expect(find.text('Private account A note'), findsOneWidget);
      auth.switchTo('account-b');
      await tester.pump();
      expect(find.text('Private account A note'), findsNothing);
      expect(find.text('Okay'), findsNothing);
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
          body: MoodJourneySummary(history: history, now: now),
        ),
      ),
    );
    expect(find.byKey(const Key('mood-seven-day-strip')), findsOneWidget);
    expect(find.text('2 check-ins · 1 mood-active day'), findsOneWidget);
    expect(find.text('Most logged mood: Okay'), findsOneWidget);
    expect(find.text('Based on loaded entries'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('journey strip never wraps at $width with large text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.utc(2026, 11, 11);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: MoodJourneySummary(
                  history: const MoodHistoryWindow(
                    events: [],
                    coverage: MoodHistoryCoverage.complete,
                  ),
                  now: now,
                ),
              ),
            ),
          ),
        ),
      );
      final strip = find.byKey(const Key('mood-seven-day-strip'));
      expect(
        tester.widget<SingleChildScrollView>(strip).scrollDirection,
        Axis.horizontal,
      );
      expect(find.text('Mood streak · 0 days'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('journey week month changes counts and respects ties', (
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
          body: MoodJourneySummary(
            history: MoodHistoryWindow(
              events: events,
              coverage: MoodHistoryCoverage.partial,
            ),
            now: now,
          ),
        ),
      ),
    );
    expect(find.text('Most logged moods are tied.'), findsOneWidget);
    expect(find.text('2 check-ins · 1 mood-active day'), findsOneWidget);
    await tester.tap(find.text('This Month'));
    await tester.pumpAndSettle();
    expect(find.text('3 check-ins · 2 mood-active days'), findsOneWidget);
    expect(find.text('Most logged mood: Great'), findsOneWidget);
    expect(find.text('Based on loaded entries'), findsOneWidget);
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
