import '../models/quick_assessment_models.dart';

/// Presentation policy for a completed Quick Assessment. It deliberately
/// consumes the existing calculated level instead of scoring responses.
class QuickAssessmentActionPolicy {
  const QuickAssessmentActionPolicy._({
    required this.heading,
    required this.guidance,
    required this.recommendsFullAssessment,
    required this.showsFullAssessmentAction,
    required this.showsAppointmentAction,
    required this.promptsForAppointment,
  });

  final String heading;
  final String guidance;
  final bool recommendsFullAssessment;
  final bool showsFullAssessmentAction;
  final bool showsAppointmentAction;
  final bool promptsForAppointment;

  static QuickAssessmentActionPolicy forLevel(
    QuickAssessmentLevel level,
  ) => switch (level) {
    QuickAssessmentLevel.low => const QuickAssessmentActionPolicy._(
      heading: 'Continue with your day',
      guidance:
          'Your brief check-in suggests supportive patterns. Keep noticing what helps you feel steady.',
      recommendsFullAssessment: false,
      showsFullAssessmentAction: false,
      showsAppointmentAction: false,
      promptsForAppointment: false,
    ),
    QuickAssessmentLevel.moderate => const QuickAssessmentActionPolicy._(
      heading: 'A fuller check-in may help',
      guidance:
          'A Full Assessment can offer a more complete reflection across your well-being areas.',
      recommendsFullAssessment: true,
      showsFullAssessmentAction: true,
      showsAppointmentAction: false,
      promptsForAppointment: false,
    ),
    QuickAssessmentLevel.high => const QuickAssessmentActionPolicy._(
      heading: 'Consider additional support',
      guidance:
          'A Full Assessment can offer deeper reflection, and you may choose to request a PACC appointment.',
      recommendsFullAssessment: true,
      showsFullAssessmentAction: true,
      showsAppointmentAction: true,
      promptsForAppointment: false,
    ),
    QuickAssessmentLevel.veryHigh => const QuickAssessmentActionPolicy._(
      heading: 'Support is available',
      guidance:
          'You may choose to request confidential support from PACC. A Full Assessment remains available when you are ready.',
      recommendsFullAssessment: false,
      showsFullAssessmentAction: true,
      showsAppointmentAction: true,
      promptsForAppointment: true,
    ),
  };
}
