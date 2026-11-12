import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  group('StreakFlame', () {
    Widget host(int days, {bool disableAnimations = false}) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Center(child: StreakFlame(days: days)),
          ),
        ),
      ),
    );

    testWidgets('flickers for a lit streak', (tester) async {
      await tester.pumpWidget(host(5));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const Key('streak-flame')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('flickers for three loops then rests so screens can settle', (
      tester,
    ) async {
      await tester.pumpWidget(host(5));
      await tester.pump(const Duration(seconds: 7));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byKey(const Key('streak-flame')), findsOneWidget);
    });

    testWidgets('a new streak length flickers again', (tester) async {
      await tester.pumpWidget(host(5));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(6));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpAndSettle();
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
