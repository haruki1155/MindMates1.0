class BreathingTechnique {
  const BreathingTechnique({
    required this.id,
    required this.title,
    required this.durationSeconds,
    required this.bestFor,
    required this.howTo,
    required this.pattern,
    this.hasBreathHold = false,
  });

  final String id;
  final String title;
  final int durationSeconds;
  final String bestFor;
  final String howTo;
  final BreathingPattern pattern;
  final bool hasBreathHold;

  String get durationLabel {
    if (durationSeconds < 60) return '$durationSeconds sec';
    final minutes = durationSeconds ~/ 60;
    return '$minutes min';
  }
}

class BreathingPattern {
  const BreathingPattern(this.steps);

  final List<BreathingStep> steps;

  static const emergencyReset = BreathingPattern([
    BreathingStep('Inhale gently', 4, 'Breathe in softly through your nose.'),
    BreathingStep(
      'Exhale slowly',
      6,
      'Let the breath leave through your mouth.',
    ),
  ]);

  static const cyclicSigh = BreathingPattern([
    BreathingStep('Inhale', 2, 'Breathe in through your nose.'),
    BreathingStep('Top-up inhale', 1, 'Take one smaller inhale to expand.'),
    BreathingStep('Long exhale', 5, 'Release slowly through your mouth.'),
  ]);

  static const longExhale = BreathingPattern([
    BreathingStep('Inhale', 3, 'Breathe in for three counts.'),
    BreathingStep('Exhale', 6, 'Exhale for six counts.'),
  ]);

  static const box = BreathingPattern([
    BreathingStep('Inhale', 4, 'Breathe in steadily.'),
    BreathingStep('Hold', 4, 'Hold gently. Stop if uncomfortable.'),
    BreathingStep('Exhale', 4, 'Breathe out steadily.'),
    BreathingStep('Hold', 4, 'Pause softly before the next breath.'),
  ]);

  static const balanced = BreathingPattern([
    BreathingStep('Inhale', 4, 'Breathe in calmly.'),
    BreathingStep('Exhale', 4, 'Breathe out calmly.'),
  ]);

  static const nhsCalm = BreathingPattern([
    BreathingStep('Belly inhale', 5, 'Breathe gently into your belly.'),
    BreathingStep('Soft exhale', 5, 'Exhale through your mouth.'),
  ]);

  static const fourSevenEight = BreathingPattern([
    BreathingStep('Inhale', 4, 'Breathe in through your nose.'),
    BreathingStep('Hold', 7, 'Hold gently, or shorten this count.'),
    BreathingStep('Exhale', 8, 'Exhale slowly through your mouth.'),
  ]);

  static const belly = BreathingPattern([
    BreathingStep('Belly inhale', 4, 'Let your belly rise under your hands.'),
    BreathingStep('Pursed-lip exhale', 6, 'Exhale slowly through pursed lips.'),
  ]);

  static const mindful = BreathingPattern([
    BreathingStep('Calm breathing', 300, 'Settle into an easy breath.'),
    BreathingStep(
      'Belly breathing',
      300,
      'Notice the belly rising and falling.',
    ),
    BreathingStep(
      'Breath awareness',
      300,
      'Let thoughts pass and return to the breath.',
    ),
  ]);

  static const fullRoutine = BreathingPattern([
    BreathingStep(
      'Belly breathing',
      300,
      'Relax your shoulders and breathe low.',
    ),
    BreathingStep('Long exhale', 300, 'Let every exhale last a little longer.'),
    BreathingStep('Box breathing', 300, 'Use gentle four-count box breathing.'),
    BreathingStep(
      'Quiet reflection',
      300,
      'Rest with your breath or gratitude.',
    ),
  ]);
}

class BreathingStep {
  const BreathingStep(this.label, this.seconds, this.guidance);

  final String label;
  final int seconds;
  final String guidance;
}

class BreathingPhase {
  const BreathingPhase({
    required this.label,
    required this.guidance,
    required this.stepSeconds,
    required this.remainingStepSeconds,
    required this.stepIndex,
  });

  final String label;
  final String guidance;
  final int stepSeconds;
  final int remainingStepSeconds;
  final int stepIndex;
}

/// Research is linked to the general method, not to an untested app outcome.
/// Exact counts and concern-to-technique matching are app design decisions
/// unless the cited publication explicitly evaluated them.
class BreathingEvidence {
  const BreathingEvidence({
    required this.source,
    required this.title,
    required this.url,
    required this.summary,
    required this.limitations,
  });

  final String source;
  final String title;
  final String url;
  final String summary;
  final String limitations;
}

class BreathingPlan {
  const BreathingPlan._();

  static const techniques = [
    BreathingTechnique(
      id: 'emergency_reset',
      title: 'Emergency Reset Breath',
      durationSeconds: 30,
      bestFor: 'Sudden stress, overwhelm',
      howTo:
          'Inhale gently through the nose, then exhale slowly through the mouth. Repeat 3-5 times.',
      pattern: BreathingPattern.emergencyReset,
    ),
    BreathingTechnique(
      id: 'cyclic_sighing',
      title: 'Cyclic Sighing Mini Reset',
      durationSeconds: 60,
      bestFor: 'Quick anxiety relief',
      howTo:
          'Inhale through the nose, take a second small inhale, then slowly exhale through the mouth.',
      pattern: BreathingPattern.cyclicSigh,
    ),
    BreathingTechnique(
      id: 'long_exhale',
      title: 'Long Exhale Breathing',
      durationSeconds: 120,
      bestFor: 'Calming the nervous system',
      howTo: 'Inhale for 3 counts, exhale for 6 counts.',
      pattern: BreathingPattern.longExhale,
    ),
    BreathingTechnique(
      id: 'box_breathing',
      title: 'Box Breathing',
      durationSeconds: 180,
      bestFor: 'Focus, stress control',
      howTo: 'Inhale 4, hold 4, exhale 4, hold 4. Repeat slowly.',
      pattern: BreathingPattern.box,
      hasBreathHold: true,
    ),
    BreathingTechnique(
      id: 'balanced_calm',
      title: 'Balanced Calm Breathing',
      durationSeconds: 240,
      bestFor: 'General relaxation',
      howTo: 'Inhale 4, exhale 4. No breath holding.',
      pattern: BreathingPattern.balanced,
    ),
    BreathingTechnique(
      id: 'nhs_calm',
      title: 'NHS Calm Breathing',
      durationSeconds: 300,
      bestFor: 'Stress and anxiety',
      howTo:
          'Breathe gently into the belly, inhale through the nose and exhale through the mouth.',
      pattern: BreathingPattern.nhsCalm,
    ),
    BreathingTechnique(
      id: 'four_seven_eight',
      title: '4-7-8 Breathing',
      durationSeconds: 420,
      bestFor: 'Sleep preparation, evening relaxation',
      howTo: 'Inhale 4, hold 7, exhale 8. Reduce counts if uncomfortable.',
      pattern: BreathingPattern.fourSevenEight,
      hasBreathHold: true,
    ),
    BreathingTechnique(
      id: 'belly_breathing',
      title: 'Belly / Diaphragmatic Breathing',
      durationSeconds: 600,
      bestFor: 'Deep relaxation, body awareness',
      howTo:
          'Sit or lie down, place hands on belly, inhale through the nose, exhale slowly through pursed lips.',
      pattern: BreathingPattern.belly,
    ),
    BreathingTechnique(
      id: 'mindful_session',
      title: 'Mindful Breathing Session',
      durationSeconds: 900,
      bestFor: 'Emotional regulation',
      howTo:
          'Do 5 min calm breathing, 5 min belly breathing, then 5 min silent breath awareness.',
      pattern: BreathingPattern.mindful,
    ),
    BreathingTechnique(
      id: 'full_relaxation',
      title: 'Full Relaxation Routine',
      durationSeconds: 1200,
      bestFor: 'Daily mental wellbeing',
      howTo:
          '5 min belly breathing, 5 min long-exhale breathing, 5 min box breathing, 5 min quiet breathing or gratitude.',
      pattern: BreathingPattern.fullRoutine,
      hasBreathHold: true,
    ),
  ];

  static const slowBreathingEvidence = BreathingEvidence(
    source: 'Zaccaro et al. (2018) — systematic review',
    title: 'How Breath-Control Can Change Your Life',
    url: 'https://doi.org/10.3389/fnhum.2018.00353',
    summary:
        'A systematic review describes physiological and psychological '
        'correlates of slow breathing (under 10 breaths per minute).',
    limitations:
        'The review does not establish this exact count, session duration, '
        'or concern-based matching as a proven treatment.',
  );

  static const boxBreathingEvidence = BreathingEvidence(
    source: 'Yilmaz Balban et al. (2023) — randomized study',
    title: 'Brief Structured Respiration Practices Enhance Mood and Reduce '
        'Physiological Arousal',
    url: 'https://doi.org/10.1016/j.xcrm.2022.100895',
    summary:
        'The study included equal-duration inhale, hold, exhale and hold '
        'box breathing sessions over 28 days.',
    limitations:
        'The study individualized box-breathing counts. MindMate uses '
        '4–4–4–4 seconds as an example, not a universally optimal schedule. '
        'Breath holds may feel uncomfortable; stop or choose a non-hold mode.',
  );

  static const cyclicSighEvidence = BreathingEvidence(
    source: 'Yilmaz Balban et al. (2023) — randomized study',
    title: 'Brief Structured Respiration Practices Enhance Mood and Reduce '
        'Physiological Arousal',
    url: 'https://doi.org/10.1016/j.xcrm.2022.100895',
    summary:
        'Participants practiced a slow inhale, a shorter second inhale '
        'and an extended exhale. Daily five-minute practice showed '
        'promising improvements in positive affect.',
    limitations:
        'MindMate’s fixed 2–1–5 timing is an illustrative pacing choice; '
        'the study did not validate that exact timing or a one-minute dose.',
  );

  static const nhsBreathingGuidance = BreathingEvidence(
    source: 'NHS — breathing exercises for stress',
    title: 'Breathing exercises for stress',
    url:
        'https://www.nhs.uk/mental-health/self-help/guides-tools-and-activities/breathing-exercises-for-stress/',
    summary:
        'The NHS recommends breathing in and out gently, optionally '
        'counting up to five each way, without forcing the breath.',
    limitations:
        'This is clinical self-help guidance, not a trial validating '
        'MindMate or promising an individual result.',
  );

  static BreathingEvidence evidenceFor(BreathingTechnique technique) {
    if (identical(technique.pattern, BreathingPattern.box)) {
      return boxBreathingEvidence;
    }
    if (identical(technique.pattern, BreathingPattern.cyclicSigh)) {
      return cyclicSighEvidence;
    }
    if (identical(technique.pattern, BreathingPattern.nhsCalm)) {
      return nhsBreathingGuidance;
    }
    return slowBreathingEvidence;
  }

  static String patternLabel(BreathingTechnique technique) => technique
      .pattern.steps
      .map((step) => '${step.label} ${step.seconds}s')
      .join(' → ');

  static BreathingPhase phaseFor(
    BreathingTechnique technique,
    int elapsedSeconds,
  ) {
    final steps = technique.pattern.steps;
    final cycleSeconds = steps.fold<int>(
      0,
      (total, step) => total + step.seconds,
    );
    final elapsedInCycle = cycleSeconds == 0
        ? 0
        : elapsedSeconds % cycleSeconds;
    var cursor = 0;

    for (var index = 0; index < steps.length; index++) {
      final step = steps[index];
      final end = cursor + step.seconds;
      if (elapsedInCycle < end) {
        return BreathingPhase(
          label: step.label,
          guidance: step.guidance,
          stepSeconds: step.seconds,
          remainingStepSeconds: end - elapsedInCycle,
          stepIndex: index,
        );
      }
      cursor = end;
    }

    final fallback = steps.last;
    return BreathingPhase(
      label: fallback.label,
      guidance: fallback.guidance,
      stepSeconds: fallback.seconds,
      remainingStepSeconds: 1,
      stepIndex: steps.length - 1,
    );
  }
}
