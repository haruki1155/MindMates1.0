import '../domain/mind_aid_context.dart';
import '../domain/mind_aid_dataset_models.dart';
import '../domain/mind_aid_engine_result.dart';
import 'intent_engine.dart';
import 'memory_engine.dart';
import 'response_builder.dart';
import 'score_engine.dart';
import 'triage_engine.dart';

class MindAidEngine {
  MindAidEngine({MemoryEngine? memory}) : _memory = memory ?? MemoryEngine();

  final MemoryEngine _memory;

  void resetSession() => _memory.reset();

  MindAidEngineResult process(
    String input,
    MindAidDatasetBundle dataset, {
    MindAidContext context = const MindAidContext(),
  }) {
    final normalizedInput = ScoreEngine.normalize(input);
    if (normalizedInput.isEmpty) {
      return _fallback();
    }

    final mergedContext = MindAidContext(
      recentMessages: [
        ..._memory.snapshot().recentMessages,
        ...context.recentMessages,
      ],
      moodLevel: context.moodLevel,
      assessmentScore: context.assessmentScore,
      quickAssessment: context.quickAssessment,
      assessment: context.assessment,
      conversationSummary: context.conversationSummary,
      preferredSupportStyle: context.preferredSupportStyle,
      journalText: context.journalText,
      wellnessSnapshot: context.wellnessSnapshot,
    );

    final match = IntentEngine.detectBestMatch(
      normalizedInput,
      dataset,
      context: mergedContext,
    );

    if (match == null) {
      _memory.update(intent: 'general_support', message: input);
      return _fallback();
    }

    final record = match.record;
    final triage = TriageEngine.classify(record);
    final response = ResponseBuilder.build(
      record: record,
      dataset: dataset,
      normalizedInput: normalizedInput,
    );
    _memory.update(intent: record.intent, message: input);

    return MindAidEngineResult(
      intent: record.intent,
      category: record.category,
      severity: triage.severity,
      score: match.score,
      response: response,
      riskFlags: triage.riskFlags,
      copingSteps: record.copingSteps
          .map(dataset.copingById)
          .whereType<MindAidCopingExercise>()
          .toList(growable: false),
      recommendations: record.recommendations
          .map(dataset.resourceById)
          .whereType<MindAidResource>()
          .toList(growable: false),
      followUpQuestions: record.followUpQuestions,
      requiresEscalation: triage.requiresEscalation,
    );
  }

  MindAidEngineResult _fallback() {
    return const MindAidEngineResult(
      intent: 'general_support',
      category: 'support',
      severity: MindAidSeverity.low,
      score: 0,
      response: ResponseBuilder.fallbackResponse,
      riskFlags: [],
      copingSteps: [],
      recommendations: [],
      followUpQuestions: ['What feels hardest right now?'],
      requiresEscalation: false,
    );
  }
}
