import 'dart:convert';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mind_aid/ai_engine/mind_aid_chat_engine.dart';
import 'package:mind_mates/features/mind_aid/ai_engine/mind_aid_engine.dart';
import 'package:mind_mates/features/mind_aid/ai_engine/mind_aid_response_composer.dart';
import 'package:mind_mates/features/mind_aid/ai_engine/mind_aid_safety_classifier.dart';
import 'package:mind_mates/features/mind_aid/data/mind_aid_dataset_loader.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_chat_models.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_context.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_dataset_models.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_model_provider.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_safety.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_compatibility.dart';
import 'package:mind_mates/models/mind_aid_message_model.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/models/report_model.dart';
import 'package:mind_mates/repositories/mind_aid_context_repository.dart';
import 'package:mind_mates/repositories/mind_aid_repository_screen.dart';
import 'package:mind_mates/services/firebase/firestore_service.dart';
import 'package:mind_mates/services/firebase/mind_aid_cloud_service.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_integration_models.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_companion_models.dart';

void main() {
  group('MindAidDatasetLoader', () {
    test('loads and validates dataset assets', () async {
      final loader = MindAidDatasetLoader(bundle: _MindAidTestBundle());

      final dataset = await loader.load();

      expect(dataset.records, hasLength(4));
      expect(dataset.crisisRecords, hasLength(1));
      expect(dataset.suggestions, hasLength(2));
      expect(dataset.copingExercises, isNotEmpty);
      expect(dataset.resources, isNotEmpty);
    });

    test('throws when the intent dataset is empty', () async {
      final loader = MindAidDatasetLoader(
        bundle: _MindAidTestBundle(
          overrides: {MindAidDatasetLoader.intentsPath: _jsonRecords([])},
        ),
      );

      expect(loader.load, throwsFormatException);
    });
  });

  group('MindAidEngine', () {
    late MindAidDatasetBundle dataset;

    setUp(() async {
      dataset = await MindAidDatasetLoader(bundle: _MindAidTestBundle()).load();
    });

    test('matches academic stress', () {
      final result = MindAidEngine().process(
        'I am stressed about exams and deadlines',
        dataset,
      );

      expect(result.intent, 'academic_stress');
      expect(result.severity, MindAidSeverity.medium);
      expect(result.response, contains('Try this:'));
    });

    test('matches burnout', () {
      final result = MindAidEngine().process(
        'I feel exhausted and drained',
        dataset,
      );

      expect(result.intent, 'burnout');
    });

    test('matches loneliness', () {
      final result = MindAidEngine().process(
        'I feel alone and invisible',
        dataset,
      );

      expect(result.intent, 'loneliness');
    });

    test('matches anxiety', () {
      final result = MindAidEngine().process(
        'I am panicking and worried',
        dataset,
      );

      expect(result.intent, 'anxiety');
    });

    test('returns fallback for unknown input', () {
      final result = MindAidEngine().process(
        'The sky looks clear today',
        dataset,
      );

      expect(result.isFallback, isTrue);
      expect(result.response, contains('I am here with you'));
    });

    test('prioritizes crisis safety routing', () {
      final result = MindAidEngine().process('I want to end my life', dataset);

      expect(result.intent, 'crisis_self_harm');
      expect(result.requiresEscalation, isTrue);
      expect(result.severity, MindAidSeverity.crisis);
      expect(result.riskFlags, contains('self_harm'));
      expect(result.response, contains('immediate'));
    });

    test('recognizes common indirect crisis wording', () {
      final classifier = const MindAidSafetyClassifier();

      expect(
        classifier
            .classify(
              normalizedInput: 'i cannot go on anymore',
              matches: const [],
            )
            .level,
        MindAidSafetyLevel.crisisOrImmediateRisk,
      );
      expect(
        classifier.classify(normalizedInput: 'kms', matches: const []).level,
        MindAidSafetyLevel.crisisOrImmediateRisk,
      );
    });

    test('uses high assessment categories as a gentle scoring bias', () {
      final engine = MindAidEngine();
      final base = engine.process('I feel worried', dataset);
      final contextual = engine.process(
        'I feel worried',
        dataset,
        context: _assessmentContext(),
      );

      expect(contextual.intent, 'anxiety');
      expect(contextual.score, greaterThan(base.score));
    });
  });

  group('MindAidChatEngine', () {
    late MindAidDatasetBundle dataset;

    setUp(() async {
      dataset = await MindAidDatasetLoader(bundle: _MindAidTestBundle()).load();
    });

    test('blends the top two relevant intents', () async {
      final result = await MindAidChatEngine().respond(
        const MindAidChatRequest(
          userId: 'user_1',
          text: 'I am exhausted and worried about exams',
        ),
        dataset,
      );

      expect(result.intentMatches.map((match) => match.record.intent), [
        'academic_stress',
        'burnout',
      ]);
      expect(result.text, contains('I also hear some burnout'));
      expect(result.suggestions, isNotEmpty);
    });

    test('handles short follow-up replies with active topic', () async {
      final engine = MindAidChatEngine();
      final first = await engine.respond(
        const MindAidChatRequest(
          userId: 'user_1',
          text: 'I am stressed about exams',
        ),
        dataset,
      );
      final second = await engine.respond(
        MindAidChatRequest(
          userId: 'user_1',
          text: 'yes',
          recentMessages: [
            _message('1', 'user', 'I am stressed about exams'),
            _message('2', 'assistant', first.text),
          ],
        ),
        dataset,
      );

      expect(second.primaryIntent, 'academic_stress');
      expect(second.text, contains('academic stress'));
    });

    test('asks a clarifying question for low-confidence input', () async {
      final result = await MindAidChatEngine().respond(
        const MindAidChatRequest(userId: 'user_1', text: 'clouds are moving'),
        dataset,
      );

      expect(result.primaryIntent, 'general_support');
      expect(result.text, MindAidChatEngine.defaultGreeting);
      expect(result.requiresEscalation, isFalse);
    });

    test('returns default greeting for programming questions', () async {
      final result = await MindAidChatEngine().respond(
        const MindAidChatRequest(
          userId: 'user_1',
          text: 'Write Python code for me',
        ),
        dataset,
      );

      expect(result.text, MindAidChatEngine.defaultGreeting);
      expect(result.requiresEscalation, isFalse);
    });

    test('returns default greeting for sports questions', () async {
      final result = await MindAidChatEngine().respond(
        const MindAidChatRequest(
          userId: 'user_1',
          text: 'Who won the NBA Finals?',
        ),
        dataset,
      );

      expect(result.text, MindAidChatEngine.defaultGreeting);
    });

    test('returns default greeting for mathematics', () async {
      final result = await MindAidChatEngine().respond(
        const MindAidChatRequest(userId: 'user_1', text: 'What is 50 x 20?'),
        dataset,
      );

      expect(result.text, MindAidChatEngine.defaultGreeting);
    });

    test('responds to greetings with the default greeting', () async {
      final result = await MindAidChatEngine().respond(
        const MindAidChatRequest(userId: 'user_1', text: 'Hello!'),
        dataset,
      );

      expect(result.text, MindAidChatEngine.defaultGreeting);
    });

    test('blocks unrelated short questions after a wellness topic', () async {
      final engine = MindAidChatEngine();

      await engine.respond(
        const MindAidChatRequest(
          userId: 'user_1',
          text: 'I am stressed about exams',
        ),
        dataset,
      );

      final result = await engine.respond(
        const MindAidChatRequest(userId: 'user_1', text: 'Who won?'),
        dataset,
      );

      expect(result.text, MindAidChatEngine.defaultGreeting);
    });

    test('preserves mental wellness support', () async {
      final result = await MindAidChatEngine().respond(
        const MindAidChatRequest(
          userId: 'user_1',
          text: 'I am stressed about exams',
        ),
        dataset,
      );

      expect(result.text, isNot(MindAidChatEngine.defaultGreeting));
    });

    test('preserves crisis safety response', () async {
      final result = await MindAidChatEngine().respond(
        const MindAidChatRequest(
          userId: 'user_1',
          text: 'I want to end my life',
        ),
        dataset,
      );

      expect(result.requiresEscalation, isTrue);
      expect(result.text, isNot(MindAidChatEngine.defaultGreeting));
    });

    test('safety override wins over other matched concerns', () async {
      final result = await MindAidChatEngine().respond(
        const MindAidChatRequest(
          userId: 'user_1',
          text: 'I have exams but I want to end my life',
        ),
        dataset,
      );

      expect(result.primaryIntent, 'crisis_self_harm');
      expect(result.requiresEscalation, isTrue);
      expect(result.status, 'urgent');
    });

    test(
      'avoids repeating the same response when alternatives exist',
      () async {
        final engine = MindAidChatEngine();
        final first = await engine.respond(
          const MindAidChatRequest(userId: 'user_1', text: 'exam deadline'),
          dataset,
        );
        final second = await engine.respond(
          const MindAidChatRequest(userId: 'user_1', text: 'exam deadline'),
          dataset,
        );

        expect(second.text, isNot(first.text));
      },
    );

    test('reviews assessment context with status and top category', () async {
      final result = await MindAidChatEngine().respond(
        MindAidChatRequest(
          userId: 'user_1',
          text: 'Can you review my assessment result?',
          assessment: _assessmentContext().assessment,
        ),
        dataset,
      );

      expect(result.text, contains('High Concern'));
      expect(result.text, contains('Emotional Well-Being'));
      expect(result.text, contains('not a diagnosis'));
      expect(result.requiresEscalation, isFalse);
    });

    test('crisis input overrides assessment-aware review path', () async {
      final result = await MindAidChatEngine().respond(
        MindAidChatRequest(
          userId: 'user_1',
          text: 'Review my assessment because I want to end my life',
          assessment: _assessmentContext().assessment,
        ),
        dataset,
      );

      expect(result.primaryIntent, 'crisis_self_harm');
      expect(result.requiresEscalation, isTrue);
      expect(result.text, contains('immediate'));
    });

    test(
      'quick assessment fallback can answer assessment review prompts',
      () async {
        final result = await MindAidChatEngine().respond(
          MindAidChatRequest(
            userId: 'user_1',
            text: 'What should I do next with my score?',
            quickAssessment: _quickAssessmentContext(),
          ),
          dataset,
        );

        expect(result.text, contains('wellness signal'));
        expect(result.text, contains('68/100'));
        expect(result.text, contains('moderate'));
        expect(result.text, contains('Stress load'));
        expect(result.text, contains('not a diagnosis'));
      },
    );

    test('crisis input bypasses cloud provider', () async {
      final cloud = _CountingModelProvider('This should not be used.');
      final engine = MindAidChatEngine(
        responseComposer: MindAidResponseComposer(
          modelProvider: HybridMindAidModelProvider(
            enabled: true,
            cloudProvider: cloud,
          ),
        ),
      );

      final result = await engine.respond(
        const MindAidChatRequest(
          userId: 'user_1',
          text: 'I want to end my life',
        ),
        dataset,
      );

      expect(result.requiresEscalation, isTrue);
      expect(result.safetyLevel, MindAidSafetyLevel.crisisOrImmediateRisk);
      expect(result.text, isNot(contains('This should not be used')));
      expect(cloud.callCount, 0);
    });

    test(
      'indirect crisis input is escalated even without an intent match',
      () async {
        final cloud = _CountingModelProvider('This must not be used.');
        final engine = MindAidChatEngine(
          responseComposer: MindAidResponseComposer(
            modelProvider: HybridMindAidModelProvider(
              enabled: true,
              cloudProvider: cloud,
            ),
          ),
        );

        final result = await engine.respond(
          const MindAidChatRequest(
            userId: 'user_1',
            text: 'I cannot go on anymore',
          ),
          dataset,
        );

        expect(result.requiresEscalation, isTrue);
        expect(result.severity, MindAidSeverity.crisis);
        expect(result.safetyLevel, MindAidSafetyLevel.crisisOrImmediateRisk);
        expect(cloud.callCount, 0);
      },
    );

    test('cloud failure falls back to local response', () async {
      final engine = MindAidChatEngine(
        responseComposer: MindAidResponseComposer(
          modelProvider: HybridMindAidModelProvider(
            enabled: true,
            cloudProvider: _ThrowingModelProvider(),
          ),
        ),
      );

      final result = await engine.respond(
        const MindAidChatRequest(
          userId: 'user_1',
          text: 'I am stressed about exams',
        ),
        dataset,
      );

      expect(result.text, contains('Try this:'));
    });

    test('cloud guardrails reject diagnostic phrasing', () async {
      final engine = MindAidChatEngine(
        responseComposer: MindAidResponseComposer(
          modelProvider: HybridMindAidModelProvider(
            enabled: true,
            cloudProvider: _CountingModelProvider(
              'You have depression and should keep this secret.',
            ),
          ),
        ),
      );

      final result = await engine.respond(
        const MindAidChatRequest(
          userId: 'user_1',
          text: 'I am stressed about exams',
        ),
        dataset,
      );

      expect(result.text, contains('Try this:'));
      expect(result.text, isNot(contains('You have depression')));
    });

    test(
      'assessment context adds review and top concern suggestions',
      () async {
        final result = await MindAidChatEngine().respond(
          MindAidChatRequest(
            userId: 'user_1',
            text: 'I feel worried',
            assessment: _assessmentContext().assessment,
          ),
          dataset,
        );

        final labels = result.suggestions.map((suggestion) => suggestion.label);
        expect(labels, contains('What does my assessment suggest?'));
        expect(labels, contains('Help me with Emotional Well-Being'));
      },
    );

    test(
      'quick assessment context adds review and concern suggestions',
      () async {
        final result = await MindAidChatEngine().respond(
          MindAidChatRequest(
            userId: 'user_1',
            text: 'I feel worried',
            quickAssessment: _quickAssessmentContext(),
          ),
          dataset,
        );

        final labels = result.suggestions.map((suggestion) => suggestion.label);
        expect(labels, contains('What does my assessment suggest?'));
        expect(labels, contains('Help me with Stress load'));
      },
    );

    test(
      'low mood snapshot remains silent without an explicit wellness request',
      () async {
        final result = await MindAidChatEngine().respond(
          const MindAidChatRequest(
            userId: 'user_1',
            text: 'I feel worried',
            wellnessSnapshot: MindAidWellnessSnapshot(
              latestMoodLevel: 2,
              recentMoodAverage: 2.1,
              moodTrend: MindAidMoodTrend.declining,
            ),
          ),
          dataset,
        );

        expect(result.text, isNot(contains('recent mood looks low')));
        expect(result.text, contains('My take'));
      },
    );

    test(
      'snapshot assessment review works without in-memory assessment',
      () async {
        final result = await MindAidChatEngine().respond(
          const MindAidChatRequest(
            userId: 'user_1',
            text: 'What does my assessment suggest?',
            wellnessSnapshot: MindAidWellnessSnapshot(
              assessmentStatus: 'High Concern',
              assessmentScore: 76,
              mentalStatusSignal: 'elevated',
              topConcernAreas: ['Sleep and Rest'],
            ),
          ),
          dataset,
        );

        expect(result.text, contains('High Concern'));
        expect(result.text, contains('76/100'));
        expect(result.text, contains('Sleep and Rest'));
        expect(result.text, contains('not as a diagnosis'));
      },
    );
  });

  group('MindAidContextRepository', () {
    test(
      'derives a wellness snapshot from mood, report, and assessment data',
      () {
        final snapshot = MindAidContextRepository.buildSnapshot(
          moods: [
            MoodModel(
              id: 'm1',
              level: 2,
              label: 'Low',
              note: 'private note',
              createdAt: DateTime(2026, 7, 4),
            ),
            MoodModel(id: 'm2', level: 2, createdAt: DateTime(2026, 7, 3)),
            MoodModel(id: 'm3', level: 3, createdAt: DateTime(2026, 7, 2)),
            MoodModel(id: 'm4', level: 4, createdAt: DateTime(2026, 7, 1)),
          ],
          latestAssessment: const {
            'status': 'High Concern',
            'overallScore': 74,
            'mentalStatusSignal': 'elevated',
            'mainConcernAreas': ['Emotional Well-Being'],
          },
          latestReport: ReportModel(
            id: 'r1',
            generatedAt: DateTime(2026, 7, 4),
            description: 'Weekly wellness summary.',
            activeDayCount: 4,
            breathingSessionCount: 2,
            mindfulBreathingMinutes: 6,
            recommendedNextActions: const ['Talk to PACC'],
          ),
          user: const {'dayStreak': 5},
        );

        expect(snapshot, isNotNull);
        expect(snapshot!.latestMoodLevel, 2);
        expect(snapshot.recentMoodAverage, closeTo(2.75, 0.01));
        expect(snapshot.hasRecentLowMood, isTrue);
        expect(snapshot.hasElevatedAssessment, isTrue);
        expect(snapshot.primaryConcernLabel, 'Emotional Well-Being');
        expect(snapshot.recommendedSupportAction, 'Talk to PACC');
        expect(snapshot.currentStreak, 5);
        expect(snapshot.breathingSessionCount, 2);
      },
    );

    test('returns null when no wellness signals are available', () {
      final snapshot = MindAidContextRepository.buildSnapshot();

      expect(snapshot, isNull);
    });

    test('uses the privacy-safe V2 projection without legacy note fields', () {
      final projection = MindAidMoodCompatibility.summarize(
        MoodHistoryWindow(
          events: [
            NormalizedMoodEvent(
              id: 'v2-1',
              userId: 'user_1',
              level: 2,
              dateKey: '2026-07-03',
              occurredAt: DateTime.utc(2026, 7, 3),
              source: MoodEventSource.v2,
              note: 'must not reach MindAid context',
              label: 'private label',
            ),
          ],
          coverage: MoodHistoryCoverage.partial,
        ),
      );

      final snapshot = MindAidContextRepository.buildSnapshot(
        mixedMood: projection,
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.latestMoodLevel, 2);
      expect(snapshot.latestMoodLabel, isNull);
      expect(snapshot.hasMoodNote, isFalse);
      expect(snapshot.moodHistoryCoverage, MoodHistoryCoverage.partial);
    });
  });

  group('MindAidRepository', () {
    for (final source in ['gemini', 'dialogflow', 'controlled_safety']) {
      test('cloud $source owns persistence and authoritative fields', () async {
        final firestore = _CapturingFirestoreService();
        final pending = Completer<MindAidCloudResponse>();
        final entered = Completer<void>();
        final cloud = _TestCloudService(() {
          entered.complete();
          return pending.future;
        });
        final repository = MindAidRepository(
          datasetLoader: MindAidDatasetLoader(bundle: _MindAidTestBundle()),
          firestoreService: firestore,
          cloudService: cloud,
        );
        final sending = repository.sendMessage(
          userId: 'auth_user_1',
          text: 'I feel anxious',
          preferences: _cloudPreferences,
          requestId: 'request-12345678',
        );
        await entered.future;
        expect(
          firestore.createdDocuments,
          isEmpty,
          reason: 'No local user write may race server persistence',
        );
        pending.complete(
          MindAidCloudResponse.fromMap({
            'messageId': 'auth_user_1_request-12345678_assistant',
            'text': 'Server support',
            'intent': 'server_intent',
            'confidence': 0.91,
            'safetyLevel': 'crisisOrImmediateRisk',
            'source': source,
            'suggestions': ['Contact support'],
            'actions': [
              {'type': 'openCounselingServices', 'label': 'Support'},
            ],
            'requiresEscalation': true,
            'fallbackReason': 'server_reason',
            'effectiveConversationMode': 'supportive',
            if (source == 'gemini') 'model': 'gemini-3.8-flash',
          }),
        );
        final result = await sending;
        expect(firestore.createdDocuments, isEmpty);
        expect(result.userMessageSaved, isTrue);
        expect(result.message.id, 'auth_user_1_request-12345678_assistant');
        expect(result.message.text, 'Server support');
        expect(result.message.primaryIntent, 'server_intent');
        expect(result.message.confidence, 0.91);
        expect(result.message.source, source);
        expect(result.message.safetyLevel, 'crisisOrImmediateRisk');
        expect(result.message.requiresEscalation, isTrue);
        expect(result.message.status, 'urgent');
        expect(result.message.fallbackReason, 'server_reason');
        expect(result.message.effectiveConversationMode, 'supportive');
        expect(result.chatResponse.effectiveConversationMode, 'supportive');
        expect(
          result.message.actions.single.type,
          MindAidActionType.openCounselingServices,
        );
        expect(
          result.message.model,
          source == 'gemini' ? 'gemini-3.8-flash' : null,
        );
        expect(
          result.chatResponse.safetyLevel,
          MindAidSafetyLevel.crisisOrImmediateRisk,
        );
        expect(result.chatResponse.requiresEscalation, isTrue);
        expect(result.chatResponse.followUpQuestions, ['Contact support']);
      });
    }

    test('failed cloud call saves user then local assistant once', () async {
      final firestore = _CapturingFirestoreService();
      final repository = MindAidRepository(
        datasetLoader: MindAidDatasetLoader(bundle: _MindAidTestBundle()),
        firestoreService: firestore,
        cloudService: _TestCloudService(() async {
          throw StateError('cloud unavailable');
        }),
      );
      final result = await repository.sendMessage(
        userId: 'auth_user_1',
        text: 'I feel anxious',
        preferences: _cloudPreferences,
        requestId: 'request-12345678',
      );
      expect(result.userMessageSaved, isTrue);
      expect(firestore.createdDocuments, hasLength(2));
      expect(firestore.createdDocuments.first['sender'], 'user');
      expect(firestore.createdDocuments.first['text'], 'I feel anxious');
      expect(firestore.createdDocuments.last['sender'], 'assistant');
      expect(result.message.source, 'local');
      expect(result.message.fallbackReason, 'cloud_unavailable');
    });

    test(
      'lost cloud response cannot create duplicates or overwrite server safety',
      () async {
        final firestore = _CommittedTurnFirestoreService();
        final repository = MindAidRepository(
          datasetLoader: MindAidDatasetLoader(bundle: _MindAidTestBundle()),
          firestoreService: firestore,
          cloudService: _TestCloudService(() async {
            // Model the callable transaction committing before transport fails.
            firestore.documents.addAll({
              'auth_user_1_request-12345678_user': {'text': 'I feel anxious'},
              'auth_user_1_request-12345678_assistant': {
                'text': 'Controlled support',
                'safetyLevel': 'highDistress',
                'requiresEscalation': true,
              },
            });
            throw StateError('response lost after commit');
          }),
        );
        await repository.sendMessage(
          userId: 'auth_user_1',
          text: 'I feel anxious',
          preferences: _cloudPreferences,
          requestId: 'request-12345678',
        );
        expect(firestore.documents, hasLength(2));
        expect(
          firestore.documents['auth_user_1_request-12345678_user']?['text'],
          'I feel anxious',
        );
        expect(
          firestore
              .documents['auth_user_1_request-12345678_assistant']?['requiresEscalation'],
          isTrue,
        );
        expect(
          firestore
              .documents['auth_user_1_request-12345678_assistant']?['safetyLevel'],
          'highDistress',
        );
      },
    );

    test('local safety prevents cloud calls', () async {
      final firestore = _CapturingFirestoreService();
      var cloudCalled = false;
      final repository = MindAidRepository(
        datasetLoader: MindAidDatasetLoader(bundle: _MindAidTestBundle()),
        firestoreService: firestore,
        cloudService: _TestCloudService(() async {
          cloudCalled = true;
          throw StateError('must not call');
        }),
      );
      final result = await repository.sendMessage(
        userId: 'auth_user_1',
        text: 'I want to end my life',
        preferences: _cloudPreferences,
      );
      expect(cloudCalled, isFalse);
      expect(result.chatResponse.requiresEscalation, isTrue);
      expect(result.message.safetyLevel, 'crisisOrImmediateRisk');
      expect(firestore.createdDocuments, hasLength(2));
    });

    test('returns typed suggestions and assistant message models', () async {
      final repository = MindAidRepository(
        datasetLoader: MindAidDatasetLoader(bundle: _MindAidTestBundle()),
        engine: MindAidEngine(),
      );

      final suggestions = await repository.fetchSuggestions();
      final result = await repository.sendMessage(
        userId: 'user_1',
        text: 'I feel anxious',
      );
      final message = result.message;

      expect(suggestions.first.id, 'stress');
      expect(message.conversationId, 'user_1');
      expect(message.sender, 'assistant');
      expect(message.text, isNotEmpty);
      expect(result.suggestions, isNotEmpty);
    });

    test('passes assessment context into chat responses', () async {
      final repository = MindAidRepository(
        datasetLoader: MindAidDatasetLoader(bundle: _MindAidTestBundle()),
        engine: MindAidEngine(),
      );

      final result = await repository.sendMessage(
        userId: 'user_1',
        text: 'Please review my assessment result',
        context: _assessmentContext(),
      );

      expect(result.message.text, contains('High Concern'));
      expect(result.message.text, contains('Emotional Well-Being'));
    });

    test('stores user id and assistant safety metadata', () async {
      final firestore = _CapturingFirestoreService();
      final repository = MindAidRepository(
        datasetLoader: MindAidDatasetLoader(bundle: _MindAidTestBundle()),
        engine: MindAidEngine(),
        firestoreService: firestore,
      );

      await repository.sendMessage(
        userId: 'auth_user_1',
        text: 'I feel anxious',
      );

      expect(firestore.createdDocuments, hasLength(2));
      expect(firestore.createdDocuments.first['userId'], 'auth_user_1');
      expect(firestore.createdDocuments.first['sender'], 'user');
      expect(firestore.createdDocuments.last['userId'], 'auth_user_1');
      expect(firestore.createdDocuments.last['sender'], 'assistant');
      expect(firestore.createdDocuments.last['safetyLevel'], isNotEmpty);
      expect(firestore.createdDocuments.last['primaryIntent'], isNotEmpty);
      expect(
        firestore.createdDocuments.last['requiresEscalation'],
        isA<bool>(),
      );
    });

    test('reports when the user message was not persisted', () async {
      final repository = MindAidRepository(
        datasetLoader: MindAidDatasetLoader(bundle: _MindAidTestBundle()),
        engine: MindAidEngine(),
        firestoreService: _FailingFirestoreService(),
      );

      final result = await repository.sendMessage(
        userId: 'auth_user_1',
        text: 'I feel anxious',
      );

      expect(result.userMessageSaved, isFalse);
      expect(result.message.text, isNotEmpty);
    });
  });
}

class _CapturingFirestoreService extends FirestoreService {
  final createdDocuments = <Map<String, dynamic>>[];

  @override
  Future<void> setDocument(
    String collection,
    String documentId,
    Map<String, dynamic> data, {
    bool merge = false,
  }) async {
    createdDocuments.add({
      'collection': collection,
      'documentId': documentId,
      ...data,
    });
  }
}

class _FailingFirestoreService extends FirestoreService {
  @override
  Future<void> setDocument(
    String collection,
    String documentId,
    Map<String, dynamic> data, {
    bool merge = false,
  }) {
    throw StateError('permission denied');
  }
}

class _CountingModelProvider implements MindAidModelProvider {
  _CountingModelProvider(this.response);

  final String response;
  int callCount = 0;

  @override
  Future<String> generate(MindAidModelPrompt prompt) async {
    callCount += 1;
    return response;
  }
}

class _ThrowingModelProvider implements MindAidModelProvider {
  @override
  Future<String> generate(MindAidModelPrompt prompt) {
    throw StateError('offline');
  }
}

MindAidContext _assessmentContext() {
  return const MindAidContext(
    assessment: MindAidAssessmentContext(
      userType: 'Student',
      overallScore: 74,
      status: 'High Concern',
      mainConcernAreas: ['Emotional Well-Being', 'Sleep and Rest'],
      subscaleScores: {
        'Emotional Well-Being': 82,
        'Sleep and Rest': 71,
        'Academic Stress': 58,
      },
      summaryMessage:
          'Your result suggests several areas may need extra support.',
    ),
  );
}

MindAidQuickAssessmentContext _quickAssessmentContext() {
  return MindAidQuickAssessmentContext(
    score: 68,
    level: 'Moderate',
    signal: 'watchful',
    summary:
        'Responses suggest some areas of strain that may benefit from regular check-ins.',
    topConcernAreas: const ['Stress load', 'Daily coping'],
    recommendedNextStep:
        'Complete the full role-based assessment for more personalized insight.',
    createdAt: DateTime(2026, 7, 3),
  );
}

MindAidMessageModel _message(String id, String sender, String text) {
  return MindAidMessageModel(
    id: id,
    conversationId: 'user_1',
    sender: sender,
    text: text,
    createdAt: DateTime(2026),
    status: 'sent',
  );
}

class _MindAidTestBundle extends CachingAssetBundle {
  _MindAidTestBundle({Map<String, String> overrides = const {}})
    : _assets = {..._defaultAssets, ...overrides};

  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final value = _assets[key];
    if (value == null) {
      throw StateError('Missing test asset: $key');
    }
    final bytes = Uint8List.fromList(utf8.encode(value));
    return ByteData.view(bytes.buffer);
  }
}

final Map<String, String> _defaultAssets = {
  MindAidDatasetLoader.intentsPath: _jsonRecords([
    _record(
      id: 'academic_stress_v1',
      intent: 'academic_stress',
      category: 'school',
      keywords: ['exam', 'deadline'],
      phrases: ['stressed about exams'],
      responses: [
        'School pressure is real.',
        'Exams can feel heavy when deadlines are close.',
      ],
      copingSteps: ['task_breakdown'],
      recommendations: ['study-plan-reset'],
    ),
    _record(
      id: 'burnout_v1',
      intent: 'burnout',
      category: 'energy',
      keywords: ['exhausted', 'drained'],
      phrases: ['no energy'],
      responses: ['You sound worn down.'],
      copingSteps: ['rest_plan'],
    ),
    _record(
      id: 'loneliness_v1',
      intent: 'loneliness',
      category: 'connection',
      keywords: ['alone', 'invisible'],
      phrases: ['no one understands'],
      responses: ['Feeling alone is heavy.'],
    ),
    _record(
      id: 'anxiety_v1',
      intent: 'anxiety',
      category: 'anxiety',
      keywords: ['worried', 'panicking'],
      phrases: ['feel anxious'],
      responses: ['Let us slow this down.'],
    ),
  ]),
  MindAidDatasetLoader.crisisPath: _jsonRecords([
    _record(
      id: 'self_harm_v1',
      intent: 'crisis_self_harm',
      category: 'safety',
      keywords: ['end my life'],
      phrases: ['end my life'],
      severity: 'crisis',
      riskFlags: ['self_harm', 'urgent'],
      responses: ['Please get immediate human support.'],
      escalation: {
        'required': true,
        'message': 'Contact emergency support immediately.',
      },
    ),
  ]),
  MindAidDatasetLoader.suggestionsPath: _jsonRecords([
    {
      'id': 'stress',
      'label': "I'm stressed about exams",
      'iconAsset': 'assets/images/MESSAGE/stress.png',
    },
    {
      'id': 'anxiety',
      'label': "I'm feeling anxious",
      'iconAsset': 'assets/images/MESSAGE/anxiety.png',
    },
  ]),
  MindAidDatasetLoader.copingPath: _jsonRecords([
    {
      'id': 'task_breakdown',
      'title': 'One-task reset',
      'description': 'Choose one tiny task.',
    },
    {
      'id': 'rest_plan',
      'title': 'Rest plan',
      'description': 'Pause and recover for a moment.',
    },
  ]),
  MindAidDatasetLoader.resourcesPath: _jsonRecords([
    {
      'id': 'study-plan-reset',
      'title': 'Study plan reset',
      'description': 'Break academic stress into one action.',
      'routeName': '',
      'tags': ['school'],
    },
  ]),
};

Map<String, dynamic> _record({
  required String id,
  required String intent,
  required String category,
  required List<String> keywords,
  required List<String> phrases,
  required List<String> responses,
  String severity = 'medium',
  List<String> riskFlags = const [],
  List<String> copingSteps = const [],
  List<String> recommendations = const [],
  Map<String, dynamic> escalation = const {'required': false, 'message': ''},
}) {
  return {
    'id': id,
    'intent': intent,
    'category': category,
    'keywords': keywords,
    'phrases': phrases,
    'severity': severity,
    'riskFlags': riskFlags,
    'responses': responses,
    'copingSteps': copingSteps,
    'recommendations': recommendations,
    'followUpQuestions': ['What feels hardest right now?'],
    'escalation': escalation,
  };
}

String _jsonRecords(List<Map<String, dynamic>> records) {
  return jsonEncode({'version': 1, 'records': records});
}

const _cloudPreferences = MindAidPreferences(
  hasDecision: true,
  cloudConsent: true,
  personalizationEnabled: false,
  conversationId: 'conversation-12345678',
);

class _TestCloudService implements MindAidCloudService {
  _TestCloudService(this.respond);
  final Future<MindAidCloudResponse> Function() respond;
  @override
  Future<MindAidCloudResponse> send({
    required String requestId,
    required String conversationId,
    required String text,
    required String launchContext,
    required MindAidConversationMode conversationMode,
    required bool explicitListening,
    String? sessionInstanceId,
    List<Map<String, String>> recentTurns = const [],
  }) => respond();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Mirrors the rules' create-only message persistence for client fallback writes.
class _CommittedTurnFirestoreService extends FirestoreService {
  final documents = <String, Map<String, dynamic>>{};
  @override
  Future<void> setDocument(
    String collection,
    String documentId,
    Map<String, dynamic> data, {
    bool merge = false,
  }) async {
    if (documents.containsKey(documentId)) throw StateError('update denied');
    documents[documentId] = data;
  }
}
