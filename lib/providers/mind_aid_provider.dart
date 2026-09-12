import 'package:flutter/material.dart';

import '/features/counseling/screens/mind_aid_screen.dart';
import '/features/mind_aid/domain/mind_aid_context.dart';
import '/features/mind_aid/domain/mind_aid_integration_models.dart';
import '/features/mind_aid/domain/mind_aid_safety.dart';
import '/models/mind_aid_message_model.dart';
import '/models/mind_aid_suggestion_model.dart';
import '/repositories/mind_aid_repository_screen.dart';

class MindAidAnalyticsSnapshot {
  const MindAidAnalyticsSnapshot({
    required this.selectedSuggestionCount,
    required this.highRiskTriggerCount,
    required this.fallbackCount,
    required this.commonIntentCounts,
  });

  final int selectedSuggestionCount;
  final int highRiskTriggerCount;
  final int fallbackCount;
  final Map<String, int> commonIntentCounts;
}

class MindAidProvider extends ChangeNotifier {
  final MindAidRepository repository;

  MindAidProvider(this.repository);

  List<MindAidMessage> messages = [];
  List<MindAidSuggestion> suggestions = [];

  bool isLoading = false;
  bool isSending = false;
  String? errorMessage;
  String? _conversationSummary;
  MindAidPreferences? _preferences;
  MindAidLaunchContext? _launchContext;
  String? _lastFailedText;
  String? _sessionUserId;
  bool _lastUserMessagePersisted = false;
  int _selectedSuggestionCount = 0;
  int _highRiskTriggerCount = 0;
  int _fallbackCount = 0;
  final Map<String, int> _commonIntentCounts = {};

  MindAidAnalyticsSnapshot get analytics => MindAidAnalyticsSnapshot(
    selectedSuggestionCount: _selectedSuggestionCount,
    highRiskTriggerCount: _highRiskTriggerCount,
    fallbackCount: _fallbackCount,
    commonIntentCounts: Map.unmodifiable(_commonIntentCounts),
  );
  bool get lastUserMessagePersisted => _lastUserMessagePersisted;
  MindAidPreferences? get preferences => _preferences;
  bool get needsConsent => _preferences != null && !_preferences!.hasDecision;
  bool get usesDialogflow => _preferences?.cloudConsent == true;
  String? get lastFailedText => _lastFailedText;

  Future<void> loadChat(
    String userId, {
    MindAidContext context = const MindAidContext(),
    MindAidLaunchContext? launchContext,
  }) async {
    _launchContext = launchContext ?? _launchContext;
    errorMessage = null;
    if (_sessionUserId != userId) {
      repository.resetSession();
      _sessionUserId = userId;
    }
    final effectiveContext = _contextWithSessionMemory(context);
    isLoading = true;
    notifyListeners();

    try {
      _preferences = await repository.loadPreferences(userId);
      final results = await Future.wait([
        repository.fetchMessages(
          userId,
          conversationId: _preferences?.conversationId,
        ),
        repository.fetchSuggestions(),
      ]);
      final msgResult = results[0] as List<MindAidMessageModel>;
      final sugResult = results[1] as List<MindAidSuggestionModel>;

      messages = msgResult
          .map(
            (e) => MindAidMessage(
              id: e.id,
              sender: e.sender == "user"
                  ? MindAidSender.user
                  : MindAidSender.assistant,
              text: e.text,
              createdAt: e.createdAt,
              status: e.status,
              categoryLabel: null,
              supportCards: const [],
              actions: e.actions,
              source: e.source,
            ),
          )
          .toList();

      suggestions = _suggestionsWithAssessmentReview(
        sugResult
            .map(
              (e) => MindAidSuggestion(
                id: e.id,
                label: e.label,
                iconAsset: e.iconAsset,
              ),
            )
            .toList(growable: false),
        effectiveContext,
      );
      final openingPrompt = _launchContext?.openingPrompt?.trim();
      if (openingPrompt != null &&
          openingPrompt.isNotEmpty &&
          !suggestions.any((item) => item.label == openingPrompt)) {
        suggestions = [
          MindAidSuggestion(id: 'launch_context', label: openingPrompt),
          ...suggestions,
        ].take(5).toList(growable: false);
      }
    } catch (e) {
      errorMessage = 'MindAid could not load this conversation.';
    }

    isLoading = false;
    notifyListeners();
  }

  Future<bool> sendMessage(
    String userId,
    String text, {
    MindAidContext context = const MindAidContext(),
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty || trimmedText.length > 1200 || isSending) {
      return false;
    }
    final effectiveContext = _contextWithSessionMemory(context);
    isSending = true;
    _lastUserMessagePersisted = false;
    notifyListeners();

    try {
      _lastFailedText = null;
      final userMessage = MindAidMessage(
        id: DateTime.now().toString(),
        sender: MindAidSender.user,
        text: trimmedText,
        createdAt: DateTime.now(),
        status: "sent",
      );

      messages.add(userMessage);
      notifyListeners();

      final recentMessages = messages
          .map((message) {
            return message.toModel(
              conversationId: _preferences?.conversationId ?? userId,
            );
          })
          .toList(growable: false);
      final result = await repository.sendMessage(
        userId: userId,
        text: trimmedText,
        recentMessages: recentMessages,
        context: effectiveContext,
        preferences: _preferences,
        launchContext: _launchContext?.source ?? '',
      );
      final bot = result.message;

      final botMessage = MindAidMessage(
        id: bot.id,
        sender: MindAidSender.assistant,
        text: bot.text,
        createdAt: bot.createdAt,
        status: bot.status,
        categoryLabel: _categoryLabelFor(result),
        supportCards: _supportCardsFor(result, context),
        actions: _actionsFor(result),
        source: result.chatResponse.source,
      );

      messages.add(botMessage);
      suggestions = _suggestionsWithAssessmentReview(
        result.suggestions
            .map(
              (suggestion) => MindAidSuggestion(
                id: suggestion.id,
                label: suggestion.label,
                iconAsset: suggestion.iconAsset,
              ),
            )
            .toList(growable: false),
        effectiveContext,
      );
      _trackChatResult(result);
      _lastUserMessagePersisted = result.userMessageSaved;
      _conversationSummary = _summarizeConversation();
      isSending = false;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'MindAid could not send that message. Please try again.';
      _fallbackCount += 1;
      _lastFailedText = trimmedText;
      final index = messages.lastIndexWhere(
        (message) => message.sender == MindAidSender.user,
      );
      if (index >= 0) {
        final failed = messages[index];
        messages[index] = MindAidMessage(
          id: failed.id,
          sender: failed.sender,
          text: failed.text,
          createdAt: failed.createdAt,
          status: 'failed',
        );
      }
    }

    isSending = false;
    notifyListeners();
    return false;
  }

  Future<bool> retryLastMessage(
    String userId, {
    MindAidContext context = const MindAidContext(),
  }) async {
    final text = _lastFailedText;
    if (text == null || text.isEmpty) return false;
    final index = messages.lastIndexWhere(
      (message) =>
          message.sender == MindAidSender.user && message.status == 'failed',
    );
    if (index >= 0) messages.removeAt(index);
    return sendMessage(userId, text, context: context);
  }

  Future<void> setConsent({
    required String userId,
    required bool cloudConsent,
  }) async {
    _preferences = await repository.saveConsent(
      userId: userId,
      cloudConsent: cloudConsent,
      personalizationEnabled: cloudConsent,
      conversationId: _preferences?.conversationId,
    );
    notifyListeners();
  }

  Future<void> clearHistory(String userId) async {
    await repository.clearHistory(userId);
    repository.resetSession();
    messages = [];
    _conversationSummary = null;
    _lastFailedText = null;
    _preferences = await repository.loadPreferences(userId);
    notifyListeners();
  }

  Future<void> startNewConversation(String userId) async {
    final nextId = await repository.startNewConversation(userId);
    repository.resetSession();
    final current = _preferences;
    _preferences = MindAidPreferences(
      hasDecision: current?.hasDecision ?? true,
      cloudConsent: current?.cloudConsent ?? false,
      personalizationEnabled: current?.personalizationEnabled ?? false,
      conversationId: nextId,
      consentVersion: current?.consentVersion,
    );
    messages = [];
    _conversationSummary = null;
    _lastFailedText = null;
    notifyListeners();
  }

  Future<void> submitFeedback({
    required String userId,
    required String messageId,
    required bool helpful,
  }) => repository.submitFeedback(
    userId: userId,
    messageId: messageId,
    helpful: helpful,
  );

  Future<bool> selectSuggestion(
    MindAidSuggestion suggestion,
    String userId, {
    MindAidContext context = const MindAidContext(),
  }) {
    _selectedSuggestionCount += 1;
    return sendMessage(
      userId,
      suggestion.label,
      context: _contextWithSessionMemory(context),
    );
  }

  void _trackChatResult(MindAidSendResult result) {
    final response = result.chatResponse;
    if (response.safetyLevel == MindAidSafetyLevel.highDistress ||
        response.safetyLevel == MindAidSafetyLevel.crisisOrImmediateRisk) {
      _highRiskTriggerCount += 1;
    }

    final intent = response.primaryIntent;
    _commonIntentCounts[intent] = (_commonIntentCounts[intent] ?? 0) + 1;

    if (response.text.trim().isEmpty) {
      _fallbackCount += 1;
    }
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  List<MindAidSuggestion> _suggestionsWithAssessmentReview(
    List<MindAidSuggestion> base,
    MindAidContext context,
  ) {
    if (!context.hasAssessment ||
        base.any((suggestion) => suggestion.id == 'review_assessment')) {
      return base;
    }

    return [
      const MindAidSuggestion(
        id: 'review_assessment',
        label: 'What does my assessment suggest?',
      ),
      ...base,
    ];
  }

  MindAidContext _contextWithSessionMemory(MindAidContext context) {
    return context.copyWith(
      conversationSummary: context.conversationSummary ?? _conversationSummary,
      recentMessages: messages.reversed
          .map((message) => message.text)
          .take(8)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
  }

  String? _summarizeConversation() {
    final userMessages = messages
        .where((message) => message.sender == MindAidSender.user)
        .map((message) => message.text.trim())
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    if (userMessages.isEmpty) return null;

    final latest = userMessages.reversed.take(3).toList().reversed.join(' | ');
    return 'Recent user concerns: $latest';
  }

  List<MindAidSupportCard> _supportCardsFor(
    MindAidSendResult result,
    MindAidContext context,
  ) {
    final cards = <MindAidSupportCard>[];
    final snapshot = context.wellnessSnapshot;

    if (snapshot != null && !result.chatResponse.requiresEscalation) {
      if (snapshot.hasMoodData) {
        final trend = snapshot.moodTrend?.label;
        final average = snapshot.recentMoodAverage;
        cards.add(
          MindAidSupportCard(
            title: 'Mood pattern',
            description: [
              if (snapshot.latestMoodLevel != null)
                'Latest mood: ${snapshot.latestMoodLevel}/5',
              if (average != null)
                'recent average: ${average.toStringAsFixed(1)}/5',
              if (trend != null) 'trend: $trend',
            ].join(', '),
            icon: Icons.mood_rounded,
          ),
        );
      }

      final concern = snapshot.primaryConcernLabel;
      if (concern != null) {
        cards.add(
          MindAidSupportCard(
            title: 'Assessment focus',
            description: concern,
            icon: Icons.insights_rounded,
          ),
        );
      }

      final action = snapshot.recommendedSupportAction;
      if (action != null) {
        cards.add(
          MindAidSupportCard(
            title: 'Suggested next step',
            description: action,
            icon: Icons.flag_rounded,
          ),
        );
      }
    }

    if (context.assessment?.highestCategory case final topConcern?) {
      cards.add(
        MindAidSupportCard(
          title: 'Assessment insight',
          description:
              '${topConcern.key} is one of your higher areas (${topConcern.value.round()}%).',
          icon: Icons.insights_rounded,
        ),
      );
    }

    if (result.chatResponse.requiresEscalation) {
      cards.insert(
        0,
        const MindAidSupportCard(
          title: 'Immediate support',
          description:
              'If there is immediate danger, contact emergency services, campus security, PACC, or a trusted person now.',
          icon: Icons.health_and_safety_rounded,
        ),
      );
    }

    final unique = <String, MindAidSupportCard>{};
    for (final card in cards) {
      unique.putIfAbsent('${card.title}:${card.description}', () => card);
    }
    return unique.values.take(3).toList(growable: false);
  }

  String? _categoryLabelFor(MindAidSendResult result) {
    final matches = result.chatResponse.intentMatches;
    if (matches.isEmpty) return null;

    final raw = matches.first.record.category.trim();
    if (raw.isEmpty) return null;

    return raw.replaceAll('_', ' ').toLowerCase();
  }

  List<MindAidAction> _actionsFor(MindAidSendResult result) {
    if (result.chatResponse.actions.isNotEmpty) {
      return result.chatResponse.actions;
    }
    if (result.chatResponse.requiresEscalation) {
      return const [
        MindAidAction(
          type: MindAidActionType.openCounselingServices,
          label: 'View support services',
        ),
        MindAidAction(
          type: MindAidActionType.bookAppointment,
          label: 'Contact PACC',
        ),
      ];
    }
    final intent = result.chatResponse.primaryIntent.toLowerCase();
    if (intent.contains('breath') || intent.contains('panic')) {
      return const [
        MindAidAction(
          type: MindAidActionType.startBreathing,
          label: 'Start breathing exercise',
        ),
      ];
    }
    if (intent.contains('assessment')) {
      return const [
        MindAidAction(
          type: MindAidActionType.openInsights,
          label: 'View my insights',
        ),
      ];
    }
    if (intent.contains('counsel') || intent.contains('pacc')) {
      return const [
        MindAidAction(
          type: MindAidActionType.bookAppointment,
          label: 'Book an appointment',
        ),
      ];
    }
    return const [];
  }
}

extension _MindAidMessageModelMapper on MindAidMessage {
  MindAidMessageModel toModel({required String conversationId}) {
    return MindAidMessageModel(
      id: id,
      conversationId: conversationId,
      sender: sender == MindAidSender.user ? 'user' : 'assistant',
      text: text,
      createdAt: createdAt,
      status: status ?? '',
    );
  }
}
