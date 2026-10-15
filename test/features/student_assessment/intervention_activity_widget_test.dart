import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mind_mates/features/student_assessment/models/intervention_models.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_breathing_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_feedback_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_grounding_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_walking_screen.dart';

void main() {
  testWidgets(
    'breathing keeps every control reachable without overflow in short landscape',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: InterventionBreathingScreen()),
      );

      expect(find.textContaining('Inhale'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Restart'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('breathing retains progress and controls after a layout resize', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: InterventionBreathingScreen()),
    );

    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(800, 360));
    await tester.pump();

    expect(find.text('Resume'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('breathing renders all controls in portrait', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: InterventionBreathingScreen()),
    );

    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('breathing exercise pauses, resumes, and restarts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: InterventionBreathingScreen()),
    );

    expect(find.textContaining('Inhale'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);
    await tester.tap(find.text('Restart'));
    await tester.pump();
    expect(find.textContaining('Inhale'), findsOneWidget);
  });

  testWidgets(
    'breathing completes five cycles when the hold phase is disabled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: InterventionBreathingScreen()),
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();
      for (var second = 0; second < 41; second += 1) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(find.text('Breathing exercise'), findsNothing);
    },
  );

  testWidgets('grounding exercise moves through each prompt', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: InterventionGroundingScreen()),
    );

    expect(find.text('Step 1 of 5'), findsOneWidget);
    for (var step = 2; step <= 5; step += 1) {
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Step $step of 5'), findsOneWidget);
    }
    expect(find.text('Finish'), findsOneWidget);
  });

  testWidgets(
    'walking derives progress from sensor baseline and shows fallback on error',
    (tester) async {
      final steps = StreamController<int>.broadcast(sync: true);
      addTearDown(steps.close);
      await tester.pumpWidget(
        MaterialApp(
          home: InterventionWalkingScreen(stepCountStream: steps.stream),
        ),
      );

      steps.add(1000);
      await tester.pump();
      steps.add(1012);
      await tester.pump();
      expect(find.text('12 / 500 steps'), findsOneWidget);

      steps.addError(StateError('sensor unavailable'));
      await tester.pump();
      expect(
        find.textContaining('Automatic step counting is unavailable'),
        findsOneWidget,
      );
      expect(find.text('Use timed-walk option'), findsOneWidget);
    },
  );

  testWidgets('walking completes after 500 sensor steps', (tester) async {
    final steps = StreamController<int>.broadcast(sync: true);
    addTearDown(steps.close);
    late Future<InterventionOutcome?> outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              outcome = Navigator.of(context).push<InterventionOutcome>(
                MaterialPageRoute(
                  builder: (_) =>
                      InterventionWalkingScreen(stepCountStream: steps.stream),
                ),
              );
            },
            child: const Text('Start walking'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Start walking'));
    await tester.pumpAndSettle();
    steps
      ..add(1000)
      ..add(1500);
    await tester.pumpAndSettle();

    expect(await outcome, InterventionOutcome.completed);
  });

  testWidgets('walking offers recovery when the sensor remains silent', (
    tester,
  ) async {
    final steps = StreamController<int>.broadcast(sync: true);
    addTearDown(steps.close);
    await tester.pumpWidget(
      MaterialApp(
        home: InterventionWalkingScreen(stepCountStream: steps.stream),
      ),
    );

    await tester.pump(const Duration(seconds: 15));

    expect(find.textContaining('No step reading arrived'), findsOneWidget);
    expect(find.text('Use timed-walk option'), findsOneWidget);
  });

  testWidgets('walking offers safe recovery when permission is denied', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InterventionWalkingScreen(
          requestActivityRecognitionPermission: () async =>
              PermissionStatus.denied,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('permission was not granted'), findsOneWidget);
    expect(find.text('Use timed-walk option'), findsOneWidget);
  });

  testWidgets('walking does not count sensor steps received while paused', (
    tester,
  ) async {
    final steps = StreamController<int>.broadcast(sync: true);
    addTearDown(steps.close);
    await tester.pumpWidget(
      MaterialApp(
        home: InterventionWalkingScreen(stepCountStream: steps.stream),
      ),
    );
    steps
      ..add(1000)
      ..add(1010);
    await tester.pump();
    await tester.tap(find.text('Pause'));
    await tester.pump();
    steps.add(1200);
    await tester.pump();
    expect(find.text('10 / 500 steps'), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await tester.pump();
    steps.add(1210);
    await tester.pump();
    expect(find.text('10 / 500 steps'), findsOneWidget);
  });

  testWidgets(
    'walking reports a delayed reading and recovers after counter reset',
    (tester) async {
      final steps = StreamController<int>.broadcast(sync: true);
      addTearDown(steps.close);
      await tester.pumpWidget(
        MaterialApp(
          home: InterventionWalkingScreen(
            stepCountStream: steps.stream,
            initialReadingDelay: const Duration(seconds: 1),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Still waiting'), findsOneWidget);
      steps
        ..add(1000)
        ..add(1010)
        ..add(4)
        ..add(14);
      await tester.pump();
      expect(find.text('20 / 500 steps'), findsOneWidget);
    },
  );

  testWidgets('feedback permits a neutral choice with no reflection', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: InterventionFeedbackScreen()),
    );
    await tester.tap(find.text('Neutral / Not sure'));
    await tester.pump();
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Yes, it helped'), findsOneWidget);
    expect(find.text("No, it didn't help"), findsOneWidget);
    expect(find.textContaining('optional'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('walking ignores invalid negative counter readings', (
    tester,
  ) async {
    final steps = StreamController<int>.broadcast(sync: true);
    addTearDown(steps.close);
    await tester.pumpWidget(
      MaterialApp(
        home: InterventionWalkingScreen(stepCountStream: steps.stream),
      ),
    );
    steps
      ..add(100)
      ..add(-1)
      ..add(105);
    await tester.pump();
    expect(find.text('5 / 500 steps'), findsOneWidget);
  });

  testWidgets('manual fallback is explicitly selected before self-reporting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InterventionWalkingScreen(
          requestActivityRecognitionPermission: () async =>
              PermissionStatus.denied,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Record self-reported walk'), findsNothing);
    await tester.tap(find.text('Use timed-walk option'));
    await tester.pump();
    expect(find.text('Record self-reported walk'), findsOneWidget);
  });
}
