import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/quick_assessment/data/quick_assessment_questions.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/features/quick_assessment/screens/quick_assessment_category_screen.dart';
import 'package:mind_mates/features/quick_assessment/services/quick_assessment_scoring.dart';
import 'package:mind_mates/features/quick_assessment/widgets/quick_result_visuals.dart';
import 'package:mind_mates/features/student_assessment/models/assessment_interpretation_models.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:provider/provider.dart';

void main() {
  test('QuickPatternVisual maps every code and falls back', () {
    expect(
      QuickPatternVisual.forCode('wellBeingSupported').icon,
      Icons.sentiment_very_satisfied_rounded,
    );
    expect(
      QuickPatternVisual.forCode('generallySteady').icon,
      Icons.sentiment_satisfied_rounded,
    );
    expect(
      QuickPatternVisual.forCode('someStrain').icon,
      Icons.sentiment_neutral_rounded,
    );
    expect(
      QuickPatternVisual.forCode('supportMayHelp').color,
      const Color(0xFFC62828),
    );
    expect(
      QuickPatternVisual.forCode('supportMayHelp').label,
      'Support may be useful',
    );
    expect(
      QuickPatternVisual.forCode('bogus').icon,
      Icons.help_outline_rounded,
    );
  });

  testWidgets(
    'low-concern result shows illustration, per-indicator icons and legend',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpResult(tester, pickLowestConcern: true);

      expect(
        find.descendant(
          of: find.byKey(const Key('quick-result-illustration')),
          matching: find.byIcon(Icons.sentiment_very_satisfied_rounded),
        ),
        findsOneWidget,
      );
      for (final domain
          in QuickAssessmentScoring.concernAreasByQuestionId.values) {
        final row = find.byKey(ValueKey('quick-indicator-$domain'));
        expect(row, findsOneWidget, reason: domain);
        expect(
          find.descendant(of: row, matching: find.byIcon(quickDomainIcon(domain))),
          findsOneWidget,
          reason: domain,
        );
      }
      final legend = find.byKey(const Key('quick-pattern-legend'));
      expect(legend, findsOneWidget);
      for (final code in QuickPatternVisual.legendCodes) {
        expect(
          find.descendant(
            of: legend,
            matching: find.text(AssessmentResponsePattern.labelForCode(code)),
          ),
          findsOneWidget,
          reason: code,
        );
      }
      expect(find.byIcon(Icons.school_rounded), findsOneWidget);
      expect(find.text('ST'), findsNothing);
    },
  );

  testWidgets('high-concern result at 360px: no overflow, prompt still shown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpResult(tester, pickLowestConcern: false);

    expect(tester.takeException(), isNull);
    expect(
      find.text('Would you like to talk with a PACC counselor?'),
      findsOneWidget,
    );
    await tester.tap(find.text('No, Continue'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Would you like to talk with a PACC counselor?'),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('quick-indicator-Stress load')),
        matching: find.byIcon(Icons.volunteer_activism_rounded),
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpResult(
  WidgetTester tester, {
  required bool pickLowestConcern,
}) async {
  final provider = AssessmentProvider(AssessmentRepository())
    ..beginQuickAssessment(role: AssessmentRole.student, name: 'Leo');
  for (final question in QuickAssessmentQuestions.questions) {
    provider.selectAnswer(
      pickLowestConcern ? question.options.first : question.options.last,
    );
    provider.moveToNextQuestion();
  }
  expect(provider.quickResult, isNotNull);

  await tester.pumpWidget(
    ChangeNotifierProvider<AssessmentProvider>.value(
      value: provider,
      child: const MaterialApp(home: QuickAssessmentCategoryScreen()),
    ),
  );
  await tester.pumpAndSettle();
}
