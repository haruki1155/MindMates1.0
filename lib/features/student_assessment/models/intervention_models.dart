enum InterventionType { walking, breathing, grounding, appointment }

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
