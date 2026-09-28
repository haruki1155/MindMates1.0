import '../../../models/mind_aid_message_model.dart';
import '../../../models/mind_aid_suggestion_model.dart';
import 'mind_aid_context.dart';
import 'mind_aid_dataset_models.dart';
import 'mind_aid_integration_models.dart';
import 'mind_aid_safety.dart';

class MindAidIntentMatch {
  const MindAidIntentMatch({
    required this.record,
    required this.score,
    required this.matchedKeywords,
    required this.matchedPhrases,
    required this.confidence,
  });

  final MindAidDatasetRecord record;
  final double score;
  final List<String> matchedKeywords;
  final List<String> matchedPhrases;
  final double confidence;

  bool get requiresEscalation => record.requiresEscalation;
}

class MindAidChatRequest {
  const MindAidChatRequest({
    required this.userId,
    required this.text,
    this.recentMessages = const [],
    this.moodLevel,
    this.assessmentScore,
    this.quickAssessment,
    this.assessment,
    this.conversationSummary,
    this.preferredSupportStyle,
    this.wellnessSnapshot,
  });

  final String userId;
  final String text;
  final List<MindAidMessageModel> recentMessages;
  final int? moodLevel;
  final int? assessmentScore;
  final MindAidQuickAssessmentContext? quickAssessment;
  final MindAidAssessmentContext? assessment;
  final String? conversationSummary;
  final MindAidSupportStyle? preferredSupportStyle;
  final MindAidWellnessSnapshot? wellnessSnapshot;
}

class MindAidConversationState {
  const MindAidConversationState({
    this.activeIntent,
    this.activeCategory,
    this.lastQuestion,
    this.unresolvedConcern,
    this.severity = MindAidSeverity.low,
    this.recentIntents = const [],
    this.recentResponses = const [],
    this.awaitingFollowUp = false,
    this.turnCount = 0,
  });

  final String? activeIntent;
  final String? activeCategory;
  final String? lastQuestion;
  final String? unresolvedConcern;
  final MindAidSeverity severity;
  final List<String> recentIntents;
  final List<String> recentResponses;
  final bool awaitingFollowUp;
  final int turnCount;

  factory MindAidConversationState.fromMessages(
    List<MindAidMessageModel> messages,
  ) {
    final assistantMessages = messages
        .where((message) => message.sender == 'assistant')
        .map((message) => message.text)
        .toList(growable: false);

    return MindAidConversationState(
      lastQuestion: _lastQuestionFrom(assistantMessages),
      recentResponses: assistantMessages.take(6).toList(growable: false),
      awaitingFollowUp:
          assistantMessages.isNotEmpty &&
          assistantMessages.last.trim().endsWith('?'),
      turnCount: messages.where((message) => message.sender == 'user').length,
    );
  }

  MindAidConversationState updateFromResponse({
    required List<MindAidIntentMatch> matches,
    required String response,
    required List<String> followUpQuestions,
    required MindAidSeverity severity,
  }) {
    final primary = matches.isEmpty ? null : matches.first.record;
    return MindAidConversationState(
      activeIntent: primary?.intent ?? activeIntent,
      activeCategory: primary?.category ?? activeCategory,
      lastQuestion: followUpQuestions.isNotEmpty
          ? followUpQuestions.first
          : _questionFrom(response),
      unresolvedConcern: primary?.intent ?? unresolvedConcern,
      severity: severity,
      recentIntents: [
        if (primary != null) primary.intent,
        ...recentIntents,
      ].take(8).toList(growable: false),
      recentResponses: [
        response,
        ...recentResponses,
      ].take(8).toList(growable: false),
      awaitingFollowUp:
          followUpQuestions.isNotEmpty || response.trim().endsWith('?'),
      turnCount: turnCount + 1,
    );
  }

  static String? _lastQuestionFrom(List<String> messages) {
    for (final message in messages.reversed) {
      final question = _questionFrom(message);
      if (question != null) return question;
    }
    return null;
  }

  static String? _questionFrom(String message) {
    final parts = message.split(RegExp(r'(?<=[.!?])\s+'));
    for (final part in parts.reversed) {
      final trimmed = part.trim();
      if (trimmed.endsWith('?')) return trimmed;
    }
    return null;
  }
}

class MindAidChatResponse {
  const MindAidChatResponse({
    required this.text,
    required this.intentMatches,
    required this.severity,
    required this.suggestions,
    required this.followUpQuestions,
    required this.recommendations,
    required this.requiresEscalation,
    required this.conversationState,
    required this.status,
    this.safetyLevel = MindAidSafetyLevel.safeSupport,
    this.intentOverride,
    this.source = 'local',
    this.confidence = 0,
    this.fallbackReason = '',
    this.actions = const [],
  });

  final String text;
  final List<MindAidIntentMatch> intentMatches;
  final MindAidSeverity severity;
  final List<MindAidSuggestionModel> suggestions;
  final List<String> followUpQuestions;
  final List<MindAidResource> recommendations;
  final bool requiresEscalation;
  final MindAidConversationState conversationState;
  final String status;
  final MindAidSafetyLevel safetyLevel;
  final String? intentOverride;
  final String source;
  final double confidence;
  final String fallbackReason;
  final List<MindAidAction> actions;

  String get primaryIntent => intentOverride?.trim().isNotEmpty == true
      ? intentOverride!.trim()
      : intentMatches.isEmpty
      ? 'general_support'
      : intentMatches.first.record.intent;
}
