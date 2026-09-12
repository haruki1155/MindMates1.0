import '../models/quick_assessment_models.dart';
import '../../student_assessment/models/assessment_interpretation_models.dart';

class QuickAssessmentScoring {
  const QuickAssessmentScoring._();

  static const Map<String, String> concernAreasByQuestionId = {
    'calm_relaxed': 'Emotional calm',
    'overwhelmed': 'Stress load',
    'connected': 'Social connection',
    'little_interest': 'Motivation and interest',
    'stress_affecting_life': 'Daily coping',
  };

  static double concernScore({
    required QuickQuestionDirection direction,
    required int value,
    int minValue = 1,
    int maxValue = 5,
  }) {
    final range = maxValue - minValue;
    if (range <= 0) return 0;
    if (direction == QuickQuestionDirection.protective) {
      return ((maxValue - value) / range) * 100;
    }

    return ((value - minValue) / range) * 100;
  }

  static String progressLabelForStep(int step, {int total = 5}) {
    return '${step.clamp(1, total)}/$total';
  }

  static double averageConcernScore(List<QuickAssessmentResponse> responses) {
    if (responses.isEmpty) return 0;

    final total = responses.fold<double>(
      0,
      (sum, response) => sum + response.concernScore,
    );

    return double.parse((total / responses.length).toStringAsFixed(2));
  }

  static Map<String, double> areaScores(
    List<QuickAssessmentResponse> responses,
  ) {
    final scores = <String, double>{};

    for (final response in responses) {
      final area =
          concernAreasByQuestionId[response.questionId] ?? 'General well-being';
      scores[area] = response.concernScore;
    }

    return scores;
  }

  static QuickAssessmentLevel overallLevel(double concernScore) {
    if (concernScore >= 75) return QuickAssessmentLevel.veryHigh;
    if (concernScore >= 55) return QuickAssessmentLevel.high;
    if (concernScore >= 30) return QuickAssessmentLevel.moderate;
    return QuickAssessmentLevel.low;
  }

  static QuickAssessmentSignal signalForLevel(QuickAssessmentLevel level) {
    switch (level) {
      case QuickAssessmentLevel.low:
        return QuickAssessmentSignal.stable;
      case QuickAssessmentLevel.moderate:
        return QuickAssessmentSignal.watchful;
      case QuickAssessmentLevel.high:
        return QuickAssessmentSignal.elevated;
      case QuickAssessmentLevel.veryHigh:
        return QuickAssessmentSignal.highSupport;
    }
  }

  static List<String> topConcernAreas(List<QuickAssessmentResponse> responses) {
    final sorted = areaScores(responses).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .where((entry) => entry.value >= 30)
        .take(3)
        .map((entry) => entry.key)
        .toList();
  }

  static String summaryForLevel(QuickAssessmentLevel level) {
    switch (level) {
      case QuickAssessmentLevel.low:
        return 'Your brief check-in shows several supportive patterns worth continuing.';
      case QuickAssessmentLevel.moderate:
        return 'Your brief check-in appears generally balanced, with some opportunities for continued awareness.';
      case QuickAssessmentLevel.high:
        return 'Your brief check-in highlights one or more areas you may want to explore more closely.';
      case QuickAssessmentLevel.veryHigh:
        return 'Your brief check-in highlights areas where support may make current challenges easier to manage.';
    }
  }

  static String summaryForScore(double score) {
    final pattern = AssessmentResponsePattern.codeForScore(score);
    return switch (pattern) {
      'wellBeingSupported' =>
        'Your brief check-in shows several supportive patterns worth continuing.',
      'generallySteady' =>
        'Your brief check-in appears generally balanced, with some opportunities for continued awareness.',
      'someStrain' =>
        'Your brief check-in highlights one or more areas you may want to explore more closely.',
      _ =>
        'Your brief check-in highlights areas where support may make current challenges easier to manage.',
    };
  }

  static String recommendedNextStepForLevel(QuickAssessmentLevel level) {
    switch (level) {
      case QuickAssessmentLevel.low:
        return 'Continue regular MindMate check-ins and wellness habits.';
      case QuickAssessmentLevel.moderate:
        return 'Complete the full role-based assessment for more personalized insight.';
      case QuickAssessmentLevel.high:
        return 'Complete the full assessment and consider contacting PACC counseling support.';
      case QuickAssessmentLevel.veryHigh:
        return 'Reach out to PACC counseling support or another trusted support person as soon as possible.';
    }
  }

  static AssessmentInterpretation interpretationFor(
    List<QuickAssessmentResponse> responses,
  ) {
    final domains = areaScores(responses).entries.map((entry) {
      final band = _band(entry.value);
      return AssessmentDomainResult(
        domain: entry.key,
        score: entry.value,
        band: band,
        answeredCount: 1,
        skippedCount: 0,
        presentedCount: 1,
        completionPercent: 100,
        isScorable: true,
        interpretation:
            '${AssessmentResponsePattern.labelForScore(entry.value)} based on this single quick-check response.',
        suggestedAction: recommendedNextStepForLevel(
          overallLevel(averageConcernScore(responses)),
        ),
      );
    }).toList()..sort((a, b) => b.score.compareTo(a.score));
    final level = overallLevel(averageConcernScore(responses));
    final priority = switch (level) {
      QuickAssessmentLevel.low => AssessmentSupportPriority.routine,
      QuickAssessmentLevel.moderate => AssessmentSupportPriority.monitor,
      QuickAssessmentLevel.high => AssessmentSupportPriority.followUpSuggested,
      QuickAssessmentLevel.veryHigh => AssessmentSupportPriority.promptFollowUp,
    };
    final top = domains.where((domain) => domain.score >= 30).take(3).toList();
    final focus = top.isEmpty
        ? 'No quick-check answer stood out as an immediate area to explore.'
        : 'Areas you may want to explore are ${top.map((domain) => domain.domain).join(', ')}.';
    final strengths = domains
        .where((domain) => domain.score <= 40)
        .take(3)
        .map(
          (domain) =>
              '${domain.domain} showed a supportive or balanced response.',
        )
        .toList();
    final focusInsights = domains
        .where((domain) => domain.score > 40)
        .take(3)
        .map(
          (domain) =>
              '${domain.domain} may be worth reflecting on or exploring in the full assessment.',
        )
        .toList();
    return AssessmentInterpretation(
      supportPriority: priority,
      responseQuality: AssessmentResponseQuality(
        presented: responses.length,
        answered: responses.length,
        skipped: 0,
        completionPercent: 100,
        confidence: AssessmentResponseConfidence.high,
      ),
      domainResults: domains,
      rationale: [focus],
      strengthInsights: strengths,
      focusInsights: focusInsights,
      userSummary: '${summaryForScore(averageConcernScore(responses))} $focus',
      counselorSummary:
          'Quick wellness screen: ${priority.label}. The five indicators each represent one response; use the full role-based assessment for category-level interpretation.',
      suggestedActions: [recommendedNextStepForLevel(level)],
      questionSetVersion: 'quick_v2',
    );
  }

  static AssessmentConcernBand _band(double score) {
    if (score <= 20) return AssessmentConcernBand.low;
    if (score <= 40) return AssessmentConcernBand.watchful;
    if (score <= 60) return AssessmentConcernBand.moderate;
    if (score <= 80) return AssessmentConcernBand.elevated;
    return AssessmentConcernBand.high;
  }
}
