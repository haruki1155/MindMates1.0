import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_assessment_detail_screen.dart';
import 'package:mind_mates/repositories/admin_status_repository.dart';

void main() {
  for (final version in const [
    'student_wellbeing_v4',
    'teaching_workplace_reflection_v4',
    'non_teaching_workplace_reflection_v4',
  ]) {
    testWidgets('simplifies $version V4 assessment details', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminAssessmentDetailScreen(
            userId: 'user-1',
            userLabel: 'Student',
            repository: _Repository(_v4Record(version)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_displayName(version)), findsNWidgets(2));
      expect(
        find.text('Well-being appears generally supported.'),
        findsNWidgets(2),
      );
      expect(find.text('Stored profile summary.'), findsOneWidget);
      expect(find.text('Follow-up guidance.'), findsOneWidget);
      expect(find.text('Response quality'), findsOneWidget);
      expect(find.text('Well-being areas'), findsOneWidget);
      expect(find.text('Current strengths'), findsOneWidget);
      expect(find.text('Areas to explore'), findsOneWidget);
      expect(find.text('Assessment information'), findsOneWidget);

      expect(find.text('What the responses suggest overall'), findsNothing);
      expect(find.text('Suggested next steps'), findsNothing);
      expect(find.text('Counselor discussion guide'), findsNothing);
      expect(find.text(version), findsNothing);
    });
  }
}

class _Repository extends AdminStatusRepository {
  _Repository(this.record);
  final Map<String, dynamic> record;

  @override
  Future<List<Map<String, dynamic>>> fetchUserAssessments(
    String userId,
  ) async => [record];
}

Map<String, dynamic> _v4Record(String version) => {
  'id': 'assessment-1',
  'schemaVersion': 'assessment_record_v4',
  'createdAt': '2026-09-29T00:00:00.000Z',
  'verificationStatus': 'Verified',
  'instrument': {'version': version, 'recallPeriodDays': 7},
  'result': {
    'profileStatus': 'generallySupported',
    'responseQuality': {'answered': 50, 'presented': 50, 'confidence': 'high'},
    'domainResults': [
      {
        'domainId': 'wellbeing',
        'status': 'generallySupported',
        'answeredCount': 10,
        'presentedCount': 10,
        'isScorable': true,
      },
    ],
  },
  'interpretation': {
    'userSummary': 'Stored profile summary.',
    'disclaimer': 'Follow-up guidance.',
    'overallResponseSummary': 'Removed overall response text.',
    'suggestedActions': ['Removed suggested action.'],
    'strengthInsights': ['Current strength.'],
    'focusInsights': ['Area to explore.'],
    'domainSummaries': [
      {
        'domainId': 'wellbeing',
        'domainLabel': 'Well-being',
        'focusInsight': 'A discussion guide source.',
      },
    ],
  },
};

String _displayName(String version) => switch (version) {
  'teaching_workplace_reflection_v4' =>
    'Teaching workplace well-being reflection',
  'non_teaching_workplace_reflection_v4' =>
    'Non-teaching workplace well-being reflection',
  _ => 'Student well-being reflection',
};
