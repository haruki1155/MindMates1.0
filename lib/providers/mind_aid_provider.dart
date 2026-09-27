import 'dart:async';

import 'package:flutter/material.dart';

import '/features/counseling/screens/mind_aid_screen.dart';
import '/features/mind_aid/domain/mind_aid_context.dart';
import '/features/mind_aid/domain/mind_aid_dialogue_state.dart';
import '/features/mind_aid/domain/mind_aid_integration_models.dart';
import '/features/mind_aid/domain/mind_aid_safety.dart';
import '/features/mind_aid/models/paacc_route_decision.dart';
import '/features/mind_aid/services/paacc_intent_router.dart';
import '/features/mind_aid/services/paacc_intent_resolver.dart';
import '/features/mind_aid/services/paacc_mind_aid_response_composer.dart';
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
  final PaaccIntentRouter _paaccIntentRouter;
  final PaaccIntentResolver _paaccResolver = const PaaccIntentResolver();

  MindAidProvider(this.repository, {PaaccIntentRouter? paaccIntentRouter})
    : _paaccIntentRouter = paaccIntentRouter ?? PaaccIntentRouter();

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
  int _conversationRevision = 0;
  PaaccRouteDecision? _lastPaaccRouteDecision;
  final List<PaaccRouteDecision> _routingDiagnostics = [];
  MindAidDialogueState? _dialogueState;
  Timer? _dialogueExpiryTimer;
  bool _dialogueStateSynced = false;
  String? dialogueSyncError;
  String? _paaccRoutingError;
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
  PaaccRouteDecision? get lastPaaccRouteDecision => _lastPaaccRouteDecision;
  String? get paaccRoutingError => _paaccRoutingError;
  List<PaaccRouteDecision> get routingDiagnostics =>
      List.unmodifiable(_routingDiagnostics);
  String? get activeActionMessageId =>
      _dialogueState?.isPendingAt(DateTime.now()) == true
      ? _dialogueState!.sourceMessageId
      : null;

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
      _dialogueState = null;
      _dialogueStateSynced = false;
      _dialogueExpiryTimer?.cancel();
      _routingDiagnostics.clear();
    }
    final effectiveContext = _contextWithSessionMemory(context);
    final previousConversationId = _preferences?.conversationId;
    final previousDialogueState = _dialogueState;
    final previousDialogueStateSynced = _dialogueStateSynced;
    final loadRevision = _conversationRevision;
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
      if (loadRevision != _conversationRevision || _sessionUserId != userId) {
        return;
      }

      final conversationId = _preferences?.conversationId ?? userId;
      final sameConversation = previousConversationId == conversationId;
      MindAidDialogueState loadedState;
      try {
        loadedState = await repository.loadDialogueState(
          userId,
          conversationId,
        );
        _dialogueStateSynced = true;
      } catch (_) {
        loadedState = _dialogueState?.conversationId == conversationId
            ? _dialogueState!
            : MindAidDialogueState(conversationId: conversationId);
        _dialogueStateSynced = false;
      }
      final displayedMessages = await _displayMessagesForHistory(msgResult);
      if (loadRevision != _conversationRevision || _sessionUserId != userId) {
        return;
      }
      final keepLocalPending = sameConversation &&
          !previousDialogueStateSynced &&
          previousDialogueState?.isPendingAt(DateTime.now()) == true &&
          !loadedState.isPendingAt(DateTime.now());
      _dialogueState = keepLocalPending ? previousDialogueState : loadedState;
      if (keepLocalPending) _dialogueStateSynced = false;
      if (!sameConversation ||
          messages.isEmpty ||
          displayedMessages.any((message) => message.id == messages.last.id)) {
        messages = displayedMessages;
      }
      _scheduleDialogueExpiry();
      _stripInactiveActions();

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
      if (loadRevision != _conversationRevision || _sessionUserId != userId) {
        return;
      }
      errorMessage = 'MindAid could not load this conversation.';
    }

    if (loadRevision != _conversationRevision || _sessionUserId != userId) {
      return;
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
    _conversationRevision += 1;
    isLoading = false;
    isSending = true;
    _lastUserMessagePersisted = false;
    notifyListeners();

    try {
      _lastFailedText = null;
      _paaccRoutingError = null;
      _lastPaaccRouteDecision = null;
      if (userId != 'guest' && _dialogueStateSynced) {
        try {
          _dialogueState = await repository.loadDialogueState(
            userId,
            _preferences?.conversationId ?? userId,
          );
        } catch (_) {
          // Continue from this device's pending choice when sync is unavailable.
        }
      }
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
      PaaccMindAidResponse? paaccResponse;
      final isSafety =
          result.chatResponse.requiresEscalation ||
          result.chatResponse.safetyLevel.blocksCloud;
      if (isSafety) {
        await _setDialogueState(userId, null);
      } else {
        final pending = _dialogueState;
        final normalized = trimmedText
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z]+'), ' ')
            .trim();
        if (pending?.isPendingAt(DateTime.now()) == true &&
            normalized == 'no') {
          paaccResponse = const PaaccMindAidResponse(
            text:
                'Okay. We can talk about something else whenever you are ready.',
          );
          await _setDialogueState(userId, null);
        } else if (pending?.isPendingAt(DateTime.now()) == true &&
            normalized == 'yes') {
          paaccResponse = PaaccMindAidResponse(
            text: 'You can use the button below whenever you are ready.',
            actions: [pending!.action!],
          );
          await _setDialogueState(
            userId,
            MindAidDialogueState(
              conversationId: pending.conversationId,
              sourceMessageId: bot.id,
              action: pending.action,
              expiresAt: pending.expiresAt,
            ),
          );
        } else {
          await _setDialogueState(userId, null);
          PaaccRouteDecision? prediction;
          try {
            prediction = await _paaccIntentRouter.route(trimmedText);
          } catch (_) {
            _paaccRoutingError = 'Intent routing is temporarily unavailable.';
          }
          _lastPaaccRouteDecision = _paaccResolver.resolve(
            trimmedText,
            prediction,
          );
          _routingDiagnostics.add(_lastPaaccRouteDecision!);
          if (_routingDiagnostics.length > 50) _routingDiagnostics.removeAt(0);
          paaccResponse = const PaaccMindAidResponseComposer().compose(
            _lastPaaccRouteDecision!,
          );
          if (paaccResponse.actions.isNotEmpty) {
            await _setDialogueState(
              userId,
              MindAidDialogueState(
                conversationId: _preferences?.conversationId ?? userId,
                sourceMessageId: bot.id,
                action: paaccResponse.actions.first,
                expiresAt: DateTime.now().add(const Duration(minutes: 10)),
              ),
            );
          }
        }
      }
      if (paaccResponse != null) {
        await repository.savePaaccDisplayOverride(
          messageId: bot.id,
          text: paaccResponse.text,
          actions: paaccResponse.actions,
        );
      }

      final botMessage = MindAidMessage(
        id: bot.id,
        sender: MindAidSender.assistant,
        text: paaccResponse?.text ?? bot.text,
        createdAt: bot.createdAt,
        status: bot.status,
        categoryLabel: paaccResponse == null ? _categoryLabelFor(result) : null,
        supportCards:
            paaccResponse == null ||
                _lastPaaccRouteDecision?.route == PaaccRouteType.venting ||
                _lastPaaccRouteDecision?.route == PaaccRouteType.copingHelp ||
                _lastPaaccRouteDecision?.route == PaaccRouteType.assessmentHelp
            ? _supportCardsFor(result, context)
            : const [],
        actions: paaccResponse?.actions ?? _actionsFor(result),
        source: result.chatResponse.source,
      );

      _stripInactiveActions();
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
    await _setDialogueState(userId, null);
    await repository.clearHistory(userId);
    repository.resetSession();
    messages = [];
    _conversationSummary = null;
    _lastFailedText = null;
    _preferences = await repository.loadPreferences(userId);
    notifyListeners();
  }

  Future<void> startNewConversation(String userId) async {
    await _setDialogueState(userId, null);
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
    _dialogueState = MindAidDialogueState(conversationId: nextId);
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

  Future<void> _setDialogueState(
    String userId,
    MindAidDialogueState? next,
  ) async {
    final state =
        next ??
        MindAidDialogueState(
          conversationId: _preferences?.conversationId ?? userId,
        );
    _dialogueState = state;
    _dialogueStateSynced = false;
    _scheduleDialogueExpiry();
    try {
      await repository.saveDialogueState(userId, state);
      _dialogueStateSynced = true;
      dialogueSyncError = null;
    } catch (_) {
      dialogueSyncError =
          'Dialogue choices could not sync. Please try again when connected.';
    }
  }

  void _scheduleDialogueExpiry() {
    _dialogueExpiryTimer?.cancel();
    final expiry = _dialogueState?.expiresAt;
    if (expiry == null) return;
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) return;
    _dialogueExpiryTimer = Timer(remaining, () {
      _stripInactiveActions();
      notifyListeners();
    });
  }

  Future<void> addReturnPrompt(MindAidAction action) async {
    if (messages.lastOrNull?.status == 'urgent') return;
    final text = switch (action.type) {
      MindAidActionType.bookAppointment || MindAidActionType.viewAppointments =>
        'Would you like help preparing what to discuss with PACC?',
      MindAidActionType.openAssessment =>
        'Would you like to talk about how the self-assessment felt?',
      MindAidActionType.startBreathing =>
        'How are you feeling after taking that pause?',
      MindAidActionType.openCounselingServices =>
        'Is there a support service you would like to know more about?',
      _ => null,
    };
    if (text == null) return;
    final message = MindAidMessage(
      id: 'return_${DateTime.now().microsecondsSinceEpoch}',
      sender: MindAidSender.assistant,
      text: text,
      createdAt: DateTime.now(),
    );
    messages.add(message);
    notifyListeners();
    final userId = _sessionUserId;
    if (userId == null || userId == 'guest') return;
    await repository.saveDialogueFollowUp(
      userId,
      MindAidMessageModel(
        id: message.id,
        conversationId: _preferences?.conversationId ?? userId,
        sender: 'assistant',
        text: message.text,
        createdAt: message.createdAt,
        status: 'sent',
        safetyLevel: MindAidSafetyLevel.safeSupport.name,
      ),
    );
  }

  Future<bool> consumeAction(
    String userId,
    String messageId,
    MindAidAction action,
  ) async {
    if (isSending || isLoading) return false;
    final message = messages.where((item) => item.id == messageId).firstOrNull;
    if (message?.status == 'urgent') {
      return message!.actions.any(
        (allowed) =>
            allowed.type == action.type && allowed.label == action.label,
      );
    }
    final state = _dialogueState;
    final dismiss = action.type == MindAidActionType.dismissPending;
    if (state == null ||
        (dismiss
            ? !(state.isPendingAt(DateTime.now()) &&
                  state.sourceMessageId == messageId)
            : !state.matches(messageId, action, DateTime.now()))) {
      return false;
    }
    if (_dialogueStateSynced) {
      try {
        if (!await repository.consumeDialogueAction(
          userId,
          state.conversationId,
          messageId,
          action,
          dismiss: dismiss,
        )) {
          errorMessage =
              'That choice is no longer available. Please ask MindAid again.';
          notifyListeners();
          return false;
        }
      } catch (_) {
        errorMessage =
            'MindAid could not verify that choice. Please check your connection and try again.';
        notifyListeners();
        return false;
      }
    }
    _dialogueState = MindAidDialogueState(conversationId: state.conversationId);
    _scheduleDialogueExpiry();
    _stripInactiveActions();
    notifyListeners();
    return true;
  }

  void _stripInactiveActions() {
    final activeId = activeActionMessageId;
    messages = messages.map((message) {
      if (message.actions.isEmpty ||
          message.status == 'urgent' ||
          message.id == activeId) {
        return message;
      }
      return MindAidMessage(
        id: message.id,
        sender: message.sender,
        text: message.text,
        createdAt: message.createdAt,
        status: message.status,
        categoryLabel: message.categoryLabel,
        supportCards: message.supportCards,
        source: message.source,
      );
    }).toList();
  }

  Future<List<MindAidMessage>> _displayMessagesForHistory(
    List<MindAidMessageModel> history,
  ) async {
    final displayed = <MindAidMessage>[];
    for (var index = 0; index < history.length; index++) {
      final message = history[index];
      PaaccMindAidResponse? paaccResponse;
      if (message.sender == 'assistant' &&
          !message.hasPaaccDisplay &&
          index > 0 &&
          history[index - 1].sender == 'user' &&
          !_historyResponseRequiresSafety(message)) {
        try {
          final decision = await _paaccIntentRouter.route(
            history[index - 1].text,
          );
          paaccResponse = const PaaccMindAidResponseComposer().compose(
            _paaccResolver.resolve(history[index - 1].text, decision),
          );
        } catch (_) {
          // Preserve the recorded response if the optional on-device route
          // cannot be restored while history is loading.
        }
      }
      displayed.add(
        MindAidMessage(
          id: message.id,
          sender: message.sender == 'user'
              ? MindAidSender.user
              : MindAidSender.assistant,
          text: paaccResponse?.text ?? message.text,
          createdAt: message.createdAt,
          status: message.status,
          categoryLabel: null,
          supportCards: const [],
          actions: paaccResponse?.actions ?? message.actions,
          source: message.source,
        ),
      );
    }
    return displayed;
  }

  bool _historyResponseRequiresSafety(MindAidMessageModel message) {
    if (message.requiresEscalation) return true;
    if (message.safetyLevel == null) return true;
    final safetyLevel = MindAidSafetyLevel.values.firstWhere(
      (level) => level.name == message.safetyLevel,
      orElse: () => MindAidSafetyLevel.highDistress,
    );
    return safetyLevel.blocksCloud;
  }

  @override
  void dispose() {
    _dialogueExpiryTimer?.cancel();
    _paaccIntentRouter.dispose();
    super.dispose();
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
