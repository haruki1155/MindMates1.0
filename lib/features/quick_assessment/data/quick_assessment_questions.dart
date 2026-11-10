import '../models/quick_assessment_models.dart';

class QuickAssessmentQuestions {
  const QuickAssessmentQuestions._();

  static const basePath = 'assets/images/Quick assesment';

  static const questions = [
    QuickAssessmentQuestion(
      id: 'calm_relaxed',
      prompt:
          'Over the last two weeks, how often have you felt calm and relaxed?',
      direction: QuickQuestionDirection.protective,
      options: [
        QuickAssessmentOption(
          id: 'all_time',
          label: 'All of the time',
          value: 5,
          iconAssetPath: '$basePath/QUESTION 1/relieved.png',
        ),
        QuickAssessmentOption(
          id: 'most_time',
          label: 'Most of the time',
          value: 4,
          iconAssetPath: '$basePath/QUESTION 1/slightly_smiling.png',
        ),
        QuickAssessmentOption(
          id: 'more_than_half',
          label: 'More than half the time',
          value: 3,
          iconAssetPath: '$basePath/QUESTION 1/neutral.png',
        ),
        QuickAssessmentOption(
          id: 'less_than_half',
          label: 'Less than half the time',
          value: 2,
          iconAssetPath: '$basePath/QUESTION 1/worried.png',
        ),
        QuickAssessmentOption(
          id: 'at_no_time',
          label: 'At no time',
          value: 1,
          iconAssetPath: '$basePath/QUESTION 1/crying.png',
        ),
      ],
    ),
    QuickAssessmentQuestion(
      id: 'overwhelmed',
      prompt:
          'Over the last two weeks, how often have you felt overwhelmed by the number of things you need to do?',
      direction: QuickQuestionDirection.risk,
      options: [
        QuickAssessmentOption(
          id: 'never',
          label: 'Never',
          value: 1,
          iconAssetPath: '$basePath/QUESTION 2/cool.png',
        ),
        QuickAssessmentOption(
          id: 'rarely',
          label: 'Rarely',
          value: 2,
          iconAssetPath: '$basePath/QUESTION 2/slightly_smiling.png',
        ),
        QuickAssessmentOption(
          id: 'sometimes',
          label: 'Sometimes',
          value: 3,
          iconAssetPath: '$basePath/QUESTION 2/neutral.png',
        ),
        QuickAssessmentOption(
          id: 'fairly_often',
          label: 'Fairly often',
          value: 4,
          iconAssetPath: '$basePath/QUESTION 2/sweating.png',
        ),
        QuickAssessmentOption(
          id: 'very_often',
          label: 'Very often',
          value: 5,
          iconAssetPath: '$basePath/QUESTION 5/worried.png',
        ),
      ],
    ),
    QuickAssessmentQuestion(
      id: 'connected',
      prompt:
          'Over the last two weeks, how connected have you felt to the people around you at school or at work?',
      direction: QuickQuestionDirection.protective,
      options: [
        QuickAssessmentOption(
          id: 'very_connected',
          label: 'Very connected',
          value: 5,
          iconAssetPath: '$basePath/QUESTION 3/handshake.png',
        ),
        QuickAssessmentOption(
          id: 'somewhat_connected',
          label: 'Somewhat connected',
          value: 4,
          iconAssetPath: '$basePath/QUESTION 3/slightly_smiling.png',
        ),
        QuickAssessmentOption(
          id: 'neutral',
          label: 'Neutral',
          value: 3,
          iconAssetPath: '$basePath/QUESTION 3/neutral.png',
        ),
        QuickAssessmentOption(
          id: 'somewhat_disconnected',
          label: 'Somewhat disconnected',
          value: 2,
          iconAssetPath: '$basePath/QUESTION 3/worried.png',
        ),
        QuickAssessmentOption(
          id: 'very_disconnected',
          label: 'Very disconnected',
          value: 1,
          iconAssetPath: '$basePath/QUESTION 3/crying.png',
        ),
      ],
    ),
    QuickAssessmentQuestion(
      id: 'little_interest',
      prompt:
          'Over the last two weeks, how often have you had little interest or pleasure in doing things you usually enjoy?',
      direction: QuickQuestionDirection.risk,
      options: [
        QuickAssessmentOption(
          id: 'not_at_all',
          label: 'Not at all',
          value: 1,
          iconAssetPath: '$basePath/QUESTION 4/relieved.png',
        ),
        QuickAssessmentOption(
          id: 'several_days',
          label: 'Several days',
          value: 2,
          iconAssetPath: '$basePath/QUESTION 4/slightly_smiling.png',
        ),
        QuickAssessmentOption(
          id: 'more_than_half',
          label: 'More than half the time',
          value: 3,
          iconAssetPath: '$basePath/QUESTION 4/neutral.png',
        ),
        QuickAssessmentOption(
          id: 'nearly_every_day',
          label: 'Nearly every day',
          value: 4,
          iconAssetPath: '$basePath/QUESTION 4/worried.png',
        ),
      ],
    ),
    QuickAssessmentQuestion(
      id: 'stress_affecting_life',
      prompt:
          'Over the last two weeks, how often has stress from academics or work affected your ability to cope with daily life?',
      direction: QuickQuestionDirection.risk,
      options: [
        QuickAssessmentOption(
          id: 'never',
          label: 'Never',
          value: 1,
          iconAssetPath: '$basePath/QUESTION 5/strong.png',
        ),
        QuickAssessmentOption(
          id: 'rarely',
          label: 'Rarely',
          value: 2,
          iconAssetPath: '$basePath/QUESTION 5/slightly_smiling.png',
        ),
        QuickAssessmentOption(
          id: 'sometimes',
          label: 'Sometimes',
          value: 3,
          iconAssetPath: '$basePath/QUESTION 5/neutral.png',
        ),
        QuickAssessmentOption(
          id: 'often',
          label: 'Often',
          value: 4,
          iconAssetPath: '$basePath/QUESTION 5/sweating.png',
        ),
        QuickAssessmentOption(
          id: 'always',
          label: 'Always',
          value: 5,
          iconAssetPath: '$basePath/QUESTION 5/tired.png',
        ),
      ],
    ),
  ];
}
