import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/student_assessment/screens/student_assessment_complete_screen.dart';
import 'package:mind_mates/features/student_assessment/screens/student_assessment_screen.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/features/student_assessment/data/student_assessment_questions.dart';
import 'package:mind_mates/features/student_assessment/models/student_assessment_models.dart';
import 'package:mind_mates/features/student_assessment/services/student_assessment_calculator.dart';
import 'package:mind_mates/models/report_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/report_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/services/firebase/firestore_service.dart';
import 'package:provider/provider.dart';

void main() {
  group('StudentAssessmentCalculator', () {
    test('scores risk and protective answers correctly', () {
      expect(
        StudentAssessmentCalculator.riskScore(
          answer: LikertAnswer.always,
          direction: AssessmentDirection.risk,
        ),
        100,
      );
      expect(
        StudentAssessmentCalculator.riskScore(
          answer: LikertAnswer.always,
          direction: AssessmentDirection.protective,
        ),
        0,
      );
      expect(
        StudentAssessmentCalculator.riskScore(
          answer: LikertAnswer.rarely,
          direction: AssessmentDirection.risk,
        ),
        closeTo(33.33, 0.01),
      );
      expect(
        StudentAssessmentCalculator.riskScore(
          answer: LikertAnswer.often,
          direction: AssessmentDirection.risk,
        ),
        closeTo(66.67, 0.01),
      );
      expect(LikertAnswer.values, hasLength(4));
      expect(
        LikertAnswer.values.map((answer) => answer.label),
        isNot(contains('Neutral')),
      );
    });

    test('keeps the student assessment in the intended domain sequence', () {
      List<AssessmentSection> sequenceOf(
        List<StudentAssessmentQuestion> questions,
      ) {
        final orderedSections = <AssessmentSection>[];
        for (final question in questions.where(
          (question) => !question.isConditional,
        )) {
          if (!orderedSections.contains(question.section)) {
            orderedSections.add(question.section);
          }
        }
        return orderedSections;
      }

      expect(sequenceOf(StudentAssessmentQuestions.questions), [
        AssessmentSection.academicCore,
        AssessmentSection.financialConcern,
        AssessmentSection.socialAdjustment,
        AssessmentSection.sleepRest,
        AssessmentSection.emotionalWellBeing,
      ]);
      expect(sequenceOf(StudentAssessmentQuestions.facultyQuestions), [
        AssessmentSection.workplaceStressCore,
        AssessmentSection.professionalSupport,
        AssessmentSection.professionalWellBeing,
        AssessmentSection.sleepRest,
        AssessmentSection.emotionalWellBeing,
      ]);
      expect(sequenceOf(StudentAssessmentQuestions.staffQuestions), [
        AssessmentSection.workplaceResponsibilityCore,
        AssessmentSection.workplaceSupport,
        AssessmentSection.workplaceWellBeing,
        AssessmentSection.sleepRest,
        AssessmentSection.emotionalWellBeing,
      ]);
    });

    test('provides exactly ten active questions for every topic and role', () {
      for (final questions in [
        StudentAssessmentQuestions.questions,
        StudentAssessmentQuestions.facultyQuestions,
        StudentAssessmentQuestions.staffQuestions,
      ]) {
        final active = questions
            .where((question) => !question.isConditional)
            .toList();
        final counts = <AssessmentSection, int>{};
        for (final question in active) {
          counts.update(
            question.section,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }

        expect(active, hasLength(50));
        expect(counts, hasLength(5));
        expect(counts.values, everyElement(10));
      }
    });

    test('triggers deeper academic questions for elevated core answers', () {
      final answers = [
        const StudentAssessmentAnswer(
          questionId: 'academic_core_1',
          answer: LikertAnswer.always,
        ),
      ];

      expect(
        StudentAssessmentCalculator.shouldShowDeeperAcademicQuestions(
          questions: StudentAssessmentQuestions.questions,
          answers: answers,
        ),
        isTrue,
      );
    });

    test('does not count duplicate answer records twice', () {
      final questions = [
        for (var index = 0; index < 3; index++)
          StudentAssessmentQuestion(
            id: 'core_$index',
            text: 'Question $index',
            section: AssessmentSection.academicCore,
            direction: AssessmentDirection.risk,
          ),
      ];
      final answers = [
        for (final question in questions)
          StudentAssessmentAnswer(
            questionId: question.id,
            answer: LikertAnswer.never,
          ),
        const StudentAssessmentAnswer(
          questionId: 'core_0',
          answer: LikertAnswer.often,
        ),
      ];

      expect(
        StudentAssessmentCalculator.shouldShowDeeperQuestions(
          questions: questions,
          answers: answers,
          coreSection: AssessmentSection.academicCore,
        ),
        isFalse,
      );
    });

    test('ignores answers for unknown question IDs', () {
      final questions = [
        for (var index = 0; index < 3; index++)
          StudentAssessmentQuestion(
            id: 'known_$index',
            text: 'Question $index',
            section: AssessmentSection.academicCore,
            direction: AssessmentDirection.risk,
          ),
      ];
      final answers = [
        for (final question in questions)
          StudentAssessmentAnswer(
            questionId: question.id,
            answer: LikertAnswer.never,
          ),
        const StudentAssessmentAnswer(
          questionId: 'unknown',
          answer: LikertAnswer.always,
        ),
      ];

      expect(
        StudentAssessmentCalculator.shouldShowDeeperQuestions(
          questions: questions,
          answers: answers,
          coreSection: AssessmentSection.academicCore,
        ),
        isFalse,
      );
    });

    test('calculates weighted student result', () {
      final questions = StudentAssessmentQuestions.questions
          .where((question) => !question.isConditional)
          .toList();
      final answers = [
        for (final question in questions)
          StudentAssessmentAnswer(
            questionId: question.id,
            answer: question.direction == AssessmentDirection.risk
                ? LikertAnswer.always
                : LikertAnswer.never,
          ),
      ];

      final result = StudentAssessmentCalculator.calculate(
        questions: questions,
        answers: answers,
      );

      expect(result.overallScore, 100);
      expect(result.status, 'At Risk');
      expect(result.totalResponses, questions.length);
      expect(result.subscaleScores['Sleep and Rest'], 100);
      expect(
        result.interpretation.algorithmVersion,
        'internal_wellness_policy_v2',
      );
      expect(result.interpretation.responseQuality.completionPercent, 100);
      expect(
        result.interpretation.userSummary,
        startsWith(
          'One or more areas may be placing extra pressure on daily life.',
        ),
      );
      expect(
        result.interpretation.domainResults.every(
          (domain) => domain.wellBeingStatus == 'At Risk',
        ),
        isTrue,
      );
      expect(result.interpretation.focusInsights, isNotEmpty);
      expect(
        result.interpretation.focusInsights,
        everyElement(isNot(startsWith('I '))),
      );
    });

    test('excludes skipped responses and reports insufficient coverage', () {
      final questions = StudentAssessmentQuestions.questions
          .where((question) => !question.isConditional)
          .take(10)
          .toList();
      final answers = [
        for (var index = 0; index < questions.length; index++)
          StudentAssessmentAnswer(
            questionId: questions[index].id,
            answer: LikertAnswer.rarely,
            isSkipped: index >= 5,
          ),
      ];

      final result = StudentAssessmentCalculator.calculate(
        questions: questions,
        answers: answers,
      );

      expect(result.totalResponses, 5);
      expect(result.interpretation.responseQuality.skipped, 5);
      expect(result.interpretation.responseQuality.completionPercent, 50);
      expect(
        result.interpretation.supportPriority.name,
        'insufficientResponses',
      );
    });

    test('protective answers are reversed and retained as strengths', () {
      final question = StudentAssessmentQuestions.questions.firstWhere(
        (item) => item.direction == AssessmentDirection.protective,
      );
      final result = StudentAssessmentCalculator.calculate(
        questions: [question],
        answers: [
          StudentAssessmentAnswer(
            questionId: question.id,
            answer: LikertAnswer.always,
          ),
        ],
      );

      expect(result.interpretation.protectiveFactors, contains(question.text));
    });

    test('does not report missing categories as zero concern', () {
      final questions = StudentAssessmentQuestions.questions
          .where(
            (question) => question.section == AssessmentSection.academicCore,
          )
          .toList();
      final answers = [
        for (final question in questions)
          StudentAssessmentAnswer(
            questionId: question.id,
            answer: LikertAnswer.never,
          ),
      ];

      final result = StudentAssessmentCalculator.calculate(
        questions: StudentAssessmentQuestions.questions
            .where((question) => !question.isConditional)
            .toList(),
        answers: answers,
      );

      expect(result.overallScore, isNull);
      expect(result.subscaleScores.containsKey('Sleep and Rest'), isFalse);
      expect(
        result.interpretation.domainResults
            .firstWhere((domain) => domain.domain == 'Sleep and Rest')
            .isScorable,
        isFalse,
      );
    });

    test(
      'conditional follow-up answers do not change the core domain score',
      () {
        final core = StudentAssessmentQuestions.questions
            .where(
              (question) => question.section == AssessmentSection.academicCore,
            )
            .toList();
        final deeper = StudentAssessmentQuestions.questions
            .where(
              (question) =>
                  question.section == AssessmentSection.academicDeeper,
            )
            .toList();
        final coreAnswers = [
          for (final question in core)
            StudentAssessmentAnswer(
              questionId: question.id,
              answer: LikertAnswer.often,
            ),
        ];
        final withoutFollowUps = StudentAssessmentCalculator.calculate(
          questions: [...core],
          answers: coreAnswers,
        );
        final withFollowUps = StudentAssessmentCalculator.calculate(
          questions: [...core, ...deeper],
          answers: [
            ...coreAnswers,
            for (final question in deeper)
              StudentAssessmentAnswer(
                questionId: question.id,
                answer: LikertAnswer.never,
              ),
          ],
        );

        expect(
          withFollowUps.subscaleScores['Academic Stress'],
          withoutFollowUps.subscaleScores['Academic Stress'],
        );
      },
    );

    test('uses consistent concern-band boundaries', () {
      expect(StudentAssessmentCalculator.getStatus(0), 'Thriving');
      expect(StudentAssessmentCalculator.getStatus(20), 'Thriving');
      expect(StudentAssessmentCalculator.getStatus(20.01), 'Stable');
      expect(StudentAssessmentCalculator.getStatus(40), 'Stable');
      expect(StudentAssessmentCalculator.getStatus(40.01), 'Needs Improvement');
      expect(StudentAssessmentCalculator.getStatus(60), 'Needs Improvement');
      expect(StudentAssessmentCalculator.getStatus(60.01), 'At Risk');
      expect(StudentAssessmentCalculator.getStatus(100), 'At Risk');
    });

    test(
      'serializes nullable results and answer metadata without losing values',
      () {
        const answer = StudentAssessmentAnswer(
          questionId: 'q1',
          answer: LikertAnswer.often,
          isSkipped: true,
        );
        expect(answer.toJson(), {
          'questionId': 'q1',
          'answer': 'often',
          'value': 3,
          'isSkipped': true,
        });

        final result = StudentAssessmentCalculator.calculate(
          questions: const [],
          answers: const [],
        );
        final json = result.toJson();
        expect(json['overallScore'], isNull);
        expect(json['status'], 'Insufficient Responses');
        expect(json['totalResponses'], 0);
        expect(json['interpretation'], isA<Map<String, Object>>());
      },
    );

    test(
      'does not trigger faculty deeper questions from protective answers',
      () {
        const answers = [
          StudentAssessmentAnswer(
            questionId: 'faculty_workplace_core_1',
            answer: LikertAnswer.always,
          ),
        ];

        expect(
          StudentAssessmentCalculator.shouldShowDeeperQuestions(
            questions: StudentAssessmentQuestions.facultyQuestions,
            answers: answers,
            coreSection: AssessmentSection.workplaceStressCore,
          ),
          isFalse,
        );
      },
    );

    test('calculates weighted faculty result', () {
      final questions = StudentAssessmentQuestions.facultyQuestions
          .where((question) => !question.isConditional)
          .toList();
      final answers = [
        for (final question in questions)
          StudentAssessmentAnswer(
            questionId: question.id,
            answer: question.direction == AssessmentDirection.risk
                ? LikertAnswer.always
                : LikertAnswer.never,
          ),
      ];

      final result = StudentAssessmentCalculator.calculate(
        questions: questions,
        answers: answers,
        userType: AssessmentUserType.faculty,
      );

      expect(result.userType, 'Teaching Personnel');
      expect(result.overallScore, 100);
      expect(result.status, 'At Risk');
      expect(result.subscaleScores['Workplace Stress'], 100);
      expect(result.subscaleScores['Professional Support'], 100);
    });

    test('calculates weighted staff result', () {
      final questions = StudentAssessmentQuestions.staffQuestions
          .where((question) => !question.isConditional)
          .toList();
      final answers = [
        for (final question in questions)
          StudentAssessmentAnswer(
            questionId: question.id,
            answer: question.direction == AssessmentDirection.risk
                ? LikertAnswer.always
                : LikertAnswer.never,
          ),
      ];

      final result = StudentAssessmentCalculator.calculate(
        questions: questions,
        answers: answers,
        userType: AssessmentUserType.staff,
      );

      expect(result.userType, 'Non-Teaching Personnel');
      expect(result.overallScore, 100);
      expect(result.status, 'At Risk');
      expect(result.subscaleScores['Workplace Responsibilities'], 100);
      expect(result.subscaleScores['Workplace Support'], 100);
    });
  });

  group('AssessmentProvider student assessment flow', () {
    test('keeps a fixed 50-question assessment after elevated answers', () {
      final provider = AssessmentProvider(AssessmentRepository());
      provider.startStudentAssessment();

      for (var index = 0; index < 10; index += 1) {
        provider.answerCurrentStudentQuestion(LikertAnswer.always);
      }

      expect(
        provider.studentQuestions.any((question) => question.isConditional),
        isFalse,
      );
      expect(provider.studentQuestions, hasLength(50));
      expect(
        provider.currentStudentQuestion?.section,
        AssessmentSection.financialConcern,
      );
    });

    test('goes back and allows a previous answer to be changed', () {
      final provider = AssessmentProvider(AssessmentRepository())
        ..startStudentAssessment();

      provider.answerCurrentStudentQuestion(LikertAnswer.always);
      expect(provider.studentQuestionIndex, 1);

      provider.goBackStudentQuestion();
      expect(provider.studentQuestionIndex, 0);
      expect(provider.currentStudentAnswer, LikertAnswer.always);

      provider.answerCurrentStudentQuestion(LikertAnswer.rarely);
      expect(provider.studentQuestionIndex, 1);
      expect(
        provider.studentAnswers
            .singleWhere((answer) => answer.questionId == 'academic_core_1')
            .answer,
        LikertAnswer.rarely,
      );
    });

    test('starts faculty questions from selected role', () {
      final provider = AssessmentProvider(AssessmentRepository());
      provider.selectRole(AssessmentRole.faculty);
      provider.startStudentAssessment();

      expect(provider.activeAssessmentTitle, 'Teaching Assessment');
      expect(
        provider.currentStudentQuestion?.section,
        AssessmentSection.workplaceStressCore,
      );
    });

    test('starts staff questions from selected role', () {
      final provider = AssessmentProvider(AssessmentRepository());
      provider.selectRole(AssessmentRole.staff);
      provider.startStudentAssessment();

      expect(provider.activeAssessmentTitle, 'Non-Teaching Assessment');
      expect(
        provider.currentStudentQuestion?.section,
        AssessmentSection.workplaceResponsibilityCore,
      );
    });

    test('allows full assessment when none were completed recently', () {
      final eligibility = FullAssessmentEligibility.fromCompletedDates(
        completedAt: const [],
        now: DateTime(2026, 7, 3, 9),
      );

      expect(eligibility.canStart, isTrue);
    });

    test('blocks full assessment until 2 days after latest completion', () {
      final eligibility = FullAssessmentEligibility.fromCompletedDates(
        completedAt: [DateTime(2026, 7, 2, 9)],
        now: DateTime(2026, 7, 3, 9),
      );

      expect(eligibility.canStart, isFalse);
      expect(eligibility.nextEligibleAt, DateTime(2026, 7, 4, 9));
      expect(eligibility.reason, FullAssessmentBlockReason.minimumInterval);
    });

    test('allows full assessment 2 days after one completion', () {
      final eligibility = FullAssessmentEligibility.fromCompletedDates(
        completedAt: [DateTime(2026, 7, 1, 9)],
        now: DateTime(2026, 7, 3, 9),
      );

      expect(eligibility.canStart, isTrue);
    });

    test('blocks after 2 full assessments in a rolling 7-day period', () {
      final eligibility = FullAssessmentEligibility.fromCompletedDates(
        completedAt: [DateTime(2026, 6, 29, 9), DateTime(2026, 7, 1, 9)],
        now: DateTime(2026, 7, 3, 9),
      );

      expect(eligibility.canStart, isFalse);
      expect(eligibility.nextEligibleAt, DateTime(2026, 7, 6, 9));
      expect(eligibility.reason, FullAssessmentBlockReason.rollingLimit);
    });

    test(
      'uses the later interval date when it is after the rolling window',
      () {
        final eligibility = FullAssessmentEligibility.fromCompletedDates(
          completedAt: [DateTime(2026, 6, 27, 9), DateTime(2026, 7, 3, 8)],
          now: DateTime(2026, 7, 3, 9),
        );

        expect(eligibility.canStart, isFalse);
        expect(eligibility.nextEligibleAt, DateTime(2026, 7, 5, 8));
        expect(eligibility.reason, FullAssessmentBlockReason.minimumInterval);
      },
    );
  });

  group('AssessmentRepository full assessment eligibility', () {
    test(
      'uses indexed user and descending createdAt query and ignores quick records',
      () async {
        final firestore = _EligibilityFirestoreService(
          docs: [
            {
              'type': 'quick',
              'createdAt': DateTime(2026, 7, 3, 9).toIso8601String(),
            },
            {
              'type': 'student',
              'createdAt': DateTime(2026, 7, 2, 9).toIso8601String(),
            },
          ],
        );
        final repository = AssessmentRepository(firestoreService: firestore);

        final eligibility = await repository.fullAssessmentEligibility(
          'user_1',
          now: DateTime(2026, 7, 3, 9),
        );

        expect(firestore.collection, 'assessments');
        expect(firestore.whereEquals, {'userId': 'user_1'});
        expect(firestore.orderBy, 'createdAt');
        expect(firestore.descending, isTrue);
        expect(eligibility.canStart, isFalse);
        expect(eligibility.nextEligibleAt, DateTime(2026, 7, 4, 9));
        expect(eligibility.reason, FullAssessmentBlockReason.minimumInterval);
      },
    );
  });

  group('StudentAssessmentScreen UI', () {
    testWidgets('offers four choices without a neutral option', (tester) async {
      final provider = AssessmentProvider(AssessmentRepository())
        ..startStudentAssessment();

      await tester.pumpWidget(
        ChangeNotifierProvider<AssessmentProvider>.value(
          value: provider,
          child: const MaterialApp(home: StudentAssessmentScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Strongly Disagree'), findsOneWidget);
      expect(find.text('Disagree'), findsOneWidget);
      expect(find.text('Agree'), findsOneWidget);
      expect(find.text('Strongly Agree'), findsOneWidget);
      expect(find.text('Neutral'), findsNothing);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Academic Stress'), findsWidgets);
      expect(find.textContaining('Question 1 of'), findsNothing);
    });
  });

  group('StudentAssessmentCompleteScreen', () {
    testWidgets('saving full assessment refreshes weekly report', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final assessmentRepository = _FakeAssessmentRepository();
      final assessmentProvider = AssessmentProvider(assessmentRepository)
        ..startStudentAssessment();
      _completeAssessment(assessmentProvider);
      final userProvider = UserProvider(_FakeUserRepository())
        ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));
      final reportRepository = _FakeReportRepository();
      final reportProvider = ReportProvider(reportRepository);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AssessmentProvider>.value(
              value: assessmentProvider,
            ),
            ChangeNotifierProvider<UserProvider>.value(value: userProvider),
            ChangeNotifierProvider<ReportProvider>.value(value: reportProvider),
          ],
          child: const MaterialApp(home: StudentAssessmentCompleteScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Set an appointment?'), findsOneWidget);
      expect(
        find.text(
          'Do you want to set an appointment with PACC to discuss your well-being result?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('No'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Your Well-being Profile'), findsOneWidget);
      expect(find.text('Secondary overall concern index'), findsNothing);
      expect(find.text('/ 100'), findsNothing);
      expect(find.text('Your well-being areas'), findsOneWidget);
      expect(find.text('Your personal insights'), findsOneWidget);
      expect(find.text('Domain interpretation'), findsNothing);
      expect(
        find.textContaining('Functional-impact observation'),
        findsNothing,
      );
      expect(assessmentRepository.savedFullAssessmentUserId, 'user_1');
      expect(reportRepository.generatedForUserId, 'user_1');
      expect(
        reportProvider.latestReport?.latestAssessmentSource,
        'fullAssessment',
      );
    });
  });
}

void _completeAssessment(AssessmentProvider provider) {
  var guard = 0;
  while (provider.studentResult == null && guard < 100) {
    provider.answerCurrentStudentQuestion(LikertAnswer.rarely);
    guard += 1;
  }
}

class _FakeAssessmentRepository extends AssessmentRepository {
  String? savedFullAssessmentUserId;

  @override
  Future<Map<String, Object>> saveStudentAssessment({
    required String userId,
    required StudentAssessmentResult result,
    List<StudentAssessmentAnswer> answers = const [],
  }) async {
    savedFullAssessmentUserId = userId;
    return {
      'userId': userId,
      'type': result.userType.toLowerCase(),
      ...result.toJson(),
    };
  }
}

class _EligibilityFirestoreService extends FirestoreService {
  _EligibilityFirestoreService({required this.docs});

  final List<Map<String, dynamic>> docs;
  String? collection;
  Map<String, Object?>? whereEquals;
  String? orderBy;
  bool? descending;

  @override
  Future<List<Map<String, dynamic>>> getDocuments(
    String collection, {
    Map<String, Object?> whereEquals = const {},
    String? orderBy,
    bool descending = true,
    int? limit,
  }) async {
    this.collection = collection;
    this.whereEquals = whereEquals;
    this.orderBy = orderBy;
    this.descending = descending;
    return docs;
  }
}

class _FakeUserRepository extends UserRepository {
  @override
  Future<UserModel?> recordActivity(
    String uid,
    UserActivityType type, {
    DateTime? occurredAt,
  }) async {
    return UserModel(
      id: uid,
      email: 'leo@example.com',
      dayStreak: 1,
      activeDateKeys: const ['2026-07-03'],
    );
  }
}

class _FakeReportRepository extends ReportRepository {
  String? generatedForUserId;
  ReportModel? latest;

  @override
  Future<String> generateWeeklyReport(String userId, {DateTime? now}) async {
    generatedForUserId = userId;
    latest = ReportModel(
      id: 'report_1',
      userId: userId,
      generatedAt: DateTime(2026, 7, 3),
      description: 'Latest full assessment shows Moderate Concern concern.',
      hasEnoughData: true,
      latestAssessmentSource: 'fullAssessment',
    );
    return 'report_1';
  }

  @override
  Future<ReportModel?> fetchLatestReport(String userId) async => latest;
}
