import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/secret_chat/domain/secret_chat_safety_validator.dart';
import 'package:mind_mates/repositories/secret_chat_repository.dart';

FirebaseFunctionsException _refusal(
  String code,
  String? reason,
  String message,
) => FirebaseFunctionsException(
  code: code,
  message: message,
  details: reason == null ? null : {'reason': reason},
);

void main() {
  test('server refusals become the errors the Forum screens handle', () {
    final language = secretChatPublishError(
      _refusal(
        'invalid-argument',
        'inappropriate_language',
        forumLanguageWarning,
      ),
    );
    expect(language, isA<SecretChatValidationException>());
    final languageResult = (language as SecretChatValidationException).result;
    expect(languageResult.code, SecretChatValidationCode.inappropriateLanguage);
    expect(languageResult.message, forumLanguageWarning);

    final crisis =
        secretChatPublishError(
              _refusal(
                'failed-precondition',
                'crisis_support',
                'Please use MindAid.',
              ),
            )
            as SecretChatValidationException;
    expect(crisis.result.code, SecretChatValidationCode.crisisSupport);

    expect(
      secretChatPublishError(
        _refusal('failed-precondition', 'thread_unavailable', 'gone'),
      ),
      isA<SecretChatThreadUnavailableException>(),
    );
    final unavailable = _refusal(
      'unavailable',
      'moderation_unavailable',
      'later',
    );
    expect(secretChatPublishError(unavailable), same(unavailable));
  });
}
