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

      expect(find.text('Your Well-being Profile'), findsOneWidget);
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

      expect(find.text('Your Work Well-Being Profile'), findsOneWidget);
      expect(find.text('Verified workplace V4 result.'), findsOneWidget);
    },
  );
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
      'focusInsights': const [],
      'strengthInsights': const [],
      'suggestedActions': const [],
    },
  };
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
