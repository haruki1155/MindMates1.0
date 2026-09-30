enum MindAidConversationMode {
  supportive,
  listening,
  reflective,
  coaching,
  casual,
  navigation;

  static MindAidConversationMode fromWire(String? value) {
    return MindAidConversationMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => MindAidConversationMode.supportive,
    );
  }
}

class MindAidCompanionState {
  const MindAidCompanionState({
    this.mode = MindAidConversationMode.supportive,
    this.explicitListening = false,
  });

  final MindAidConversationMode mode;
  final bool explicitListening;
}
