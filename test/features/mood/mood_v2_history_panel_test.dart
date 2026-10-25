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

  testWidgets(
    'shows an accessible retryable load-more control without hiding history',
    (tester) async {
      var loadMoreCalls = 0;
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          MoodHistoryWindow(
            events: [
              _event('one', DateTime.utc(2026, 7, 8), 3, MoodEventSource.v2),
            ],
            coverage: MoodHistoryCoverage.partial,
          ),
          hasMore: true,
          paginationErrorMessage:
              'Some mood history could not be loaded. Try again.',
          onLoadMore: () => loadMoreCalls++,
        ),
      );

      expect(find.textContaining('Mood 3/5'), findsOneWidget);
      expect(
        find.byKey(const Key('mood-v2-history-pagination-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mood-v2-history-load-more')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Load more mood history'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mood-v2-history-load-more')));
      expect(loadMoreCalls, 1);
    },
  );

  testWidgets('empty partial history still offers an accessible retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _app(
        const MoodHistoryWindow(
          events: [],
          coverage: MoodHistoryCoverage.partial,
        ),
        hasMore: true,
        paginationErrorMessage:
            'Some mood history could not be loaded. Try again.',
        onLoadMore: () => retries++,
      ),
    );

    expect(
      find.byKey(const Key('mood-v2-history-pagination-error')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Load more mood history'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mood-v2-history-load-more')));
    expect(retries, 1);
  });
}

Widget _app(
  MoodHistoryWindow? history, {
  String? errorMessage,
  bool hasMore = false,
  bool isLoadingMore = false,
  String? paginationErrorMessage,
  VoidCallback? onLoadMore,
}) => MaterialApp(
  theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber)),
  home: Scaffold(
    body: MoodV2HistoryPanel(
      history: history,
      errorMessage: errorMessage,
      hasMore: hasMore,
      isLoadingMore: isLoadingMore,
      paginationErrorMessage: paginationErrorMessage,
      onLoadMore: onLoadMore,
    ),
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
