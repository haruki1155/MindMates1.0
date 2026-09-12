import '../core/utils/firestore_mapper.dart';
import 'assessment_explanation_model.dart';

class ReportModel {
  const ReportModel({
    required this.id,
    required this.generatedAt,
    this.userId,
    this.title = 'Mental Health Summary',
    this.description = "This week's positive moods",
    this.reportStatus = 'final',
    this.weekStart,
    this.weekEnd,
    this.moodCheckInCount = 0,
    this.averageMoodLevel,
    this.latestMoodLevel,
    this.positiveMoodCount = 0,
    this.assessmentCount = 0,
    this.quickAssessmentScore,
    this.quickAssessmentStatus,
    this.quickAssessmentSignal,
    this.quickAssessmentSummary,
    this.quickAssessmentAreaStatuses = const {},
    this.quickAssessmentExplanation,
    this.fullAssessmentScore,
    this.fullAssessmentStatus,
    this.fullAssessmentSummary,
    this.fullAssessmentDomainStatuses = const {},
    this.fullAssessmentTopConcernAreas = const [],
    this.fullAssessmentExplanation,
    this.mindAidMessageCount = 0,
    this.activeDayCount = 0,
    this.currentStreak = 0,
    this.breathingSessionCount = 0,
    this.mindfulBreathingMinutes = 0,
    this.secretChatPostCount = 0,
    this.secretChatCommentCount = 0,
    this.secretChatInteractionCount = 0,
    this.secretChatEngagementCount = 0,
    this.totalEngagementCount = 0,
    this.mentalStatus = 'normal',
    this.mentalStatusLabel = 'Normal',
    this.latestAssessmentStatus,
    this.latestAssessmentSource,
    this.mentalStatusSignal,
    this.topConcernAreas = const [],
    this.recommendedNextActions = const [],
    this.hasEnoughData = false,
  });

  final String id;
  final DateTime generatedAt;
  final String? userId;
  final String title;
  final String description;
  final String reportStatus;
  final DateTime? weekStart;
  final DateTime? weekEnd;
  final int moodCheckInCount;
  final double? averageMoodLevel;
  final int? latestMoodLevel;
  final int positiveMoodCount;
  final int assessmentCount;
  final int? quickAssessmentScore;
  final String? quickAssessmentStatus;
  final String? quickAssessmentSignal;
  final String? quickAssessmentSummary;
  final Map<String, String> quickAssessmentAreaStatuses;
  final AssessmentExplanationModel? quickAssessmentExplanation;
  final int? fullAssessmentScore;
  final String? fullAssessmentStatus;
  final String? fullAssessmentSummary;
  final Map<String, String> fullAssessmentDomainStatuses;
  final List<String> fullAssessmentTopConcernAreas;
  final AssessmentExplanationModel? fullAssessmentExplanation;
  final int mindAidMessageCount;
  final int activeDayCount;
  final int currentStreak;
  final int breathingSessionCount;
  final int mindfulBreathingMinutes;
  final int secretChatPostCount;
  final int secretChatCommentCount;
  final int secretChatInteractionCount;
  final int secretChatEngagementCount;
  final int totalEngagementCount;
  final String mentalStatus;
  final String mentalStatusLabel;
  final String? latestAssessmentStatus;
  final String? latestAssessmentSource;
  final String? mentalStatusSignal;
  final List<String> topConcernAreas;
  final List<String> recommendedNextActions;
  final bool hasEnoughData;

  factory ReportModel.fromJson(Map<String, dynamic> json, {String? id}) {
    final weekEnd = dateTimeFromFirestore(json['weekEnd']);
    return ReportModel(
      id: (json['id'] ?? id ?? '').toString(),
      userId: json['userId']?.toString(),
      title: (json['title'] ?? 'Mental Health Summary').toString(),
      description: (json['description'] ?? "This week's positive moods")
          .toString(),
      reportStatus: _statusFromJson(json['reportStatus'], weekEnd: weekEnd),
      generatedAt: dateTimeFromFirestoreOrNow(json['generatedAt']),
      weekStart: dateTimeFromFirestore(json['weekStart']),
      weekEnd: weekEnd,
      moodCheckInCount: intFromFirestore(json['moodCheckInCount']),
      averageMoodLevel: _doubleOrNull(json['averageMoodLevel']),
      latestMoodLevel: _intOrNull(json['latestMoodLevel']),
      positiveMoodCount: intFromFirestore(json['positiveMoodCount']),
      assessmentCount: intFromFirestore(json['assessmentCount']),
      quickAssessmentScore: _intOrNull(json['quickAssessmentScore']),
      quickAssessmentStatus: _stringOrNull(json['quickAssessmentStatus']),
      quickAssessmentSignal: _stringOrNull(json['quickAssessmentSignal']),
      quickAssessmentSummary: _stringOrNull(json['quickAssessmentSummary']),
      quickAssessmentAreaStatuses: _stringMap(
        json['quickAssessmentAreaStatuses'],
      ),
      quickAssessmentExplanation: _explanation(
        json['quickAssessmentExplanation'],
      ),
      fullAssessmentScore: _intOrNull(json['fullAssessmentScore']),
      fullAssessmentStatus: _stringOrNull(json['fullAssessmentStatus']),
      fullAssessmentSummary: _stringOrNull(json['fullAssessmentSummary']),
      fullAssessmentDomainStatuses: _stringMap(
        json['fullAssessmentDomainStatuses'],
      ),
      fullAssessmentTopConcernAreas:
          (json['fullAssessmentTopConcernAreas'] as List<dynamic>? ?? const [])
              .map((area) => area.toString())
              .toList(growable: false),
      fullAssessmentExplanation: _explanation(
        json['fullAssessmentExplanation'],
      ),
      mindAidMessageCount: intFromFirestore(json['mindAidMessageCount']),
      activeDayCount: intFromFirestore(json['activeDayCount']),
      currentStreak: intFromFirestore(json['currentStreak']),
      breathingSessionCount: intFromFirestore(json['breathingSessionCount']),
      mindfulBreathingMinutes: intFromFirestore(
        json['mindfulBreathingMinutes'],
      ),
      secretChatPostCount: intFromFirestore(json['secretChatPostCount']),
      secretChatCommentCount: intFromFirestore(json['secretChatCommentCount']),
      secretChatInteractionCount: intFromFirestore(
        json['secretChatInteractionCount'],
      ),
      secretChatEngagementCount: intFromFirestore(
        json['secretChatEngagementCount'],
      ),
      totalEngagementCount: intFromFirestore(json['totalEngagementCount']),
      mentalStatus: (json['mentalStatus'] ?? 'normal').toString(),
      mentalStatusLabel: (json['mentalStatusLabel'] ?? 'Normal').toString(),
      latestAssessmentStatus: _stringOrNull(json['latestAssessmentStatus']),
      latestAssessmentSource: _stringOrNull(json['latestAssessmentSource']),
      mentalStatusSignal: _stringOrNull(json['mentalStatusSignal']),
      topConcernAreas: (json['topConcernAreas'] as List<dynamic>? ?? const [])
          .map((area) => area.toString())
          .toList(growable: false),
      recommendedNextActions:
          (json['recommendedNextActions'] as List<dynamic>? ?? const [])
              .map((action) => action.toString())
              .toList(growable: false),
      hasEnoughData: boolFromFirestore(json['hasEnoughData']),
    );
  }

  Map<String, dynamic> toJson({String? userId}) {
    return {
      'userId': userId ?? this.userId,
      'title': title,
      'description': description,
      'reportStatus': reportStatus,
      'generatedAt': generatedAt,
      'weekStart': weekStart,
      'weekEnd': weekEnd,
      'moodCheckInCount': moodCheckInCount,
      'averageMoodLevel': averageMoodLevel,
      'latestMoodLevel': latestMoodLevel,
      'positiveMoodCount': positiveMoodCount,
      'assessmentCount': assessmentCount,
      'quickAssessmentScore': quickAssessmentScore,
      'quickAssessmentStatus': quickAssessmentStatus,
      'quickAssessmentSignal': quickAssessmentSignal,
      'quickAssessmentSummary': quickAssessmentSummary,
      'quickAssessmentAreaStatuses': quickAssessmentAreaStatuses,
      'quickAssessmentExplanation': quickAssessmentExplanation?.toJson(),
      'fullAssessmentScore': fullAssessmentScore,
      'fullAssessmentStatus': fullAssessmentStatus,
      'fullAssessmentSummary': fullAssessmentSummary,
      'fullAssessmentDomainStatuses': fullAssessmentDomainStatuses,
      'fullAssessmentTopConcernAreas': fullAssessmentTopConcernAreas,
      'fullAssessmentExplanation': fullAssessmentExplanation?.toJson(),
      'mindAidMessageCount': mindAidMessageCount,
      'activeDayCount': activeDayCount,
      'currentStreak': currentStreak,
      'breathingSessionCount': breathingSessionCount,
      'mindfulBreathingMinutes': mindfulBreathingMinutes,
      'secretChatPostCount': secretChatPostCount,
      'secretChatCommentCount': secretChatCommentCount,
      'secretChatInteractionCount': secretChatInteractionCount,
      'secretChatEngagementCount': secretChatEngagementCount,
      'totalEngagementCount': totalEngagementCount,
      'mentalStatus': mentalStatus,
      'mentalStatusLabel': mentalStatusLabel,
      'latestAssessmentStatus': latestAssessmentStatus,
      'latestAssessmentSource': latestAssessmentSource,
      'mentalStatusSignal': mentalStatusSignal,
      'topConcernAreas': topConcernAreas,
      'recommendedNextActions': recommendedNextActions,
      'hasEnoughData': hasEnoughData,
    };
  }

  String get averageMoodLabel {
    final average = averageMoodLevel;
    if (average == null) return '-';
    return average.toStringAsFixed(1);
  }

  bool get isFinalReport {
    if (reportStatus == 'final') return true;
    final end = weekEnd;
    if (end == null) return false;
    final today = DateTime.now();
    final currentDay = DateTime(today.year, today.month, today.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return currentDay.isAfter(endDay);
  }

  bool get isDraftReport => !isFinalReport;

  String get weekDateRangeLabel {
    final start = weekStart;
    final end = weekEnd;
    if (start == null || end == null) return '';
    return '${_shortDate(start)} - ${_shortDate(end)}';
  }

  static String _shortDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  static String _statusFromJson(Object? value, {DateTime? weekEnd}) {
    final status = value?.toString().trim().toLowerCase();
    if (status == 'draft' || status == 'final') return status!;
    if (weekEnd == null) return 'final';
    final today = DateTime.now();
    final currentDay = DateTime(today.year, today.month, today.day);
    final endDay = DateTime(weekEnd.year, weekEnd.month, weekEnd.day);
    return currentDay.isAfter(endDay) ? 'final' : 'draft';
  }

  static String? _stringOrNull(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _intOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  static double? _doubleOrNull(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.key.toString().trim().isNotEmpty &&
            entry.value.toString().trim().isNotEmpty)
          entry.key.toString(): entry.value.toString(),
    };
  }

  static AssessmentExplanationModel? _explanation(Object? value) {
    if (value is! Map) return null;
    return AssessmentExplanationModel.fromJson(
      Map<String, dynamic>.from(value),
    );
  }
}
