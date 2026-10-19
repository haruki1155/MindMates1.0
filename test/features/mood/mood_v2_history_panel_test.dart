import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/features/mood/widgets/mood_v2_history_panel.dart';

void main() {
  testWidgets(
    'groups multiple entries on one Manila date without hiding either',
    (tester) async {
      await tester.pumpWidget(
        _app(
          MoodHistoryWindow(
            events: [
              _event(
                'legacy',
                DateTime.utc(2026, 7, 7, 16),
                2,
                MoodEventSource.legacy,
              ),
              _event(
                'v2-one',
                DateTime.utc(2026, 7, 7, 17),
                4,
                MoodEventSource.v2,
              ),
            ],
            coverage: MoodHistoryCoverage.complete,
          ),
        ),
      );

      expect(find.byKey(const Key('mood-v2-history-list')), findsOneWidget);
      expect(find.text('2026-07-08'), findsOneWidget);
      expect(find.textContaining('Mood 2/5'), findsOneWidget);
      expect(find.textContaining('Mood 4/5'), findsOneWidget);
    },
  );

  testWidgets('distinguishes empty, partial, and failed history', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MoodHistoryWindow(
          events: [],
          coverage: MoodHistoryCoverage.complete,
        ),
      ),
    );
    expect(
      find.text('No mood entries in this history window.'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _app(
        MoodHistoryWindow(
          events: [
            _event('one', DateTime.utc(2026, 7, 8), 3, MoodEventSource.v2),
          ],
          coverage: MoodHistoryCoverage.partial,
        ),
      ),
    );
    expect(find.text('History window is incomplete.'), findsOneWidget);

    await tester.pumpWidget(
      _app(null, errorMessage: 'Unable to load mood history.'),
    );
    expect(find.text('Unable to load mood history.'), findsOneWidget);
  });
}

Widget _app(MoodHistoryWindow? history, {String? errorMessage}) => MaterialApp(
  theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber)),
  home: Scaffold(
    body: MoodV2HistoryPanel(history: history, errorMessage: errorMessage),
  ),
);

NormalizedMoodEvent _event(
  String id,
  DateTime at,
  int level,
  MoodEventSource source,
) => NormalizedMoodEvent(
  id: id,
  userId: 'user_1',
  level: level,
  dateKey: MoodManilaCalendar.dateKeyForInstant(at),
  occurredAt: at,
  source: source,
);
