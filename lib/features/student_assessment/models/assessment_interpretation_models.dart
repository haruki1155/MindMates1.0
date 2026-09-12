enum AssessmentConcernBand { low, watchful, moderate, elevated, high }

class AssessmentResponsePattern {
  const AssessmentResponsePattern._();

  static String codeForScore(double? score, {bool isScorable = true}) {
    if (!isScorable || score == null) return 'insufficientResponses';
    if (score <= 20) return 'wellBeingSupported';
    if (score <= 40) return 'generallySteady';
    if (score <= 60) return 'someStrain';
    return 'supportMayHelp';
  }

  static String labelForScore(double? score, {bool isScorable = true}) =>
      labelForCode(codeForScore(score, isScorable: isScorable));

  static String labelForCode(String code) => switch (code) {
    'wellBeingSupported' => 'Thriving patterns',
    'generallySteady' => 'Balanced patterns',
    'someStrain' => 'Areas to strengthen',
    'supportMayHelp' => 'Support may be useful',
    _ => 'More responses needed',
  };

  static String codeFromLegacy(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    if (text.contains('insufficient') || text.contains('not enough')) {
      return 'insufficientResponses';
    }
    if (text.contains('veryhigh') ||
        text.contains('very high') ||
        text.contains('at risk') ||
        text.contains('elevated') ||
        text == 'high') {
      return 'supportMayHelp';
    }
    if (text.contains('needs improvement') || text.contains('moderate')) {
      return 'someStrain';
    }
    if (text.contains('stable') || text.contains('watchful')) {
      return 'generallySteady';
    }
    return 'wellBeingSupported';
  }
}

extension AssessmentConcernBandLabel on AssessmentConcernBand {
  String get label => switch (this) {
    AssessmentConcernBand.low => 'Low',
    AssessmentConcernBand.watchful => 'Watchful',
    AssessmentConcernBand.moderate => 'Moderate',
    AssessmentConcernBand.elevated => 'Elevated',
    AssessmentConcernBand.high => 'High',
  };

  String get wellBeingStatus => switch (this) {
    AssessmentConcernBand.low => 'Thriving',
    AssessmentConcernBand.watchful => 'Stable',
    AssessmentConcernBand.moderate => 'Needs Improvement',
    AssessmentConcernBand.elevated || AssessmentConcernBand.high => 'At Risk',
  };
}

enum AssessmentSupportPriority {
  routine,
  monitor,
  followUpSuggested,
  promptFollowUp,
  insufficientResponses,
}

extension AssessmentSupportPriorityLabel on AssessmentSupportPriority {
  String get label => switch (this) {
    AssessmentSupportPriority.routine => 'Routine check-in',
    AssessmentSupportPriority.monitor => 'Continue monitoring',
    AssessmentSupportPriority.followUpSuggested =>
      'Consider additional support',
    AssessmentSupportPriority.promptFollowUp => 'Timely support encouraged',
    AssessmentSupportPriority.insufficientResponses =>
      'Complete more responses',
  };
}

enum AssessmentResponseConfidence { high, usableWithCaution, limited }

extension AssessmentResponseConfidenceLabel on AssessmentResponseConfidence {
  String get label => switch (this) {
    AssessmentResponseConfidence.high => 'High confidence',
    AssessmentResponseConfidence.usableWithCaution => 'Usable with caution',
    AssessmentResponseConfidence.limited => 'Limited responses',
  };
}

class AssessmentDomainResult {
  const AssessmentDomainResult({
    required this.domain,
    required this.score,
    required this.band,
    required this.answeredCount,
    required this.skippedCount,
    required this.presentedCount,
    required this.completionPercent,
    required this.isScorable,
    required this.interpretation,
    required this.suggestedAction,
    this.elevatedIndicators = const [],
    this.protectiveIndicators = const [],
  });

  final String domain;
  final double score;
  final AssessmentConcernBand band;
  final int answeredCount;
  final int skippedCount;
  final int presentedCount;
  final double completionPercent;
  final bool isScorable;
  final String interpretation;
  final String suggestedAction;
  final List<String> elevatedIndicators;
  final List<String> protectiveIndicators;

  factory AssessmentDomainResult.fromJson(Map<String, dynamic> json) {
    return AssessmentDomainResult(
      domain: json['domain']?.toString() ?? '',
      score: _double(json['score']),
      band:
          _enumValue(AssessmentConcernBand.values, json['band']) ??
          AssessmentConcernBand.low,
      answeredCount: _int(json['answeredCount']),
      skippedCount: _int(json['skippedCount']),
      presentedCount: _int(json['presentedCount']),
      completionPercent: _double(json['completionPercent']),
      isScorable: json['isScorable'] == true,
      interpretation: json['interpretation']?.toString() ?? '',
      suggestedAction: json['suggestedAction']?.toString() ?? '',
      elevatedIndicators: _strings(json['elevatedIndicators']),
      protectiveIndicators: _strings(json['protectiveIndicators']),
    );
  }

  Map<String, Object> toJson() => {
    'domain': domain,
    'score': score,
    'band': band.name,
    'bandLabel': responsePatternLabel,
    'concernBandLabel': band.label,
    'wellBeingStatus': wellBeingStatus,
    'responsePatternCode': responsePatternCode,
    'responsePatternLabel': responsePatternLabel,
    'answeredCount': answeredCount,
    'skippedCount': skippedCount,
    'presentedCount': presentedCount,
    'completionPercent': completionPercent,
    'isScorable': isScorable,
    'interpretation': interpretation,
    'suggestedAction': suggestedAction,
    'elevatedIndicators': elevatedIndicators,
    'protectiveIndicators': protectiveIndicators,
  };

  String get wellBeingStatus =>
      isScorable ? band.wellBeingStatus : 'Insufficient responses';

  String get responsePatternCode =>
      AssessmentResponsePattern.codeForScore(score, isScorable: isScorable);
  String get responsePatternLabel =>
      AssessmentResponsePattern.labelForCode(responsePatternCode);
}

class AssessmentResponseQuality {
  const AssessmentResponseQuality({
    required this.presented,
    required this.answered,
    required this.skipped,
    required this.completionPercent,
    required this.confidence,
  });

  final int presented;
  final int answered;
  final int skipped;
  final double completionPercent;
  final AssessmentResponseConfidence confidence;

  factory AssessmentResponseQuality.fromJson(Map<String, dynamic> json) {
    return AssessmentResponseQuality(
      presented: _int(json['presented']),
      answered: _int(json['answered']),
      skipped: _int(json['skipped']),
      completionPercent: _double(json['completionPercent']),
      confidence:
          _enumValue(AssessmentResponseConfidence.values, json['confidence']) ??
          AssessmentResponseConfidence.limited,
    );
  }

  Map<String, Object> toJson() => {
    'presented': presented,
    'answered': answered,
    'skipped': skipped,
    'completionPercent': completionPercent,
    'confidence': confidence.name,
    'confidenceLabel': confidence.label,
  };
}

class AssessmentInterpretation {
  const AssessmentInterpretation({
    required this.supportPriority,
    required this.responseQuality,
    required this.domainResults,
    required this.rationale,
    required this.userSummary,
    required this.counselorSummary,
    required this.suggestedActions,
    this.strengthInsights = const [],
    this.focusInsights = const [],
    this.protectiveFactors = const [],
    this.functionalImpactFlags = const [],
    this.algorithmVersion = 'internal_wellness_policy_v2',
    this.questionSetVersion = 'experimental_role_based_v3',
    this.recallPeriodDays = 14,
  });

  final String algorithmVersion;
  final String questionSetVersion;
  final int recallPeriodDays;
  final AssessmentSupportPriority supportPriority;
  final AssessmentResponseQuality responseQuality;
  final List<AssessmentDomainResult> domainResults;
  final List<String> protectiveFactors;
  final List<String> functionalImpactFlags;
  final List<String> rationale;
  final String userSummary;
  final String counselorSummary;
  final List<String> suggestedActions;
  final List<String> strengthInsights;
  final List<String> focusInsights;

  factory AssessmentInterpretation.fromJson(Map<String, dynamic> json) {
    final quality = _map(json['responseQuality']);
    return AssessmentInterpretation(
      algorithmVersion: json['algorithmVersion']?.toString() ?? 'legacy',
      questionSetVersion: json['questionSetVersion']?.toString() ?? 'legacy',
      recallPeriodDays: _int(json['recallPeriodDays'], fallback: 14),
      supportPriority:
          _enumValue(
            AssessmentSupportPriority.values,
            json['supportPriority'],
          ) ??
          AssessmentSupportPriority.insufficientResponses,
      responseQuality: AssessmentResponseQuality.fromJson(quality ?? const {}),
      domainResults: json['domainResults'] is List
          ? (json['domainResults'] as List)
                .map(_map)
                .whereType<Map<String, dynamic>>()
                .map(AssessmentDomainResult.fromJson)
                .toList()
          : const [],
      protectiveFactors: _strings(json['protectiveFactors']),
      functionalImpactFlags: _strings(json['functionalImpactFlags']),
      rationale: _strings(json['rationale']),
      userSummary: json['userSummary']?.toString() ?? '',
      counselorSummary: json['counselorSummary']?.toString() ?? '',
      suggestedActions: _strings(json['suggestedActions']),
      strengthInsights: _strings(json['strengthInsights']),
      focusInsights: _strings(json['focusInsights']),
    );
  }

  Map<String, Object> toJson() => {
    'algorithmVersion': algorithmVersion,
    'questionSetVersion': questionSetVersion,
    'recallPeriodDays': recallPeriodDays,
    'supportPriority': supportPriority.name,
    'supportPriorityLabel': supportPriority.label,
    'responseQuality': responseQuality.toJson(),
    'domainResults': domainResults.map((result) => result.toJson()).toList(),
    'protectiveFactors': protectiveFactors,
    'functionalImpactFlags': functionalImpactFlags,
    'rationale': rationale,
    'userSummary': userSummary,
    'counselorSummary': counselorSummary,
    'suggestedActions': suggestedActions,
    'strengthInsights': strengthInsights,
    'focusInsights': focusInsights,
  };
}

T? _enumValue<T extends Enum>(List<T> values, Object? value) {
  final name = value?.toString();
  for (final item in values) {
    if (item.name == name) return item;
  }
  return null;
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<String> _strings(Object? value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];

int _int(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
