import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/theme/app_theme.dart';
import 'package:mind_mates/features/student_assessment/models/intervention_models.dart';
import 'package:mind_mates/features/student_assessment/screens/student_v4_category_intervention_screen.dart';

void main() {
  Future<void> openScreen(
    WidgetTester tester, {
    required InterventionType type,
    required ValueSetter<InterventionOutcome?> onResult,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                final res = await Navigator.of(context)
                    .push<InterventionOutcome>(
                      MaterialPageRoute(
                        builder: (_) => StudentV4CategoryInterventionScreen(
                          intervention: type,
                        ),
                      ),
                    );
                onResult(res);
              },
              child: const Text('Open activity'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open activity'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Academic planning shows 5-minute steps, cues, non-saved note, and completes/skips/cancels cleanly',
    (tester) async {
      InterventionOutcome? result;
      await openScreen(
        tester,
        type: InterventionType.academicPlanning,
        onResult: (v) => result = v,
      );

      expect(find.text('Start with five minutes'), findsOneWidget);
      expect(
        find.text('Your choices and notes stay on this screen and are not saved.'),
        findsOneWidget,
      );
      expect(find.textContaining('diagnos'), findsNothing);
      expect(find.byKey(const Key('academic-note-field')), findsOneWidget);

      await tester.ensureVisible(find.text('Open and skim the first section'));
      await tester.tap(find.text('Open and skim the first section'));
      await tester.pump();
      await tester.ensureVisible(find.text('Right after this assessment'));
      await tester.tap(find.text('Right after this assessment'));
      await tester.pump();
      expect(find.text('Your on-screen plan'), findsOneWidget);
      expect(
        find.text('Step: Open and skim the first section'),
        findsOneWidget,
      );
      expect(
        find.text('When: Right after this assessment'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Finish activity'));
      await tester.tap(find.text('Finish activity'));
      await tester.pumpAndSettle();
      expect(result, InterventionOutcome.completed);

      // Completing without any optional selection works, as do Skip and Back.
      await tester.tap(find.text('Open activity'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Skip activity'));
      await tester.tap(find.text('Skip activity'));
      await tester.pumpAndSettle();
      expect(result, InterventionOutcome.skipped);

      await tester.tap(find.text('Open activity'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );

  testWidgets(
    'Financial planning avoids balance/income/advice requests and completes without selections in dark landscape',
    (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      InterventionOutcome? result;
      await openScreen(
        tester,
        type: InterventionType.financialPlanning,
        theme: AppTheme.dark,
        onResult: (v) => result = v,
      );

      expect(find.text('Choose one practical next step'), findsOneWidget);
      expect(
        find.textContaining('not financial advice'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const Key('academic-note-field')), findsNothing);
      expect(
        find.text('Check one upcoming due date or school fee deadline'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(find.text('Finish activity'), 200);
      await tester.tap(find.text('Finish activity'));
      await tester.pumpAndSettle();
      expect(result, InterventionOutcome.completed);
      expect(tester.takeException(), isNull);
    },
  );
}
