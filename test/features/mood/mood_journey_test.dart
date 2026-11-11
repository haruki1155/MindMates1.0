import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/features/mood/widgets/mood_v2_history_panel.dart';
import 'package:mind_mates/features/mood/screens/mood_journey_screen.dart';
import 'package:mind_mates/features/home/widgets/home_dashboard_widgets.dart';
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
    expect(find.text('2 check-ins · 1 mood-active day'), findsOneWidget);
    expect(find.text('Most logged mood: Okay'), findsOneWidget);
    expect(find.text('Based on loaded entries'), findsOneWidget);
  });
  testWidgets('home check-in card opens logging and journey', (tester) async {
    var log = 0;
    var journey = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeMoodV2SummaryCard(
            latestLevel: 3,
            entriesToday: 3,
            moodStreakDays: 1,
            isPartial: false,
            onLogMood: () => log++,
            onViewJourney: () => journey++,
          ),
        ),
      ),
    );
    expect(find.text("Today's check-ins: 3"), findsOneWidget);
    await tester.tap(find.text('Log another mood'));
    await tester.tap(find.text('My Mood Journey'));
    expect(log, 1);
    expect(journey, 1);
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
