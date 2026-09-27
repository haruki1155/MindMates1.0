import '../models/student_assessment_models.dart';

/// Immutable mobile projections of the staging-only workplace V4 catalogs.
/// The callable backend remains the sole scoring authority.
class TeachingAssessmentV4Questions {
  const TeachingAssessmentV4Questions._();

  static const instrumentVersion = 'teaching_workplace_reflection_v4';
  static final questions = _WorkplaceV4Catalog.build(
    prefix: 'teaching_v4',
    workloadDomain: 'teachingWorkloadDemands',
    supportDomain: 'teachingSupport',
    engagementDomain: 'teachingEngagementMeaning',
    workloadSection: AssessmentSection.professionalWellBeing,
    supportSection: AssessmentSection.professionalSupport,
    engagementSection: AssessmentSection.professionalWellBeing,
    workload: const [
      [
        'workload_manageability',
        'protective',
        'My teaching workload felt manageable.',
      ],
      [
        'preparation_time',
        'protective',
        'I had enough time to prepare for my teaching responsibilities.',
      ],
      [
        'deadline_pressure',
        'risk',
        'I found it difficult to keep up with work deadlines.',
      ],
      [
        'administrative_load',
        'risk',
        'Administrative duties competed with the time I needed for teaching.',
      ],
      [
        'role_clarity',
        'protective',
        'I was clear about what was expected of me in my role.',
      ],
      [
        'prioritization',
        'protective',
        'I was able to prioritize my work responsibilities.',
      ],
      [
        'work_personal_boundary',
        'risk',
        'My work extended into time I intended for my personal life.',
      ],
      [
        'work_pace',
        'risk',
        'The pace of my teaching-related responsibilities was difficult to sustain.',
      ],
      [
        'work_control',
        'protective',
        'I had enough control over how I organized my work.',
      ],
      [
        'time_sufficiency',
        'protective',
        'I could complete my essential duties within a reasonable amount of working time.',
      ],
    ],
    support: const [
      [
        'colleague_support',
        'protective',
        'I could rely on colleagues for help when I needed it.',
      ],
      [
        'speaking_up_safety',
        'protective',
        'I felt safe raising a workplace concern.',
      ],
      [
        'leadership_listening',
        'protective',
        'Department or unit leaders listened to concerns from staff.',
      ],
      [
        'workplace_respect',
        'protective',
        'I was treated with respect at work.',
      ],
      ['recognition', 'protective', 'My contributions were acknowledged.'],
      [
        'feedback_quality',
        'protective',
        'The feedback I received helped me improve my work.',
      ],
      [
        'teaching_resources',
        'protective',
        'I had access to the resources I needed to teach effectively.',
      ],
      [
        'communication_clarity',
        'protective',
        'Important workplace information was communicated clearly.',
      ],
      [
        'support_navigation',
        'protective',
        'I knew where to seek help for a workplace or well-being concern.',
      ],
      [
        'professional_belonging',
        'protective',
        'I felt part of a cooperative professional community.',
      ],
    ],
    engagement: const [
      ['work_meaning', 'protective', 'My teaching work felt meaningful to me.'],
      [
        'positive_contribution',
        'protective',
        'I felt that my work made a positive contribution to students or the university.',
      ],
      [
        'work_interest',
        'protective',
        'I remained interested in my teaching and professional tasks.',
      ],
      [
        'strength_use',
        'protective',
        'I had opportunities to use my strengths in my work.',
      ],
      [
        'professional_growth',
        'protective',
        'I had opportunities to learn or grow professionally.',
      ],
      [
        'role_self_efficacy',
        'protective',
        'I felt capable of handling the challenges that came with my role.',
      ],
      [
        'work_autonomy',
        'protective',
        'I had enough choice in how I approached my work.',
      ],
      [
        'progress',
        'protective',
        'I could see progress in work that mattered to me.',
      ],
      [
        'work_absorption',
        'protective',
        'I experienced periods of strong focus and involvement in my work.',
      ],
      [
        'role_motivation',
        'protective',
        'I felt motivated to continue contributing in my professional role.',
      ],
    ],
  );
}

class NonTeachingAssessmentV4Questions {
  const NonTeachingAssessmentV4Questions._();

  static const instrumentVersion = 'non_teaching_workplace_reflection_v4';
  static final questions = _WorkplaceV4Catalog.build(
    prefix: 'non_teaching_v4',
    workloadDomain: 'nonTeachingWorkloadDemands',
    supportDomain: 'nonTeachingSupport',
    engagementDomain: 'nonTeachingEngagementMeaning',
    workloadSection: AssessmentSection.workplaceWellBeing,
    supportSection: AssessmentSection.workplaceSupport,
    engagementSection: AssessmentSection.workplaceWellBeing,
    workload: const [
      ['workload_manageability', 'protective', 'My workload felt manageable.'],
      [
        'time_sufficiency',
        'protective',
        'I had enough time to complete my main work duties.',
      ],
      [
        'deadline_pressure',
        'risk',
        'I found it difficult to keep up with work deadlines.',
      ],
      [
        'interruptions',
        'risk',
        'Frequent interruptions made it difficult to complete my work.',
      ],
      [
        'role_clarity',
        'protective',
        'I was clear about what was expected of me in my role.',
      ],
      ['work_pace', 'risk', 'The pace of my work was difficult to sustain.'],
      [
        'work_personal_boundary',
        'risk',
        'My work extended into time I intended for my personal life.',
      ],
      [
        'task_load',
        'risk',
        'I found it difficult to manage several work responsibilities at the same time.',
      ],
      [
        'prioritization',
        'protective',
        'I was able to prioritize my work responsibilities.',
      ],
      [
        'work_completion',
        'protective',
        'I could complete my essential duties within a reasonable amount of working time.',
      ],
    ],
    support: const [
      [
        'supervisor_support',
        'protective',
        'I could ask my supervisor for help when I needed it.',
      ],
      [
        'coworker_support',
        'protective',
        'I could rely on coworkers for help when I needed it.',
      ],
      [
        'speaking_up_safety',
        'protective',
        'I felt safe raising a workplace concern.',
      ],
      [
        'workplace_respect',
        'protective',
        'I was treated with respect at work.',
      ],
      ['recognition', 'protective', 'My contributions were acknowledged.'],
      [
        'supervisor_listening',
        'protective',
        'My supervisor listened when I raised a work-related concern.',
      ],
      [
        'work_resources',
        'protective',
        'I had access to the tools and resources needed for my duties.',
      ],
      [
        'communication_clarity',
        'protective',
        'Important workplace information was communicated clearly.',
      ],
      [
        'support_navigation',
        'protective',
        'I knew where to seek help for a workplace or well-being concern.',
      ],
      [
        'team_cooperation',
        'protective',
        'My team cooperated when work demands were high.',
      ],
    ],
    engagement: const [
      ['work_meaning', 'protective', 'My work felt meaningful to me.'],
      [
        'positive_contribution',
        'protective',
        'I felt that my work contributed positively to the university community.',
      ],
      [
        'work_interest',
        'protective',
        'I remained interested in my day-to-day work.',
      ],
      [
        'strength_use',
        'protective',
        'I had opportunities to use my strengths in my work.',
      ],
      [
        'skill_growth',
        'protective',
        'I had opportunities to learn or develop useful skills.',
      ],
      [
        'role_self_efficacy',
        'protective',
        'I felt capable of handling the challenges that came with my role.',
      ],
      [
        'work_autonomy',
        'protective',
        'I had enough choice in how I approached my work.',
      ],
      [
        'progress',
        'protective',
        'I could see progress in work that mattered to me.',
      ],
      [
        'work_absorption',
        'protective',
        'I experienced periods of strong focus and involvement in my work.',
      ],
      [
        'role_motivation',
        'protective',
        'I felt motivated to continue contributing in my role.',
      ],
    ],
  );
}

class _WorkplaceV4Catalog {
  static List<StudentAssessmentQuestion> build({
    required String prefix,
    required String workloadDomain,
    required String supportDomain,
    required String engagementDomain,
    required AssessmentSection workloadSection,
    required AssessmentSection supportSection,
    required AssessmentSection engagementSection,
    required List<List<String>> workload,
    required List<List<String>> support,
    required List<List<String>> engagement,
  }) => [
    ..._items(
      prefix,
      'workload_demands',
      workloadDomain,
      workloadSection,
      workload,
      1,
    ),
    ..._items(prefix, 'support', supportDomain, supportSection, support, 11),
    ..._items(
      prefix,
      'engagement_meaning',
      engagementDomain,
      engagementSection,
      engagement,
      21,
    ),
    ..._items(
      prefix,
      'sleep_rest',
      'sleepRest',
      AssessmentSection.sleepRest,
      _sleep,
      31,
    ),
    ..._items(
      prefix,
      'emotional_wellbeing',
      'emotionalWellbeing',
      AssessmentSection.emotionalWellBeing,
      _emotional,
      41,
    ),
  ];

  static List<StudentAssessmentQuestion> _items(
    String prefix,
    String idPart,
    String domain,
    AssessmentSection section,
    List<List<String>> source,
    int start,
  ) => [
    for (var i = 0; i < source.length; i++)
      StudentAssessmentQuestion(
        id: '${prefix}_${idPart}_${(i + 1).toString().padLeft(2, '0')}',
        text: source[i][2],
        section: section,
        direction: source[i][1] == 'risk'
            ? AssessmentDirection.risk
            : AssessmentDirection.protective,
        v4DomainId: domain,
        constructId: source[i][0],
        displayOrder: start + i,
      ),
  ];

  static const _sleep = [
    [
      'sleep_onset',
      'protective',
      'I was able to fall asleep in a reasonable amount of time.',
    ],
    [
      'sleep_continuity',
      'risk',
      'I woke during sleep and found it difficult to return to sleep.',
    ],
    [
      'sleep_rest',
      'protective',
      'I got enough sleep to feel rested the next day.',
    ],
    ['sleep_refreshment', 'protective', 'I woke feeling refreshed.'],
    [
      'sleep_routine',
      'protective',
      'My sleep and wake times were close to the schedule I intended.',
    ],
    [
      'daytime_alertness',
      'risk',
      'I struggled to stay awake during the day because I had not slept enough.',
    ],
    [
      'sleep_worry',
      'risk',
      'Worrying thoughts made it hard for me to fall asleep.',
    ],
    [
      'rest_opportunity',
      'protective',
      'I had enough opportunity to rest when I needed it.',
    ],
    [
      'sleep_quality',
      'protective',
      'I was satisfied with the quality of my sleep.',
    ],
    [
      'sleep_wind_down',
      'protective',
      'I was able to set aside time to wind down before sleep.',
    ],
  ];
  static const _emotional = [
    [
      'emotional_positivity',
      'protective',
      'I felt cheerful or in good spirits.',
    ],
    ['emotional_calm', 'protective', 'I felt calm and settled.'],
    [
      'emotional_engagement',
      'protective',
      'I felt interested in my day-to-day activities.',
    ],
    [
      'frustration_coping',
      'protective',
      'I felt able to handle everyday frustrations.',
    ],
    [
      'emotional_awareness',
      'protective',
      'I could recognize what I was feeling.',
    ],
    ['hope', 'protective', 'I felt hopeful about the near future.'],
    ['emotional_exhaustion', 'risk', 'I felt emotionally drained.'],
    [
      'emotional_demands',
      'risk',
      'I felt overwhelmed by everyday emotional demands.',
    ],
    [
      'emotional_recovery',
      'protective',
      'I could regain emotional balance after an ordinary setback.',
    ],
    [
      'emotional_satisfaction',
      'protective',
      'I felt satisfied with my current emotional well-being.',
    ],
  ];
}
