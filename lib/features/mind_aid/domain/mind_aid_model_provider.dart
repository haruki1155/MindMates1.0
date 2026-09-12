import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mind_aid_chat_models.dart';
import 'mind_aid_context.dart';
import 'mind_aid_dataset_models.dart';
import 'mind_aid_safety.dart';

class MindAidModelPrompt {
  const MindAidModelPrompt({
    required this.userText,
    required this.matches,
    required this.state,
    required this.dataset,
    required this.requiresEscalation,
    required this.context,
    required this.safetyLevel,
  });

  final String userText;
  final List<MindAidIntentMatch> matches;
  final MindAidConversationState state;
  final MindAidDatasetBundle dataset;
  final bool requiresEscalation;
  final MindAidContext context;
  final MindAidSafetyLevel safetyLevel;
}

abstract class MindAidModelProvider {
  Future<String> generate(MindAidModelPrompt prompt);
}

class LocalMindAidModelProvider implements MindAidModelProvider {
  const LocalMindAidModelProvider();

  @override
  Future<String> generate(MindAidModelPrompt prompt) async {
    return '';
  }
}

class HybridMindAidModelProvider implements MindAidModelProvider {
  const HybridMindAidModelProvider({
    required this.enabled,
    required this.cloudProvider,
    this.timeout = const Duration(seconds: 8),
  });

  factory HybridMindAidModelProvider.fromEnvironment() {
    const enabled = bool.fromEnvironment('MINDAID_AI_ENABLED');
    const endpoint = String.fromEnvironment('MINDAID_AI_ENDPOINT');
    const apiKey = String.fromEnvironment('MINDAID_AI_API_KEY');
    const model = String.fromEnvironment(
      'MINDAID_AI_MODEL',
      defaultValue: 'gpt-4o-mini',
    );

    return HybridMindAidModelProvider(
      enabled: enabled && endpoint != '' && apiKey != '',
      cloudProvider: OpenAICompatibleMindAidModelProvider(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
      ),
    );
  }

  final bool enabled;
  final MindAidModelProvider cloudProvider;
  final Duration timeout;

  @override
  Future<String> generate(MindAidModelPrompt prompt) async {
    if (!enabled ||
        prompt.requiresEscalation ||
        prompt.safetyLevel.blocksCloud) {
      return '';
    }

    try {
      final raw = await cloudProvider.generate(prompt).timeout(timeout);
      final guarded = MindAidOutputGuardrails.clean(raw);
      return guarded;
    } catch (_) {
      return '';
    }
  }
}

class OpenAICompatibleMindAidModelProvider implements MindAidModelProvider {
  const OpenAICompatibleMindAidModelProvider({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    this.client,
  });

  final String endpoint;
  final String apiKey;
  final String model;
  final http.Client? client;

  @override
  Future<String> generate(MindAidModelPrompt prompt) async {
    if (endpoint.isEmpty || apiKey.isEmpty) return '';

    final httpClient = client ?? http.Client();
    final ownsClient = client == null;

    try {
      final response = await httpClient.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'temperature': 0.35,
          'max_tokens': 260,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': _userPrompt(prompt)},
          ],
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return '';
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return '';

      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final message = first['message'];
          if (message is Map<String, dynamic>) {
            return (message['content'] as String?)?.trim() ?? '';
          }
          return (first['text'] as String?)?.trim() ?? '';
        }
      }

      return (decoded['text'] as String?)?.trim() ?? '';
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  static const _systemPrompt = '''
You are MindAid, a supportive campus well-being assistant.
Stay warm, brief, and practical.
Do not diagnose, do not claim medical certainty, and do not pretend to be a counselor.
Use phrases like "may suggest" and "could help".
Offer one clear next step when possible.
Encourage trusted human or PACC support when concern is elevated.
If the user may be unsafe, say to seek immediate human support.''';

  String _userPrompt(MindAidModelPrompt prompt) {
    final primary = prompt.matches.isEmpty ? null : prompt.matches.first.record;
    final assessment = prompt.context.assessment;
    final quickAssessment = prompt.context.quickAssessment;
    final topCategory = assessment?.highestCategory;
    final supportStyle = prompt.context.preferredSupportStyle?.label;
    final snapshot = prompt.context.wellnessSnapshot;

    return jsonEncode({
      'userMessage': prompt.userText,
      'matchedIntent': primary?.intent,
      'matchedCategory': primary?.category,
      'severity': primary?.severity.name,
      'supportStyle': supportStyle,
      'conversationSummary': prompt.context.conversationSummary,
      'assessment': assessment == null
          ? {
              'quickScore':
                  quickAssessment?.score ?? prompt.context.assessmentScore,
              'quickLevel': quickAssessment?.level,
              'wellnessSignal': quickAssessment?.signal,
              'topConcernAreas': quickAssessment?.topConcernAreas,
              'summary': quickAssessment?.summary,
              'recommendedNextStep': quickAssessment?.recommendedNextStep,
              'guardrail': 'screening signal only, not a diagnosis',
            }
          : {
              'userType': assessment.userType,
              'overallScore': assessment.overallScore?.round(),
              'status': assessment.status,
              'mainConcernAreas': assessment.mainConcernAreas,
              'topCategory': topCategory == null
                  ? null
                  : {
                      'name': topCategory.key,
                      'score': topCategory.value.round(),
                    },
            },
      'wellnessSnapshot': snapshot == null
          ? null
          : {
              'latestMoodLevel': snapshot.latestMoodLevel,
              'recentMoodAverage': snapshot.recentMoodAverage?.toStringAsFixed(
                1,
              ),
              'moodTrend': snapshot.moodTrend?.label,
              'latestMoodLabel': snapshot.latestMoodLabel,
              'hasMoodNote': snapshot.hasMoodNote,
              'assessmentStatus': snapshot.assessmentStatus,
              'assessmentScore': snapshot.assessmentScore,
              'mentalStatusSignal': snapshot.mentalStatusSignal,
              'topConcernAreas': snapshot.topConcernAreas,
              'reportSummary': snapshot.reportSummary,
              'recommendedActions': snapshot.recommendedActions,
              'currentStreak': snapshot.currentStreak,
              'activeDayCount': snapshot.activeDayCount,
              'breathingSessionCount': snapshot.breathingSessionCount,
              'mindfulBreathingMinutes': snapshot.mindfulBreathingMinutes,
              'hasRecentLowMood': snapshot.hasRecentLowMood,
              'hasElevatedAssessment': snapshot.hasElevatedAssessment,
              'hasNoRecentCheckIn': snapshot.hasNoRecentCheckIn,
            },
      'localResponseOptions': primary?.responses.take(2).toList() ?? const [],
      'copingSteps': primary?.copingSteps ?? const [],
      'followUpQuestions':
          primary?.followUpQuestions.take(2).toList() ?? const [],
    });
  }
}

class MindAidOutputGuardrails {
  const MindAidOutputGuardrails._();

  static const _blockedPatterns = [
    'you have depression',
    'you have anxiety disorder',
    'you have bipolar',
    'you have ptsd',
    'you are diagnosed',
    'i diagnose',
    'as your therapist',
    'as a licensed counselor',
    'keep this secret',
    'do not tell anyone',
    'take this medication',
    'guaranteed to work',
  ];

  static String clean(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final normalized = trimmed.toLowerCase();

    for (final blocked in _blockedPatterns) {
      if (normalized.contains(blocked)) return '';
    }

    if (trimmed.length > 1200) {
      return '${trimmed.substring(0, 1200).trimRight()}...';
    }

    return trimmed;
  }
}
