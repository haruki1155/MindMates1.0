import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/features/quick_assessment/services/quick_assessment_action_policy.dart';

void main() {
  test('maps low to supportive guidance without emphasized actions', () {
    final policy = QuickAssessmentActionPolicy.forLevel(
      QuickAssessmentLevel.low,
    );

    expect(policy.recommendsFullAssessment, isFalse);
    expect(policy.showsFullAssessmentAction, isFalse);
    expect(policy.showsAppointmentAction, isFalse);
    expect(policy.promptsForAppointment, isFalse);
  });

  test('maps moderate to a recommended full assessment without booking', () {
    final policy = QuickAssessmentActionPolicy.forLevel(
      QuickAssessmentLevel.moderate,
    );

    expect(policy.recommendsFullAssessment, isTrue);
    expect(policy.showsFullAssessmentAction, isTrue);
    expect(policy.showsAppointmentAction, isFalse);
    expect(policy.promptsForAppointment, isFalse);
  });

  test('maps high to full assessment and optional PACC booking', () {
    final policy = QuickAssessmentActionPolicy.forLevel(
      QuickAssessmentLevel.high,
    );

    expect(policy.recommendsFullAssessment, isTrue);
    expect(policy.showsFullAssessmentAction, isTrue);
    expect(policy.showsAppointmentAction, isTrue);
    expect(policy.promptsForAppointment, isFalse);
  });

  test(
    'maps veryHigh to one prominent appointment prompt and secondary full assessment',
    () {
      final policy = QuickAssessmentActionPolicy.forLevel(
        QuickAssessmentLevel.veryHigh,
      );

      expect(policy.recommendsFullAssessment, isFalse);
      expect(policy.showsFullAssessmentAction, isTrue);
      expect(policy.showsAppointmentAction, isTrue);
      expect(policy.promptsForAppointment, isTrue);
    },
  );
}
