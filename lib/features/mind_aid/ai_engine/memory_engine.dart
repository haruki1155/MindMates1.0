import '../domain/mind_aid_context.dart';

class MemoryEngine {
  final List<String> _recentMessages = [];
  String? _lastIntent;

  MindAidContext snapshot() {
    return MindAidContext(recentMessages: List.unmodifiable(_recentMessages));
  }

  void update({required String intent, required String message}) {
    _lastIntent = intent;
    _recentMessages.add(message);

    if (_recentMessages.length > 10) {
      _recentMessages.removeAt(0);
    }
  }

  bool isRepeatingIntent(String intent) {
    return _lastIntent == intent;
  }

  void reset() {
    _recentMessages.clear();
    _lastIntent = null;
  }
}
