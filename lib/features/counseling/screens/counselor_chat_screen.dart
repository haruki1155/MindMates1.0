import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../../routes/mindmate_back_navigation.dart';
import '../controllers/counselor_send_controller.dart';
import '../repositories/counselor_chat_repository.dart';
import '../widgets/counselor_message_timeline.dart';
import '../widgets/guidance_quick_reply_composer.dart';
import '../widgets/messaging_dashboard_theme.dart';
import 'pacc_counseling_screen.dart';

typedef OpenPaccCounseling =
    void Function(BuildContext context, {required bool startBooking});

const guidanceAssistanceInfo =
    'Guidance Assistance allows you to receive instructions from your '
    'guidance counselor and respond using predefined Quick Replies. For '
    'concerns requiring detailed discussion, please request a counseling '
    'session.';

void _openPaccCounseling(BuildContext context, {required bool startBooking}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PaccCounselingScreen(startBooking: startBooking),
    ),
  );
}

/// Manual human counselor inbox. Never reads or writes MindAid history.
class CounselorChatScreen extends StatefulWidget {
  const CounselorChatScreen({
    super.key,
    this.repository,
    this.outbox,
    this.userId,
    this.openPaccCounseling = _openPaccCounseling,
  });
  final CounselorChatRepository? repository;

  /// Opens PACC counseling, booking a session when [startBooking] is true.
  final OpenPaccCounseling openPaccCounseling;
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
  Stream<DateTime?>? _counselorReadAt;
  bool _collapsed = false;
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
    _counselorReadAt = repository.watchCounselorReadAt(uid);
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

  Future<void> _sendReply() async {
    final sender = _sender!;
    await sender.sendSelected();
    if (mounted && sender.pending == null && sender.error == null) {
      setState(() => _collapsed = true);
    }
  }

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Guidance Assistance'),
        content: const Text(guidanceAssistanceInfo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
          IconButton(
            tooltip: 'About Guidance Assistance',
            icon: const Icon(Icons.info_outline),
            onPressed: _showInfo,
          ),
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
                  // Scrolls instead of overflowing at large text on small screens.
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'PACC counselor · Manual messaging\nNot a live emergency service.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
                          child: StreamBuilder<DateTime?>(
                            stream: _counselorReadAt,
                            builder: (context, readAt) =>
                                CounselorMessageTimeline(
                                  uid: _uid!,
                                  counterpartReadAt: readAt.data,
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
                                  onRetry:
                                      sender.sending || sender.pendingNotAllowed
                                      ? null
                                      : sender.retry,
                                  onAtBottom: () {
                                    final replies = snapshot.data?.where(
                                      (m) =>
                                          m.senderId != _uid &&
                                          !m.pendingWrites,
                                    );
                                    if (replies != null && replies.isNotEmpty) {
                                      _markRead(replies.last.id);
                                    }
                                  },
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (sender.error != null && !sender.pendingNotAllowed)
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
                GuidanceQuickReplyComposer(
                  selected: sender.selected,
                  onSelected: sender.sending ? null : sender.select,
                  onSend:
                      !sender.ready ||
                          sender.sending ||
                          sender.pending != null ||
                          sender.selected == null
                      ? null
                      : _sendReply,
                  sending: sender.sending,
                  collapsed: _collapsed,
                  onExpand: () => setState(() => _collapsed = false),
                  onRequestSession: () =>
                      widget.openPaccCounseling(context, startBooking: true),
                  onUrgentSupport: () =>
                      widget.openPaccCounseling(context, startBooking: false),
                  notice: sender.pendingNotAllowed ? sender.error : null,
                  onDiscard: sender.pendingNotAllowed
                      ? sender.discardPending
                      : null,
                ),
              ],
            ),
    );
  }
}
