import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../features/mind_aid/ai_engine/mind_aid_chat_engine.dart';
import '../features/mind_aid/ai_engine/mind_aid_engine.dart';
import '../features/mind_aid/ai_engine/mind_aid_safety_classifier.dart';
import '../features/mind_aid/ai_engine/score_engine.dart';
import '../features/mind_aid/data/mind_aid_dataset_loader.dart';
import '../features/mind_aid/domain/mind_aid_chat_models.dart';
import '../features/mind_aid/domain/mind_aid_context.dart';
import '../features/mind_aid/domain/mind_aid_engine_result.dart';
import '../features/mind_aid/domain/mind_aid_integration_models.dart';
import '../features/mind_aid/domain/mind_aid_dataset_models.dart';
import '../features/mind_aid/domain/mind_aid_safety.dart';
import '../models/mind_aid_message_model.dart';
import '../models/mind_aid_suggestion_model.dart';
import '../services/firebase/firestore_service.dart';
import '../services/firebase/mind_aid_cloud_service.dart';

class MindAidSendResult {
  const MindAidSendResult({
    required this.message,
    required this.suggestions,
    required this.chatResponse,
    required this.userMessageSaved,
  });

  final MindAidMessageModel message;
  final List<MindAidSuggestionModel> suggestions;
  final MindAidChatResponse chatResponse;
  final bool userMessageSaved;
}

class MindAidRepository {
  MindAidRepository({
    MindAidDatasetLoader? datasetLoader,
    MindAidEngine? engine,
    MindAidChatEngine? chatEngine,
    FirestoreService? firestoreService,
    MindAidCloudService? cloudService,
  }) : _datasetLoader = datasetLoader ?? MindAidDatasetLoader(),
       _engine = engine ?? MindAidEngine(),
       _chatEngine = chatEngine ?? MindAidChatEngine(),
       _firestoreService = firestoreService ?? FirestoreService(),
       _cloudServiceOverride = cloudService;

  final MindAidDatasetLoader _datasetLoader;
  final MindAidEngine _engine;
  final MindAidChatEngine _chatEngine;
  final FirestoreService _firestoreService;
  final MindAidCloudService? _cloudServiceOverride;
  MindAidCloudService? _createdCloudService;

  MindAidCloudService get _cloudService =>
      _cloudServiceOverride ?? (_createdCloudService ??= MindAidCloudService());

  void resetSession() {
    _engine.resetSession();
    _chatEngine.resetSession();
  }

  Future<MindAidPreferences> loadPreferences(String userId) async {
    if (userId.isEmpty || userId == 'guest') {
      return MindAidPreferences(
        hasDecision: true,
        cloudConsent: false,
        personalizationEnabled: false,
        conversationId: MindAidCloudService.createConversationId(),
      );
    }
    try {
      final preferences = await _cloudService.loadPreferences(userId);
      if (preferences.conversationId.isNotEmpty) return preferences;
      if (!preferences.hasDecision) {
        return MindAidPreferences(
          hasDecision: false,
          cloudConsent: false,
          personalizationEnabled: false,
          conversationId: userId,
        );
      }
      return _cloudService.saveConsent(
        userId: userId,
        cloudConsent: preferences.cloudConsent,
        personalizationEnabled: preferences.personalizationEnabled,
      );
    } catch (_) {
      return MindAidPreferences(
        hasDecision: false,
        cloudConsent: false,
        personalizationEnabled: false,
        conversationId: userId,
      );
    }
  }

  Future<MindAidPreferences> saveConsent({
    required String userId,
    required bool cloudConsent,
    required bool personalizationEnabled,
    String? conversationId,
  }) {
    return _cloudService.saveConsent(
      userId: userId,
      cloudConsent: cloudConsent,
      personalizationEnabled: personalizationEnabled,
      existingConversationId: conversationId,
    );
  }

  Future<void> clearHistory(String userId) =>
      _cloudService.clearHistory(userId);

  Future<String> startNewConversation(String userId) =>
      _cloudService.startNewConversation(userId);

  Future<void> submitFeedback({
    required String userId,
    required String messageId,
    required bool helpful,
  }) => _cloudService.submitFeedback(
    userId: userId,
    messageId: messageId,
    helpful: helpful,
  );

  Future<List<MindAidMessageModel>> fetchMessages(
    String userId, {
    String? conversationId,
  }) async {
    try {
      final docs = await _firestoreService.getDocuments(
        FirestoreCollections.mindAidMessages,
        whereEquals: {
          'userId': userId,
          if (conversationId?.trim().isNotEmpty == true)
            'conversationId': conversationId!.trim(),
        },
        orderBy: 'createdAt',
        descending: false,
        limit: 50,
      );
      return docs
          .map((doc) => MindAidMessageModel.fromMap(doc))
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  Future<MindAidSendResult> sendMessage({
    required String userId,
    required String text,
    List<MindAidMessageModel> recentMessages = const [],
    MindAidContext context = const MindAidContext(),
    MindAidPreferences? preferences,
    String launchContext = '',
    String? requestId,
  }) async {
    final dataset = await _datasetLoader.load();
    final effectiveRequestId = requestId ?? _requestId();
    final conversationId = preferences?.conversationId.trim().isNotEmpty == true
        ? preferences!.conversationId
        : userId;
    final analysis = _engine.process(text, dataset, context: context);
    final safety = const MindAidSafetyClassifier().classify(
      normalizedInput: ScoreEngine.normalize(text),
      matches: const [],
    );
    final isHighRisk =
        safety.level.blocksCloud ||
        analysis.requiresEscalation ||
        analysis.severity == MindAidSeverity.high ||
        analysis.severity == MindAidSeverity.crisis;

    if (!isHighRisk &&
        userId != 'guest' &&
        preferences?.cloudConsent == true &&
        await _cloudService.isCloudEnabled()) {
      try {
        final cloud = await _cloudService.send(
          requestId: effectiveRequestId,
          conversationId: conversationId,
          text: text,
          launchContext: launchContext,
        );
        final safety = MindAidSafetyLevel.values.firstWhere(
          (item) => item.name == cloud.safetyLevel,
          orElse: () => MindAidSafetyLevel.safeSupport,
        );
        final response = MindAidChatResponse(
          text: cloud.text,
          intentMatches: const [],
          severity: cloud.requiresEscalation
              ? MindAidSeverity.high
              : MindAidSeverity.low,
          suggestions: cloud.suggestions
              .asMap()
              .entries
              .map(
                (entry) => MindAidSuggestionModel(
                  id: 'cx_${entry.key}_${entry.value.hashCode.abs()}',
                  label: entry.value,
                ),
              )
              .toList(growable: false),
          followUpQuestions: const [],
          recommendations: const [],
          requiresEscalation: cloud.requiresEscalation,
          conversationState: const MindAidConversationState(),
          status: cloud.requiresEscalation ? 'urgent' : 'sent',
          safetyLevel: safety,
          intentOverride: cloud.intent,
          source: cloud.source,
          confidence: cloud.confidence,
          fallbackReason: cloud.fallbackReason,
          actions: cloud.actions,
        );
        final message = MindAidMessageModel(
          id: cloud.messageId,
          conversationId: conversationId,
          sender: 'assistant',
          text: cloud.text,
          createdAt: DateTime.now(),
          status: response.status,
          safetyLevel: cloud.safetyLevel,
          primaryIntent: cloud.intent,
          requiresEscalation: cloud.requiresEscalation,
          source: cloud.source,
          confidence: cloud.confidence,
          fallbackReason: cloud.fallbackReason,
          actions: cloud.actions,
        );
        return MindAidSendResult(
          message: message,
          suggestions: response.suggestions,
          chatResponse: response,
          userMessageSaved: true,
        );
      } catch (_) {
        // The local engine below is the reliable fallback for rollout, network,
        // quota, permission, and Dialogflow response failures.
      }
    }

    final userMessageSaved = await _trySaveMessage(
      userId: userId,
      message: MindAidMessageModel(
        id: '${effectiveRequestId}_user',
        conversationId: conversationId,
        sender: 'user',
        text: text,
        createdAt: DateTime.now(),
        status: 'sent',
      ),
    );

    final result = await _chatEngine.respond(
      MindAidChatRequest(
        userId: userId,
        text: text,
        recentMessages: recentMessages,
        moodLevel: context.moodLevel,
        assessmentScore: context.effectiveAssessmentScore,
        quickAssessment: context.quickAssessment,
        assessment: context.assessment,
        conversationSummary: context.conversationSummary,
        preferredSupportStyle: context.preferredSupportStyle,
        journalText: context.journalText,
        wellnessSnapshot: context.wellnessSnapshot,
      ),
      dataset,
    );

    final message = MindAidMessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: conversationId,
      sender: 'assistant',
      text: result.text,
      createdAt: DateTime.now(),
      status: result.status,
      safetyLevel: result.safetyLevel.name,
      primaryIntent: result.primaryIntent,
      requiresEscalation: result.requiresEscalation,
      source: 'local',
      fallbackReason: preferences?.cloudConsent == true
          ? 'cloud_unavailable'
          : '',
    );

    await _trySaveMessage(userId: userId, message: message);

    return MindAidSendResult(
      message: message,
      suggestions: result.suggestions,
      chatResponse: result,
      userMessageSaved: userMessageSaved,
    );
  }

  String _requestId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'req_${now}_${identityHashCode(this).toRadixString(36)}';
  }

  Future<MindAidEngineResult> analyzeMessage({
    required String text,
    MindAidContext context = const MindAidContext(),
  }) async {
    final dataset = await _datasetLoader.load();
    return _engine.process(text, dataset, context: context);
  }

  Future<List<MindAidSuggestionModel>> fetchSuggestions() async {
    final dataset = await _datasetLoader.load();
    return dataset.suggestions;
  }

  Future<void> _saveMessage({
    required String userId,
    required MindAidMessageModel message,
  }) {
    return _firestoreService.setDocument(
      FirestoreCollections.mindAidMessages,
      message.id,
      {
        'userId': userId,
        ...message.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<bool> _trySaveMessage({
    required String userId,
    required MindAidMessageModel message,
  }) async {
    try {
      await _saveMessage(userId: userId, message: message);
      return true;
    } catch (_) {
      // Chat support remains available even while backend persistence is being
      // configured.
      return false;
    }
  }
}
