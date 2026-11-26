import '../domain/mind_aid_chat_models.dart';
import '../domain/mind_aid_context.dart';
import '../domain/mind_aid_dataset_models.dart';
import 'score_engine.dart';

class MindAidKnowledgeRetriever {
  const MindAidKnowledgeRetriever({this.minimumScore = 1, this.maxMatches = 3});

  final double minimumScore;
  final int maxMatches;

  List<MindAidIntentMatch> retrieve(
    String normalizedInput,
    MindAidDatasetBundle dataset, {
    MindAidContext context = const MindAidContext(),
  }) {
    final matches = <MindAidIntentMatch>[];

    for (final record in dataset.allRecords) {
      final matchedKeywords = ScoreEngine.matchedTerms(
        normalizedInput,
        record.keywords,
      );
      final matchedPhrases = ScoreEngine.matchedPhrases(
        normalizedInput,
        record.phrases,
      );
      final score = ScoreEngine.scoreRecord(
        normalizedInput,
        record,
        context: context,
      );

      if (score < minimumScore) continue;
      matches.add(
        MindAidIntentMatch(
          record: record,
          score: score,
          matchedKeywords: matchedKeywords,
          matchedPhrases: matchedPhrases,
          confidence: _confidenceFor(record, score),
        ),
      );
    }

    // General stress should not automatically become academic stress.
    final hasSpecificStressContext = RegExp(
      r'\b(exam|exams|academic|school|class|classes|'
      r'grade|grades|assignment|assignments|deadline|deadlines|'
      r'financial|money|family|work|workplace)\b',
    ).hasMatch(normalizedInput);

    if (!hasSpecificStressContext &&
        RegExp(r'\b(stress|stressed|stressful)\b').hasMatch(normalizedInput)) {
      matches.sort((left, right) {
        if (left.record.intent == 'general_stress' &&
            right.record.intent != 'general_stress') {
          return -1;
        }
        if (right.record.intent == 'general_stress' &&
            left.record.intent != 'general_stress') {
          return 1;
        }
        return right.score.compareTo(left.score);
      });
    } else {
      matches.sort((left, right) => right.score.compareTo(left.score));
    }
    return matches.take(maxMatches).toList(growable: false);
  }

  MindAidIntentMatch? matchByIntent(
    String intent,
    MindAidDatasetBundle dataset,
  ) {
    for (final record in dataset.allRecords) {
      if (record.intent == intent) {
        return MindAidIntentMatch(
          record: record,
          score: 0.5,
          matchedKeywords: const [],
          matchedPhrases: const [],
          confidence: 0.35,
        );
      }
    }
    return null;
  }

  double _confidenceFor(MindAidDatasetRecord record, double score) {
    if (record.requiresEscalation && score >= 1) return 1;
    return (score / 4).clamp(0.05, 1).toDouble();
  }
}
