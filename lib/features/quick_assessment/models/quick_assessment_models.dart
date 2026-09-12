import '../../student_assessment/models/assessment_interpretation_models.dart';
import '../../../models/profile_roles.dart';

enum AssessmentRole {
  student,
  faculty,
  staff;

  String get label {
    switch (this) {
      case AssessmentRole.student:
        return 'Student';
      case AssessmentRole.faculty:
        return 'Teaching';
      case AssessmentRole.staff:
        return 'Non-Teaching';
    }
  }

  String get description {
    switch (this) {
      case AssessmentRole.student:
        return 'Academic stress, financial well-being & social adjustment';
      case AssessmentRole.faculty:
        return 'Teaching workload, professional support & work-life balance';
      case AssessmentRole.staff:
        return 'Workplace responsibilities, support & emotional well-being';
    }
  }

  static AssessmentRole? fromStoredValue(String? value) {
    return fromPopulationRole(PopulationRole.parse(value));
  }

  PopulationRole get populationRole => switch (this) {
    AssessmentRole.student => PopulationRole.student,
    AssessmentRole.faculty => PopulationRole.teaching,
    AssessmentRole.staff => PopulationRole.nonTeaching,
  };

  static AssessmentRole? fromPopulationRole(PopulationRole? role) =>
      switch (role) {
        PopulationRole.student => AssessmentRole.student,
        PopulationRole.teaching => AssessmentRole.faculty,
        PopulationRole.nonTeaching => AssessmentRole.staff,
        null => null,
      };
}

enum QuickQuestionDirection { risk, protective }

enum QuickAssessmentLevel {
  low,
  moderate,
  high,
  veryHigh;

  String get label {
    switch (this) {
      case QuickAssessmentLevel.low:
        return 'Low';
      case QuickAssessmentLevel.moderate:
        return 'Moderate';
      case QuickAssessmentLevel.high:
        return 'High';
      case QuickAssessmentLevel.veryHigh:
        return 'Very high';
    }
  }
}

enum QuickAssessmentSignal {
  stable,
  watchful,
  elevated,
  highSupport;

  String get label {
    switch (this) {
      case QuickAssessmentSignal.stable:
        return 'Stable wellness signal';
      case QuickAssessmentSignal.watchful:
        return 'Watchful wellness signal';
      case QuickAssessmentSignal.elevated:
        return 'Elevated support signal';
      case QuickAssessmentSignal.highSupport:
        return 'High support signal';
    }
  }
}

class QuickAssessmentOption {
  const QuickAssessmentOption({
    required this.id,
    required this.label,
    required this.value,
    required this.iconAssetPath,
  });

  final String id;
  final String label;
  final int value;
  final String iconAssetPath;
}

class QuickAssessmentQuestion {
  const QuickAssessmentQuestion({
    required this.id,
    required this.prompt,
    required this.direction,
    required this.options,
  });

  final String id;
  final String prompt;
  final QuickQuestionDirection direction;
  final List<QuickAssessmentOption> options;
}

class QuickAssessmentResponse {
  const QuickAssessmentResponse({
    required this.questionId,
    required this.optionId,
    required this.value,
    required this.concernScore,
  });

  final String questionId;
  final String optionId;
  final int value;
  final double concernScore;

  Map<String, Object> toJson() {
    return {
      'questionId': questionId,
      'optionId': optionId,
      'value': value,
      'concernScore': concernScore,
    };
  }
}

class QuickAssessmentResult {
  const QuickAssessmentResult({
    required this.role,
    required this.name,
    required this.responses,
    required this.concernScore,
    required this.overallLevel,
    required this.summary,
    required this.topConcernAreas,
    required this.recommendedNextStep,
    required this.mentalStatusSignal,
    required this.signalSource,
    required this.signalGeneratedAt,
    required this.createdAt,
    required this.interpretation,
  });

  final AssessmentRole role;
  final String name;
  final List<QuickAssessmentResponse> responses;
  final double concernScore;
  final QuickAssessmentLevel overallLevel;
  final String summary;
  final List<String> topConcernAreas;
  final String recommendedNextStep;
  final QuickAssessmentSignal mentalStatusSignal;
  final String signalSource;
  final DateTime signalGeneratedAt;
  final DateTime createdAt;
  final AssessmentInterpretation interpretation;

  String get responsePatternCode =>
      AssessmentResponsePattern.codeForScore(concernScore);
  String get responsePatternLabel =>
      AssessmentResponsePattern.labelForCode(responsePatternCode);

  Map<String, Object> toJson() {
    return {
      'role': role.name,
      'name': name,
      'responses': responses.map((response) => response.toJson()).toList(),
      'concernScore': concernScore,
      'overallLevel': overallLevel.name,
      'responsePatternCode': responsePatternCode,
      'responsePatternLabel': responsePatternLabel,
      'summary': summary,
      'topConcernAreas': topConcernAreas,
      'recommendedNextStep': recommendedNextStep,
      'mentalStatusSignal': mentalStatusSignal.name,
      'signalSource': signalSource,
      'signalGeneratedAt': signalGeneratedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'algorithmVersion': interpretation.algorithmVersion,
      'questionSetVersion': interpretation.questionSetVersion,
      'supportPriority': interpretation.supportPriority.name,
      'interpretation': interpretation.toJson(),
    };
  }
}
