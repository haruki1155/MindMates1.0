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

  static const String defaultGreeting =
      "Hi! I'm MindAid, your mental wellness companion. 💙\n\n"
      "I'm here to support your emotional well-being and help you "
      "with PACC services, counseling, and MindMate wellness features.\n\n"
      "How can I help you today?";

  static const String _mindAidDefaultGreeting = defaultGreeting;

  static bool _hasTerm(String input, String term) {
    final pattern = RegExp(r'(^|\s)' + RegExp.escape(term) + r'($|\s)');
    return pattern.hasMatch(input);
  }

  static bool _hasAny(String input, List<String> terms) {
    return terms.any((term) => _hasTerm(input, term));
  }

  static bool _isRelatedTopic(String input) {
    // Explicit unrelated requests take precedence over incidental
    // wellness keywords, e.g. "write Python code about stress".
    const unrelatedRequests = [
      'python',
      'javascript',
      'programming',
      'source code',
      'write code',
      'generate code',
      'debug code',
      'flutter code',
      'nba',
      'basketball score',
      'football score',
      'world cup',
      'who won',
      'movie review',
      'recipe',
      'cook',
      'weather',
      'capital of',
      'president of',
      'calculate',
      'solve equation',
      'multiply',
      'divide',
      'translate',
      'essay about',
      'write an essay',
    ];

    if (_hasAny(input, unrelatedRequests) ||
        RegExp(r'\d+\s*(?:x|\*|\+|/)\s*\d+').hasMatch(input)) {
      return false;
    }

    const wellnessTerms = [
      'mental health',
      'mental wellness',
      'emotional health',
      'wellbeing',
      'well being',
      'wellness',
      'stress',
      'stressed',
      'stressful',
      'anxiety',
      'anxious',
      'panic',
      'panicking',
      'depression',
      'depressed',
      'sad',
      'sadness',
      'lonely',
      'loneliness',
      'alone',
      'burnout',
      'burned out',
      'exhausted',
      'overwhelmed',
      'worried',
      'worry',
      'fear',
      'afraid',
      'scared',
      'crying',
      'upset',
      'hopeless',
      'helpless',
      'mood',
      'emotion',
      'emotions',
      'feelings',
      'feeling down',
      'sleep problem',
      'insomnia',
      'cant sleep',
      'cannot sleep',
      'self esteem',
      'self confidence',
      'insecure',
      'coping',
      'cope',
      'grounding',
      'breathing exercise',
      'mindfulness',
      'meditation',
      'relaxation',
      'grief',
      'trauma',
      'bullying',
      'bullied',
      'relationship problems',
      'family problems',
      'academic stress',
      'school pressure',
      'exam pressure',
      'exams',
      'exam',
      'deadline',
      'deadlines',
      'pagod',
      'malungkot',
      'nalulungkot',
      'lungkot',
      'kinakabahan',
      'kabado',
      'takot',
      'naiiyak',
      'umiiyak',
      'nahihirapan',
      'problema',
      'pag aalala',
      'pagkabalisa',
      'sobrang stress',
    ];

    const paccTerms = [
      'pacc',
      'guidance',
      'guidance counselor',
      'guidance assistant',
      'counselor',
      'counseling',
      'counselling',
      'therapy',
      'appointment',
      'book counseling',
      'book appointment',
      'schedule counseling',
      'mental health assessment',
      'self assessment',
      'assessment result',
      'assessment score',
      'phq 9',
      'gad 7',
      'mindmate',
      'mindaid',
      'mood tracker',
      'mood tracking',
      'secret posting',
      'breathing exercises',
      'facial tracking',
      'facial recognition',
      'insights',
      'journal',
      'wellness resources',
      'daily streak',
      'daily quest',
      'psychological assessment',
    ];

    return _hasAny(input, wellnessTerms) || _hasAny(input, paccTerms);
  }

  static bool _isSimpleGreeting(String input) {
    const greetings = [
      'hi',
      'hello',
      'hey',
      'hello mindaid',
      'hi mindaid',
      'hey mindaid',
      'good morning',
      'good afternoon',
      'good evening',
      'kumusta',
      'kamusta',
      'musta',
      'yo',
    ];
    return greetings.contains(input);
  }

  static bool _isShortFollowUp(String input) {
    const replies = [
      'yes',
      'no',
      'yeah',
      'yep',
      'nope',
      'okay',
      'ok',
      'sure',
      'please',
      'continue',
      'tell me more',
      'go on',
      'oo',
      'opo',
      'hindi',
      'sige',
      'salamat',
      'thanks',
    ];
    if (replies.contains(input)) return true;

    // Recognize natural replies about an existing wellness topic.
    // Only the active conversation can authorize these follow-ups.
    const contextualReplies = [
      'my grades',
      'my exam',
      'my exams',
      'my family',
      'my parents',
      'my work',
      'my job',
      'because of my family',
      'because of my grades',
      'because of my exams',
      'what should i do',
      'what can i do',
      'how can i cope',
      'how do i cope',
      'can you help me',
      'give me advice',
      'any advice',
      'tell me more about it',
      'what do you suggest',
      'help me with that',
    ];

    return contextualReplies.contains(input);
  }

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
      wellnessSnapshot: request.wellnessSnapshot,
      conversationMode: request.conversationMode,
      explicitListening: request.explicitListening,
      allowsWellnessReference: request.allowsWellnessReference,
    );

    final matches = normalizedInput.isEmpty
        ? <MindAidIntentMatch>[]
        : _retriever.retrieve(normalizedInput, dataset, context: context);
    final safety = _safetyClassifier.classify(
      normalizedInput: normalizedInput,
      matches: matches,
    );

    // Crisis and high-distress handling must run before topic filtering.
    final isSafetyConcern =
        safety.level.blocksCloud ||
        matches.any(
          (match) =>
              match.requiresEscalation ||
              match.record.severity == MindAidSeverity.high ||
              match.record.severity == MindAidSeverity.crisis,
        );

    final isContextualFollowUp =
        (state.awaitingFollowUp || state.activeIntent != null) &&
        _isShortFollowUp(normalizedInput);

    // Assessment questions are legitimate MindMate wellness requests.
    // Keep the existing assessment response logic available.
    final isAssessmentReview =
        (context.hasAssessment ||
            request.quickAssessment != null ||
            request.wellnessSnapshot != null) &&
        (_hasAny(normalizedInput, const [
          'assessment',
          'result',
          'results',
          'score',
          'scores',
          'review',
          'progress',
          'status',
          'how am i doing',
          'what should i do next',
          'wellness signal',
          'how severe',
          'what does it mean',
        ]));

    final isAllowedTopic =
        _isRelatedTopic(normalizedInput) ||
        isContextualFollowUp ||
        isAssessmentReview;

    if (!isSafetyConcern &&
        (_isSimpleGreeting(normalizedInput) || !isAllowedTopic)) {
      final nextState = const MindAidConversationState();
      _state = nextState;

      return MindAidChatResponse(
        text: _mindAidDefaultGreeting,
        intentMatches: const [],
        severity: MindAidSeverity.low,
        suggestions: const [],
        followUpQuestions: const [],
        recommendations: const [],
        requiresEscalation: false,
        conversationState: nextState,
        status: 'sent',
        safetyLevel: MindAidSafetyLevel.safeSupport,
      );
    }

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
