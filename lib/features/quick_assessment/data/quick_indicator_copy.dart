import 'quick_assessment_questions.dart';

class QuickIndicatorCopy {
  const QuickIndicatorCopy({
    required this.name,
    required this.goingWell,
    required this.closerLook,
    required this.purpose,
  });

  final String name;
  final String goingWell;
  final String closerLook;
  final String purpose;

  static QuickIndicatorCopy? forQuestionId(String questionId) {
    final index = QuickAssessmentQuestions.questions.indexWhere(
      (q) => q.id == questionId,
    );
    if (index < 0) return null;
    final question = QuickAssessmentQuestions.questions[index];
    final text = _byQuestionId[questionId];
    if (text == null) return null;
    return QuickIndicatorCopy(
      name: text.name,
      goingWell: text.goingWell,
      closerLook: text.closerLook,
      purpose: question.purpose,
    );
  }

  static const _byQuestionId = <String, QuickIndicatorCopy>{
    'calm_relaxed': QuickIndicatorCopy(
      name: 'Emotional calm',
      goingWell:
          'You have often felt calm, which suggests you are finding time to rest and recover.',
      closerLook:
          'You have not felt calm very often lately. Short breaks, slow breathing, or a MindMate breathing exercise may help.',
      purpose: '',
    ),
    'overwhelmed': QuickIndicatorCopy(
      name: 'Stress load',
      goingWell:
          'Your tasks feel manageable right now. Keep the routines that help you stay on top of things.',
      closerLook:
          'Your tasks have felt overwhelming. Breaking work into smaller steps or talking to someone you trust can lighten the load.',
      purpose: '',
    ),
    'connected': QuickIndicatorCopy(
      name: 'Social connection',
      goingWell:
          'You feel connected to the people around you. These relationships are a strong source of support.',
      closerLook:
          'You have felt less connected lately. Reaching out to a friend, classmate, or co-worker can make a real difference.',
      purpose: '',
    ),
    'little_interest': QuickIndicatorCopy(
      name: 'Motivation and interest',
      goingWell:
          'You are still enjoying the things you like to do, which is a healthy sign for your mood and energy.',
      closerLook:
          'You have had less interest in things you usually enjoy. If this continues, it is worth talking to someone, such as a PACC counselor.',
      purpose: '',
    ),
    'stress_affecting_life': QuickIndicatorCopy(
      name: 'Daily coping',
      goingWell:
          'Stress has not been getting in the way of your daily life. You seem to be coping well.',
      closerLook:
          'Stress has been affecting your daily life. This is a good time to look for support before it builds up.',
      purpose: '',
    ),
  };
}
