import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_session_memory.dart';

void main() {
  test('keeps only eight current-session turns', () {
    var memory = const MindAidSessionMemory();
    for (var index = 0; index < 5; index++) {
      memory = memory.commit(
        userText: 'user $index',
        assistantText: index == 0
            ? 'What part are you handling yourself?'
            : 'Thanks for explaining.',
      );
    }
    expect(memory.liveTurns, hasLength(8));
  });

  test('session instance identifiers are opaque and rotate', () {
    final first = MindAidSessionMemory.newSessionInstanceId();
    final second = MindAidSessionMemory.newSessionInstanceId();
    expect(first, matches(RegExp(r'^[a-f0-9]{48}$')));
    expect(second, isNot(first));
  });
}
