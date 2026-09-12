import '../models/student_assessment_models.dart';
import '../models/assessment_interpretation_models.dart';
import 'assessment_interpretation_engine.dart';

enum AssessmentUserType { student, faculty, staff }

class StudentAssessmentCalculator {
  const StudentAssessmentCalculator._();

  static const double minimumDomainCompletion = 0.70;
  static const int minimumDomainAnswers = 3;
  static const int minimumAnswerValue = 1;
  static const int maximumAnswerValue = 4;

  static double riskScore({
    required LikertAnswer answer,
    required AssessmentDirection direction,
  }) {
    final normalized =
        ((answer.value - minimumAnswerValue) /
            (maximumAnswerValue - minimumAnswerValue)) *
        100;
    return direction == AssessmentDirection.protective
        ? 100 - normalized
        : normalized;
  }

  static bool shouldShowDeeperAcademicQuestions({
    required List<StudentAssessmentQuestion> questions,
    required List<StudentAssessmentAnswer> answers,
  }) => shouldShowDeeperQuestions(
    questions: questions,
    answers: answers,
    coreSection: AssessmentSection.academicCore,
  );

  static bool shouldShowDeeperQuestions({
    required List<StudentAssessmentQuestion> questions,
    required List<StudentAssessmentAnswer> answers,
    required AssessmentSection coreSection,
  }) {
    final coreQuestions = questions
        .where(
          (question) =>
              question.section == coreSection &&
              question.direction == AssessmentDirection.risk,
        )
        .toList();
    var alwaysCount = 0;
    var oftenOrAlwaysCount = 0;
    final coreScores = <double>[];

    // A corrected answer may be represented more than once by callers that
    // append to an answer log. Score the latest answer once per question so
    // duplicates cannot inflate the deeper-question trigger.
    final answerById = {
      for (final answer in answers) answer.questionId: answer,
    };
    for (final answer in answerById.values.where(
      (answer) => !answer.isSkipped,
    )) {
      final question = coreQuestions
          .where((question) => question.id == answer.questionId)
          .firstOrNull;
      if (question == null) continue;
      if (answer.answer == LikertAnswer.always) alwaysCount++;
      if (answer.answer == LikertAnswer.often ||
          answer.answer == LikertAnswer.always) {
        oftenOrAlwaysCount++;
      }
      coreScores.add(
        riskScore(answer: answer.answer, direction: question.direction),
      );
    }

    return alwaysCount >= 1 ||
        oftenOrAlwaysCount >= 2 ||
        _average(coreScores) >= 50;
  }

  static StudentAssessmentResult calculate({
    required List<StudentAssessmentQuestion> questions,
    required List<StudentAssessmentAnswer> answers,
    AssessmentUserType userType = AssessmentUserType.student,
  }) {
    final config = _RoleConfig.forType(userType);
    final domainScores = <String, double>{};
    final scorableDomains = <String, bool>{};
    final weights = <String, double>{};

    for (final domain in config.domains) {
      final score = _scoreDomain(
        questions: questions,
        answers: answers,
        sections: domain.scoredSections,
      );
      scorableDomains[domain.label] = score.isScorable;
      weights[domain.label] = domain.weight;
      if (score.isScorable) domainScores[domain.label] = _round(score.score!);
    }

    final allRequiredScorable = config.domains.every(
      (domain) => scorableDomains[domain.label] == true,
    );
    final overallScore = allRequiredScorable
        ? _round(
            config.domains.fold<double>(
              0,
              (total, domain) =>
                  total + domainScores[domain.label]! * domain.weight,
            ),
          )
        : null;
    final status = overallScore == null
        ? 'Insufficient Responses'
        : getStatus(overallScore);
    final interpretation = AssessmentInterpretationEngine.build(
      questions: questions,
      answers: answers,
      domainScores: domainScores,
      domainSections: {
        for (final domain in config.domains) domain.label: domain.allSections,
      },
      userType: config.userLabel,
      overallWellBeingStatus: AssessmentResponsePattern.labelForScore(
        overallScore,
        isScorable: overallScore != null,
      ),
    );

    return StudentAssessmentResult(
      userType: config.userLabel,
      overallScore: overallScore,
      status: status,
      subscaleScores: domainScores,
      mainConcernAreas: getMainConcernAreas(domainScores),
      message: overallScore == null
          ? 'Some wellness categories did not have enough responses for a dependable summary. Review the category results that are available.'
          : getMessage(status),
      disclaimer: _pilotDisclaimer,
      totalResponses: answers.where((answer) => !answer.isSkipped).length,
      interpretation: interpretation,
    );
  }

  static String getStatus(double score) {
    if (score <= 20) return 'Thriving';
    if (score <= 40) return 'Stable';
    if (score <= 60) return 'Needs Improvement';
    return 'At Risk';
  }

  static String getMessage(String status) => switch (status) {
    'Thriving' =>
      'Your answered categories suggest strong current well-being. Continue the routines and support that are working for you.',
    'Stable' =>
      'Your responses suggest some areas worth watching. Small supportive habits and regular check-ins may help you notice changes.',
    'Needs Improvement' =>
      'Your responses show noticeable strain in one or more wellness areas. Review the category details and consider talking with someone you trust.',
    'At Risk' =>
      'Your responses show elevated strain in one or more areas. Timely support from the university guidance office or a qualified professional is recommended.',
    _ => 'Your category results are ready to review.',
  };

  static List<String> getMainConcernAreas(Map<String, double> scores) => scores
      .entries
      .where((entry) => entry.value > 60)
      .map((entry) => entry.key)
      .toList();

  static _DomainScore _scoreDomain({
    required List<StudentAssessmentQuestion> questions,
    required List<StudentAssessmentAnswer> answers,
    required Set<AssessmentSection> sections,
  }) {
    final presented = questions
        .where((question) => sections.contains(question.section))
        .toList();
    final answerById = {
      for (final answer in answers) answer.questionId: answer,
    };
    final scored = <double>[];
    for (final question in presented) {
      final answer = answerById[question.id];
      if (answer == null || answer.isSkipped) continue;
      scored.add(
        riskScore(answer: answer.answer, direction: question.direction),
      );
    }
    final completion = presented.isEmpty
        ? 0.0
        : scored.length / presented.length;
    final isScorable =
        scored.length >= minimumDomainAnswers &&
        completion >= minimumDomainCompletion;
    return _DomainScore(
      score: isScorable ? _average(scored) : null,
      isScorable: isScorable,
    );
  }

  static double _average(List<double> scores) =>
      scores.isEmpty ? 0 : scores.reduce((a, b) => a + b) / scores.length;

  static double _round(double value) => double.parse(value.toStringAsFixed(2));

  static const _pilotDisclaimer =
      'This result comes from an experimental university wellness-awareness screener, not a formally validated instrument or a diagnosis. It is designed to support reflection and conversation, not replace professional judgment. If you feel unsafe or need immediate help, contact your university support office, a trusted person, or a qualified mental health professional.';
}

class _DomainScore {
  const _DomainScore({required this.score, required this.isScorable});
  final double? score;
  final bool isScorable;
}

class _DomainConfig {
  const _DomainConfig({
    required this.label,
    required this.scoredSections,
    required this.allSections,
    required this.weight,
  });
  final String label;
  final Set<AssessmentSection> scoredSections;
  final Set<AssessmentSection> allSections;
  final double weight;
}

class _RoleConfig {
  const _RoleConfig(this.userLabel, this.domains);
  final String userLabel;
  final List<_DomainConfig> domains;

  static _RoleConfig forType(AssessmentUserType type) => switch (type) {
    AssessmentUserType.student => const _RoleConfig('Student', [
      _DomainConfig(
        label: 'Academic Stress',
        scoredSections: {AssessmentSection.academicCore},
        allSections: {
          AssessmentSection.academicCore,
          AssessmentSection.academicDeeper,
        },
        weight: .20,
      ),
      _DomainConfig(
        label: 'Financial Well-Being',
        scoredSections: {AssessmentSection.financialConcern},
        allSections: {AssessmentSection.financialConcern},
        weight: .20,
      ),
      _DomainConfig(
        label: 'Social Adjustment',
        scoredSections: {AssessmentSection.socialAdjustment},
        allSections: {AssessmentSection.socialAdjustment},
        weight: .20,
      ),
      _DomainConfig(
        label: 'Sleep and Rest',
        scoredSections: {AssessmentSection.sleepRest},
        allSections: {AssessmentSection.sleepRest},
        weight: .20,
      ),
      _DomainConfig(
        label: 'Emotional Well-Being',
        scoredSections: {AssessmentSection.emotionalWellBeing},
        allSections: {AssessmentSection.emotionalWellBeing},
        weight: .20,
      ),
    ]),
    AssessmentUserType.faculty => const _RoleConfig('Teaching Personnel', [
      _DomainConfig(
        label: 'Workplace Stress',
        scoredSections: {AssessmentSection.workplaceStressCore},
        allSections: {
          AssessmentSection.workplaceStressCore,
          AssessmentSection.workplaceStressDeeper,
        },
        weight: .20,
      ),
      _DomainConfig(
        label: 'Professional Support',
        scoredSections: {AssessmentSection.professionalSupport},
        allSections: {AssessmentSection.professionalSupport},
        weight: .20,
      ),
      _DomainConfig(
        label: 'Professional Well-Being',
        scoredSections: {AssessmentSection.professionalWellBeing},
        allSections: {AssessmentSection.professionalWellBeing},
        weight: .20,
      ),
      _DomainConfig(
        label: 'Sleep and Rest',
        scoredSections: {AssessmentSection.sleepRest},
        allSections: {AssessmentSection.sleepRest},
        weight: .20,
      ),
      _DomainConfig(
        label: 'Emotional Well-Being',
        scoredSections: {AssessmentSection.emotionalWellBeing},
        allSections: {AssessmentSection.emotionalWellBeing},
        weight: .20,
      ),
    ]),
    AssessmentUserType.staff => const _RoleConfig('Non-Teaching Personnel', [
      _DomainConfig(
        label: 'Workplace Responsibilities',
        scoredSections: {AssessmentSection.workplaceResponsibilityCore},
        allSections: {
          AssessmentSection.workplaceResponsibilityCore,
          AssessmentSection.workplaceResponsibilityDeeper,
        },
        weight: .20,
      ),
      _DomainConfig(
        label: 'Workplace Support',
        scoredSections: {AssessmentSection.workplaceSupport},
        allSections: {AssessmentSection.workplaceSupport},
        weight: .20,
      ),
      _DomainConfig(
        label: 'Workplace Well-Being',
        scoredSections: {AssessmentSection.workplaceWellBeing},
        allSections: {AssessmentSection.workplaceWellBeing},
        weight: .20,
      ),
      _DomainConfig(
        label: 'Sleep and Rest',
        scoredSections: {AssessmentSection.sleepRest},
        allSections: {AssessmentSection.sleepRest},
        weight: .20,
      ),
      _DomainConfig(
        label: 'Emotional Well-Being',
        scoredSections: {AssessmentSection.emotionalWellBeing},
        allSections: {AssessmentSection.emotionalWellBeing},
        weight: .20,
      ),
    ]),
  };
}
