import 'dart:math';

class MindAidLiveTurn {
  const MindAidLiveTurn({required this.role, required this.text});
  final String role;
  final String text;

  Map<String, String> toMap() => {'role': role, 'text': text};
}

class MindAidSessionMemory {
  const MindAidSessionMemory({this.liveTurns = const []});

  // This is the only conversational memory in Phase 3. It is populated only
  // during the live provider instance and is never reconstructed from history.
  final List<MindAidLiveTurn> liveTurns;

  static String newSessionInstanceId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  MindAidSessionMemory commit({
    required String userText,
    required String assistantText,
  }) => MindAidSessionMemory(
    liveTurns: [
      ...liveTurns,
      MindAidLiveTurn(role: 'user', text: userText),
      MindAidLiveTurn(role: 'assistant', text: assistantText),
    ].takeLast(8),
  );
}

extension<T> on List<T> {
  List<T> takeLast(int count) => length <= count
      ? List.unmodifiable(this)
      : List.unmodifiable(sublist(length - count));
}
