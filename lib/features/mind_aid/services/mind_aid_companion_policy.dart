import '../domain/mind_aid_companion_models.dart';

/// Determines how MindAid should respond. It does not select product actions
/// and must never influence safety or access decisions.
class MindAidCompanionPolicy {
  const MindAidCompanionPolicy();

  MindAidCompanionState resolve({
    required String text,
    required MindAidCompanionState current,
  }) {
    final input = _normalize(text);
    if (_isProductRequest(input)) {
      return const MindAidCompanionState(
        mode: MindAidConversationMode.navigation,
      );
    }
    if (_has(input, _coachingPhrases)) {
      return const MindAidCompanionState(
        mode: MindAidConversationMode.coaching,
      );
    }
    if (_has(input, _listeningPhrases)) {
      return const MindAidCompanionState(
        mode: MindAidConversationMode.listening,
        explicitListening: true,
      );
    }
    if (_has(input, _reflectionPhrases)) {
      return const MindAidCompanionState(
        mode: MindAidConversationMode.reflective,
      );
    }
    if (_has(input, _casualPhrases)) {
      return const MindAidCompanionState(mode: MindAidConversationMode.casual);
    }
    if (current.explicitListening) {
      return const MindAidCompanionState(
        mode: MindAidConversationMode.listening,
        explicitListening: true,
      );
    }
    return const MindAidCompanionState();
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  bool _has(String input, List<String> phrases) =>
      phrases.any((phrase) => RegExp('(^| )$phrase( |\$)').hasMatch(input));

  bool _isProductRequest(String input) {
    final asks = _has(input, const [
      'can i',
      'can we',
      'could i',
      'please',
      'show me',
      'open',
      'start',
      'book',
      'schedule',
      'take',
      'give me',
      'help me',
    ]);
    final target = _has(input, const [
      'appointment',
      'counselor',
      'counseling',
      'assessment',
      'pacc services',
      'paacc services',
      'breathing exercise',
      'grounding exercise',
      'my appointments',
    ]);
    return asks && target;
  }

  static const _listeningPhrases = [
    'just listen',
    'just want to talk',
    'just want to keep talking',
    'just want to rant',
    'let me rant',
    'let me vent',
    'need to vent',
    'no advice',
    'dont give me advice',
    'dont want solutions',
    'dont try to fix',
    'can i tell you something',
  ];
  static const _coachingPhrases = [
    'what should i do',
    'what should i actually do',
    'what can i do',
    'help me figure this out',
    'help me make a plan',
    'give me advice',
    'what would you suggest',
    'how should i handle this',
    'how do i deal with this',
    'okay help me',
  ];
  static const _reflectionPhrases = [
    'why do i keep doing this',
    'why am i feeling this way',
    'i dont understand why',
    'why does this bother me',
    'help me understand this',
    'why do i always worry',
  ];
  static const _casualPhrases = [
    'i passed',
    'i finished',
    'today was actually good',
    'im bored',
    'guess what happened',
    'i finally did it',
  ];
}
