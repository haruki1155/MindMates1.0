import 'forum_language_guard.dart';

export 'forum_language_guard.dart'
    show forumLanguageGuideline, forumLanguageWarning;

enum SecretChatValidationCode {
  allowed,
  offTopic,
  unsafe,
  tooShort,
  tooLong,
  containsPersonalInfo,
  crisisSupport,
  inappropriateLanguage,
}

class SecretChatValidationResult {
  const SecretChatValidationResult({
    required this.code,
    required this.message,
    this.labels = const [],
  });

  final SecretChatValidationCode code;
  final String message;
  final List<String> labels;

  bool get isAllowed => code == SecretChatValidationCode.allowed;
}

class SecretChatSafetyValidator {
  const SecretChatSafetyValidator();

  static const postMaxLength = 500;
  static const commentMaxLength = 400;

  SecretChatValidationResult validatePost(String text) {
    return _validate(
      text,
      minLength: 8,
      maxLength: postMaxLength,
      requireWellbeingTopic: true,
    );
  }

  SecretChatValidationResult validateComment(String text) {
    return _validate(
      text,
      minLength: 3,
      maxLength: commentMaxLength,
      requireWellbeingTopic: false,
    );
  }

  SecretChatValidationResult _validate(
    String text, {
    required int minLength,
    required int maxLength,
    required bool requireWellbeingTopic,
  }) {
    final normalized = text.trim().toLowerCase();
    if (normalized.length < minLength) {
      return const SecretChatValidationResult(
        code: SecretChatValidationCode.tooShort,
        message: 'Share a little more so others can understand your thought.',
      );
    }
    if (normalized.length > maxLength) {
      return SecretChatValidationResult(
        code: SecretChatValidationCode.tooLong,
        message: 'Please keep this under $maxLength characters.',
      );
    }
    if (_containsPersonalInfo(normalized)) {
      return const SecretChatValidationResult(
        code: SecretChatValidationCode.containsPersonalInfo,
        message:
            'For anonymity, please remove emails, phone numbers, links, handles, or IDs.',
      );
    }
    if (_containsCrisisLanguage(normalized)) {
      return const SecretChatValidationResult(
        code: SecretChatValidationCode.crisisSupport,
        labels: ['crisis_support'],
        message:
            'This sounds urgent. Please use MindAid or contact PACC/crisis support instead of posting publicly.',
      );
    }
    if (containsInappropriateLanguage(text)) {
      return const SecretChatValidationResult(
        code: SecretChatValidationCode.inappropriateLanguage,
        message: forumLanguageWarning,
      );
    }
    if (_containsUnsafeLanguage(normalized)) {
      return const SecretChatValidationResult(
        code: SecretChatValidationCode.unsafe,
        message:
            'Let us keep this space supportive. Please remove harmful, explicit, or attacking language.',
      );
    }
    if (requireWellbeingTopic && !_isWellbeingRelated(normalized)) {
      return const SecretChatValidationResult(
        code: SecretChatValidationCode.offTopic,
        message:
            'Secret Chat is only for mental health, wellbeing, school stress, coping, gratitude, and support.',
      );
    }

    return SecretChatValidationResult(
      code: SecretChatValidationCode.allowed,
      labels: _labelsFor(normalized),
      message: 'Ready to share anonymously.',
    );
  }

  bool _containsPersonalInfo(String text) {
    final patterns = [
      RegExp(r'\b[\w\.\-]+@[\w\.\-]+\.\w{2,}\b'),
      RegExp(r'\b(?:\+?\d[\d\-\s()]{7,}\d)\b'),
      RegExp(
        r'\b(?:facebook|instagram|tiktok|telegram|discord)\s*[:@]\s*\w{3,}\b',
      ),
      RegExp(
        r'\b(?:my|add me on|follow me on)\s+(?:facebook|instagram|tiktok|telegram|discord)\b',
      ),
      RegExp(r'@\w{3,}'),
      RegExp(r'\b(?:http|www\.)\S+'),
      RegExp(r'\b(?:student id|school id|id number)\b'),
    ];
    return patterns.any((pattern) => pattern.hasMatch(text));
  }

  bool _containsCrisisLanguage(String text) {
    final patterns = [
      RegExp(r'\bkill\s+myself\b'),
      RegExp(r'\bend\s+my\s+life\b'),
      RegExp(r'\bsuicid(?:e|al)\b'),
      RegExp(r'\bself[ -]?harm\b'),
      RegExp(r'\bhurt\s+myself\b'),
      RegExp(r"\b(?:do not|don't|dont|not)\s+want\s+to\s+live\b"),
    ];
    return patterns.any((pattern) => pattern.hasMatch(text));
  }

  bool _containsUnsafeLanguage(String text) {
    final patterns = [
      RegExp(r'\b(?:porn|sex|sexual|nudes?|explicit\s+sexual)\b'),
      RegExp(r'\b(?:buy\s+now|promo\s+code|free\s+money)\b'),
      RegExp(
        r'\b(?:(?:drugs?|weapons?)\s+for\s+sale|(?:selling|buy)\s+(?:cocaine|meth|ecstasy|illegal\s+drugs?))\b',
      ),
      RegExp(r'\b(?:i\s+will\s+)?(?:beat|hurt|kill)\s+(?:you|him|her|them)\b'),
      RegExp(r'\b(?:hate\s+you|stupid\s+idiot)\b'),
      RegExp(r"\byou(?:\s+are|'re)\s+(?:stupid|worthless|an\s+idiot)\b"),
      RegExp(r'(?:https?://|www\.)\S+(?:\s+\S+){2,}'),
      RegExp(r'\b(?:click|follow)\s+(?:this|my)\s+link\b'),
    ];
    return patterns.any((pattern) => pattern.hasMatch(text));
  }

  bool _isWellbeingRelated(String text) {
    const keywords = [
      'mental',
      'wellbeing',
      'wellness',
      'stress',
      'stressed',
      'anxiety',
      'anxious',
      'gratitude',
      'grateful',
      'pressure',
      'school',
      'class',
      'exam',
      'assignment',
      'study',
      'sleep',
      'rest',
      'tired',
      'burnout',
      'coping',
      'breathe',
      'breathing',
      'self care',
      'self-care',
      'support',
      'family',
      'friends',
      'lonely',
      'sad',
      'overwhelmed',
      'motivation',
      'focus',
      'therapy',
      'counseling',
      'healing',
      'emotion',
      'feel',
      'feeling',
      'mood',
      'worry',
      'worried',
    ];
    return keywords.any(text.contains);
  }

  List<String> _labelsFor(String text) {
    final labels = <String>[];
    void addIf(String label, List<String> words) {
      if (words.any(text.contains)) labels.add(label);
    }

    addIf('stress', ['stress', 'pressure', 'overwhelmed', 'burnout']);
    addIf('anxiety', ['anxiety', 'anxious', 'worry', 'worried']);
    addIf('gratitude', ['gratitude', 'grateful', 'thankful']);
    addIf('school_pressure', [
      'school',
      'class',
      'exam',
      'assignment',
      'study',
    ]);
    addIf('support', ['support', 'family', 'friends', 'lonely']);
    addIf('self_care', ['self care', 'self-care', 'rest', 'sleep', 'breathe']);
    return labels.isEmpty ? const ['wellbeing'] : labels.toSet().toList();
  }
}

/// A post or comment refused on the device or by the server's moderation.
class SecretChatValidationException implements Exception {
  const SecretChatValidationException(this.result);

  final SecretChatValidationResult result;

  @override
  String toString() => result.message;
}
