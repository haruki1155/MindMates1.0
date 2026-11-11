import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/features/mood/widgets/mood_v2_history_panel.dart';

void main() {
  testWidgets('personal detail shows saved note instead of false empty placeholder', (tester) async {
    final window = MoodHistoryWindow(events: [_event('saved', DateTime.utc(2026, 11, 12), 3, MoodEventSource.v2)], coverage: MoodHistoryCoverage.complete);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MoodV2HistoryPanel(
      history: window, showPersonalDetails: true, v2PersonalNotes: const {'v2:saved': 'A persisted reflection'},
    ))));
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(find.text('A persisted reflection'), findsOneWidget);
    expect(find.text('No note added.'), findsNothing);
  });
  testWidgets(
    'summary separates entries from days and labels windowed streak',
    (tester) async {
      final window = MoodHistoryWindow(
        events: [
          _event('one', DateTime.utc(2026, 7, 7, 16), 2, MoodEventSource.v2),
          _event('two', DateTime.utc(2026, 7, 7, 17), 4, MoodEventSource.v2),
        ],
        coverage: MoodHistoryCoverage.partial,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodV2HistoryPanel(
                history: window,
                analytics: MoodAnalytics.summarize(
                  window,
                  referenceInstant: DateTime.utc(2026, 7, 8),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('2 entries across 1 mood-active day in loaded history'),
        findsOneWidget,
      );
      expect(
        find.text('2 entries · 1 mood-active day this week'),
        findsOneWidget,
      );
      expect(
        find.text('Longest mood streak (loaded window): 1 day'),
        findsOneWidget,
      );
      expect(find.text('Level 2: 1'), findsOneWidget);
    expect(find.text('Latest recorded level: 4/5'), findsOneWidget);
      expect(find.text('Level 4: 1'), findsOneWidget);
      expect(
        find.text('Summary uses incomplete recorded history.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('newest entry renders first within each Manila day', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MoodHistoryWindow(
          events: [
            _event(
              'older',
              DateTime.utc(2026, 7, 7, 16),
              2,
              MoodEventSource.v2,
            ),
            _event(
              'newer',
              DateTime.utc(2026, 7, 7, 17),
              4,
              MoodEventSource.v2,
            ),
          ],
          coverage: MoodHistoryCoverage.complete,
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.textContaining('Mood 4/5')).dy,
      lessThan(tester.getTopLeft(find.textContaining('Mood 2/5')).dy),
    );
  });

  testWidgets('initial history failure offers an explicit retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoodV2HistoryPanel(
            history: null,
            errorMessage: 'Unable to load mood history.',
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Retry history'));
    expect(retries, 1);
  });

  testWidgets('loading is distinct from empty history', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MoodV2HistoryPanel(history: null, isLoading: true),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No mood entries in this history window.'), findsNothing);
  });
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
