import 'dart:async';

import 'secret_chat_safety_validator.dart';

/// Asks the server whether a Forum draft may be published; null means allowed
/// (or the check could not run; publishing is still refused by the server).
typedef CheckForumText =
    Future<SecretChatValidationResult?> Function(String text);

/// Runs [CheckForumText] once typing pauses and reports a refusal only while
/// that exact text is still the draft.
class ForumLiveCheck {
  ForumLiveCheck(this._check, this._onRefused);

  final CheckForumText? _check;
  final void Function(SecretChatValidationResult result) _onRefused;
  Timer? _timer;
  String _latest = '';

  void schedule(String text) {
    _latest = text;
    _timer?.cancel();
    final check = _check;
    if (check == null || text.trim().isEmpty) return;
    _timer = Timer(const Duration(milliseconds: 450), () async {
      SecretChatValidationResult? result;
      try {
        result = await check(text);
      } catch (_) {
        return;
      }
      if (result != null && text == _latest) _onRefused(result);
    });
  }

  void dispose() => _timer?.cancel();
}

/// Results that must keep Post and Send disabled.
bool blocksPublishing(SecretChatValidationResult? result) =>
    result?.code == SecretChatValidationCode.inappropriateLanguage ||
    result?.code == SecretChatValidationCode.crisisSupport;
