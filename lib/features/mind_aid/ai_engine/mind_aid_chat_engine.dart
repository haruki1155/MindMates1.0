import '../../../models/mind_aid_suggestion_model.dart';
import '../domain/mind_aid_chat_models.dart';
import '../domain/mind_aid_context.dart';
import '../domain/mind_aid_dataset_models.dart';
import '../domain/mind_aid_safety.dart';
import 'mind_aid_dialogue_manager.dart';
import 'mind_aid_knowledge_retriever.dart';
import 'mind_aid_response_composer.dart';
import 'mind_aid_safety_classifier.dart';
import 'score_engine.dart';

class MindAidChatEngine {
  MindAidChatEngine({
    MindAidKnowledgeRetriever? retriever,
    MindAidDialogueManager? dialogueManager,
    MindAidResponseComposer? responseComposer,
    MindAidSafetyClassifier? safetyClassifier,
  }) : _retriever = retriever ?? const MindAidKnowledgeRetriever(),
       _dialogueManager = dialogueManager ?? const MindAidDialogueManager(),
       _responseComposer = responseComposer ?? MindAidResponseComposer(),
       _safetyClassifier = safetyClassifier ?? const MindAidSafetyClassifier();

  final MindAidKnowledgeRetriever _retriever;
  final MindAidDialogueManager _dialogueManager;
  final MindAidResponseComposer _responseComposer;
  final MindAidSafetyClassifier _safetyClassifier;
  MindAidConversationState _state = const MindAidConversationState();

  void resetSession() {
    _state = const MindAidConversationState();
  }

  Future<MindAidChatResponse> respond(
    MindAidChatRequest request,
    MindAidDatasetBundle dataset,
  ) async {
    final normalizedInput = ScoreEngine.normalize(request.text);
    final requestState = MindAidConversationState.fromMessages(
      request.recentMessages,
    );
    final state = _mergeState(_state, requestState);
    final context = MindAidContext(
      recentMessages: request.recentMessages
          .map((message) => message.text)
          .toList(growable: false),
      moodLevel: request.moodLevel,
      assessmentScore: request.assessmentScore,
      quickAssessment: request.quickAssessment,
      assessment: request.assessment,
      conversationSummary: request.conversationSummary,
      preferredSupportStyle: request.preferredSupportStyle,
      journalText: request.journalText,
      wellnessSnapshot: request.wellnessSnapshot,
    );

    final matches = normalizedInput.isEmpty
        ? <MindAidIntentMatch>[]
        : _retriever.retrieve(normalizedInput, dataset, context: context);
    final safety = _safetyClassifier.classify(
      normalizedInput: normalizedInput,
      matches: matches,
    );
    final safetyIntercept = safety.level.blocksCloud;
    final activeFollowUpMatch = state.activeIntent == null
        ? null
        : _retriever.matchByIntent(state.activeIntent!, dataset);
    final decision = safetyIntercept
        ? MindAidDialogueDecision(
            action: MindAidDialogueAction.escalate,
            matches: matches,
            reason: 'safety_intercept',
          )
        : _dialogueManager.decide(
            normalizedInput: normalizedInput,
            matches: matches,
            state: state,
            activeFollowUpMatch: activeFollowUpMatch,
          );
    final responseText = await _responseComposer.compose(
      action: decision.action,
      normalizedInput: normalizedInput,
      originalInput: request.text,
      matches: decision.matches,
      dataset: dataset,
      state: state,
      context: context,
      safetyLevel: safety.level,
    );
    final severity = _highestSeverity(decision.matches, safety.level);
    final followUps = _followUpsFor(decision, state);
    final nextState = state.updateFromResponse(
      matches: decision.matches,
      response: responseText,
      followUpQuestions: followUps,
      severity: severity,
    );
    _state = nextState;

    return MindAidChatResponse(
      text: responseText,
      intentMatches: decision.matches,
      severity: severity,
      suggestions: _suggestionsFor(followUps, dataset, context, decision),
      followUpQuestions: followUps,
      recommendations: _recommendationsFor(decision.matches, dataset),
      requiresEscalation:
          decision.action == MindAidDialogueAction.escalate ||
          decision.matches.any((match) => match.requiresEscalation),
      conversationState: nextState,
      status: decision.action == MindAidDialogueAction.escalate
          ? 'urgent'
          : 'sent',
      safetyLevel: safety.level,
    );
  }

  MindAidConversationState _mergeState(
    MindAidConversationState current,
    MindAidConversationState fromMessages,
  ) {
    return MindAidConversationState(
      activeIntent: current.activeIntent ?? fromMessages.activeIntent,
      activeCategory: current.activeCategory ?? fromMessages.activeCategory,
      lastQuestion: current.lastQuestion ?? fromMessages.lastQuestion,
      unresolvedConcern:
          current.unresolvedConcern ?? fromMessages.unresolvedConcern,
      severity: current.severity,
      recentIntents: current.recentIntents,
      recentResponses: [
        ...current.recentResponses,
        ...fromMessages.recentResponses,
      ].take(8).toList(growable: false),
      awaitingFollowUp:
          current.awaitingFollowUp || fromMessages.awaitingFollowUp,
      turnCount: current.turnCount > fromMessages.turnCount
          ? current.turnCount
          : fromMessages.turnCount,
    );
  }

  MindAidSeverity _highestSeverity(
    List<MindAidIntentMatch> matches,
    MindAidSafetyLevel safetyLevel,
  ) {
    if (safetyLevel == MindAidSafetyLevel.crisisOrImmediateRisk) {
      return MindAidSeverity.crisis;
    }
    if (safetyLevel == MindAidSafetyLevel.highDistress) {
      return MindAidSeverity.high;
    }
    if (matches.any(
      (match) => match.record.severity == MindAidSeverity.crisis,
    )) {
      return MindAidSeverity.crisis;
    }
    if (matches.any((match) => match.record.severity == MindAidSeverity.high)) {
      return MindAidSeverity.high;
    }
    if (matches.any(
      (match) => match.record.severity == MindAidSeverity.medium,
    )) {
      return MindAidSeverity.medium;
    }
    return MindAidSeverity.low;
  }

  List<String> _followUpsFor(
    MindAidDialogueDecision decision,
    MindAidConversationState state,
  ) {
    if (decision.action == MindAidDialogueAction.clarify) {
      return [
        state.lastQuestion ??
            'Is this mostly about school, relationships, stress, anxiety, or something else?',
      ];
    }
    final questions = <String>[];
    for (final match in decision.matches) {
      questions.addAll(match.record.followUpQuestions);
    }
    return questions.take(3).toList(growable: false);
  }

  List<MindAidResource> _recommendationsFor(
    List<MindAidIntentMatch> matches,
    MindAidDatasetBundle dataset,
  ) {
    final resources = <MindAidResource>[];
    for (final match in matches) {
      for (final id in [
        ...match.record.recommendations,
        ...match.record.resourceIds,
      ]) {
        final resource = dataset.resourceById(id);
        if (resource != null &&
            !resources.any((item) => item.id == resource.id)) {
          resources.add(resource);
        }
      }
    }
    return resources;
  }

  List<MindAidSuggestionModel> _suggestionsFor(
    List<String> followUps,
    MindAidDatasetBundle dataset,
    MindAidContext context,
    MindAidDialogueDecision decision,
  ) {
    if (followUps.isNotEmpty) {
      final contextual = _contextualSuggestions(context, decision);
      return [
        ...contextual,
        ...followUps
            .take(3)
            .map(
              (question) => MindAidSuggestionModel(
                id: 'follow_up_${question.hashCode.abs()}',
                label: question,
              ),
            ),
      ].take(5).toList(growable: false);
    }
    return [
      ..._contextualSuggestions(context, decision),
      ...dataset.suggestions,
    ].take(5).toList(growable: false);
  }

  List<MindAidSuggestionModel> _contextualSuggestions(
    MindAidContext context,
    MindAidDialogueDecision decision,
  ) {
    final suggestions = <MindAidSuggestionModel>[];

    if (context.hasAssessment) {
      suggestions.add(
        MindAidSuggestionModel(
          id: 'review_assessment',
          label: 'What does my assessment suggest?',
        ),
      );

      final topConcern = context.assessment?.highestCategory?.key;
      if (topConcern != null && topConcern.trim().isNotEmpty) {
        suggestions.add(
          MindAidSuggestionModel(
            id: 'top_concern_${topConcern.hashCode.abs()}',
            label: 'Help me with $topConcern',
          ),
        );
      }

      final quickConcerns = context.quickAssessment?.topConcernAreas;
      final quickConcern = quickConcerns == null || quickConcerns.isEmpty
          ? null
          : quickConcerns.first;
      if (topConcern == null &&
          quickConcern != null &&
          quickConcern.trim().isNotEmpty) {
        suggestions.add(
          MindAidSuggestionModel(
            id: 'quick_concern_${quickConcern.hashCode.abs()}',
            label: 'Help me with $quickConcern',
          ),
        );
      }
    }

    final snapshot = context.wellnessSnapshot;
    if (snapshot != null) {
      if (snapshot.hasMoodData) {
        suggestions.add(
          MindAidSuggestionModel(
            id: 'understand_mood_trend',
            label: 'Help me understand my mood trend',
          ),
        );
      }
      if (snapshot.hasElevatedAssessment && !context.hasAssessment) {
        suggestions.add(
          MindAidSuggestionModel(
            id: 'review_wellness_signal',
            label: 'What does my assessment suggest?',
          ),
        );
      }
      if (snapshot.hasNoRecentCheckIn) {
        suggestions.add(
          MindAidSuggestionModel(
            id: 'quick_check_in',
            label: 'Help me check in with myself',
          ),
        );
      }
    }

    suggestions.addAll([
      MindAidSuggestionModel(
        id: 'two_minute_coping',
        label: 'Give me a 2-minute grounding step',
      ),
      MindAidSuggestionModel(id: 'make_a_plan', label: 'Help me make a plan'),
      MindAidSuggestionModel(id: 'talk_to_pacc', label: 'Talk to PACC'),
    ]);

    if (decision.action == MindAidDialogueAction.escalate) {
      return suggestions
          .where((suggestion) => suggestion.id == 'talk_to_pacc')
          .toList(growable: false);
    }

    final unique = <String, MindAidSuggestionModel>{};
    for (final suggestion in suggestions) {
      unique.putIfAbsent(suggestion.id, () => suggestion);
    }
    return unique.values.toList(growable: false);
  }
}
