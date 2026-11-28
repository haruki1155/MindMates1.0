import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/home/domain/home_streak_source.dart';
import 'package:mind_mates/features/home/widgets/streak_flame.dart';

void main() {
  group('streakFlameColor', () {
    test('hits the exact stops from deep red to royal blue', () {
      expect(streakFlameColor(1), const Color(0xFFC62828));
      expect(streakFlameColor(7), const Color(0xFFA0237A));
      expect(streakFlameColor(14), const Color(0xFF7B2FA8));
      expect(streakFlameColor(21), const Color(0xFF5B3FC4));
      expect(streakFlameColor(30), const Color(0xFF4169E1));
      expect(streakFlameColor(61), const Color(0xFF4169E1));
      expect(streakFlameColor(365), const Color(0xFF4169E1));
    });

    test('day 0 is the unlit grey', () {
      expect(
        streakFlameColor(0),
        const Color(0xFFB8B2A6).withValues(alpha: .6),
      );
    });

    test('interpolates between stops', () {
      expect(
        streakFlameColor(4),
        Color.lerp(const Color(0xFFC62828), const Color(0xFFA0237A), 3 / 6),
      );
    });
  });

  group('streakFlamePalette', () {
    test('returns distinct 3-layer palettes per tier and interpolates smoothly', () {
      final day1 = streakFlamePalette(1);
      final day7 = streakFlamePalette(7);
      final day4 = streakFlamePalette(4);
      final day30 = streakFlamePalette(30);

      expect(day1.outer, const Color(0xFFC62828));
      expect(day1.mid, const Color(0xFFFA6B1F));
      expect(day1.core, const Color(0xFFFFF0B8));

      expect(day4, StreakFlamePalette.lerp(day1, day7, 3 / 6));
      expect(day30.outer, const Color(0xFF4169E1));
      expect(day30.mid, const Color(0xFF3DB8FA));
      expect(day30.core, const Color(0xFFE0FAFF));
      expect(streakFlamePalette(90), day30);
    });
  });

  group('StreakFlame', () {
    Widget host(
      int days, {
      double size = 84,
      HomeStreakState? state,
      bool disableAnimations = false,
    }) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Center(
              child: StreakFlame(days: days, size: size, state: state),
            ),
          ),
        ),
      ),
    );

    testWidgets('animates continuously for a lit streak inside RepaintBoundary', (
      tester,
    ) async {
      await tester.pumpWidget(host(5));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const Key('streak-flame')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('streak-flame')),
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      // Remains smoothly animating well past a short entrance loop.
      await tester.pump(const Duration(seconds: 10));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('transitions smoothly across streak states and sizes', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(4, size: 44, state: HomeStreakState.activeNotToday),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pumpWidget(
        host(7, size: 84, state: HomeStreakState.milestone),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('relights after going out without errors', (tester) async {
      await tester.pumpWidget(host(5));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(host(0, state: HomeStreakState.notStarted));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.binding.transientCallbackCount, 0);

      await tester.pumpWidget(host(1, state: HomeStreakState.doneToday));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('survives reduced motion being toggled', (tester) async {
      await tester.pumpWidget(host(5));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(host(5, disableAnimations: true));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      await tester.pumpWidget(host(5));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('stays still when animations are disabled', (tester) async {
      await tester.pumpWidget(host(5, disableAnimations: true));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('an unlit flame never animates', (tester) async {
      await tester.pumpWidget(host(0));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
