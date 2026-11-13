import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/home/domain/home_streak_source.dart';
import 'package:mind_mates/features/home/models/home_dashboard_data.dart';
import 'package:mind_mates/features/home/widgets/home_dashboard_widgets.dart';

void main() {
  HomeStreakData data(
    HomeStreakState state,
    int days, {
    bool canViewRecap = false,
  }) => HomeStreakData(
    title: 'Day streak',
    days: days,
    description: homeStreakDescription(
      state,
      days: days,
      canViewRecap: canViewRecap,
    ),
    linkLabel: '',
    state: state,
    canViewRecap: canViewRecap,
  );

  Future<({List<String> taps})> pump(
    WidgetTester tester,
    HomeStreakData streak, {
    double width = 390,
  }) async {
    final taps = <String>[];
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: HomeStreakCard(
                  data: streak,
                  onTap: () => taps.add('card'),
                  onViewRecap: () => taps.add('recap'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (taps: taps);
  }

  testWidgets('not started asks for the first check-in', (tester) async {
    final result = await pump(tester, data(HomeStreakState.notStarted, 0));
    expect(find.text('Log your mood today to start a streak.'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('days'), findsOneWidget);
    await tester.tap(find.text('Log mood'));
    expect(result.taps, ['card']);
    expect(find.byKey(const Key('streak-flame')), findsOneWidget);
  });

  testWidgets('Log mood pill matches the gold card', (tester) async {
    await pump(tester, data(HomeStreakState.notStarted, 0));
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Log mood'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.style?.backgroundColor?.resolve({}), HomePalette.surface);
    expect(button.style?.foregroundColor?.resolve({}), HomePalette.text);
  });

  testWidgets('active but not checked in today', (tester) async {
    await pump(tester, data(HomeStreakState.activeNotToday, 4));
    expect(find.text('4'), findsOneWidget);
    expect(find.text('days'), findsOneWidget);
    expect(find.text('Check in today to keep your streak.'), findsOneWidget);
    expect(find.text('Log mood'), findsOneWidget);
  });

  testWidgets('done today uses the singular day and no button', (tester) async {
    await pump(tester, data(HomeStreakState.doneToday, 1));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('day'), findsOneWidget);
    expect(find.text('days'), findsNothing);
    expect(find.text('Done for today. See you tomorrow!'), findsOneWidget);
    expect(find.text('Log mood'), findsNothing);
    expect(find.byKey(const Key('streak-flame')), findsOneWidget);
  });

  testWidgets('milestone opens the recap', (tester) async {
    final result = await pump(
      tester,
      data(HomeStreakState.milestone, 7, canViewRecap: true),
    );
    expect(find.text('Your week in moods is ready'), findsOneWidget);
    await tester.tap(find.text('View recap ›'));
    expect(result.taps, ['recap']);
  });

  testWidgets('milestone without Journey shows a celebration only', (
    tester,
  ) async {
    await pump(tester, data(HomeStreakState.milestone, 7));
    expect(find.text('Milestone reached: 7 days!'), findsOneWidget);
    expect(find.text('View recap ›'), findsNothing);
  });

  for (final state in HomeStreakState.values) {
    testWidgets('${state.name} fits a 360 px phone', (tester) async {
      await pump(
        tester,
        data(
          state,
          state == HomeStreakState.notStarted ? 0 : 30,
          canViewRecap: true,
        ),
        width: 360,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
