enum InterventionType {
  walking,
  breathing,
  grounding,
  appointment,
  academicPlanning,
  financialPlanning,
}

/// Concise review-card and intro copy for one Student Well-Being V4 activity.
class StudentV4ActivityCopy {
  const StudentV4ActivityCopy({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

const Map<InterventionType, StudentV4ActivityCopy> _studentV4ActivityCopy = {
  InterventionType.academicPlanning: StudentV4ActivityCopy(
    title: 'Start with five minutes',
    description:
        'Pick one small 5-minute first step and pair it with a practical time or cue.',
  ),
  InterventionType.financialPlanning: StudentV4ActivityCopy(
    title: 'Choose one practical next step',
    description:
        'Select one manageable step, such as checking a due date, finding a student support contact, or setting a calm time to revisit it.',
  ),
  InterventionType.walking: StudentV4ActivityCopy(
    title: 'Take a short walk',
    description:
        'Step out for a brief 1–3 minute walk at a comfortable pace—alone or with someone if you feel like company.',
  ),
  InterventionType.breathing: StudentV4ActivityCopy(
    title: 'Try a breathing wind-down',
    description:
        'Take a short guided breathing pause with an optional hold control you can keep comfortable.',
  ),
  InterventionType.grounding: StudentV4ActivityCopy(
    title: 'Ground and notice',
    description:
        'Reset with the five senses and optionally take a moment to notice or name what you feel.',
  ),
};

StudentV4ActivityCopy? studentV4ActivityCopyFor(InterventionType type) =>
    _studentV4ActivityCopy[type];

enum InterventionOutcome {
  completed,
  selfReportedCompleted,
  skipped,
  cancelled,
  failed,
}

enum InterventionFeedbackChoice { helped, neutral, didNotHelp }

class InterventionFeedback {
  const InterventionFeedback({required this.choice, this.reflection});

  final InterventionFeedbackChoice choice;
  final String? reflection;
}
