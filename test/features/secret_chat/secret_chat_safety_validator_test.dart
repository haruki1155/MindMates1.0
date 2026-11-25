import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/secret_chat/domain/secret_chat_safety_validator.dart';

const forumLanguageWarning =
    'MindMate is a safe and supportive community. Please revise your message using respectful language before publishing.';

void main() {
  const validator = SecretChatSafetyValidator();

  test('allows mental health and wellbeing posts', () {
    final result = validator.validatePost(
      'I feel overwhelmed by school pressure, but breathing helps me rest.',
    );

    expect(result.isAllowed, isTrue);
    expect(result.labels, contains('stress'));
  });

  test('blocks off-topic posts', () {
    final result = validator.validatePost('Selling my old laptop this week.');

    expect(result.code, SecretChatValidationCode.offTopic);
  });

  test('blocks personal contact information', () {
    final result = validator.validatePost(
      'I feel anxious, please message me at test@example.com.',
    );

    expect(result.code, SecretChatValidationCode.containsPersonalInfo);
  });

  test('routes crisis language away from public posting', () {
    final result = validator.validatePost(
      'I feel suicidal and do not know what to do.',
    );

    expect(result.code, SecretChatValidationCode.crisisSupport);
  });

  test('allows ordinary contextual comments without wellbeing keywords', () {
    expect(validator.validateComment('Same here!').isAllowed, isTrue);
    expect(
      validator.validateComment('I disagree, but I hear you.').isAllowed,
      isTrue,
    );
    expect(validator.validateComment('You got this').isAllowed, isTrue);
  });

  test('comments still block personal information and unsafe language', () {
    expect(
      validator.validateComment('Message me at person@example.com').code,
      SecretChatValidationCode.containsPersonalInfo,
    );
    expect(
      validator.validateComment('I will hurt you').code,
      SecretChatValidationCode.unsafe,
    );
    expect(
      validator.validateComment('I want to kill myself').code,
      SecretChatValidationCode.crisisSupport,
    );
  });

  test('boundary-aware filters avoid harmless substring false positives', () {
    expect(
      validator.validateComment('My class is in Essex.').isAllowed,
      isTrue,
    );
    expect(
      validator.validateComment('I study weaponry in history.').isAllowed,
      isTrue,
    );
  });

  test('comment length stays between 3 and 400 characters', () {
    expect(
      validator.validateComment('ok').code,
      SecretChatValidationCode.tooShort,
    );
    expect(
      validator.validateComment(List.filled(401, 'a').join()).code,
      SecretChatValidationCode.tooLong,
    );
  });

  test('common and disguised profanity get the community warning', () {
    for (final text in [
      'putangina mo talaga',
      'f*ck this exam stress',
      'g@go ka ba',
      'p u t a n g i n a',
      'tang ina mo',
      'fuuuuuck this school',
      'katangahan ko na naman',
      'Gago​ka',
      'ANG BOBO MO',
    ]) {
      final result = validator.validateComment(text);
      expect(
        result.code,
        SecretChatValidationCode.inappropriateLanguage,
        reason: text,
      );
      expect(result.message, forumLanguageWarning, reason: text);
    }
  });

  test('ordinary words and honest disclosures are not profanity', () {
    for (final text in [
      'I feel anxious about my class assessment.',
      'Napatitig ako sa notes ko at umiyak.',
      'Leche flan made my stressful day better.',
      'I was abused and therapy is helping slowly.',
      'Tangan ko pa rin ang pag-asa.',
    ]) {
      expect(
        validator.validateComment(text).code,
        isNot(SecretChatValidationCode.inappropriateLanguage),
        reason: text,
      );
    }
    expect(
      validator.validatePost('I want to kill myself, school is too much').code,
      SecretChatValidationCode.crisisSupport,
    );
  });
}
