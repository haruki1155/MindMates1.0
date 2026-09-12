import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/quick_assessment/data/quick_assessment_questions.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/features/quick_assessment/screens/quick_assessment_category_screen.dart';
import 'package:mind_mates/features/quick_assessment/screens/quick_assessment_question_screen.dart';
import 'package:mind_mates/features/quick_assessment/screens/quick_assessment_role_screen.dart';
import 'package:mind_mates/features/quick_assessment/services/quick_assessment_scoring.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:mind_mates/services/firebase/firestore_service.dart';
import 'package:provider/provider.dart';

void main() {
  group('QuickAssessmentScoring', () {
    test('returns progress labels from 1/5 through 5/5', () {
      expect(QuickAssessmentScoring.progressLabelForStep(1), '1/5');
      expect(QuickAssessmentScoring.progressLabelForStep(2), '2/5');
      expect(QuickAssessmentScoring.progressLabelForStep(3), '3/5');
      expect(QuickAssessmentScoring.progressLabelForStep(4), '4/5');
      expect(QuickAssessmentScoring.progressLabelForStep(5), '5/5');
    });

    test('reverse scores protective questions', () {
      expect(
        QuickAssessmentScoring.concernScore(
          direction: QuickQuestionDirection.protective,
          value: 5,
        ),
        0,
      );
      expect(
        QuickAssessmentScoring.concernScore(
          direction: QuickQuestionDirection.protective,
          value: 1,
        ),
        100,
      );
    });

    test('scores risk questions directly', () {
      expect(
        QuickAssessmentScoring.concernScore(
          direction: QuickQuestionDirection.risk,
          value: 1,
        ),
        0,
      );
      expect(
        QuickAssessmentScoring.concernScore(
          direction: QuickQuestionDirection.risk,
          value: 5,
        ),
        100,
      );
    });

    test('normalizes each item using its actual response range', () {
      expect(
        QuickAssessmentScoring.concernScore(
          direction: QuickQuestionDirection.risk,
          value: 1,
          minValue: 1,
          maxValue: 4,
        ),
        0,
      );
      expect(
        QuickAssessmentScoring.concernScore(
          direction: QuickQuestionDirection.risk,
          value: 4,
          minValue: 1,
          maxValue: 4,
        ),
        100,
      );
    });

    test('builds hidden interpretation from concern score and areas', () {
      final responses = [
        const QuickAssessmentResponse(
          questionId: 'overwhelmed',
          optionId: 'very_often',
          value: 5,
          concernScore: 100,
        ),
        const QuickAssessmentResponse(
          questionId: 'connected',
          optionId: 'neutral',
          value: 3,
          concernScore: 50,
        ),
      ];

      expect(
        QuickAssessmentScoring.overallLevel(75),
        QuickAssessmentLevel.veryHigh,
      );
      expect(QuickAssessmentScoring.topConcernAreas(responses), [
        'Stress load',
        'Social connection',
      ]);
      expect(
        QuickAssessmentScoring.summaryForLevel(QuickAssessmentLevel.high),
        contains('areas you may want to explore'),
      );
      expect(
        QuickAssessmentScoring.recommendedNextStepForLevel(
          QuickAssessmentLevel.moderate,
        ),
        contains('full role-based assessment'),
      );
    });

    test('maps assessment level into a non-diagnostic wellness signal', () {
      expect(
        QuickAssessmentScoring.signalForLevel(QuickAssessmentLevel.low),
        QuickAssessmentSignal.stable,
      );
      expect(
        QuickAssessmentScoring.signalForLevel(QuickAssessmentLevel.moderate),
        QuickAssessmentSignal.watchful,
      );
      expect(
        QuickAssessmentScoring.signalForLevel(QuickAssessmentLevel.high),
        QuickAssessmentSignal.elevated,
      );
      expect(
        QuickAssessmentScoring.signalForLevel(QuickAssessmentLevel.veryHigh),
        QuickAssessmentSignal.highSupport,
      );
    });
  });

  group('AssessmentProvider quick assessment flow', () {
    test('requires a non-empty name', () {
      final provider = AssessmentProvider(AssessmentRepository());

      expect(provider.isNameValid, isFalse);

      provider.updateName('  Leo  ');

      expect(provider.isNameValid, isTrue);
    });

    test('requires an answer before advancing', () {
      final provider = _readyProvider();

      expect(provider.currentQuestionIndex, 0);
      expect(provider.hasSelectedAnswer, isFalse);
      expect(provider.moveToNextQuestion(), isFalse);
      expect(provider.currentQuestionIndex, 0);
    });

    test('calculates final average score from all five answers', () {
      final provider = _readyProvider();
      final questions = provider.questions;

      for (var index = 0; index < questions.length; index += 1) {
        final question = questions[index];
        provider.selectAnswer(question.options.last);
        provider.moveToNextQuestion();
      }

      final result = provider.quickResult;

      expect(result, isNotNull);
      expect(result!.role, AssessmentRole.student);
      expect(result.name, 'Leo');
      expect(result.responses.length, 5);
      expect(result.concernScore, 100);
      expect(result.overallLevel, QuickAssessmentLevel.veryHigh);
      expect(result.mentalStatusSignal, QuickAssessmentSignal.highSupport);
      expect(result.signalSource, 'quickAssessment');
      expect(result.signalGeneratedAt, result.createdAt);
      expect(result.summary, isNotEmpty);
      expect(result.topConcernAreas, isNotEmpty);
      expect(result.recommendedNextStep, isNotEmpty);
    });

    test('carries selected role and name into pending result data', () {
      final provider = _readyProvider(
        role: AssessmentRole.faculty,
        name: 'Mia',
      );

      for (final question in QuickAssessmentQuestions.questions) {
        provider.selectAnswer(question.options.first);
        provider.moveToNextQuestion();
      }

      final result = provider.quickResult;

      expect(result, isNotNull);
      expect(result!.role, AssessmentRole.faculty);
      expect(result.name, 'Mia');
    });

    test('saving does nothing without a pending quick result', () async {
      final repository = AssessmentRepository(
        firestoreService: _FakeFirestoreService(),
      );
      final provider = AssessmentProvider(repository);

      expect(await provider.saveQuickAssessmentForUser('user_1'), isNull);
    });

    test(
      'saving uses authenticated user id and complete hidden payload',
      () async {
        final firestore = _FakeFirestoreService();
        final repository = AssessmentRepository(firestoreService: firestore);
        final provider = _readyProvider(repository: repository);

        for (final question in QuickAssessmentQuestions.questions) {
          provider.selectAnswer(question.options.last);
          provider.moveToNextQuestion();
        }

        final payload = await provider.saveQuickAssessmentForUser('user_123');

        expect(payload, isNotNull);
        expect(payload!['userId'], 'user_123');
        expect(payload['type'], 'quick');
        expect(payload['overallLevel'], QuickAssessmentLevel.veryHigh.name);
        expect(payload['responsePatternCode'], 'supportMayHelp');
        expect(payload['responsePatternLabel'], 'Support may be useful');
        expect(payload['summary'], isA<String>());
        expect(payload['topConcernAreas'], isA<List<String>>());
        expect(payload['recommendedNextStep'], isA<String>());
        expect(
          payload['mentalStatusSignal'],
          QuickAssessmentSignal.highSupport.name,
        );
        expect(payload['signalSource'], 'quickAssessment');
        expect(payload['signalGeneratedAt'], isA<String>());
        expect(payload['responses'], isA<List<Object>>());
        final interpretation = Map<String, dynamic>.from(
          payload['interpretation']! as Map,
        );
        final domains = interpretation['domainResults']! as List;
        expect(
          (domains.first as Map)['bandLabel'],
          isNot(anyOf('Low', 'Watchful', 'Moderate', 'Elevated', 'High')),
        );
        expect(firestore.collection, 'assessments');
        expect(firestore.createdDocumentId, 'quick_user_123');
        expect(firestore.createdDocument?['userId'], 'user_123');
      },
    );

    test('repeated save keeps one deterministic quick assessment', () async {
      final firestore = _FakeFirestoreService();
      final repository = AssessmentRepository(firestoreService: firestore);
      final provider = _readyProvider(repository: repository);

      for (final question in QuickAssessmentQuestions.questions) {
        provider.selectAnswer(question.options.first);
        provider.moveToNextQuestion();
      }

      await provider.saveQuickAssessmentForUser('user_1');
      await provider.saveQuickAssessmentForUser('user_1');

      expect(firestore.atomicWriteCount, 1);
      expect(firestore.createdDocumentId, 'quick_user_1');
      expect(firestore.setDocumentData?['quickAssessmentCompleted'], isTrue);
    });

    test('legacy quick assessment backfills profile completion', () async {
      final firestore = _FakeFirestoreService(
        legacyDocuments: [
          {'id': 'legacy_1', 'userId': 'user_1', 'type': 'quick'},
        ],
      );
      final repository = AssessmentRepository(firestoreService: firestore);

      final completed = await repository.ensureQuickAssessmentCompletion(
        'user_1',
      );

      expect(completed, isTrue);
      expect(firestore.setDocumentData?['quickAssessmentCompleted'], isTrue);
    });
  });

  group('QuickAssessmentCategoryScreen', () {
    testWidgets('quick assessment completion opens optional full assessment', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final firestore = _FakeFirestoreService();
      final assessmentProvider = _readyProvider(
        repository: AssessmentRepository(firestoreService: firestore),
      )..resetQuestions();
      final userProvider = UserProvider(_FakeUserRepository())
        ..setUser(
          const UserModel(
            id: 'user_123',
            email: 'leo@example.com',
            role: 'student',
          ),
        );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AssessmentProvider>.value(
              value: assessmentProvider,
            ),
            ChangeNotifierProvider<AuthProvider>(
              create: (_) =>
                  AuthProvider(_FakeAuthRepository(currentUserId: 'user_123')),
            ),
            ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ],
          child: MaterialApp(
            routes: {
              RouteNames.quickAssessmentCategory: (_) =>
                  const _RouteMarker('optional full assessment target'),
            },
            home: const QuickAssessmentQuestionScreen(),
          ),
        ),
      );

      for (final question in QuickAssessmentQuestions.questions) {
        await tester.tap(find.text(question.options.first.label).first);
        await tester.pump();
        await tester.ensureVisible(find.text('Next'));
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      expect(find.text('optional full assessment target'), findsOneWidget);
      expect(firestore.createdDocument?['userId'], 'user_123');
      expect(firestore.createdDocument?['type'], 'quick');
    });

    testWidgets('blocks full assessment when rolling limit is reached', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final assessmentProvider =
          AssessmentProvider(
              _EligibilityAssessmentRepository(
                const FullAssessmentEligibility(
                  canStart: false,
                  nextEligibleAt: null,
                  reason: FullAssessmentBlockReason.rollingLimit,
                ),
              ),
            )
            ..selectRole(AssessmentRole.student)
            ..updateName('Leo');
      final userProvider = UserProvider(_FakeUserRepository())
        ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AssessmentProvider>.value(
              value: assessmentProvider,
            ),
            ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ],
          child: MaterialApp(
            routes: {
              RouteNames.studentAssessment: (_) =>
                  const _RouteMarker('student assessment target'),
            },
            home: const QuickAssessmentCategoryScreen(),
          ),
        ),
      );

      await tester.tap(find.text('Take Student Assessment'));
      await tester.pumpAndSettle();

      expect(find.text('Assessment limit reached'), findsOneWidget);
      expect(find.textContaining('up to 2 times in 7 days'), findsOneWidget);
      expect(find.text('student assessment target'), findsNothing);
    });

    testWidgets('warns and continues when eligibility check throws', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final assessmentProvider =
          AssessmentProvider(
              _EligibilityAssessmentRepository(
                const FullAssessmentEligibility(canStart: true),
                throws: true,
              ),
            )
            ..selectRole(AssessmentRole.student)
            ..updateName('Leo');
      final userProvider = UserProvider(_FakeUserRepository())
        ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AssessmentProvider>.value(
              value: assessmentProvider,
            ),
            ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ],
          child: MaterialApp(
            routes: {
              RouteNames.studentAssessment: (_) =>
                  const _RouteMarker('student assessment target'),
            },
            home: const QuickAssessmentCategoryScreen(),
          ),
        ),
      );

      await tester.tap(find.text('Take Student Assessment'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Unable to verify assessment limit. You can continue for now.',
        ),
        findsOneWidget,
      );
      expect(find.text('student assessment target'), findsOneWidget);
    });
  });

  testWidgets('completed user cannot reopen quick assessment entry', (
    tester,
  ) async {
    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(
        const UserModel(
          id: 'user_1',
          email: 'user@mindmate.local',
          quickAssessmentCompleted: true,
        ),
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<AssessmentProvider>(
            create: (_) => AssessmentProvider(AssessmentRepository()),
          ),
        ],
        child: MaterialApp(
          routes: {RouteNames.home: (_) => const _RouteMarker('home target')},
          home: const QuickAssessmentRoleScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('home target'), findsOneWidget);
  });
}

AssessmentProvider _readyProvider({
  AssessmentRole role = AssessmentRole.student,
  String name = 'Leo',
  AssessmentRepository? repository,
}) {
  final provider = AssessmentProvider(repository ?? AssessmentRepository());
  provider.selectRole(role);
  provider.updateName(name);
  return provider;
}

class _FakeFirestoreService extends FirestoreService {
  _FakeFirestoreService({this.legacyDocuments = const []});

  String? collection;
  String? createdDocumentId;
  Map<String, dynamic>? createdDocument;
  Map<String, dynamic>? setDocumentData;
  int atomicWriteCount = 0;
  final List<Map<String, dynamic>> legacyDocuments;
  final Map<String, Map<String, dynamic>> _documents = {};

  @override
  Future<Map<String, dynamic>?> getDocument(
    String collection,
    String documentId,
  ) async => _documents['$collection/$documentId'];

  @override
  Future<List<Map<String, dynamic>>> getDocuments(
    String collection, {
    Map<String, Object?> whereEquals = const {},
    String? orderBy,
    bool descending = true,
    int? limit,
  }) async {
    final matches = legacyDocuments.where((document) {
      return whereEquals.entries.every(
        (entry) => document[entry.key] == entry.value,
      );
    }).toList();
    return limit == null ? matches : matches.take(limit).toList();
  }

  @override
  Future<String> createDocument(
    String collection,
    Map<String, dynamic> data,
  ) async {
    this.collection = collection;
    createdDocument = data;
    return 'doc_1';
  }

  @override
  Future<void> setDocument(
    String collection,
    String documentId,
    Map<String, dynamic> data, {
    bool merge = false,
  }) async {
    setDocumentData = data;
    _documents['$collection/$documentId'] = data;
  }

  @override
  Future<void> setDocumentsAtomically(
    List<FirestoreSetOperation> operations,
  ) async {
    atomicWriteCount += 1;
    for (final operation in operations) {
      _documents['${operation.collection}/${operation.documentId}'] =
          operation.data;
      if (operation.collection == 'assessments') {
        collection = operation.collection;
        createdDocumentId = operation.documentId;
        createdDocument = operation.data;
      }
      if (operation.collection == 'users') {
        setDocumentData = operation.data;
      }
    }
  }
}

class _EligibilityAssessmentRepository extends AssessmentRepository {
  _EligibilityAssessmentRepository(this.eligibility, {this.throws = false});

  final FullAssessmentEligibility eligibility;
  final bool throws;

  @override
  Future<FullAssessmentEligibility> fullAssessmentEligibility(
    String userId, {
    DateTime? now,
  }) async {
    if (throws) {
      throw StateError('test eligibility failure');
    }
    return eligibility;
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.currentUserId}) : super(AuthService());

  @override
  final String? currentUserId;
}

class _FakeUserRepository extends UserRepository {
  UserModel? updatedUser;
  UserActivityType? recordedActivityType;

  @override
  Future<void> updateUserProfile(String uid, UserModel user) async {
    updatedUser = user;
  }

  @override
  Future<UserModel?> recordActivity(
    String uid,
    UserActivityType type, {
    DateTime? occurredAt,
  }) async {
    recordedActivityType = type;
    return null;
  }
}

class _RouteMarker extends StatelessWidget {
  const _RouteMarker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}
