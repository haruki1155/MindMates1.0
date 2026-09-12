import '../domain/mind_aid_chat_models.dart';
import '../domain/mind_aid_dataset_models.dart';
import '../domain/mind_aid_safety.dart';
import 'score_engine.dart';

class MindAidSafetyClassifier {
  const MindAidSafetyClassifier();

  static const _crisisPhrases = [
    'kill myself',
    'end my life',
    'end it all',
    'take my life',
    'no reason to live',
    'cant go on',
    'cannot go on',
    'want to disappear',
    'unalive myself',
    'kms',
    'suicide',
    'self harm',
    'hurt myself',
    'cut myself',
    'i want to die',
    'do not want to live',
    'ayoko nang mabuhay',
    'gusto kong mamatay',
    'magpakamatay',
  ];

  static const _highDistressPhrases = [
    'panic attack',
    'cant breathe',
    'cannot breathe',
    'i am unsafe',
    'not safe right now',
    'unsafe right now',
    'someone might hurt me',
    'i might hurt someone',
    'breaking down',
    'out of control',
  ];

  MindAidSafetyResult classify({
    required String normalizedInput,
    required List<MindAidIntentMatch> matches,
  }) {
    if (normalizedInput.trim().isEmpty) {
      return const MindAidSafetyResult(
        level: MindAidSafetyLevel.needsClarification,
        reason: 'empty_input',
      );
    }

    if (matches.any(_isCrisisMatch) ||
        _containsAny(normalizedInput, _crisisPhrases)) {
      return const MindAidSafetyResult(
        level: MindAidSafetyLevel.crisisOrImmediateRisk,
        reason: 'crisis_signal',
      );
    }

    if (matches.any(_isHighRiskMatch) ||
        _containsAny(normalizedInput, _highDistressPhrases)) {
      return const MindAidSafetyResult(
        level: MindAidSafetyLevel.highDistress,
        reason: 'high_distress_signal',
      );
    }

    if (normalizedInput.split(' ').where((word) => word.isNotEmpty).length <
            2 &&
        matches.isEmpty) {
      return const MindAidSafetyResult(
        level: MindAidSafetyLevel.needsClarification,
        reason: 'short_low_context',
      );
    }

    return const MindAidSafetyResult(level: MindAidSafetyLevel.safeSupport);
  }

  bool _isCrisisMatch(MindAidIntentMatch match) {
    return match.record.severity == MindAidSeverity.crisis ||
        match.record.riskFlags.any((flag) {
          final normalized = ScoreEngine.normalize(flag);
          return normalized.contains('self harm') ||
              normalized.contains('suicidal') ||
              normalized.contains('urgent');
        });
  }

  bool _isHighRiskMatch(MindAidIntentMatch match) {
    return match.record.requiresEscalation ||
        match.record.severity == MindAidSeverity.high;
  }

  bool _containsAny(String normalizedInput, List<String> phrases) {
    for (final phrase in phrases) {
      final normalizedPhrase = ScoreEngine.normalize(phrase);
      if (normalizedPhrase == 'kms') {
        if (RegExp(r'(^|\s)kms(\s|$)').hasMatch(normalizedInput)) return true;
        continue;
      }
      if (normalizedInput.contains(normalizedPhrase)) {
        return true;
      }
    }
    return false;
  }
}
