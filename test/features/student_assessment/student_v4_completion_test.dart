import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/screens/pacc_counseling_screen.dart';
import 'package:mind_mates/features/student_assessment/models/intervention_models.dart';
import 'package:mind_mates/features/student_assessment/screens/assessment_domain_review_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_breathing_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_feedback_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_grounding_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/intervention_walking_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/student_assessment_complete_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/student_assessment_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/student_v4_category_intervention_screen.dart';
import 'package:mind_mates/features/student_assessment/widgets/assessment_domain_illustration.dart';
import 'package:mind_mates/features/student_assessment/widgets/assessment_presentation.dart';
import 'package:mind_mates/features/student_assessment/models/student_assessment_models.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/repositories/report_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

void main() {
  test('domain art maps all supported areas and status colors', () {
    const icons = <String, IconData>{
      'academic': Icons.menu_book_rounded,
      'financial': Icons.savings_rounded,
      'socialAdjustment': Icons.groups_rounded,
      'sleepRest': Icons.bedtime_rounded,
      'emotionalWellbeing': Icons.favorite_rounded,
      'teachingWorkloadDemands': Icons.work_outline_rounded,
      'nonTeachingWorkloadDemands': Icons.work_outline_rounded,
      'teachingSupport': Icons.diversity_3_rounded,
      'nonTeachingSupport': Icons.diversity_3_rounded,
      'teachingEngagementMeaning': Icons.emoji_objects_rounded,
      'nonTeachingEngagementMeaning': Icons.emoji_objects_rounded,
    };
    for (final entry in icons.entries) {
      expect(assessmentDomainIcon(entry.key), entry.value);
    }
    expect(assessmentDomainIcon('unrecognized'), Icons.insights_rounded);
    expect(assessmentStatusColor('supported'), const Color(0xFF2F7D6D));
    expect(assessmentStatusColor('mostlySupported'), const Color(0xFF5E95BC));
    expect(assessmentStatusColor('someStrain'), const Color(0xFFE09B2D));
    expect(assessmentStatusColor('supportMayHelp'), const Color(0xFFC0603A));
    expect(assessmentStatusColor('unknown'), const Color(0xFF6C665B));
  });

  testWidgets('domain art is sized and decorative', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssessmentDomainIllustration(
            domainId: 'academic',
            status: 'supported',
          ),
        ),
      ),
    );
    final art = find.byType(AssessmentDomainIllustration);
    expect(tester.getSize(art), const Size(52, 52));
    final icon = tester.widget<Icon>(find.byIcon(Icons.menu_book_rounded));
    expect(icon.size, 26);
    expect(icon.color, const Color(0xFF2F7D6D));
    expect(
      find.ancestor(
        of: find.byIcon(Icons.menu_book_rounded),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });
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

      expect(find.text('PACC support is available'), findsOneWidget);
      expect(
        find.text(
          'Your saved result suggests that speaking with a counselor may be helpful. You can continue to PACC whenever you feel ready.',
        ),
        findsOneWidget,
      );
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Continue to PACC'), findsOneWidget);
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

        expect(find.text('PACC support is available'), findsNothing);
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
      await tester.tap(find.text('Not now'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Your Full Well-Being Assessment Result'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('PACC support is available'), findsNothing);
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
      await tester.tap(find.text('Continue to PACC'));
      await tester.pumpAndSettle();

      expect(find.byType(PaccCounselingScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('intake')), findsOneWidget);
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
    expect(find.text('PACC support is available'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repository.saveCalls, 2);
    expect(find.text('PACC support is available'), findsOneWidget);
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
      expect(find.textContaining('response completeness'), findsNothing);
      await _expectTextVisible(tester, 'Strengths & Focus Areas');
      await _expectTextVisible(tester, 'Strengths');
      await _expectTextVisible(tester, 'Focus Areas');
      await _expectTextVisible(tester, 'Well-Being Areas');
      expect(find.text('Mostly supported'), findsNWidgets(5));
      expect(find.text('What to notice'), findsNothing);
      final domainCard = find.byKey(const ValueKey('v4-domain-domain_0'));
      await _scrollIntoView(tester, domainCard);
      expect(
        find.descendant(
          of: domainCard,
          matching: find.byIcon(Icons.insights_rounded),
        ),
        findsOneWidget,
      );
      await tester.tap(domainCard);
      await tester.pump(const Duration(milliseconds: 300));
      await _expectTextVisible(tester, 'What to notice');
      await _expectTextVisible(tester, 'Supportive pattern');
      await _expectTextVisible(tester, 'A practical next step');
      await _expectTextVisible(tester, 'Reflection prompt');
      await _expectTextVisible(tester, 'Suggested Next Steps');
      expect(find.text('Assessment Responses'), findsNothing);
      await _expectTextVisible(tester, 'Review Responses');
      await tester.tap(find.text('Review Responses'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Your responses'), findsOneWidget);
      final responseGroup = find.byKey(
        const ValueKey('v4-response-group-domain_0'),
      );
      await _scrollIntoView(tester, responseGroup);
      await tester.tap(responseGroup);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1. Saved review question 1.'), findsOneWidget);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Review Responses'), findsOneWidget);
      expect(find.text('Response Completeness'), findsNothing);
      expect(find.text('How This Result Was Created'), findsNothing);
      await _expectTextVisible(tester, 'About This Result');
      expect(
        find.textContaining('couldn\'t save your assessment'),
        findsNothing,
      );
      expect(find.textContaining('50 of 50 answered'), findsNothing);
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
                RouteNames.home: (_) =>
                    const Scaffold(body: Text('Home destination')),
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
    expect(find.text('Response Completeness'), findsNothing);
    await _expectTextVisible(tester, 'Review Responses');
    await tester.tap(find.text('Review Responses'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
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
    expect(find.text('Response Completeness'), findsNothing);
    await _expectTextVisible(tester, 'Well-being area');
  });

  testWidgets('keeps V4 areas and responses collapsed on a narrow phone', (
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

    final domainCard = find.byKey(const ValueKey('v4-domain-domain_0'));
    await _scrollIntoView(tester, domainCard);
    expect(find.text('What to notice'), findsNothing);
    await tester.tap(domainCard);
    await tester.pump(const Duration(milliseconds: 300));
    await _expectTextVisible(tester, 'A practical next step');

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

  testWidgets(
    'AssessmentDomainReviewScreen renders matched Student V4 titles/descriptions when eligible, hides them when ineligible, and refreshes after retry',
    (tester) async {
      const cases = [
        (
          InterventionType.academicPlanning,
          'Academic',
          'Start with five minutes',
        ),
        (
          InterventionType.financialPlanning,
          'Financial',
          'Choose one practical next step',
        ),
        (
          InterventionType.walking,
          'Social Adjustment',
          'Take a short walk',
        ),
        (
          InterventionType.breathing,
          'Sleep & Rest',
          'Try a breathing wind-down',
        ),
        (
          InterventionType.grounding,
          'Emotional Well-Being',
          'Ground and notice',
        ),
      ];

      for (final (type, label, title) in cases) {
        await tester.pumpWidget(
          MaterialApp(
            home: AssessmentDomainReviewScreen(
              key: ValueKey(type),
              isStudentV4: true,
              preview: {
                'domainLabel': label,
                'status': 'supportMayHelp',
                'interventionEligible': true,
              },
              intervention: type,
              onTryActivity: () {},
              onContinue: () {},
              onRetry: () async {},
              onBack: () {},
            ),
          ),
        );

        expect(find.byType(AssessmentStatusPill), findsOneWidget);
        expect(find.text('Optional activity · 1–3 min'), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        expect(find.text('Try Activity'), findsOneWidget);
        expect(find.text('Not now, continue assessment'), findsOneWidget);
      }

      // Ineligible hides the activity card and Try Activity button.
      await tester.pumpWidget(
        MaterialApp(
          home: AssessmentDomainReviewScreen(
            key: const ValueKey('ineligible'),
            isStudentV4: true,
            preview: const {
              'domainLabel': 'Academic',
              'status': 'mostlySupported',
              'interventionEligible': false,
            },
            onTryActivity: () {},
            onContinue: () {},
            onRetry: () async {},
            onBack: () {},
          ),
        ),
      );
      expect(find.text('Optional activity · 1–3 min'), findsNothing);
      expect(find.text('Try Activity'), findsNothing);

      // Failed preview retry refreshes preview, clears stale error, and shows matched card.
      Map<String, Object>? retriedPreview;
      Object? retriedError = StateError('temporary');
      InterventionType? retriedIntervention;
      await tester.pumpWidget(
        MaterialApp(
          home: AssessmentDomainReviewScreen(
            key: const ValueKey('retry'),
            isStudentV4: true,
            preview: null,
            error: retriedError,
            onRetry: () async {
              retriedPreview = {
                'domainLabel': 'Financial',
                'status': 'supportMayHelp',
                'interventionEligible': true,
              };
              retriedError = null;
              retriedIntervention = InterventionType.financialPlanning;
            },
            previewAfterRetry: () => retriedPreview,
            errorAfterRetry: () => retriedError,
            interventionAfterRetry: () => retriedIntervention,
            onTryActivity: () {},
            onContinue: () {},
            onBack: () {},
          ),
        ),
      );

      expect(find.text('Retry Preview'), findsOneWidget);
      await tester.tap(find.text('Retry Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Financial'), findsOneWidget);
      expect(find.text('Choose one practical next step'), findsOneWidget);
      expect(find.text('Try Activity'), findsOneWidget);
    },
  );

  testWidgets(
    'StudentAssessmentScreen routes all five eligible Student V4 categories, supports skip/back/skip-feedback, and advances to submission',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final assessment = AssessmentProvider(_AllEligiblePreviewRepository())
        ..bindAuthenticatedUser('student-v4');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AssessmentProvider>.value(value: assessment),
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => _TestAuthProvider('student-v4'),
            ),
          ],
          child: MaterialApp(
            home: const StudentAssessmentScreen(),
            routes: {
              RouteNames.studentAssessmentComplete: (_) =>
                  const Scaffold(body: Text('Completion destination')),
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('I understand, start assessment'));
      await tester.pumpAndSettle();

      Future<void> answerToDomainEnd() async {
        for (var i = 0; i < 9; i += 1) {
          await assessment.answerCurrentStudentQuestion(LikertAnswer.often);
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text(LikertAnswer.often.label));
        await tester.pumpAndSettle();
      }

      // 1. Academic -> Start with five minutes -> back/cancel returns to review -> Finish -> Skip feedback
      await answerToDomainEnd();
      expect(find.text('Start with five minutes'), findsOneWidget);
      await tester.tap(find.text('Try Activity'));
      await tester.pumpAndSettle();
      expect(find.byType(StudentV4CategoryInterventionScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Try Activity'), findsOneWidget);

      await tester.tap(find.text('Try Activity'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Finish activity'));
      await tester.tap(find.text('Finish activity'));
      await tester.pumpAndSettle();
      expect(find.byType(InterventionFeedbackScreen), findsOneWidget);
      await tester.ensureVisible(find.text('Skip feedback'));
      await tester.tap(find.text('Skip feedback'));
      await tester.pumpAndSettle();
      expect(assessment.interventionFeedback, isEmpty);
      expect(assessment.studentQuestionIndex, 10);

      // 2. Financial -> Choose one practical next step -> Skip activity
      await answerToDomainEnd();
      expect(find.text('Choose one practical next step'), findsOneWidget);
      await tester.tap(find.text('Try Activity'));
      await tester.pumpAndSettle();
      expect(find.byType(StudentV4CategoryInterventionScreen), findsOneWidget);
      await tester.ensureVisible(find.text('Skip activity'));
      await tester.tap(find.text('Skip activity'));
      await tester.pumpAndSettle();
      expect(find.byType(InterventionFeedbackScreen), findsNothing);
      expect(assessment.studentQuestionIndex, 20);

      // 3. Social Adjustment -> Permission-free Walking -> self-reported completion -> Skip feedback
      await answerToDomainEnd();
      expect(find.text('Take a short walk'), findsOneWidget);
      await tester.tap(find.text('Try Activity'));
      await tester.pumpAndSettle();
      expect(find.byType(InterventionWalkingScreen), findsOneWidget);
      expect(find.text('500-step goal'), findsNothing);
      await tester.tap(find.text('I took a short walk'));
      await tester.pumpAndSettle();
      expect(find.byType(InterventionFeedbackScreen), findsOneWidget);
      await tester.ensureVisible(find.text('Skip feedback'));
      await tester.tap(find.text('Skip feedback'));
      await tester.pumpAndSettle();
      expect(assessment.studentQuestionIndex, 30);

      // 4. Sleep & Rest -> Breathing (uses periodic timer, so use timed pumps) -> Skip activity
      await answerToDomainEnd();
      expect(find.text('Try a breathing wind-down'), findsOneWidget);
      await tester.tap(find.text('Try Activity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(InterventionBreathingScreen), findsOneWidget);
      await tester.tap(find.text('Skip activity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(assessment.studentQuestionIndex, 40);

      // 5. Emotional Well-Being -> Grounding with feeling prompt -> Skip -> submission review
      await answerToDomainEnd();
      expect(find.text('Ground and notice'), findsOneWidget);
      await tester.tap(find.text('Try Activity'));
      await tester.pumpAndSettle();
      expect(find.byType(InterventionGroundingScreen), findsOneWidget);
      expect(find.text('Step 1 of 6'), findsOneWidget);
      await tester.ensureVisible(find.text('Skip activity'));
      await tester.tap(find.text('Skip activity'));
      await tester.pumpAndSettle();
      expect(find.text('Submit assessment'), findsOneWidget);
      expect(assessment.studentAnswers, hasLength(50));
    },
  );

  testWidgets(
    'StudentAssessmentScreen pops review when retry returns an ineligible preview and keeps Teaching V4 on generic card',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Retry -> ineligible pops cleanly back to answering.
      final retryAssessment = AssessmentProvider(_FailThenIneligibleRepository())
        ..bindAuthenticatedUser('student-retry');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AssessmentProvider>.value(
              value: retryAssessment,
            ),
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => _TestAuthProvider('student-retry'),
            ),
          ],
          child: const MaterialApp(
            key: ValueKey('retry-app'),
            home: StudentAssessmentScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('I understand, start assessment'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 9; i += 1) {
        await retryAssessment.answerCurrentStudentQuestion(LikertAnswer.often);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text(LikertAnswer.often.label));
      await tester.pumpAndSettle();

      expect(find.text('Retry Preview'), findsOneWidget);
      await tester.tap(find.text('Retry Preview'));
      await tester.pumpAndSettle();
      expect(find.text('Retry Preview'), findsNothing);
      expect(retryAssessment.studentQuestionIndex, 10);

      // Teaching V4 keeps the generic review prompt rather than Student V4 card copy.
      final teachingAssessment = AssessmentProvider(
        _AllEligiblePreviewRepository(),
      )
        ..bindAuthenticatedUser('faculty-1')
        ..selectRole(AssessmentRole.faculty);
      await tester.pumpWidget(
        MultiProvider(
          key: const ValueKey('teaching-scope'),
          providers: [
            ChangeNotifierProvider<AssessmentProvider>.value(
              value: teachingAssessment,
            ),
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => _TestAuthProvider('faculty-1'),
            ),
          ],
          child: const MaterialApp(
            key: ValueKey('teaching-app'),
            home: StudentAssessmentScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('I understand, start assessment'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 9; i += 1) {
        await teachingAssessment.answerCurrentStudentQuestion(LikertAnswer.often);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text(LikertAnswer.often.label));
      await tester.pumpAndSettle();

      expect(find.text('Optional activity · 1–3 min'), findsNothing);
      expect(find.text('Start with five minutes'), findsNothing);
      expect(find.text('Try Activity'), findsOneWidget);
    },
  );
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
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
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
          'Five well-being areas were considered using your completed responses. You answered 50 of 50 questions, giving this result high response completeness.',
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

class _TestAuthProvider extends AuthProvider {
  _TestAuthProvider(String uid) : super(_TestAuthRepository(uid));
}

class _TestAuthRepository extends AuthRepository {
  _TestAuthRepository(this._uid) : super(AuthService());
  final String _uid;

  @override
  String? get currentUserId => _uid;
}

class _AllEligiblePreviewRepository extends AssessmentRepository {
  @override
  Future<Map<String, Object>> previewV4AssessmentDomain({
    required String instrumentVersion,
    required String domainId,
    required List<StudentAssessmentAnswer> answers,
  }) async => {
    'domainId': domainId,
    'domainLabel': domainId,
    'status': 'supportMayHelp',
    'isScorable': true,
    'answeredCount': answers.length,
    'presentedCount': 10,
    'summary': 'Server result.',
    'suggestedAction': 'Continue.',
    'reflectionPrompt': 'Reflect.',
    'interventionEligible': true,
    'policyVersion': 'assessment_intervention_v1',
  };
}

class _FailThenIneligibleRepository extends AssessmentRepository {
  int _calls = 0;

  @override
  Future<Map<String, Object>> previewV4AssessmentDomain({
    required String instrumentVersion,
    required String domainId,
    required List<StudentAssessmentAnswer> answers,
  }) async {
    _calls += 1;
    if (_calls == 1) throw StateError('offline');
    return {
      'domainId': domainId,
      'domainLabel': domainId,
      'status': 'mostlySupported',
      'isScorable': true,
      'answeredCount': answers.length,
      'presentedCount': 10,
      'summary': 'Server result.',
      'suggestedAction': 'Continue.',
      'reflectionPrompt': 'Reflect.',
      'interventionEligible': false,
      'policyVersion': 'assessment_intervention_v1',
    };
  }
}
