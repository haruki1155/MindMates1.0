import '../domain/mind_aid_context.dart';
import '../domain/mind_aid_dataset_models.dart';

class ScoreEngine {
  static String normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r"['’]"), '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double scoreRecord(
    String normalizedInput,
    MindAidDatasetRecord record, {
    MindAidContext context = const MindAidContext(),
  }) {
    var score = 0.0;

    for (final keyword in record.keywords) {
      if (containsTerm(normalizedInput, normalize(keyword))) {
        score += 1;
      }
    }

    for (final phrase in record.phrases) {
      if (normalizedInput.contains(normalize(phrase))) {
        score += 2.5;
      }
    }

    if (record.severity == MindAidSeverity.crisis && score > 0) {
      score += 10;
    }

    final latestMoodLevel =
        context.moodLevel ?? context.wellnessSnapshot?.latestMoodLevel;
    if (latestMoodLevel != null &&
        latestMoodLevel <= 2 &&
        record.category != 'school') {
      score += 0.25;
    }

    final snapshot = context.wellnessSnapshot;
    if (snapshot != null) {
      if (snapshot.hasLowMoodTrend && record.severity != MindAidSeverity.low) {
        score += 0.2;
      }
      for (final concern in snapshot.topConcernAreas) {
        if (_categoryRelatesToRecord(concern, record) ||
            _metadataCategoryRelatesTo(concern, record)) {
          score += 0.25;
        }
      }
    }

    final assessmentScore = context.effectiveAssessmentScore;
    if (assessmentScore != null &&
        assessmentScore >= 70 &&
        record.severity == MindAidSeverity.medium) {
      score += 0.25;
    }

    final assessment = context.assessment;
    if (assessment != null && assessment.subscaleScores.isNotEmpty) {
      for (final entry in assessment.subscaleScores.entries) {
        if (entry.value < 55) continue;
        if (_categoryRelatesToRecord(entry.key, record) ||
            _metadataCategoryRelatesTo(entry.key, record)) {
          score += entry.value >= 70 ? 0.45 : 0.25;
        }
      }
    }

    final supportStyle = context.preferredSupportStyle;
    if (supportStyle != null && record.supportStyle == supportStyle.label) {
      score += 0.2;
    }

    if (record.minConcernScore case final minConcernScore?) {
      final effectiveScore = context.effectiveAssessmentScore;
      if (effectiveScore != null && effectiveScore >= minConcernScore) {
        score += 0.25;
      }
    }

    return score;
  }

  static List<String> matchedTerms(String normalizedInput, List<String> terms) {
    return terms
        .where((term) => containsTerm(normalizedInput, normalize(term)))
        .toList(growable: false);
  }

  static List<String> matchedPhrases(
    String normalizedInput,
    List<String> phrases,
  ) {
    return phrases
        .where((phrase) => normalizedInput.contains(normalize(phrase)))
        .toList(growable: false);
  }

  static bool containsTerm(String text, String term) {
    if (term.isEmpty) return false;
    if (term.contains(' ')) return text.contains(term);
    final escaped = RegExp.escape(term);
    return RegExp('(^|\\s)${escaped}s?(\\s|\$)').hasMatch(text);
  }

  static bool _categoryRelatesToRecord(
    String assessmentCategory,
    MindAidDatasetRecord record,
  ) {
    final category = normalize(assessmentCategory);
    final intent = normalize(record.intent.replaceAll('_', ' '));
    final recordCategory = normalize(record.category);
    final haystack = '$intent $recordCategory';

    if (category.contains('academic') && haystack.contains('academic')) {
      return true;
    }
    if (category.contains('stress') && haystack.contains('stress')) {
      return true;
    }
    if (category.contains('sleep') &&
        (haystack.contains('sleep') || haystack.contains('burnout'))) {
      return true;
    }
    if (category.contains('emotional') &&
        (haystack.contains('anxiety') || haystack.contains('emotion'))) {
      return true;
    }
    if (category.contains('social') &&
        (haystack.contains('social') || haystack.contains('loneliness'))) {
      return true;
    }
    if (category.contains('support') && haystack.contains('support')) {
      return true;
    }
    if (category.contains('workplace') && haystack.contains('work')) {
      return true;
    }

    return false;
  }

  static bool _metadataCategoryRelatesTo(
    String assessmentCategory,
    MindAidDatasetRecord record,
  ) {
    final category = normalize(assessmentCategory);
    return record.assessmentCategories.any((item) {
      return normalize(item) == category;
    });
  }
}
