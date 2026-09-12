import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/report_model.dart';

void main() {
  group('ReportModel', () {
    test('parses generated mental health summary fields', () {
      final report = ReportModel.fromJson({
        'id': 'report_1',
        'userId': 'user_1',
        'title': 'Mental Health Summary',
        'description': 'Latest assessment shows moderate concern.',
        'reportStatus': 'final',
        'generatedAt': '2026-07-03T10:00:00.000',
        'weekStart': '2026-06-29T00:00:00.000',
        'weekEnd': '2026-07-05T00:00:00.000',
        'moodCheckInCount': 5,
        'averageMoodLevel': 3.4,
        'latestMoodLevel': 4,
        'assessmentCount': 2,
        'quickAssessmentScore': 62,
        'quickAssessmentStatus': 'moderate',
        'quickAssessmentSignal': 'watchful',
        'quickAssessmentSummary': 'Exact quick summary.',
        'quickAssessmentAreaStatuses': {'Stress load': 'Moderate'},
        'fullAssessmentScore': 71,
        'fullAssessmentStatus': 'High Concern',
        'fullAssessmentSummary': 'Exact full summary.',
        'fullAssessmentDomainStatuses': {'Sleep and Rest': 'Elevated'},
        'fullAssessmentTopConcernAreas': ['Sleep and Rest', 'Academic Stress'],
        'mindAidMessageCount': 4,
        'activeDayCount': 3,
        'currentStreak': 5,
        'breathingSessionCount': 3,
        'mindfulBreathingMinutes': 12,
        'secretChatPostCount': 1,
        'secretChatCommentCount': 2,
        'secretChatInteractionCount': 3,
        'secretChatEngagementCount': 6,
        'totalEngagementCount': 23,
        'mentalStatus': 'severe',
        'mentalStatusLabel': 'Needs support',
        'latestAssessmentStatus': 'moderate',
        'latestAssessmentSource': 'quickAssessment',
        'mentalStatusSignal': 'watchful',
        'topConcernAreas': ['Sleep and Rest', 'Academic Stress'],
        'recommendedNextActions': ['Continue daily check-ins'],
        'hasEnoughData': true,
      });

      expect(report.moodCheckInCount, 5);
      expect(report.averageMoodLevel, 3.4);
      expect(report.averageMoodLabel, '3.4');
      expect(report.reportStatus, 'final');
      expect(report.isFinalReport, isTrue);
      expect(report.weekDateRangeLabel, 'Jun 29, 2026 - Jul 5, 2026');
      expect(report.latestMoodLevel, 4);
      expect(report.quickAssessmentScore, 62);
      expect(report.quickAssessmentStatus, 'moderate');
      expect(report.quickAssessmentSignal, 'watchful');
      expect(report.quickAssessmentSummary, 'Exact quick summary.');
      expect(report.quickAssessmentAreaStatuses, {'Stress load': 'Moderate'});
      expect(report.fullAssessmentScore, 71);
      expect(report.fullAssessmentStatus, 'High Concern');
      expect(report.fullAssessmentSummary, 'Exact full summary.');
      expect(report.fullAssessmentDomainStatuses, {
        'Sleep and Rest': 'Elevated',
      });
      expect(report.fullAssessmentTopConcernAreas, [
        'Sleep and Rest',
        'Academic Stress',
      ]);
      expect(report.mindAidMessageCount, 4);
      expect(report.activeDayCount, 3);
      expect(report.currentStreak, 5);
      expect(report.breathingSessionCount, 3);
      expect(report.mindfulBreathingMinutes, 12);
      expect(report.secretChatPostCount, 1);
      expect(report.secretChatCommentCount, 2);
      expect(report.secretChatInteractionCount, 3);
      expect(report.secretChatEngagementCount, 6);
      expect(report.totalEngagementCount, 23);
      expect(report.mentalStatus, 'severe');
      expect(report.mentalStatusLabel, 'Needs support');
      expect(report.latestAssessmentStatus, 'moderate');
      expect(report.latestAssessmentSource, 'quickAssessment');
      expect(report.mentalStatusSignal, 'watchful');
      expect(report.topConcernAreas, ['Sleep and Rest', 'Academic Stress']);
      expect(report.hasEnoughData, isTrue);
    });

    test('treats current-week reports as drafts when no status exists', () {
      final now = DateTime.now();
      final weekStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));

      final report = ReportModel.fromJson({
        'id': 'report_current',
        'generatedAt': now.toIso8601String(),
        'weekStart': weekStart.toIso8601String(),
        'weekEnd': weekEnd.toIso8601String(),
      });

      expect(report.reportStatus, 'draft');
      expect(report.isDraftReport, isTrue);
    });
  });
}
