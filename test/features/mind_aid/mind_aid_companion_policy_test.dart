import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_companion_models.dart';
import 'package:mind_mates/features/mind_aid/services/mind_aid_companion_policy.dart';

void main() {
  const policy = MindAidCompanionPolicy();

  MindAidCompanionState resolve(
    String text, [
    MindAidCompanionState current = const MindAidCompanionState(),
  ]) => policy.resolve(text: text, current: current);

  test('listening remains sticky until the user asks for another style', () {
    final listening = resolve('I just want to rant.');
    expect(listening.mode, MindAidConversationMode.listening);
    expect(listening.explicitListening, isTrue);

    final continued = resolve("My groupmates aren't helping me.", listening);
    expect(continued.mode, MindAidConversationMode.listening);

    final coaching = resolve('Okay, what should I actually do?', continued);
    expect(coaching.mode, MindAidConversationMode.coaching);
    expect(coaching.explicitListening, isFalse);
  });

  test(
    'explicit product requests override listening without choosing an action',
    () {
      final listening = resolve('Let me vent.');
      final navigation = resolve('Can I book an appointment?', listening);
      expect(navigation.mode, MindAidConversationMode.navigation);
      expect(navigation.explicitListening, isFalse);

      final resumed = resolve(
        'Never mind, I just want to keep talking.',
        navigation,
      );
      expect(resumed.mode, MindAidConversationMode.listening);
      expect(resumed.explicitListening, isTrue);
    },
  );

  test('reflective, casual, and ambiguous support remain non-navigation', () {
    expect(
      resolve('Why does this bother me so much?').mode,
      MindAidConversationMode.reflective,
    );
    expect(resolve('I passed my exam!').mode, MindAidConversationMode.casual);
    expect(
      resolve('Maybe I should talk to someone.').mode,
      MindAidConversationMode.supportive,
    );
  });
}
