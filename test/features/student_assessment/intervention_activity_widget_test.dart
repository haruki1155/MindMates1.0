import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/student_assessment/models/intervention_models.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_breathing_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_grounding_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_walking_screen.dart';

void main() {
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
      expect(find.text('I completed my walk'), findsOneWidget);
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
}
