import '../models/assessment_interpretation_models.dart';
import '../models/student_assessment_models.dart';

class AssessmentInterpretationEngine {
  const AssessmentInterpretationEngine._();

  static AssessmentInterpretation build({
    required List<StudentAssessmentQuestion> questions,
    required List<StudentAssessmentAnswer> answers,
    required Map<String, double> domainScores,
    required Map<String, Set<AssessmentSection>> domainSections,
    required String userType,
    required String overallWellBeingStatus,
  }) {
    final answerById = {
      for (final answer in answers) answer.questionId: answer,
    };
    final answered = answers.where((answer) => !answer.isSkipped).length;
    final skipped = answers.where((answer) => answer.isSkipped).length;
    final presented = questions.length;
    final completion = presented == 0 ? 0.0 : (answered / presented) * 100;
    final confidence = completion >= 90
        ? AssessmentResponseConfidence.high
        : completion >= 70
        ? AssessmentResponseConfidence.usableWithCaution
        : AssessmentResponseConfidence.limited;
    final quality = AssessmentResponseQuality(
      presented: presented,
      answered: answered,
      skipped: skipped,
      completionPercent: _round(completion),
      confidence: confidence,
    );

    final protectiveFactors = <String>[];
    final functionalFlags = <String>[];
    final elevatedByDomain = <String, List<String>>{};
    final protectiveByDomain = <String, List<String>>{};

    for (final question in questions) {
      final answer = answerById[question.id];
      if (answer == null || answer.isSkipped) continue;
      final risk = _riskScore(answer.answer, question.direction);
      final domain = question.section.label;
      if (risk >= 75) {
        elevatedByDomain.putIfAbsent(domain, () => []).add(question.text);
        if (_isFunctionalImpact(question.text)) {
          functionalFlags.add(question.text);
        }
      }
      if (question.direction == AssessmentDirection.protective && risk <= 25) {
        protectiveFactors.add(question.text);
        protectiveByDomain.putIfAbsent(domain, () => []).add(question.text);
      }
    }

    final domainResults = <AssessmentDomainResult>[];
    for (final entry in domainSections.entries) {
      final domainQuestions = questions
          .where((question) => entry.value.contains(question.section))
          .toList();
      final scoredQuestions = domainQuestions
          .where((question) => !question.isConditional)
          .toList();
      final domainAnswers = scoredQuestions
          .map((question) => answerById[question.id])
          .whereType<StudentAssessmentAnswer>()
          .toList();
      final domainAnswered = domainAnswers
          .where((answer) => !answer.isSkipped)
          .length;
      final domainSkipped = domainAnswers
          .where((answer) => answer.isSkipped)
          .length;
      final domainCompletion = scoredQuestions.isEmpty
          ? 0.0
          : (domainAnswered / scoredQuestions.length) * 100;
      final isScorable = domainScores.containsKey(entry.key);
      final score = domainScores[entry.key] ?? 0;
      final band = bandFor(score);
      domainResults.add(
        AssessmentDomainResult(
          domain: entry.key,
          score: _round(score),
          band: band,
          answeredCount: domainAnswered,
          skippedCount: domainSkipped,
          presentedCount: scoredQuestions.length,
          completionPercent: _round(domainCompletion),
          isScorable: isScorable,
          elevatedIndicators: elevatedByDomain[entry.key] ?? const [],
          protectiveIndicators: protectiveByDomain[entry.key] ?? const [],
          interpretation: isScorable
              ? _domainInterpretation(entry.key, band)
              : '${entry.key} needs more answered questions before a dependable category result can be shown.',
          suggestedAction: isScorable
              ? _domainAction(entry.key, band)
              : 'Answer more ${entry.key.toLowerCase()} questions when you feel comfortable, or discuss this area directly with a counselor.',
        ),
      );
    }
    domainResults.sort((a, b) {
      if (a.isScorable != b.isScorable) return a.isScorable ? -1 : 1;
      return b.score.compareTo(a.score);
    });

    final priority = _priority(
      quality: quality,
      domains: domainResults,
      functionalImpactCount: functionalFlags.length,
    );
    final rationale = _rationale(priority, domainResults, functionalFlags);
    final actions = _actions(priority, domainResults);
    final strengthInsights = _strengthInsights(domainResults);
    final focusInsights = _focusInsights(domainResults, functionalFlags);
    final focus = domainResults
        .where((domain) => domain.isScorable && domain.score > 40)
        .take(3);
    final focusText = focus.isEmpty
        ? 'No wellness domain showed a moderate or higher concern pattern.'
        : 'The main areas to review are ${focus.map((item) => item.domain).join(', ')}.';

    return AssessmentInterpretation(
      supportPriority: priority,
      responseQuality: quality,
      domainResults: domainResults,
      protectiveFactors: protectiveFactors.take(5).toList(),
      functionalImpactFlags: functionalFlags.take(5).toList(),
      strengthInsights: strengthInsights,
      focusInsights: focusInsights,
      rationale: rationale,
      userSummary: _userSummary(priority, focusText, overallWellBeingStatus),
      counselorSummary:
          '$userType screening: ${priority.label}. $focusText '
          'Response confidence: ${quality.confidence.label.toLowerCase()} '
          '(${quality.completionPercent.toStringAsFixed(0)}% completed).',
      suggestedActions: actions,
    );
  }

  static AssessmentConcernBand bandFor(double score) {
    if (score <= 20) return AssessmentConcernBand.low;
    if (score <= 40) return AssessmentConcernBand.watchful;
    if (score <= 60) return AssessmentConcernBand.moderate;
    if (score <= 80) return AssessmentConcernBand.elevated;
    return AssessmentConcernBand.high;
  }

  static AssessmentSupportPriority _priority({
    required AssessmentResponseQuality quality,
    required List<AssessmentDomainResult> domains,
    required int functionalImpactCount,
  }) {
    if (quality.confidence == AssessmentResponseConfidence.limited) {
      return AssessmentSupportPriority.insufficientResponses;
    }
    if (domains.any((domain) => !domain.isScorable)) {
      return AssessmentSupportPriority.insufficientResponses;
    }
    final above80 = domains.where((domain) => domain.score > 80).length;
    final above60 = domains.where((domain) => domain.score > 60).length;
    final above40 = domains.where((domain) => domain.score > 40).length;
    if (above80 >= 1 || above60 >= 2 || functionalImpactCount >= 3) {
      return AssessmentSupportPriority.promptFollowUp;
    }
    if (above60 >= 1 || above40 >= 2 || functionalImpactCount >= 2) {
      return AssessmentSupportPriority.followUpSuggested;
    }
    if (above40 >= 1 || functionalImpactCount >= 1) {
      return AssessmentSupportPriority.monitor;
    }
    return AssessmentSupportPriority.routine;
  }

  static List<String> _rationale(
    AssessmentSupportPriority priority,
    List<AssessmentDomainResult> domains,
    List<String> functionalFlags,
  ) {
    final reasons = <String>[];
    for (final domain
        in domains
            .where((domain) => domain.isScorable && domain.score > 40)
            .take(3)) {
      reasons.add('${domain.domain}: ${domain.responsePatternLabel}');
    }
    if (functionalFlags.isNotEmpty) {
      reasons.add(
        '${functionalFlags.length} response${functionalFlags.length == 1 ? '' : 's'} indicated possible day-to-day impact',
      );
    }
    if (reasons.isEmpty) {
      reasons.add(
        'Responses did not show a moderate or higher concern pattern',
      );
    }
    if (priority == AssessmentSupportPriority.insufficientResponses) {
      reasons.insert(0, 'Too many presented questions were skipped');
    }
    return reasons;
  }

  static String _userSummary(
    AssessmentSupportPriority priority,
    String focusText,
    String overallWellBeingStatus,
  ) {
    final opening = switch (priority) {
      AssessmentSupportPriority.routine =>
        'Your responses show several supportive habits and generally manageable day-to-day well-being.',
      AssessmentSupportPriority.monitor =>
        'Most areas appear manageable, with opportunities for small adjustments and continued awareness.',
      AssessmentSupportPriority.followUpSuggested =>
        'You are managing some areas well, while other parts of daily life may benefit from more attention and support.',
      AssessmentSupportPriority.promptFollowUp =>
        'One or more areas may be placing extra pressure on daily life. You do not have to work through those challenges alone.',
      AssessmentSupportPriority.insufficientResponses =>
        'There were not enough answered questions for a dependable interpretation.',
    };
    return '$opening $focusText';
  }

  static List<String> _actions(
    AssessmentSupportPriority priority,
    List<AssessmentDomainResult> domains,
  ) {
    final actions = <String>[];
    if (priority == AssessmentSupportPriority.insufficientResponses) {
      return const [
        'Review skipped items and complete the assessment when comfortable.',
        'Speak directly with a counselor if you would prefer a conversation.',
      ];
    }
    final scorable = domains.where((domain) => domain.isScorable);
    final top = scorable.isEmpty ? null : scorable.first.domain;
    if (top != null) actions.add('Review practical support options for $top.');
    if (priority == AssessmentSupportPriority.followUpSuggested ||
        priority == AssessmentSupportPriority.promptFollowUp) {
      actions.add('Consider scheduling a confidential PACC consultation.');
    }
    actions.add('Continue mood check-ins to observe changes over time.');
    return actions;
  }

  static String _domainInterpretation(
    String domain,
    AssessmentConcernBand band,
  ) {
    return switch ((domain, band)) {
      (_, AssessmentConcernBand.low) =>
        'Your responses show supportive habits or resources in this area.',
      (_, AssessmentConcernBand.watchful) =>
        'This area appears mostly manageable, with room for continued awareness.',
      ('Academic Stress', AssessmentConcernBand.moderate) =>
        'Academic demands may be adding pressure to your concentration, motivation, or routine.',
      ('Financial Well-Being', AssessmentConcernBand.moderate) =>
        'Financial concerns may be adding pressure to your studies or daily experience.',
      ('Social Adjustment', AssessmentConcernBand.moderate) =>
        'Connection or adjustment may feel less steady in some situations right now.',
      ('Sleep and Rest', AssessmentConcernBand.moderate) =>
        'Sleep or rest patterns may be influencing your energy and concentration.',
      ('Emotional Well-Being', AssessmentConcernBand.moderate) =>
        'Emotional demands may be using more of your energy than usual.',
      (_, AssessmentConcernBand.moderate) =>
        'This area may be creating additional pressure and is worth exploring.',
      ('Academic Stress', _) =>
        'Academic demands may be creating sustained pressure. Additional planning or support could make them easier to manage.',
      ('Financial Well-Being', _) =>
        'Financial concerns may be affecting focus or daily stress. Practical guidance may help reduce some of that pressure.',
      ('Social Adjustment', _) =>
        'Social connection or adjustment may currently feel difficult. A trusted person or welcoming group may help.',
      ('Sleep and Rest', _) =>
        'Sleep and recovery may be affecting energy, focus, or daily functioning. A realistic rest plan may help.',
      ('Emotional Well-Being', _) =>
        'Emotional demands may be affecting daily well-being. A supportive conversation may make this easier to carry.',
      (_, _) =>
        'This area may currently be adding pressure. Consider one manageable support step.',
    };
  }

  static List<String> _strengthInsights(List<AssessmentDomainResult> domains) {
    final insights = <String>[];
    for (final domain in domains) {
      if (!domain.isScorable) continue;
      if (domain.score <= 20) {
        insights.add('${domain.domain} currently shows supportive patterns.');
      } else if (domain.score <= 40) {
        insights.add('${domain.domain} appears generally manageable.');
      }
      if (domain.protectiveIndicators.isNotEmpty) {
        insights.add(_protectiveInsightFor(domain.domain));
      }
    }
    return insights.toSet().take(3).toList(growable: false);
  }

  static List<String> _focusInsights(
    List<AssessmentDomainResult> domains,
    List<String> functionalFlags,
  ) {
    final insights = domains
        .where((domain) => domain.isScorable && domain.score > 40)
        .take(3)
        .map((domain) => domain.interpretation)
        .toList();
    if (functionalFlags.isNotEmpty) {
      insights.add(
        'Some responses suggest that current pressures may be affecting everyday focus, rest, motivation, or routines.',
      );
    }
    return insights.toSet().take(4).toList(growable: false);
  }

  static String _protectiveInsightFor(String domain) => switch (domain) {
    'Academic Stress' =>
      'You identified at least one academic coping habit or source of support.',
    'Financial Well-Being' =>
      'You identified at least one helpful way of understanding or responding to financial concerns.',
    'Social Adjustment' =>
      'You identified at least one positive connection or help-seeking strength.',
    'Sleep and Rest' =>
      'You identified at least one rest or recovery habit that can support you.',
    'Emotional Well-Being' =>
      'You identified at least one emotional-awareness or help-seeking strength.',
    _ => 'You identified at least one supportive habit in this area.',
  };

  static String _domainAction(String domain, AssessmentConcernBand band) {
    final support = switch (domain) {
      'Academic Stress' =>
        'review workload, deadlines, and academic support options',
      'Financial Well-Being' =>
        'review available financial-aid or student-support resources',
      'Social Adjustment' =>
        'identify one trusted person or university group you can connect with',
      'Sleep and Rest' =>
        'choose one realistic sleep or rest routine to try this week',
      'Emotional Well-Being' =>
        'continue check-ins and consider a supportive conversation',
      'Workplace Stress' || 'Workplace Responsibilities' =>
        'review workload priorities and available workplace support',
      'Professional Support' || 'Workplace Support' =>
        'identify a trusted colleague, supervisor, or university support contact',
      'Professional Well-Being' || 'Workplace Well-Being' =>
        'choose one recovery or support step that feels manageable',
      _ => 'review a practical support option for this area',
    };
    return switch (band) {
      AssessmentConcernBand.low =>
        'Continue the habits and support that are working in this area.',
      AssessmentConcernBand.watchful => 'Monitor this area and $support.',
      AssessmentConcernBand.moderate => 'Consider taking time to $support.',
      AssessmentConcernBand.elevated || AssessmentConcernBand.high =>
        'Consider discussing this area with university wellness support and $support.',
    };
  }

  static bool _isFunctionalImpact(String text) {
    final normalized = text.toLowerCase();
    return const [
      'concentrat',
      'sleep',
      'motivation',
      'social life',
      'skip meals',
      'family time',
      'personal life',
      'relationships',
      'health',
      'daily life',
    ].any(normalized.contains);
  }

  static double _riskScore(LikertAnswer answer, AssessmentDirection direction) {
    final normalized = ((answer.value - 1) / 3) * 100;
    return direction == AssessmentDirection.protective
        ? 100 - normalized
        : normalized;
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(2));
}
