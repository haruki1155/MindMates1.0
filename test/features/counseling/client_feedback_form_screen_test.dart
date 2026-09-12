import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/screens/client_feedback_form_screen.dart';

void main() {
  testWidgets('feedback form follows the supplied three-step sequence', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: ClientFeedbackFormScreen()),
    );

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(
      find.text('Please complete all required client information.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('client-type-Student')));
    await tester.enterText(
      find.byKey(const ValueKey('client-feedback-name')),
      'Dela Cruz, Juan A.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('client-feedback-course')),
      'BS Psychology',
    );
    await tester.ensureVisible(find.text('Female'));
    await tester.tap(find.text('Female'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('STEP 2 OF 3'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Email address is required'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('client-feedback-email')),
      'student@example.com',
    );
    tester.widget<Checkbox>(find.byType(Checkbox)).onChanged!(true);
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('STEP 3 OF 3'), findsOneWidget);

    await tester.tap(find.text('Submit'));
    await tester.pump();
    expect(find.text('STEP 3 OF 3'), findsOneWidget);

    for (var question = 0; question < 8; question++) {
      final rating = find.byKey(
        ValueKey('feedback-question-$question-rating-5'),
      );
      await tester.scrollUntilVisible(
        rating,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(rating);
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Submit'));
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.byType(ClientFeedbackConfirmationScreen), findsOneWidget);
    expect(find.text('Client Feedback Form'), findsOneWidget);
    expect(find.text('Your response has been recorded.'), findsOneWidget);
  });

  testWidgets(
    'client information cannot finish while required fields are empty',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ClientFeedbackFormScreen()),
      );

      expect(find.text('Client Feedback Form'), findsOneWidget);
      expect(find.text('STEP 1 OF 3'), findsOneWidget);
      expect(find.text('Client information'), findsOneWidget);
    },
  );
}
