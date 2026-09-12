import 'assessment_interpretation_models.dart';

enum LikertAnswer {
  never,
  rarely,
  often,
  always;

  int get value => switch (this) {
    LikertAnswer.never => 1,
    LikertAnswer.rarely => 2,
    LikertAnswer.often => 3,
    LikertAnswer.always => 4,
  };

  String get label {
    switch (this) {
      case LikertAnswer.never:
        return 'Strongly Disagree';
      case LikertAnswer.rarely:
        return 'Disagree';
      case LikertAnswer.often:
        return 'Agree';
      case LikertAnswer.always:
        return 'Strongly Agree';
    }
  }
}

enum AssessmentSection {
  academicCore,
  academicDeeper,
  financialConcern,
  socialAdjustment,
  workplaceStressCore,
  workplaceStressDeeper,
  professionalSupport,
  professionalWellBeing,
  workplaceResponsibilityCore,
  workplaceResponsibilityDeeper,
  workplaceSupport,
  workplaceWellBeing,
  sleepRest,
  emotionalWellBeing;

  String get label {
    switch (this) {
      case AssessmentSection.academicCore:
      case AssessmentSection.academicDeeper:
        return 'Academic Stress';
      case AssessmentSection.financialConcern:
        return 'Financial Well-Being';
      case AssessmentSection.socialAdjustment:
        return 'Social Adjustment';
      case AssessmentSection.workplaceStressCore:
      case AssessmentSection.workplaceStressDeeper:
        return 'Workplace Stress';
      case AssessmentSection.professionalSupport:
        return 'Professional Support';
      case AssessmentSection.professionalWellBeing:
        return 'Professional Well-Being';
      case AssessmentSection.workplaceResponsibilityCore:
      case AssessmentSection.workplaceResponsibilityDeeper:
        return 'Workplace Responsibilities';
      case AssessmentSection.workplaceSupport:
        return 'Workplace Support';
      case AssessmentSection.workplaceWellBeing:
        return 'Workplace Well-Being';
      case AssessmentSection.sleepRest:
        return 'Sleep and Rest';
      case AssessmentSection.emotionalWellBeing:
        return 'Emotional Well-Being';
    }
  }
}

enum AssessmentDirection { risk, protective }

class StudentAssessmentQuestion {
  const StudentAssessmentQuestion({
    required this.id,
    required this.text,
    required this.section,
    required this.direction,
    this.isConditional = false,
  });

  final String id;
  final String text;
  final AssessmentSection section;
  final AssessmentDirection direction;
  final bool isConditional;
}

class StudentAssessmentAnswer {
  const StudentAssessmentAnswer({
    required this.questionId,
    required this.answer,
    this.isSkipped = false,
  });

  final String questionId;
  final LikertAnswer answer;
  final bool isSkipped;

  Map<String, Object> toJson() {
    return {
      'questionId': questionId,
      'answer': answer.name,
      'value': answer.value,
      'isSkipped': isSkipped,
    };
  }
}

class StudentAssessmentResult {
  const StudentAssessmentResult({
    required this.userType,
    required this.overallScore,
    required this.status,
    required this.subscaleScores,
    required this.mainConcernAreas,
    required this.message,
    required this.disclaimer,
    required this.totalResponses,
    required this.interpretation,
  });

  final String userType;
  final double? overallScore;
  final String status;
  final Map<String, double> subscaleScores;
  final List<String> mainConcernAreas;
  final String message;
  final String disclaimer;
  final int totalResponses;
  final AssessmentInterpretation interpretation;

  String get responsePatternCode => AssessmentResponsePattern.codeForScore(
    overallScore,
    isScorable: overallScore != null,
  );
  String get responsePatternLabel =>
      AssessmentResponsePattern.labelForCode(responsePatternCode);

  Map<String, Object> toJson() {
    return {
      'userType': userType,
      'overallScore': ?overallScore,
      'status': status,
      'wellBeingStatus': status,
      'responsePatternCode': responsePatternCode,
      'responsePatternLabel': responsePatternLabel,
      'subscaleScores': subscaleScores,
      'mainConcernAreas': mainConcernAreas,
      'message': message,
      'disclaimer': disclaimer,
      'totalResponses': totalResponses,
      'algorithmVersion': interpretation.algorithmVersion,
      'questionSetVersion': interpretation.questionSetVersion,
      'supportPriority': interpretation.supportPriority.name,
      'interpretation': interpretation.toJson(),
    };
  }
}
