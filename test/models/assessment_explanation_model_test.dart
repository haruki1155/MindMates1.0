import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/assessment_explanation_model.dart';

void main() {
  test('builds a non-labeling quick explanation from one-item indicators', () {
    final explanation = AssessmentExplanationModel.fromAssessment({
      'type': 'quick',
      'concernScore': 50,
      'overallLevel': 'moderate',
      'createdAt': '2026-09-06T08:00:00.000Z',
      'interpretation': {
        'recallPeriodDays': 14,
        'supportPriority': 'monitor',
        'responseQuality': {
          'presented': 5,
          'answered': 5,
          'confidenceLabel': 'High confidence',
        },
        'rationale': ['Higher signals appeared in Stress load.'],
        'userSummary':
            'Responses suggest a moderate current wellness signal. This is not a diagnosis.',
        'domainResults': [
          {
            'domain': 'Stress load',
            'score': 75,
            'answeredCount': 1,
            'presentedCount': 1,
            'isScorable': true,
            'interpretation': 'This area is a wellness screening signal.',
          },
        ],
      },
    });

    expect(explanation.patternLabel, 'Areas to strengthen');
    expect(explanation.followUpGuidance, 'Continue monitoring');
    expect(explanation.isQuick, isTrue);
    expect(explanation.areas.single.patternLabel, 'Support may be useful');
    expect(explanation.summary, isNot(contains('diagnosis')));
  });

  test('adapts legacy full labels without rewriting the stored record', () {
    final explanation = AssessmentExplanationModel.fromAssessment({
      'type': 'student',
      'status': 'Needs Improvement',
      'interpretation': {
        'supportPriority': 'followUpSuggested',
        'responseQuality': {'presented': 50, 'answered': 45},
      },
    });

    expect(explanation.patternLabel, 'Areas to strengthen');
    expect(explanation.followUpGuidance, 'Consider additional support');
    expect(explanation.answeredCount, 45);
  });
}
