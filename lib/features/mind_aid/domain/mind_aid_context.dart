class MindAidAssessmentContext {
  const MindAidAssessmentContext({
    required this.userType,
    required this.overallScore,
    required this.status,
    required this.mainConcernAreas,
    required this.subscaleScores,
    required this.summaryMessage,
    this.createdAt,
  });

  final String userType;
  final double? overallScore;
  final String status;
  final List<String> mainConcernAreas;
  final Map<String, double> subscaleScores;
  final String summaryMessage;
  final DateTime? createdAt;

  bool get hasCategoryScores => subscaleScores.isNotEmpty;

  MapEntry<String, double>? get highestCategory {
    if (subscaleScores.isEmpty) return null;

    final entries = subscaleScores.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return entries.first;
  }

  List<MapEntry<String, double>> get topCategories {
    final entries = subscaleScores.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return entries.take(3).toList(growable: false);
  }
}

class MindAidQuickAssessmentContext {
  const MindAidQuickAssessmentContext({
    required this.score,
    required this.level,
    required this.signal,
    required this.summary,
    required this.topConcernAreas,
    required this.recommendedNextStep,
    this.createdAt,
  });

  final int score;
  final String level;
  final String signal;
  final String summary;
  final List<String> topConcernAreas;
  final String recommendedNextStep;
  final DateTime? createdAt;
}

class MindAidWellnessSnapshot {
  const MindAidWellnessSnapshot({
    this.latestMoodLevel,
    this.recentMoodAverage,
    this.moodTrend,
    this.latestMoodLabel,
    this.hasMoodNote = false,
    this.assessmentStatus,
    this.assessmentScore,
    this.mentalStatusSignal,
    this.topConcernAreas = const [],
    this.reportSummary,
    this.recommendedActions = const [],
    this.currentStreak = 0,
    this.activeDayCount = 0,
    this.breathingSessionCount = 0,
    this.mindfulBreathingMinutes = 0,
    this.lastCheckInAt,
  });

  final int? latestMoodLevel;
  final double? recentMoodAverage;
  final MindAidMoodTrend? moodTrend;
  final String? latestMoodLabel;
  final bool hasMoodNote;
  final String? assessmentStatus;
  final int? assessmentScore;
  final String? mentalStatusSignal;
  final List<String> topConcernAreas;
  final String? reportSummary;
  final List<String> recommendedActions;
  final int currentStreak;
  final int activeDayCount;
  final int breathingSessionCount;
  final int mindfulBreathingMinutes;
  final DateTime? lastCheckInAt;

  bool get hasMoodData => latestMoodLevel != null || recentMoodAverage != null;

  bool get hasRecentLowMood {
    final level = latestMoodLevel;
    final average = recentMoodAverage;
    return (level != null && level <= 2) || (average != null && average <= 2.4);
  }

  bool get hasElevatedAssessment {
    final status = assessmentStatus?.toLowerCase() ?? '';
    final signal = mentalStatusSignal?.toLowerCase() ?? '';
    final score = assessmentScore;
    return status.contains('high') ||
        status.contains('severe') ||
        status.contains('at risk') ||
        signal == 'watchful' ||
        signal == 'elevated' ||
        signal == 'highsupport' ||
        (score != null && score >= 70);
  }

  bool get hasNoRecentCheckIn {
    final checkedAt = lastCheckInAt;
    if (checkedAt == null) return true;
    return DateTime.now().difference(checkedAt).inDays >= 3;
  }

  bool get hasPositivePractice =>
      currentStreak >= 3 || breathingSessionCount > 0 || activeDayCount >= 3;

  bool get hasLowMoodTrend =>
      moodTrend == MindAidMoodTrend.declining || hasRecentLowMood;

  bool get hasElevatedSignal => hasElevatedAssessment || hasRecentLowMood;

  String? get primaryConcernLabel {
    if (topConcernAreas.isNotEmpty) return topConcernAreas.first;
    final status = assessmentStatus?.trim();
    if (status != null && status.isNotEmpty) return status;
    final label = latestMoodLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    return null;
  }

  String? get recommendedSupportAction {
    if (recommendedActions.isNotEmpty) return recommendedActions.first;
    if (hasElevatedAssessment) {
      return 'Consider reaching out to PACC or a trusted person';
    }
    if (hasRecentLowMood) {
      return 'Try one small grounding step and check in again later';
    }
    if (hasNoRecentCheckIn) {
      return 'Log a quick mood check-in so support can stay current';
    }
    if (hasPositivePractice) return 'Keep the routine that has been helping';
    return null;
  }

  MindAidWellnessSnapshot copyWith({
    int? latestMoodLevel,
    double? recentMoodAverage,
    MindAidMoodTrend? moodTrend,
    String? latestMoodLabel,
    bool? hasMoodNote,
    String? assessmentStatus,
    int? assessmentScore,
    String? mentalStatusSignal,
    List<String>? topConcernAreas,
    String? reportSummary,
    List<String>? recommendedActions,
    int? currentStreak,
    int? activeDayCount,
    int? breathingSessionCount,
    int? mindfulBreathingMinutes,
    DateTime? lastCheckInAt,
  }) {
    return MindAidWellnessSnapshot(
      latestMoodLevel: latestMoodLevel ?? this.latestMoodLevel,
      recentMoodAverage: recentMoodAverage ?? this.recentMoodAverage,
      moodTrend: moodTrend ?? this.moodTrend,
      latestMoodLabel: latestMoodLabel ?? this.latestMoodLabel,
      hasMoodNote: hasMoodNote ?? this.hasMoodNote,
      assessmentStatus: assessmentStatus ?? this.assessmentStatus,
      assessmentScore: assessmentScore ?? this.assessmentScore,
      mentalStatusSignal: mentalStatusSignal ?? this.mentalStatusSignal,
      topConcernAreas: topConcernAreas ?? this.topConcernAreas,
      reportSummary: reportSummary ?? this.reportSummary,
      recommendedActions: recommendedActions ?? this.recommendedActions,
      currentStreak: currentStreak ?? this.currentStreak,
      activeDayCount: activeDayCount ?? this.activeDayCount,
      breathingSessionCount:
          breathingSessionCount ?? this.breathingSessionCount,
      mindfulBreathingMinutes:
          mindfulBreathingMinutes ?? this.mindfulBreathingMinutes,
      lastCheckInAt: lastCheckInAt ?? this.lastCheckInAt,
    );
  }
}

enum MindAidMoodTrend {
  improving,
  steady,
  declining;

  String get label {
    switch (this) {
      case MindAidMoodTrend.improving:
        return 'improving';
      case MindAidMoodTrend.steady:
        return 'steady';
      case MindAidMoodTrend.declining:
        return 'declining';
    }
  }
}

class MindAidContext {
  const MindAidContext({
    this.recentMessages = const [],
    this.moodLevel,
    this.assessmentScore,
    this.quickAssessment,
    this.assessment,
    this.conversationSummary,
    this.preferredSupportStyle,
    this.journalText,
    this.wellnessSnapshot,
  });

  final List<String> recentMessages;
  final int? moodLevel;
  final int? assessmentScore;
  final MindAidQuickAssessmentContext? quickAssessment;
  final MindAidAssessmentContext? assessment;
  final String? conversationSummary;
  final MindAidSupportStyle? preferredSupportStyle;
  final String? journalText;
  final MindAidWellnessSnapshot? wellnessSnapshot;

  int? get effectiveAssessmentScore {
    final fullScore = assessment?.overallScore?.round();
    return fullScore ??
        quickAssessment?.score ??
        assessmentScore ??
        wellnessSnapshot?.assessmentScore;
  }

  bool get hasAssessment =>
      assessment != null ||
      quickAssessment != null ||
      assessmentScore != null ||
      wellnessSnapshot?.assessmentScore != null;

  bool get hasWellnessSignals => wellnessSnapshot != null;

  MindAidContext copyWith({
    List<String>? recentMessages,
    int? moodLevel,
    int? assessmentScore,
    MindAidQuickAssessmentContext? quickAssessment,
    MindAidAssessmentContext? assessment,
    String? conversationSummary,
    MindAidSupportStyle? preferredSupportStyle,
    String? journalText,
    MindAidWellnessSnapshot? wellnessSnapshot,
  }) {
    return MindAidContext(
      recentMessages: recentMessages ?? this.recentMessages,
      moodLevel: moodLevel ?? this.moodLevel,
      assessmentScore: assessmentScore ?? this.assessmentScore,
      quickAssessment: quickAssessment ?? this.quickAssessment,
      assessment: assessment ?? this.assessment,
      conversationSummary: conversationSummary ?? this.conversationSummary,
      preferredSupportStyle:
          preferredSupportStyle ?? this.preferredSupportStyle,
      journalText: journalText ?? this.journalText,
      wellnessSnapshot: wellnessSnapshot ?? this.wellnessSnapshot,
    );
  }
}

enum MindAidSupportStyle {
  calming,
  practical,
  reflective,
  motivational;

  String get label {
    switch (this) {
      case MindAidSupportStyle.calming:
        return 'calming';
      case MindAidSupportStyle.practical:
        return 'practical';
      case MindAidSupportStyle.reflective:
        return 'reflective';
      case MindAidSupportStyle.motivational:
        return 'motivational';
    }
  }
}
