class ClientFeedbackQuestionGroup {
  const ClientFeedbackQuestionGroup({
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.questions,
  });

  final String title;
  final String subtitle;
  final String iconName;
  final List<String> questions;
}

const clientFeedbackAcademicYear = 'Survey A.Y. 2025–2026';

const clientFeedbackEvaluationCopy =
    'Please answer honestly and to the best of your ability. Your responses are confidential and will be used only to improve Career Guidance and Placement Services, programs, and events.';

const clientFeedbackPrivacyNotice =
    'UCU–PACC collects your email address, full name, sex, course, client type, ratings, and optional comments for service evaluation, in accordance with the Data Privacy Act of 2012.\n\n'
    'Your information is kept confidential, stored securely, and accessed only by authorized PACC personnel. It will not be shared without your consent unless required by law.\n\n'
    'You may request access, correction, deletion, or withdrawal of consent, subject to applicable requirements. Withdrawing consent may prevent completion of this evaluation.';

const clientFeedbackClientTypes = [
  'Student',
  'Alumni',
  'Parent',
  'UCU / City Hall Employee',
  'Walk-in visitor',
];

const clientFeedbackRatingGuide = [
  (5, 'Excellent'),
  (4, 'Very satisfactory'),
  (3, 'Neutral'),
  (2, 'Poor'),
  (1, 'Needs improvement'),
];

const clientFeedbackQuestionGroups = [
  ClientFeedbackQuestionGroup(
    title: 'Service delivery',
    subtitle: 'Promptness and courtesy',
    iconName: 'support',
    questions: ['Provides prompt service', 'Delivers courteous service'],
  ),
  ClientFeedbackQuestionGroup(
    title: 'Information and output',
    subtitle: 'Clarity, accuracy, and timeliness',
    iconName: 'document',
    questions: [
      'Gives clear information',
      'Prepares accurate output',
      'Releases document/s on the scheduled date',
    ],
  ),
  ClientFeedbackQuestionGroup(
    title: 'Waiting area',
    subtitle: 'Cleanliness, comfort, and wayfinding',
    iconName: 'place',
    questions: [
      'The waiting area is clean',
      'The waiting area is comfortable',
      'Signs are clearly displayed',
    ],
  ),
];

final clientFeedbackQuestions = clientFeedbackQuestionGroups
    .expand((group) => group.questions)
    .toList(growable: false);
