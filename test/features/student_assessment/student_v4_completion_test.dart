import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/student_assessment/screens/student_assessment_complete_screen.dart';
import 'package:mind_mates/features/student_assessment/models/student_assessment_models.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';
import 'package:mind_mates/repositories/report_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'shows the PACC prompt only after a saved supportMayHelp V4 result',
    (tester) async {
      final assessment = AssessmentProvider(
        _V4Repository(profileStatus: 'supportMayHelp'),
      )..startStudentAssessment();
      await _completeV4Assessment(assessment);
      final user = UserProvider(_ActivityRepository())
        ..setUser(
          const UserModel(id: 'support_1', email: 'support@example.com'),
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
        find.text('Would you like to talk with a PACC counselor?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Your responses suggest that additional support may be helpful. Would you like to request a confidential counseling appointment with PACC?',
        ),
        findsOneWidget,
      );
      expect(find.text('No, Continue'), findsOneWidget);
      expect(find.text('Yes, Book Appointment'), findsOneWidget);
    },
  );

  testWidgets('does not prompt for lower V4 statuses in any population role', (
    tester,
  ) async {
    for (final role in [
      AssessmentRole.student,
      AssessmentRole.faculty,
      AssessmentRole.staff,
    ]) {
      for (final status in [
        'generallySupported',
        'mostlySupported',
        'someAreasNeedAttention',
        'insufficientResponses',
      ]) {
        final assessment =
            AssessmentProvider(_V4Repository(profileStatus: status))
              ..selectRole(role)
              ..startStudentAssessment();
        await _completeV4Assessment(assessment);
        final user = UserProvider(_ActivityRepository())
          ..setUser(const UserModel(id: 'lower_1', email: 'lower@example.com'));

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AssessmentProvider>.value(
                value: assessment,
              ),
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
          find.text('Would you like to talk with a PACC counselor?'),
          findsNothing,
        );
      }
    }
  });

  testWidgets(
    'declining a V4 prompt keeps the result visible without re-prompting on rebuild',
    (tester) async {
      final assessment = AssessmentProvider(
        _V4Repository(profileStatus: 'supportMayHelp'),
      )..startStudentAssessment();
      await _completeV4Assessment(assessment);
      final user = UserProvider(_ActivityRepository())
        ..setUser(
          const UserModel(id: 'decline_1', email: 'decline@example.com'),
        );

      Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider<AssessmentProvider>.value(value: assessment),
          ChangeNotifierProvider<UserProvider>.value(value: user),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FailingReportRepository()),
          ),
        ],
        child: const MaterialApp(home: StudentAssessmentCompleteScreen()),
      );

      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('No, Continue'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Your Full Well-Being Assessment Result'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('Would you like to talk with a PACC counselor?'),
        findsNothing,
      );
      expect(
        find.text('Your Full Well-Being Assessment Result'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'accepting a V4 prompt opens PACC without creating an appointment',
    (tester) async {
      final assessment = AssessmentProvider(
        _V4Repository(profileStatus: 'supportMayHelp'),
      )..startStudentAssessment();
      await _completeV4Assessment(assessment);
      final user = UserProvider(_ActivityRepository())
        ..setUser(const UserModel(id: 'accept_1', email: 'accept@example.com'));
      final appointments = _NoopAppointmentRepository();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AssessmentProvider>.value(value: assessment),
            ChangeNotifierProvider<UserProvider>.value(value: user),
            ChangeNotifierProvider<ReportProvider>(
              create: (_) => ReportProvider(_FailingReportRepository()),
            ),
            ChangeNotifierProvider(
              create: (_) => AppointmentProvider(appointments),
            ),
          ],
          child: const MaterialApp(home: StudentAssessmentCompleteScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Yes, Book Appointment'));
      await tester.pumpAndSettle();

      expect(find.text('Appointment Details'), findsOneWidget);
      expect(appointments.createCalls, 0);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Your Full Well-Being Assessment Result'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a failed V4 save does not prompt before its successful retry', (
    tester,
  ) async {
    final repository = _FailsThenSavesV4Repository();
    final assessment = AssessmentProvider(repository)..startStudentAssessment();
    await _completeV4Assessment(assessment);
    final user = UserProvider(_ActivityRepository())
      ..setUser(const UserModel(id: 'retry_1', email: 'retry@example.com'));

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
    expect(find.text('Try again'), findsOneWidget);
    expect(
      find.text('Would you like to talk with a PACC counselor?'),
      findsNothing,
    );

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repository.saveCalls, 2);
    expect(
      find.text('Would you like to talk with a PACC counselor?'),
      findsOneWidget,
    );
  });

  testWidgets(
    'keeps the verified V4 profile visible when report refresh fails',
    (tester) async {
      final assessment = AssessmentProvider(_V4Repository())
        ..startStudentAssessment();
      await _completeV4Assessment(assessment);
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
      await _expectTextVisible(tester, 'What to notice');
      await _expectTextVisible(tester, 'Supportive pattern');
      await _expectTextVisible(tester, 'A practical next step');
      await _expectTextVisible(tester, 'Reflection prompt');
      await _expectTextVisible(tester, 'Strengths');
      await _expectTextVisible(tester, 'Areas to Explore');
      await _expectTextVisible(tester, 'Suggested Next Steps');
      await _expectTextVisible(tester, 'Assessment Responses');
      final responseGroup = find.byKey(
        const ValueKey('v4-response-group-domain_0'),
      );
      await _scrollIntoView(tester, responseGroup);
      await tester.tap(responseGroup);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1. Saved review question 1.'), findsOneWidget);
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
    'renders each saved role result once, survives rebuild, and continues home',
    (tester) async {
      final expectedDomainLabels = {
        AssessmentRole.student: 'Academic Stress',
        AssessmentRole.faculty: 'Teaching Workload & Role Demands',
        AssessmentRole.staff: 'Workload & Role Demands',
      };

      for (final role in expectedDomainLabels.keys) {
        final repository = _CountingV4Repository();
        final assessment = AssessmentProvider(repository)
          ..selectRole(role)
          ..startStudentAssessment();
        await _completeV4Assessment(assessment);
        final user = UserProvider(_ActivityRepository())
          ..setUser(
            UserModel(
              id: 'render_${role.name}',
              email: 'render_${role.name}@example.com',
            ),
          );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AssessmentProvider>.value(
                value: assessment,
              ),
              ChangeNotifierProvider<UserProvider>.value(value: user),
              ChangeNotifierProvider<ReportProvider>(
                create: (_) => ReportProvider(_FailingReportRepository()),
              ),
            ],
            child: MaterialApp(
              key: ValueKey('completion_${role.name}'),
              home: const StudentAssessmentCompleteScreen(),
              routes: {
                RouteNames.home: (_) => const Scaffold(
                  body: Text('Home destination'),
                ),
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.text('Your Full Well-Being Assessment Result'),
          findsOneWidget,
        );
        await _expectTextVisible(tester, 'Overall Well-Being Status');
        await _expectTextVisible(tester, expectedDomainLabels[role]!);
        expect(repository.saveCalls, 1);

        // A provider notification rebuilds the completion screen, but its
        // cached save future must not submit the completed session again.
        assessment.updateName('rebuild_${role.name}');
        await tester.pump();
        expect(repository.saveCalls, 1);
        expect(assessment.studentAnswers, hasLength(50));

        await _expectTextVisible(tester, 'Continue');
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('Home destination'), findsOneWidget);
        expect(assessment.studentAnswers, hasLength(50));
      }
    },
  );

  testWidgets(
    'renders the workplace heading and user summary for Teaching V4',
    (tester) async {
      final assessment = AssessmentProvider(_V4Repository())
        ..selectRole(AssessmentRole.faculty)
        ..startStudentAssessment();
      await _completeV4Assessment(assessment);
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
    await _completeV4Assessment(assessment);
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
    await _completeV4Assessment(assessment);
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
    await _expectTextVisible(tester, 'Assessment Responses');
    await _expectTextVisible(
      tester,
      'Saved assessment responses are unavailable for this result.',
    );
  });

  testWidgets('renders safe fallbacks for malformed optional V4 fields', (
    tester,
  ) async {
    final assessment = AssessmentProvider(_MalformedV4Repository())
      ..startStudentAssessment();
    await _completeV4Assessment(assessment);
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

  testWidgets('expands V4 methodology and references on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final assessment = AssessmentProvider(_V4Repository())
      ..startStudentAssessment();
    await _completeV4Assessment(assessment);
    final user = UserProvider(_ActivityRepository())
      ..setUser(
        const UserModel(id: 'student_method', email: 'method@example.com'),
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

    await _expectTextVisible(tester, 'How This Result Was Created');
    await tester.tap(find.text('How This Result Was Created'));
    await tester.pump(const Duration(milliseconds: 300));
    await _expectTextVisible(
      tester,
      'The server calculated this result deterministically from your saved responses.',
    );
    await _expectTextVisible(
      tester,
      'Generative AI does not determine this Full Assessment result.',
    );
    await _expectTextVisible(
      tester,
      'Instrument version: student_wellbeing_v4',
    );
    await _expectTextVisible(tester, 'Algorithm version: student_profile_v4');
    await _expectTextVisible(tester, 'Record format: assessment_record_v4');
    await _expectTextVisible(
      tester,
      'Reference set: mindmate_wellbeing_refs_v1',
    );

    await _expectTextVisible(tester, 'References & Resources');
    await tester.tap(find.text('References & Resources'));
    await tester.pump(const Duration(milliseconds: 300));
    await _expectTextVisible(
      tester,
      'Hefferon, K., & Boniwell, I. (2011). Positive Psychology: Theory, Research and Applications. Open University Press.',
    );
    await _expectTextVisible(
      tester,
      'It is a conceptual and questionnaire-design reference, not validation of MindMate.',
    );
    expect(find.textContaining('catalogHash'), findsNothing);
    expect(find.textContaining('responseValue'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _expectTextVisible(WidgetTester tester, String value) async {
  final finder = find.text(value);
  await _scrollIntoView(tester, finder);
  expect(finder, findsOneWidget);
}

Future<void> _expectTextContainingVisible(
  WidgetTester tester,
  String value,
) async {
  final finder = find.textContaining(value);
  await _scrollIntoView(tester, finder);
  expect(finder, findsOneWidget);
}

Future<void> _scrollIntoView(WidgetTester tester, Finder finder) async {
  for (
    var attempt = 0;
    attempt < 30 && finder.evaluate().isEmpty;
    attempt += 1
  ) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _completeV4Assessment(AssessmentProvider assessment) async {
  for (var index = 0; index < 50; index += 1) {
    await assessment.answerCurrentStudentQuestion(LikertAnswer.often);
    if (assessment.flowStage == AssessmentFlowStage.domainReview ||
        assessment.flowStage == AssessmentFlowStage.recoverableError) {
      assessment.continueAfterDomainReview();
    }
  }
}

mixin _PreviewingV4Repository on AssessmentRepository {
  @override
  Future<Map<String, Object>> previewV4AssessmentDomain({
    required String instrumentVersion,
    required String domainId,
    required List<StudentAssessmentAnswer> answers,
  }) async => {
    'domainId': domainId,
    'domainLabel': domainId,
    'status': 'mostlySupported',
    'isScorable': true,
    'answeredCount': answers.length,
    'presentedCount': 10,
    'summary': 'Preview result.',
    'suggestedAction': 'Continue.',
    'reflectionPrompt': 'Reflect.',
    'interventionEligible': false,
    'policyVersion': 'assessment_intervention_v1',
  };
}

class _V4Repository extends AssessmentRepository with _PreviewingV4Repository {
  _V4Repository({this.profileStatus = 'mostlySupported'});

  final String profileStatus;

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
      'referenceSetVersion': 'mindmate_wellbeing_refs_v1',
      'algorithmVersion': instrumentVersion == 'student_wellbeing_v4'
          ? 'student_profile_v4'
          : instrumentVersion.startsWith('teaching_')
          ? 'teaching_profile_v4'
          : 'non_teaching_profile_v4',
    },
    'itemSnapshot': _itemSnapshot(),
    'responses': _savedResponses(),
    'result': {
      'profileStatus': profileStatus,
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

class _LegacyV4Repository extends AssessmentRepository
    with _PreviewingV4Repository {
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

class _FailsThenSavesV4Repository extends _V4Repository {
  _FailsThenSavesV4Repository() : super(profileStatus: 'supportMayHelp');

  int saveCalls = 0;

  @override
  Future<Map<String, Object>> saveV4FullAssessment({
    required String userId,
    required String instrumentVersion,
    required List<StudentAssessmentAnswer> answers,
    required String submissionId,
  }) async {
    saveCalls += 1;
    if (saveCalls == 1) throw StateError('save failed');
    return super.saveV4FullAssessment(
      userId: userId,
      instrumentVersion: instrumentVersion,
      answers: answers,
      submissionId: submissionId,
    );
  }
}

class _CountingV4Repository extends _V4Repository {
  int saveCalls = 0;

  @override
  Future<Map<String, Object>> saveV4FullAssessment({
    required String userId,
    required String instrumentVersion,
    required List<StudentAssessmentAnswer> answers,
    required String submissionId,
  }) async {
    saveCalls += 1;
    return super.saveV4FullAssessment(
      userId: userId,
      instrumentVersion: instrumentVersion,
      answers: answers,
      submissionId: submissionId,
    );
  }
}

class _MalformedV4Repository extends AssessmentRepository
    with _PreviewingV4Repository {
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
        'focusInsight': index == 0
            ? 'One reported pattern in this area may be worth noticing.'
            : null,
        'strengthInsight': index == 0
            ? 'One supportive pattern was identified in this area.'
            : null,
        'suggestedAction': index == 0
            ? 'Choose one manageable next step for this area this week.'
            : null,
        'reflectionPrompt': index == 0
            ? 'What would make this area feel more manageable this week?'
            : null,
      },
  ];
}

List<Map<String, Object>> _itemSnapshot() => [
  for (var index = 1; index <= 50; index += 1)
    {
      'itemId': 'item_$index',
      'domainId': 'domain_${(index - 1) ~/ 10}',
      'displayOrder': index,
      'text': 'Saved review question $index.',
    },
];

List<Map<String, Object>> _savedResponses() => [
  for (var index = 1; index <= 50; index += 1)
    {'itemId': 'item_$index', 'responseCode': 'agree', 'skipped': false},
];

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

class _NoopAppointmentRepository extends AppointmentRepository {
  int createCalls = 0;

  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async =>
      const [];

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      Stream.value(const []);

  @override
  Future<AppointmentModel> createAppointment(
    AppointmentModel appointment, {
    String? requestId,
  }) async {
    createCalls += 1;
    return appointment.copyWith(id: 'created_1');
  }
}
