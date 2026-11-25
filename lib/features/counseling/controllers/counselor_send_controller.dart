import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../services/firebase/firebase_runtime_diagnostics.dart';
import '../data/guidance_quick_replies.dart';
import '../repositories/counselor_chat_repository.dart';

class OutgoingInquiry {
  const OutgoingInquiry({required this.id, required this.text});
  final String id;
  final String text;
}

/// One encrypted outbox per Firebase project and authenticated user.
class CounselorOutboxStore {
  CounselorOutboxStore({String? projectId, String? uid})
    : _key = 'counselor_outbox_v1_${projectId}_$uid';
  final String _key;
  final _storage = const FlutterSecureStorage();
  Future<OutgoingInquiry?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return OutgoingInquiry(
      id: data['id'] as String,
      text: data['text'] as String,
    );
  }

  Future<void> save(OutgoingInquiry attempt) => _storage.write(
    key: _key,
    value: jsonEncode({'id': attempt.id, 'text': attempt.text}),
  );
  Future<void> clear() => _storage.delete(key: _key);
}

class CounselorSendController extends ChangeNotifier {
  CounselorSendController({
    required this.uid,
    required this.repository,
    required this.store,
  });
  final String uid;
  final CounselorChatRepository repository;
  final CounselorOutboxStore store;

  /// The quick reply chosen but not yet sent.
  GuidanceQuickReply? selected;
  OutgoingInquiry? pending;

  /// The pending message predates quick replies and may never be sent.
  bool pendingNotAllowed = false;
  final acknowledged = <OutgoingInquiry>[];
  String? error;
  bool sending = false;
  bool ready = false;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    if (ready || sending) return;
    sending = true;
    _changed();
    try {
      pending = await store.load();
      ready = true;
      error = pending == null
          ? null
          : 'This message has not been confirmed. Retry safely to check or send it.';
    } catch (_) {
      error = 'Unable to restore saved messages. Please retry before sending.';
    } finally {
      sending = false;
      _changed();
    }
  }

  void select(GuidanceQuickReply reply) {
    if (sending) return;
    selected = reply;
    _changed();
  }

  void clearSelection() {
    if (sending) return;
    selected = null;
    _changed();
  }

  /// Sends the selected reply's canonical text; never any other text.
  Future<void> sendSelected() async {
    final reply = selected;
    if (!ready || sending || pending != null || reply == null) return;
    pending = OutgoingInquiry(
      id: repository.newMessageId(uid),
      text: reply.text,
    );
    await retry();
  }

  /// Drops a pending message the quick reply policy refuses.
  Future<void> discardPending() async {
    if (sending || pending == null) return;
    try {
      await store.clear();
      pending = null;
      pendingNotAllowed = false;
      error = null;
    } catch (_) {
      error = 'Unable to discard the saved message. Please retry.';
    }
    _changed();
  }

  Future<void> retry() async {
    if (sending || pendingNotAllowed) return;
    if (!ready) return restore();
    final attempt = pending;
    if (attempt == null) return;
    sending = true;
    error = null;
    _changed();
    var saved = false;
    try {
      // Save before any remote write: even process termination can safely retry.
      await store.save(attempt);
      saved = true;
      await repository.send(uid, attempt.id, attempt.text);
      if (selected?.text == attempt.text) selected = null;
      acknowledged.add(attempt);
      pending = null;
      // If cleanup fails, next launch reconciles this same ID with the server.
      try {
        await store.clear();
      } catch (_) {
        /* Keep the acknowledged ID safe to reconcile. */
      }
    } on QuickReplyNotAllowedException {
      // Never delivered and not allowed any more: keep it out of retries.
      pendingNotAllowed = true;
      error =
          "This earlier message can't be sent under the new Guidance "
          'Assistance policy. Discard it and choose a quick reply.';
    } catch (e) {
      // Diagnostics only: runtime type and Firebase code/plugin. Never the
      // message text, user identifiers or the exception message.
      FirebaseRuntimeDiagnostics.log(
        event: 'counselor_send_failed',
        errorType: e.runtimeType.toString(),
        errorCode: e is FirebaseException ? e.code : null,
        errorPlugin: e is FirebaseException ? e.plugin : null,
      );
      error = !saved
          ? 'Unable to save this message on your device. Keep this screen open and retry.'
          : switch (e) {
              FirebaseException(code: 'permission-denied') =>
                'Message not confirmed. Check your account permissions or contact PACC, then retry.',
              FirebaseException(code: 'unauthenticated') =>
                'Please sign in again before retrying.',
              _ =>
                'Message not confirmed. Check your connection and retry. Your message is kept.',
            };
    } finally {
      sending = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
