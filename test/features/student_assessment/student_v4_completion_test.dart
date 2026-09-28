import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/student_assessment/screens/student_assessment_complete_screen.dart';
import 'package:mind_mates/features/student_assessment/models/student_assessment_models.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/report_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'keeps the verified V4 profile visible when report refresh fails',
    (tester) async {
      final assessment = AssessmentProvider(_V4Repository())
        ..startStudentAssessment();
      for (var index = 0; index < 50; index += 1) {
        assessment.answerCurrentStudentQuestion(LikertAnswer.often);
      }
      final user = UserProvider(_ActivityRepository())
        ..setUser(
          const UserModel(id: 'student_1', email: 'student@example.com'),
        );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AssessmentProvider>.value(value: assessment),
            ChangeNotifierProvider<UserProvider>.value(value: user),
            ChangeNotifierProvider<ReportProvider>(
              create: (_) => ReportProvider(_FailingReportRepository()),
            ),
          ],
          child: const MaterialApp(home: StudentAssessmentCompleteScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text('Your Full Well-Being Assessment Result'),
        findsOneWidget,
      );
      await _expectTextVisible(tester, 'Overall Well-Being Status');
      await _expectTextVisible(tester, 'Assessment Summary');
      await _expectTextVisible(tester, 'What Your Responses Suggest Overall');
      await _expectTextVisible(tester, 'Well-Being Areas');
      await _expectTextVisible(tester, 'Strengths');
      await _expectTextVisible(tester, 'Areas to Explore');
      await _expectTextVisible(tester, 'Suggested Next Steps');
      await _expectTextVisible(tester, 'Response Completeness');
      await _expectTextVisible(tester, 'About This Result');
      expect(
        find.textContaining('couldn\'t save your assessment'),
        findsNothing,
      );
      expect(find.textContaining('50 of 50 answered'), findsOneWidget);
    },
  );

  testWidgets(
    'renders the workplace heading and user summary for Teaching V4',
    (tester) async {
      final assessment = AssessmentProvider(_V4Repository())
        ..selectRole(AssessmentRole.faculty)
        ..startStudentAssessment();
      for (var index = 0; index < 50; index += 1) {
        assessment.answerCurrentStudentQuestion(LikertAnswer.often);
      }
      final user = UserProvider(_ActivityRepository())
        ..setUser(
          const UserModel(id: 'teaching_1', email: 'teaching@example.com'),
        );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AssessmentProvider>.value(value: assessment),
            ChangeNotifierProvider<UserProvider>.value(value: user),
            ChangeNotifierProvider<ReportProvider>(
              create: (_) => ReportProvider(_FailingReportRepository()),
            ),
          ],
          child: const MaterialApp(home: StudentAssessmentCompleteScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text('Your Full Well-Being Assessment Result'),
        findsOneWidget,
      );
      expect(find.text('Verified workplace V4 result.'), findsOneWidget);
      await _expectTextVisible(tester, 'Teaching Workload & Role Demands');
    },
  );

  testWidgets('renders the Non-Teaching V4 result and employee limitation', (
    tester,
  ) async {
    final assessment = AssessmentProvider(_V4Repository())
      ..selectRole(AssessmentRole.staff)
      ..startStudentAssessment();
    for (var index = 0; index < 50; index += 1) {
      assessment.answerCurrentStudentQuestion(LikertAnswer.often);
    }
    final user = UserProvider(_ActivityRepository())
      ..setUser(
        const UserModel(
          id: 'non_teaching_1',
          email: 'non-teaching@example.com',
        ),
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AssessmentProvider>.value(value: assessment),
          ChangeNotifierProvider<UserProvider>.value(value: user),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FailingReportRepository()),
          ),
        ],
        child: const MaterialApp(home: StudentAssessmentCompleteScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await _expectTextVisible(
      tester,
      'Supervisor, Team & Organizational Support',
    );
    await _expectTextContainingVisible(
      tester,
      'not a measure of job performance or fitness for work',
    );
  });

  testWidgets('uses studentSummary and safe fallbacks for legacy V4 payloads', (
    tester,
  ) async {
    final assessment = AssessmentProvider(_LegacyV4Repository())
      ..startStudentAssessment();
    for (var index = 0; index < 50; index += 1) {
      assessment.answerCurrentStudentQuestion(LikertAnswer.often);
    }
    final user = UserProvider(_ActivityRepository())
      ..setUser(
        const UserModel(id: 'student_legacy', email: 'legacy@example.com'),
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AssessmentProvider>.value(value: assessment),
          ChangeNotifierProvider<UserProvider>.value(value: user),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FailingReportRepository()),
          ),
        ],
        child: const MaterialApp(home: StudentAssessmentCompleteScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Legacy student V4 result.'), findsOneWidget);
    await _expectTextVisible(tester, 'Response Completeness');
    await _expectTextVisible(
      tester,
      'More responses are needed for a complete result.',
    );
  });

  testWidgets('renders safe fallbacks for malformed optional V4 fields', (
    tester,
  ) async {
    final assessment = AssessmentProvider(_MalformedV4Repository())
      ..startStudentAssessment();
    for (var index = 0; index < 50; index += 1) {
      assessment.answerCurrentStudentQuestion(LikertAnswer.often);
    }
    final user = UserProvider(_ActivityRepository())
      ..setUser(
        const UserModel(id: 'student_malformed', email: 'bad@example.com'),
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AssessmentProvider>.value(value: assessment),
          ChangeNotifierProvider<UserProvider>.value(value: user),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FailingReportRepository()),
          ),
        ],
        child: const MaterialApp(home: StudentAssessmentCompleteScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text(
        'This is a snapshot of the past 7 days based on the areas you answered.',
      ),
      findsOneWidget,
    );
    await _expectTextVisible(
      tester,
      'Response completeness details are unavailable for this saved result.',
    );
    await _expectTextVisible(tester, 'Well-being area');
  });
}

Future<void> _expectTextVisible(WidgetTester tester, String value) async {
  final finder = find.text(value);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  expect(finder, findsOneWidget);
}

Future<void> _expectTextContainingVisible(
  WidgetTester tester,
  String value,
) async {
  final finder = find.textContaining(value);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  expect(finder, findsOneWidget);
}

class _V4Repository extends AssessmentRepository {
  @override
  Future<Map<String, Object>> saveV4FullAssessment({
    required String userId,
    required String instrumentVersion,
    required List<StudentAssessmentAnswer> answers,
    required String submissionId,
  }) async => {
    'schemaVersion': 'assessment_record_v4',
    'populationRole': instrumentVersion.startsWith('teaching_')
        ? 'teaching'
        : instrumentVersion.startsWith('non_teaching_')
        ? 'nonTeaching'
        : 'student',
    'questionSetVersion': instrumentVersion,
    'algorithmVersion': instrumentVersion == 'student_wellbeing_v4'
        ? 'student_profile_v4'
        : instrumentVersion.startsWith('teaching_')
        ? 'teaching_profile_v4'
        : 'non_teaching_profile_v4',
    'createdAt': '2026-09-28T00:00:00.000Z',
    'instrument': {
      'version': instrumentVersion,
      'recallPeriodDays': 7,
      'responseScaleId': 'agreement_4_no_neutral_v1',
      'algorithmVersion': instrumentVersion == 'student_wellbeing_v4'
          ? 'student_profile_v4'
          : instrumentVersion.startsWith('teaching_')
          ? 'teaching_profile_v4'
          : 'non_teaching_profile_v4',
    },
    'result': {
      'profileStatus': 'mostlySupported',
      'responseQuality': {
        'answered': 50,
        'presented': 50,
        'confidence': 'high',
      },
      'domainResults': const [],
    },
    'interpretation': {
      if (instrumentVersion == 'student_wellbeing_v4')
        'studentSummary': 'Verified V4 result.'
      else
        'userSummary': 'Verified workplace V4 result.',
      'overallResponseSummary':
          'Five well-being areas were considered using your completed responses.',
      'domainSummaries': _domainSummariesFor(instrumentVersion),
      'focusInsights': const ['One area may benefit from attention.'],
      'strengthInsights': const ['One supportive pattern was identified.'],
      'suggestedActions': const ['Choose one small next step this week.'],
      'disclaimer': 'This is a non-clinical well-being reflection.',
    },
  };
}

class _LegacyV4Repository extends AssessmentRepository {
  @override
  Future<Map<String, Object>> saveV4FullAssessment({
    required String userId,
    required String instrumentVersion,
    required List<StudentAssessmentAnswer> answers,
    required String submissionId,
  }) async => {
    'schemaVersion': 'assessment_record_v4',
    'populationRole': 'student',
    'result': {
      'profileStatus': 'insufficientResponses',
      'responseQuality': const {},
      'domainResults': const [],
    },
    'interpretation': {'studentSummary': 'Legacy student V4 result.'},
  };
}

class _MalformedV4Repository extends AssessmentRepository {
  @override
  Future<Map<String, Object>> saveV4FullAssessment({
    required String userId,
    required String instrumentVersion,
    required List<StudentAssessmentAnswer> answers,
    required String submissionId,
  }) async => {
    'schemaVersion': 'assessment_record_v4',
    'populationRole': 'student',
    'result': {
      'profileStatus': 'generallySupported',
      'responseQuality': {'answered': 'invalid', 'presented': false},
    },
    'interpretation': {
      'userSummary': '',
      'overallResponseSummary': const ['invalid'],
      'domainSummaries': [
        {'domainLabel': '', 'status': 1, 'summary': ''},
      ],
      'focusInsights': const {'invalid': true},
      'strengthInsights': const {'invalid': true},
      'suggestedActions': const {'invalid': true},
      'disclaimer': false,
    },
  };
}

List<Map<String, Object?>> _domainSummariesFor(String instrumentVersion) {
  final labels = instrumentVersion.startsWith('teaching_')
      ? const [
          'Teaching Workload & Role Demands',
          'Collegial & Organizational Support',
          'Professional Engagement & Meaning',
          'Sleep & Rest',
          'Emotional Well-Being',
        ]
      : instrumentVersion.startsWith('non_teaching_')
      ? const [
          'Workload & Role Demands',
          'Supervisor, Team & Organizational Support',
          'Work Engagement & Meaning',
          'Sleep & Rest',
          'Emotional Well-Being',
        ]
      : const [
          'Academic Stress',
          'Financial',
          'Social Adjustment',
          'Sleep & Rest',
          'Emotional Well-Being',
        ];
  return [
    for (var index = 0; index < labels.length; index += 1)
      {
        'domainId': 'domain_$index',
        'domainLabel': labels[index],
        'status': 'mostlySupported',
        'summary': '${labels[index]} was mostly supportive.',
        'focusInsight': null,
        'strengthInsight': null,
        'suggestedAction': null,
      },
  ];
}

class _ActivityRepository extends UserRepository {
  @override
  Future<UserModel?> recordActivity(
    String uid,
    UserActivityType type, {
    DateTime? occurredAt,
  }) async => const UserModel(id: 'student_1', email: 'student@example.com');
}

class _FailingReportRepository extends ReportRepository {
  @override
  Future<String> generateWeeklyReport(String userId, {DateTime? now}) async {
    throw StateError('report refresh unavailable');
  }
}
