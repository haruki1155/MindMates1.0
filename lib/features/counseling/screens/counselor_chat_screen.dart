import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../../routes/mindmate_back_navigation.dart';
import '../controllers/counselor_send_controller.dart';
import '../repositories/counselor_chat_repository.dart';
import '../widgets/counselor_message_timeline.dart';
import '../widgets/service_inquiry_composer.dart';
import '../widgets/messaging_dashboard_theme.dart';

/// Manual human counselor inbox. Never reads or writes MindAid history.
class CounselorChatScreen extends StatefulWidget {
  const CounselorChatScreen({
    super.key,
    this.repository,
    this.outbox,
    this.userId,
  });
  final CounselorChatRepository? repository;
  final CounselorOutboxStore? outbox;
  final String? userId;
  @override
  State<CounselorChatScreen> createState() => _CounselorChatScreenState();
}

class _CounselorChatScreenState extends State<CounselorChatScreen> {
  String? _uid;
  CounselorChatRepository? _repository;
  CounselorSendController? _sender;
  Stream<List<CounselorMessage>>? _messages;
  bool _markingRead = false;
  String? _lastReadCounselorId;

  @override
  void initState() {
    super.initState();
    _uid = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
    final uid = _uid;
    if (uid == null) return;
    final repository = widget.repository ?? FirestoreCounselorChatRepository();
    _repository = repository;
    _messages = repository.watch(uid);
    _sender =
        CounselorSendController(
            uid: uid,
            repository: repository,
            store:
                widget.outbox ??
                CounselorOutboxStore(
                  projectId: Firebase.app().options.projectId,
                  uid: uid,
                ),
          )
          ..addListener(_update)
          ..restore();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  Future<void> _markRead(String messageId) async {
    if (_markingRead ||
        !mounted ||
        _uid == null ||
        _lastReadCounselorId == messageId) {
      return;
    }
    _markingRead = true;
    try {
      await _repository!.markRepliesRead(_uid!);
      _lastReadCounselorId = messageId;
    } catch (error) {
      debugPrint('COUNSELOR_READ_ERROR: $error');
    } finally {
      _markingRead = false;
    }
  }

  @override
  void dispose() {
    _sender?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MessagingDashboardTheme(child: Builder(builder: _buildChat));

  Widget _buildChat(BuildContext context) {
    final sender = _sender;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(20) > 24
            ? MediaQuery.textScalerOf(context).scale(20) * 2.4 + 16
            : kToolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => MindMateBackNavigation.backToMessages(context),
        ),
        title: const Text(
          'Guidance Assistant',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              Icons.support_agent_outlined,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
      body: sender == null
          ? const Center(child: Text('Please sign in to message a counselor.'))
          : Column(
              children: [
                if (MediaQuery.viewInsetsOf(context).bottom == 0)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'PACC counselor · Manual messaging\nNot a live emergency service.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<List<CounselorMessage>>(
                    stream: _messages,
                    builder: (context, snapshot) => Column(
                      children: [
                        if (snapshot.hasError)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Unable to load messages. Check your connection or sign in again.',
                            ),
                          ),
                        if (!snapshot.hasData && !snapshot.hasError)
                          const LinearProgressIndicator(),
                        Expanded(
                          child: CounselorMessageTimeline(
                            uid: _uid!,
                            showEmptyState:
                                snapshot.hasData && !snapshot.hasError,
                            messages: [
                              ...?snapshot.data,
                              for (final attempt in sender.acknowledged)
                                if (!(snapshot.data ?? []).any(
                                  (m) => m.id == attempt.id,
                                ))
                                  CounselorMessage(
                                    id: attempt.id,
                                    text: attempt.text,
                                    senderId: _uid!,
                                    acknowledged: true,
                                  ),
                            ],
                            pending: sender.pending,
                            sending: sender.sending,
                            error: sender.error,
                            onRetry: sender.sending ? null : sender.retry,
                            onAtBottom: () {
                              final replies = snapshot.data?.where(
                                (m) => m.senderId != _uid && !m.pendingWrites,
                              );
                              if (replies != null && replies.isNotEmpty) {
                                _markRead(replies.last.id);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (sender.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            sender.error!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (!sender.ready)
                          TextButton(
                            onPressed: sender.sending ? null : sender.restore,
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  ),
                ServiceInquiryComposer(
                  controller: sender.draft,
                  sending: sender.sending,
                  sendBlocked: !sender.ready || sender.pending != null,
                  onSend: sender.send,
                ),
              ],
            ),
    );
  }
}
