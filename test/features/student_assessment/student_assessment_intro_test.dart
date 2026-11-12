import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/student_assessment/screens/student_assessment_screen.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('legacy intro omits V4-only claims', (tester) async {
    final assessment = AssessmentProvider(AssessmentRepository());
    if (assessment.isV4FullAssessment) return;
    await tester.pumpWidget(_app(assessment));
    await tester.pump();
    expect(find.textContaining('50-question'), findsNothing);
    expect(find.textContaining('secure server'), findsNothing);
    expect(find.textContaining('simple agreement scale'), findsOneWidget);
  });

  testWidgets(
    'fresh entry waits for acknowledgement before creating a session',
    (tester) async {
      final assessment = AssessmentProvider(AssessmentRepository());
      await tester.pumpWidget(_app(assessment));
      await tester.pump();
      expect(find.text('Before you start'), findsOneWidget);
      expect(assessment.hasStudentAssessmentStarted, isFalse);
      if (assessment.isV4FullAssessment) {
        expect(
          find.text(
            'This is a 50-question reflection across five well-being areas.',
          ),
          findsOneWidget,
        );
      }
      await tester.ensureVisible(find.text('I understand, start assessment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I understand, start assessment'));
      await tester.pump();
      expect(assessment.hasStudentAssessmentStarted, isTrue);
      expect(find.text('Before you start'), findsNothing);
    },
  );

  testWidgets('same-user session resumes without disclaimer or reset', (
    tester,
  ) async {
    final assessment = AssessmentProvider(AssessmentRepository());
    assessment.startStudentAssessment(userId: 'student-1');
    final originalSession = assessment.v4SubmissionId;
    await tester.pumpWidget(_app(assessment));
    await tester.pump();
    expect(find.text('Before you start'), findsNothing);
    expect(assessment.v4SubmissionId, originalSession);
  });

  testWidgets('Not now returns home when assessment is the only route', (
    tester,
  ) async {
    final assessment = AssessmentProvider(AssessmentRepository());
    await tester.pumpWidget(_app(assessment));
    await tester.pump();
    await tester.ensureVisible(find.text('Not now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Home destination'), findsOneWidget);
    expect(assessment.hasStudentAssessmentStarted, isFalse);
  });

  testWidgets('Not now pops to the previous route when one exists', (
    tester,
  ) async {
    final assessment = AssessmentProvider(AssessmentRepository());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AssessmentProvider>.value(value: assessment),
          ChangeNotifierProvider<AuthProvider>(create: (_) => _AuthProvider()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pushNamed(RouteNames.studentAssessment),
                child: const Text('Open assessment'),
              ),
            ),
          ),
          routes: {
            RouteNames.studentAssessment: (_) =>
                const StudentAssessmentScreen(),
          },
        ),
      ),
    );
    await tester.tap(find.text('Open assessment'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Not now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Open assessment'), findsOneWidget);
    expect(assessment.hasStudentAssessmentStarted, isFalse);
  });
}

Widget _app(AssessmentProvider assessment) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AssessmentProvider>.value(value: assessment),
    ChangeNotifierProvider<AuthProvider>(create: (_) => _AuthProvider()),
  ],
  child: MaterialApp(
    home: const StudentAssessmentScreen(),
    routes: {
      RouteNames.home: (_) => const Scaffold(body: Text('Home destination')),
    },
  ),
);

class _AuthProvider extends AuthProvider {
  _AuthProvider() : super(_AuthRepository());
}

class _AuthRepository extends AuthRepository {
  _AuthRepository() : super(AuthService());

  @override
  String? get currentUserId => 'student-1';
}
