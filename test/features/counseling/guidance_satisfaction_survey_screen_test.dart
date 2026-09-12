import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/data/guidance_satisfaction_survey.dart';
import 'package:mind_mates/features/counseling/screens/guidance_satisfaction_survey_screen.dart';

void main() {
  test(
    'survey follows the six supplied image sections with ten questions each',
    () {
      expect(guidanceSurveySections.map((section) => section.title), [
        'Information Service',
        'Individual Inventory Service',
        'Counseling Service',
        'Placement Service',
        'Follow-up Service',
        'Referral Service',
      ]);
      expect(
        guidanceSurveySections.every(
          (section) => section.questions.length == 10,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'survey requires every response before opening the next section',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: GuidanceSatisfactionSurveyScreen()),
      );

      await tester.tap(find.text('Next section'));
      await tester.pump();
      expect(
        find.text('Please answer question 1 before continuing.'),
        findsOneWidget,
      );

      for (var question = 1; question <= 10; question++) {
        final choice = find.byKey(ValueKey('question-$question-rating-5'));
        await tester.scrollUntilVisible(
          choice,
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(choice);
        await tester.pump();
      }
      await tester.ensureVisible(find.text('Next section'));
      await tester.tap(find.text('Next section'));
      await tester.pumpAndSettle();

      expect(find.text('Individual Inventory Service'), findsOneWidget);
      expect(find.text('SECTION 2 OF 6'), findsOneWidget);
      expect(find.text('10 of 60 answered'), findsOneWidget);
    },
  );

  testWidgets('confirmation clearly identifies the local-only UI state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: GuidanceSurveyConfirmationScreen()),
    );

    expect(find.text('Survey complete'), findsOneWidget);
    expect(find.textContaining('Secure submission'), findsOneWidget);
    expect(find.text('Return to services'), findsOneWidget);
  });
}
