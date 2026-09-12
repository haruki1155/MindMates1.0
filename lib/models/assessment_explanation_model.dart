import '../features/student_assessment/models/assessment_interpretation_models.dart';

class AssessmentAreaExplanation {
  const AssessmentAreaExplanation({
    required this.name,
    required this.patternCode,
    required this.patternLabel,
    required this.explanation,
    required this.suggestedAction,
    required this.answeredCount,
    required this.presentedCount,
    required this.isScorable,
  });

  final String name;
  final String patternCode;
  final String patternLabel;
  final String explanation;
  final String suggestedAction;
  final int answeredCount;
  final int presentedCount;
  final bool isScorable;

  factory AssessmentAreaExplanation.fromJson(Map<String, dynamic> json) =>
      AssessmentAreaExplanation(
        name: _text(json['name'] ?? json['domain']),
        patternCode: _text(json['patternCode'] ?? json['responsePatternCode']),
        patternLabel: _text(
          json['patternLabel'] ?? json['responsePatternLabel'],
        ),
        explanation: _text(json['explanation'] ?? json['interpretation']),
        suggestedAction: _text(json['suggestedAction']),
        answeredCount: _integer(json['answeredCount']),
        presentedCount: _integer(json['presentedCount']),
        isScorable: json['isScorable'] != false,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'patternCode': patternCode,
    'patternLabel': patternLabel,
    'explanation': explanation,
    'suggestedAction': suggestedAction,
    'answeredCount': answeredCount,
    'presentedCount': presentedCount,
    'isScorable': isScorable,
  };
}

/// Presentation-safe explanation shared by the student report and counselor view.
/// Raw scores remain in the assessment record but are intentionally omitted here.
class AssessmentExplanationModel {
  const AssessmentExplanationModel({
    required this.assessmentType,
    required this.patternCode,
    required this.patternLabel,
    required this.followUpGuidance,
    required this.summary,
    required this.rationale,
    required this.areas,
    required this.protectiveFactors,
    required this.functionalImpactFlags,
    required this.suggestedActions,
    required this.strengthInsights,
    required this.focusInsights,
    required this.responseConfidence,
    required this.answeredCount,
    required this.presentedCount,
    required this.recallPeriodDays,
    required this.algorithmVersion,
    required this.questionSetVersion,
    required this.counselorSummary,
    this.completedAt,
  });

  final String assessmentType;
  final DateTime? completedAt;
  final String patternCode;
  final String patternLabel;
  final String followUpGuidance;
  final String summary;
  final List<String> rationale;
  final List<AssessmentAreaExplanation> areas;
  final List<String> protectiveFactors;
  final List<String> functionalImpactFlags;
  final List<String> suggestedActions;
  final List<String> strengthInsights;
  final List<String> focusInsights;
  final String responseConfidence;
  final int answeredCount;
  final int presentedCount;
  final int recallPeriodDays;
  final String algorithmVersion;
  final String questionSetVersion;
  final String counselorSummary;

  bool get isQuick => assessmentType == 'quick';

  factory AssessmentExplanationModel.fromAssessment(
    Map<String, dynamic> assessment,
  ) {
    final interpretation = _map(assessment['interpretation']);
    final quality = _map(interpretation['responseQuality']);
    final type = _text(assessment['type']).toLowerCase() == 'quick'
        ? 'quick'
        : 'full';
    final score = _number(
      assessment['overallScore'] ?? assessment['concernScore'],
    );
    final storedPatternCode = _text(
      assessment['responsePatternCode'] ??
          interpretation['responsePatternCode'],
    );
    final legacyStatus = _text(
      assessment['status'] ?? assessment['overallLevel'],
    );
    final patternCode = storedPatternCode.isNotEmpty
        ? storedPatternCode
        : score != null
        ? AssessmentResponsePattern.codeForScore(score)
        : AssessmentResponsePattern.codeFromLegacy(legacyStatus);
    final domainValues = interpretation['domainResults'];
    final areas = <AssessmentAreaExplanation>[];
    if (domainValues is List) {
      for (final value in domainValues) {
        final domain = _map(value);
        if (domain.isEmpty) continue;
        final isScorable = domain['isScorable'] != false;
        final domainScore = _number(domain['score']);
        final areaCode = _text(domain['responsePatternCode']).isNotEmpty
            ? _text(domain['responsePatternCode'])
            : domainScore != null
            ? AssessmentResponsePattern.codeForScore(
                domainScore,
                isScorable: isScorable,
              )
            : AssessmentResponsePattern.codeFromLegacy(
                _text(
                  domain['wellBeingStatus'] ??
                      domain['bandLabel'] ??
                      domain['band'],
                ),
              );
        areas.add(
          AssessmentAreaExplanation(
            name: _text(domain['domain']),
            patternCode: areaCode,
            patternLabel: AssessmentResponsePattern.labelForCode(areaCode),
            explanation: _cleanExplanation(
              _text(domain['interpretation']),
              AssessmentResponsePattern.labelForCode(areaCode),
            ),
            suggestedAction: _text(domain['suggestedAction']),
            answeredCount: _integer(domain['answeredCount']),
            presentedCount: _integer(domain['presentedCount']),
            isScorable: isScorable,
          ),
        );
      }
    }
    final priority = _text(
      interpretation['supportPriority'] ?? assessment['supportPriority'],
    );
    final summary = _text(
      interpretation['userSummary'] ??
          assessment['summary'] ??
          assessment['message'],
    );
    return AssessmentExplanationModel(
      assessmentType: type,
      completedAt: _date(assessment['createdAt'] ?? assessment['completedAt']),
      patternCode: patternCode,
      patternLabel: AssessmentResponsePattern.labelForCode(patternCode),
      followUpGuidance: _supportLabel(priority),
      summary: _cleanSummary(summary, patternCode),
      rationale: _strings(
        interpretation['rationale'],
      ).map(_cleanRationale).toList(growable: false),
      areas: areas,
      protectiveFactors: _strings(interpretation['protectiveFactors']),
      functionalImpactFlags: _strings(interpretation['functionalImpactFlags']),
      suggestedActions: _strings(interpretation['suggestedActions']),
      strengthInsights: _strings(interpretation['strengthInsights']).isNotEmpty
          ? _strings(interpretation['strengthInsights'])
          : _legacyStrengthInsights(areas),
      focusInsights: _strings(interpretation['focusInsights']).isNotEmpty
          ? _strings(interpretation['focusInsights'])
          : _legacyFocusInsights(areas),
      responseConfidence: _text(quality['confidenceLabel']).isNotEmpty
          ? _text(quality['confidenceLabel'])
          : _confidenceLabel(_text(quality['confidence'])),
      answeredCount: _integer(
        quality['answered'] ?? assessment['totalResponses'],
      ),
      presentedCount: _integer(quality['presented']),
      recallPeriodDays: _integer(
        interpretation['recallPeriodDays'],
        fallback: 14,
      ),
      algorithmVersion: _text(
        interpretation['algorithmVersion'] ?? assessment['algorithmVersion'],
      ),
      questionSetVersion: _text(
        interpretation['questionSetVersion'] ??
            assessment['questionSetVersion'],
      ),
      counselorSummary: _text(interpretation['counselorSummary']),
    );
  }

  factory AssessmentExplanationModel.fromJson(Map<String, dynamic> json) =>
      AssessmentExplanationModel(
        assessmentType: _text(json['assessmentType']),
        completedAt: _date(json['completedAt']),
        patternCode: _text(json['patternCode']),
        patternLabel: _text(json['patternLabel']),
        followUpGuidance: _text(json['followUpGuidance']),
        summary: _text(json['summary']),
        rationale: _strings(json['rationale']),
        areas: json['areas'] is List
            ? (json['areas'] as List)
                  .map(_map)
                  .where((item) => item.isNotEmpty)
                  .map(AssessmentAreaExplanation.fromJson)
                  .toList(growable: false)
            : const [],
        protectiveFactors: _strings(json['protectiveFactors']),
        functionalImpactFlags: _strings(json['functionalImpactFlags']),
        suggestedActions: _strings(json['suggestedActions']),
        strengthInsights: _strings(json['strengthInsights']),
        focusInsights: _strings(json['focusInsights']),
        responseConfidence: _text(json['responseConfidence']),
        answeredCount: _integer(json['answeredCount']),
        presentedCount: _integer(json['presentedCount']),
        recallPeriodDays: _integer(json['recallPeriodDays'], fallback: 14),
        algorithmVersion: _text(json['algorithmVersion']),
        questionSetVersion: _text(json['questionSetVersion']),
        counselorSummary: _text(json['counselorSummary']),
      );

  Map<String, dynamic> toJson() => {
    'assessmentType': assessmentType,
    'completedAt': completedAt,
    'patternCode': patternCode,
    'patternLabel': patternLabel,
    'followUpGuidance': followUpGuidance,
    'summary': summary,
    'rationale': rationale,
    'areas': areas.map((area) => area.toJson()).toList(),
    'protectiveFactors': protectiveFactors,
    'functionalImpactFlags': functionalImpactFlags,
    'suggestedActions': suggestedActions,
    'strengthInsights': strengthInsights,
    'focusInsights': focusInsights,
    'responseConfidence': responseConfidence,
    'answeredCount': answeredCount,
    'presentedCount': presentedCount,
    'recallPeriodDays': recallPeriodDays,
    'algorithmVersion': algorithmVersion,
    'questionSetVersion': questionSetVersion,
    'counselorSummary': counselorSummary,
  };
}

String _supportLabel(String priority) => switch (priority) {
  'routine' => 'Routine check-in',
  'monitor' => 'Continue monitoring',
  'followUpSuggested' => 'Consider additional support',
  'promptFollowUp' => 'Timely support encouraged',
  _ => 'Complete more responses',
};

String _confidenceLabel(String value) => switch (value) {
  'high' => 'High confidence',
  'usableWithCaution' => 'Usable with caution',
  _ => 'Limited responses',
};

String _cleanSummary(String value, String patternCode) {
  if (value.isEmpty) {
    return '${AssessmentResponsePattern.labelForCode(patternCode)} based on the responses provided.';
  }
  return value
      .replaceFirst(
        RegExp(
          r'^(?:Overall well-being status|Current response pattern):[^.]+\.\s*',
        ),
        '',
      )
      .replaceAll('This is not a diagnosis.', '')
      .replaceAll('This screening result is not a diagnosis.', '')
      .trim();
}

String _cleanExplanation(String value, String patternLabel) {
  if (value.isEmpty) return '$patternLabel based on this response area.';
  return value
      .replaceFirst(
        RegExp(r'^(?:Well-being status|Response pattern):[^.]+\.\s*'),
        '',
      )
      .trim();
}

String _cleanRationale(String value) => value
    .replaceAll(': At Risk', ': Support may be useful')
    .replaceAll(': Needs Improvement', ': Areas to strengthen')
    .replaceAll(': Stable', ': Balanced patterns')
    .replaceAll(': Thriving', ': Thriving patterns');

List<String> _legacyStrengthInsights(List<AssessmentAreaExplanation> areas) =>
    areas
        .where(
          (area) =>
              area.patternCode == 'wellBeingSupported' ||
              area.patternCode == 'generallySteady',
        )
        .map(
          (area) => area.patternCode == 'wellBeingSupported'
              ? '${area.name} currently shows supportive patterns.'
              : '${area.name} appears generally manageable.',
        )
        .take(3)
        .toList(growable: false);

List<String> _legacyFocusInsights(List<AssessmentAreaExplanation> areas) =>
    areas
        .where(
          (area) =>
              area.patternCode == 'someStrain' ||
              area.patternCode == 'supportMayHelp',
        )
        .map((area) => area.explanation)
        .where((value) => value.isNotEmpty)
        .take(3)
        .toList(growable: false);

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
List<String> _strings(Object? value) => value is List
    ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
    : const [];
String _text(Object? value) => value?.toString().trim() ?? '';
int _integer(Object? value, {int fallback = 0}) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;
double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
DateTime? _date(Object? value) {
  if (value is DateTime) return value;
  try {
    final dynamic dynamicValue = value;
    final converted = dynamicValue?.toDate();
    if (converted is DateTime) return converted;
  } catch (_) {}
  return DateTime.tryParse(value?.toString() ?? '');
}
