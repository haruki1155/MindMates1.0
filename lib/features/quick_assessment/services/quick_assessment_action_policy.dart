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
      heading: 'Keep up your healthy habits',
      guidance:
          'Your answers suggest you are doing well. Keep noticing what helps you feel steady, and check in again anytime.',
      recommendsFullAssessment: false,
      showsFullAssessmentAction: false,
      showsAppointmentAction: false,
      promptsForAppointment: false,
    ),
    QuickAssessmentLevel.moderate => const QuickAssessmentActionPolicy._(
      heading: 'Get a fuller picture',
      guidance:
          'The Full Assessment looks at more areas of your well-being and gives you more personalized insights.',
      recommendsFullAssessment: true,
      showsFullAssessmentAction: true,
      showsAppointmentAction: false,
      promptsForAppointment: false,
    ),
    QuickAssessmentLevel.high => const QuickAssessmentActionPolicy._(
      heading: 'Consider extra support',
      guidance:
          'The Full Assessment can give you a deeper look, and you can also book a confidential appointment with PACC.',
      recommendsFullAssessment: true,
      showsFullAssessmentAction: true,
      showsAppointmentAction: true,
      promptsForAppointment: false,
    ),
    QuickAssessmentLevel.veryHigh => const QuickAssessmentActionPolicy._(
      heading: 'Support is here for you',
      guidance:
          'You can book a confidential appointment with a PACC counselor. The Full Assessment is also available whenever you are ready.',
      recommendsFullAssessment: false,
      showsFullAssessmentAction: true,
      showsAppointmentAction: true,
      promptsForAppointment: true,
    ),
  };
}
