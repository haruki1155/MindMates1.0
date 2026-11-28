import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mind_mates/core/constants/app_colors.dart';
import 'package:mind_mates/core/theme/app_theme.dart';
import 'package:mind_mates/features/student_assessment/models/intervention_models.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_breathing_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_feedback_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_grounding_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_walking_screen.dart';
import 'package:mind_mates/features/student_assessment/widgets/assessment_presentation.dart';

double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final darker = identical(lighter, first) ? second : first;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

void main() {
  testWidgets('assessment gold presentation keeps AA contrast in light mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            final surface = Theme.of(context).colorScheme.surface;
            final softSurface = Color.alphaBlend(
              AssessmentPresentation.softAccent(context),
              surface,
            );
            expect(
              _contrastRatio(
                AssessmentPresentation.onAccent,
                AssessmentPresentation.accent,
              ),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              _contrastRatio(
                AssessmentPresentation.onSoftAccent(context),
                softSurface,
              ),
              greaterThanOrEqualTo(4.5),
            );
            expect(AppColors.error, isNot(AssessmentPresentation.accent));
            return const AssessmentStatusPill(label: 'Support may be helpful');
          },
        ),
      ),
    );

    expect(find.text('Support may be helpful'), findsOneWidget);
  });

  testWidgets('assessment gold presentation keeps AA contrast in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) {
            final surface = Theme.of(context).colorScheme.surface;
            final softSurface = Color.alphaBlend(
              AssessmentPresentation.softAccent(context),
              surface,
            );
            expect(
              _contrastRatio(
                AssessmentPresentation.onSoftAccent(context),
                softSurface,
              ),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              _contrastRatio(
                AssessmentPresentation.actionForeground(context),
                surface,
              ),
              greaterThanOrEqualTo(4.5),
            );
            return Column(
              children: [
                const AssessmentStatusPill(label: 'Support may be helpful'),
                OutlinedButton(
                  style: AssessmentPresentation.outlinedButtonStyle(context),
                  onPressed: () {},
                  child: const Text('Restart'),
                ),
                TextButton(
                  style: AssessmentPresentation.textButtonStyle(context),
                  onPressed: () {},
                  child: const Text('Skip activity'),
                ),
              ],
            );
          },
        ),
      ),
    );

    expect(find.text('Restart'), findsOneWidget);
    expect(find.text('Skip activity'), findsOneWidget);
  });

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
      expect(find.text('Skip activity'), findsOneWidget);
      expect(find.text('Pause exercise'), findsOneWidget);
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
    await tester.tap(find.text('Pause exercise'));
    await tester.pump();
    expect(find.text('Resume exercise'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(800, 360));
    await tester.pump();

    expect(find.text('Resume exercise'), findsOneWidget);
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
    expect(find.text('Skip activity'), findsOneWidget);
    expect(find.text('Pause exercise'), findsOneWidget);
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
    await tester.tap(find.text('Pause exercise'));
    await tester.pump();
    expect(find.text('Resume exercise'), findsOneWidget);
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
    await tester.tap(find.text('Pause tracking'));
    await tester.pump();
    steps.add(1200);
    await tester.pump();
    expect(find.text('10 / 500 steps'), findsOneWidget);
    await tester.tap(find.text('Resume tracking'));
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
    expect(find.text('Continue assessment'), findsOneWidget);
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

  testWidgets('feedback Skip feedback returns null and does not block', (
    tester,
  ) async {
    Object? popped = 'sentinel';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<InterventionFeedback>(
                MaterialPageRoute(
                  builder: (_) => const InterventionFeedbackScreen(),
                ),
              );
            },
            child: const Text('Open feedback'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open feedback'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Skip feedback'));
    await tester.tap(find.text('Skip feedback'));
    await tester.pumpAndSettle();
    expect(popped, isNull);
  });

  testWidgets(
    'Student V4 self-reported walking never requests permission, completes, skips, and handles dark landscape',
    (tester) async {
      var permissionCalls = 0;
      InterventionOutcome? outcome;
      Future<void> pushWalking(WidgetTester tester, ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  outcome = await Navigator.of(context)
                      .push<InterventionOutcome>(
                        MaterialPageRoute(
                          builder: (_) => InterventionWalkingScreen(
                            selfReportedMode: true,
                            requestActivityRecognitionPermission: () async {
                              permissionCalls += 1;
                              return PermissionStatus.denied;
                            },
                          ),
                        ),
                      );
                },
                child: const Text('Open walk'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open walk'));
        await tester.pumpAndSettle();
      }

      await pushWalking(tester, AppTheme.light);
      expect(permissionCalls, 0);
      expect(find.text('Take a short walk'), findsWidgets);
      expect(find.text('500-step goal'), findsNothing);
      expect(find.textContaining('/ 500 steps'), findsNothing);
      expect(find.textContaining('sensor'), findsOneWidget);

      await tester.tap(find.text('I took a short walk'));
      await tester.pumpAndSettle();
      expect(outcome, InterventionOutcome.selfReportedCompleted);

      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pushWalking(tester, AppTheme.dark);
      await tester.scrollUntilVisible(find.text('Skip activity'), 200);
      await tester.tap(find.text('Skip activity'));
      await tester.pumpAndSettle();
      expect(outcome, InterventionOutcome.skipped);
      expect(permissionCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Student V4 grounding adds optional feeling prompt on step 6, allows blank finish, and supports skip',
    (tester) async {
      InterventionOutcome? outcome;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                outcome = await Navigator.of(context).push<InterventionOutcome>(
                  MaterialPageRoute(
                    builder: (_) => const InterventionGroundingScreen(
                      includeFeelingPrompt: true,
                    ),
                  ),
                );
              },
              child: const Text('Open grounding'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open grounding'));
      await tester.pumpAndSettle();

      expect(find.text('Ground and notice'), findsOneWidget);
      for (var step = 1; step <= 5; step += 1) {
        expect(find.text('Step $step of 6'), findsOneWidget);
        await tester.tap(find.text('Next'));
        await tester.pump();
      }
      expect(find.text('Step 6 of 6'), findsOneWidget);
      expect(find.text('Notice or name a feeling (optional)'), findsOneWidget);
      expect(find.textContaining('Nothing here is saved.'), findsOneWidget);
      expect(find.byKey(const Key('grounding-feeling-note')), findsOneWidget);

      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(outcome, InterventionOutcome.completed);

      await tester.tap(find.text('Open grounding'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip activity'));
      await tester.pumpAndSettle();
      expect(outcome, InterventionOutcome.skipped);
    },
  );
}
