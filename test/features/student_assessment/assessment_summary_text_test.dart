import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/student_assessment/services/assessment_summary_text.dart';

void main() {
  test('removes a trailing response completeness sentence from saved text', () {
    expect(
      withoutResponseCompleteness(
        'A saved reflection. You answered 40 of 50 questions, giving this result Moderate RESPONSE COMPLETENESS.',
      ),
      'A saved reflection.',
    );
  });

  test(
    'leaves summaries without a trailing completeness sentence unchanged',
    () {
      const summary =
          '  You answered questions thoughtfully. Keep reflecting.  ';
      expect(withoutResponseCompleteness(summary), summary);
    },
  );

  test('does not remove a completeness phrase in the middle of a summary', () {
    const summary =
        'You answered 40 of 50 questions, giving this result moderate response completeness. A next step remains.';
    expect(withoutResponseCompleteness(summary), summary);
  });
}
