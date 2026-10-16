import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/quick_assessment/data/quick_assessment_questions.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/features/quick_assessment/screens/quick_assessment_category_screen.dart';
import 'package:mind_mates/features/counseling/screens/pacc_counseling_screen.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'low shows supportive guidance without full assessment or PACC actions',
    (tester) async {
      await _pumpResult(tester, _resultProvider([0, 0, 0, 0, 0]));

      expect(find.text('Continue with your day'), findsOneWidget);
      expect(find.text('Take Full Assessment'), findsNothing);
      expect(find.text('Book a PACC appointment'), findsNothing);
      expect(
        find.text('Would you like to talk with a PACC counselor?'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'moderate recommends full assessment without an appointment prompt',
    (tester) async {
      await _pumpResult(tester, _resultProvider([1, 2, 1, 1, 2]));

      expect(find.text('A fuller check-in may help'), findsOneWidget);
      expect(find.text('Take Full Assessment'), findsOneWidget);
      expect(find.text('Book a PACC appointment'), findsNothing);
      expect(
        find.text('Would you like to talk with a PACC counselor?'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'high shows optional PACC booking without an appointment prompt',
    (tester) async {
      await _pumpResult(tester, _resultProvider([3, 3, 3, 2, 3]));

      expect(find.text('Consider additional support'), findsOneWidget);
      expect(find.text('Take Full Assessment'), findsOneWidget);
      expect(find.text('Book a PACC appointment'), findsOneWidget);
      expect(
        find.text('Would you like to talk with a PACC counselor?'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'very high prompts once and decline preserves the result on rebuild',
    (tester) async {
      final provider = _resultProvider([4, 4, 4, 3, 4]);
      await _pumpResult(tester, provider);

      expect(find.text('Support is available'), findsOneWidget);
      expect(
        find.text('Would you like to talk with a PACC counselor?'),
        findsOneWidget,
      );
      await tester.tap(find.text('No, Continue'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Support is available'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _pumpResult(tester, provider);
      expect(
        find.text('Would you like to talk with a PACC counselor?'),
        findsNothing,
      );
      expect(find.text('Support is available'), findsOneWidget);

      provider.resetQuestions();
      _completeWithOptions(provider, [4, 4, 4, 3, 4]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Would you like to talk with a PACC counselor?'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'very high acceptance opens PACC and returning preserves the result',
    (tester) async {
      await _pumpResult(tester, _resultProvider([4, 4, 4, 3, 4]));

      await tester.tap(find.text('Yes, Book Appointment'));
      await tester.pumpAndSettle();
      expect(find.byType(PaccCounselingScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Support is available'), findsOneWidget);
    },
  );
}

Future<void> _pumpResult(
  WidgetTester tester,
  AssessmentProvider provider,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AssessmentProvider>.value(
      value: provider,
      child: const MaterialApp(home: QuickAssessmentCategoryScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

AssessmentProvider _resultProvider(List<int> optionIndexes) {
  final provider = AssessmentProvider(AssessmentRepository())
    ..selectRole(AssessmentRole.student)
    ..updateName('Taylor');
  _completeWithOptions(provider, optionIndexes);
  return provider;
}

void _completeWithOptions(
  AssessmentProvider provider,
  List<int> optionIndexes,
) {
  for (
    var index = 0;
    index < QuickAssessmentQuestions.questions.length;
    index += 1
  ) {
    final question = QuickAssessmentQuestions.questions[index];
    provider.selectAnswer(question.options[optionIndexes[index]]);
    provider.moveToNextQuestion();
  }
}
