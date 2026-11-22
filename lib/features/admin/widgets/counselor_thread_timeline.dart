import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../domain/counselor_message_presentation.dart';
import '../theme/admin_theme.dart';

class CounselorThreadTimeline extends StatefulWidget {
  const CounselorThreadTimeline({
    super.key,
    required this.uid,
    required this.studentLabel,
    required this.messages,
    this.hasMoreOlder = false,
    this.loadingOlder = false,
    this.onLoadOlder,
    this.onRetryFailed,
    this.onDismissFailed,
    this.now,
  });

  final String uid;
  final String studentLabel;
  final List<CounselorTimelineMessage> messages;
  final bool hasMoreOlder;
  final bool loadingOlder;
  final VoidCallback? onLoadOlder;
  final ValueChanged<String>? onRetryFailed;
  final ValueChanged<String>? onDismissFailed;
  final DateTime Function()? now;

  @override
  State<CounselorThreadTimeline> createState() =>
      _CounselorThreadTimelineState();
}

class _CounselorThreadTimelineState extends State<CounselorThreadTimeline>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  bool _newMessages = false;
  bool _followingLatest = true;
  final _deferred = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scroll.hasClients) {
      _followingLatest =
          _scroll.position.pixels <= kCounselorNearBottomThreshold;
      if (_scroll.position.extentBefore <= kCounselorNearBottomThreshold &&
          _newMessages) {
        setState(() {
          _newMessages = false;
          _deferred.clear();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToBottom();
        });
      }
    }
  }

  Future<void> _scrollToBottom({bool smooth = true}) async {
    if (!_scroll.hasClients) return;
    _followingLatest = true;
    if (_deferred.isNotEmpty) {
      setState(() {
        _deferred.clear();
        _newMessages = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom(smooth: smooth);
      });
      return;
    }
    if (MediaQuery.disableAnimationsOf(context) || !smooth) {
      _scroll.jumpTo(0);
    } else {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    if (mounted &&
        _scroll.hasClients &&
        _scroll.position.pixels <= kCounselorNearBottomThreshold) {
      if (!_scroll.position.isScrollingNotifier.value &&
          _scroll.position.pixels != 0) {
        _scroll.jumpTo(0);
      }
      if (_newMessages) {
        setState(() => _newMessages = false);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _settleBottom());
    }
  }

  void _settleBottom() {
    if (mounted &&
        _followingLatest &&
        _scroll.hasClients &&
        _scroll.position.pixels <= kCounselorNearBottomThreshold &&
        _scroll.position.pixels != 0) {
      _scroll.jumpTo(0);
    }
  }

  (GlobalKey, double)? _visibleAnchor(List<CounselorTimelineMessage> oldList) {
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    // Scan from bottom (latest) upward so the anchor stays valid when older
    // messages are prepended above it.
    for (var i = oldList.length - 1; i >= 0; i--) {
      final key = _keys[oldList[i].id];
      final box = key?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y >= top && y < bottom) {
        return (key!, y);
      }
    }
    return null;
  }

  void _restoreAnchor((GlobalKey, double)? anchor) {
    if (!mounted || anchor == null || !_scroll.hasClients) return;
    final box = anchor.$1.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final delta = box.localToGlobal(Offset.zero).dy - anchor.$2;
    final position = _scroll.position;
    if (delta.abs() > 0.5) {
      _scroll.jumpTo(
        (position.pixels - delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant CounselorThreadTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.messages.map((m) => m.id).toSet();
    final additions = widget.messages
        .where((m) => !oldIds.contains(m.id))
        .toList();

    DateTime? previousLatest;
    for (var i = oldWidget.messages.length - 1; i >= 0; i--) {
      final created = oldWidget.messages[i].createdAt;
      if (created != null) {
        previousLatest = created;
        break;
      }
    }

    final newAtEnd = additions
        .where(
          (m) =>
              previousLatest == null ||
              m.createdAt == null ||
              !m.createdAt!.isBefore(previousLatest),
        )
        .toList();

    final oldPendingCounselorTexts = oldWidget.messages
        .where(
          (m) =>
              m.isCounselor &&
              (m.localId != null ||
                  m.outgoingStatus == CounselorOutgoingStatus.sending ||
                  m.hasPendingWrites),
        )
        .map((m) => m.text)
        .toSet();

    final ownSendStarted = additions.any(
      (m) =>
          m.localId != null &&
          m.outgoingStatus == CounselorOutgoingStatus.sending,
    );

    final newAtEndContainsCounselor = newAtEnd.any(
      (m) => m.isCounselor && !oldPendingCounselorTexts.contains(m.text),
    );

    final nearBottom = isCounselorTimelineNearBottom(
      hasClients: _scroll.hasClients,
      pixels: _scroll.hasClients ? _scroll.position.pixels : 0,
    );

    final action = resolveCounselorTimelineScrollAction(
      hasNewAtEnd: newAtEnd.isNotEmpty,
      hasAnyAdditions: additions.isNotEmpty,
      ownSendStarted: ownSendStarted,
      newAtEndContainsCounselor: newAtEndContainsCounselor,
      nearBottom: nearBottom,
    );

    switch (action) {
      case CounselorScrollAction.scrollToBottom:
        _deferred.clear();
        _newMessages = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToBottom();
        });
      case CounselorScrollAction.deferAndPreserveAnchor:
        final anchor = _visibleAnchor(oldWidget.messages);
        _newMessages = true;
        _deferred.addAll(newAtEnd.map((m) => m.id));
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _restoreAnchor(anchor),
        );
      case CounselorScrollAction.preserveAnchor:
        final anchor = _visibleAnchor(oldWidget.messages);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _restoreAnchor(anchor),
        );
      case CounselorScrollAction.none:
        break;
    }

    final currentIds = widget.messages.map((m) => m.id).toSet();
    _keys.removeWhere((id, _) => !currentIds.contains(id));
  }

  @override
  void didChangeMetrics() {
    final near = isCounselorTimelineNearBottom(
      hasClients: _scroll.hasClients,
      pixels: _scroll.hasClients ? _scroll.position.pixels : 0,
    );
    final anchor = near ? null : _visibleAnchor(widget.messages);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (near) {
        _scrollToBottom(smooth: false);
      } else {
        _restoreAnchor(anchor);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.messages
        .where((m) => !_deferred.contains(m.id))
        .toList();
    final latestFirst = visible.reversed.toList();
    final showOlderControl = widget.hasMoreOlder || widget.loadingOlder;
    final totalCount = latestFirst.length + (showOlderControl ? 1 : 0);
    final now = widget.now?.call() ?? DateTime.now();
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);

    return DecoratedBox(
      decoration: const BoxDecoration(color: AdminColors.canvas),
      child: Stack(
        children: [
          if (visible.isEmpty && !showOlderControl)
            const Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AdminSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 36,
                      color: AdminColors.muted,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No messages in this conversation yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AdminColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Send a reply below to start the conversation.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AdminColors.muted),
                    ),
                  ],
                ),
              ),
            )
          else
            NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                if (notification.direction != ScrollDirection.idle) {
                  _followingLatest = false;
                } else if (_scroll.hasClients &&
                    _scroll.position.pixels <= kCounselorNearBottomThreshold) {
                  _followingLatest = true;
                }
                return false;
              },
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  if (_followingLatest &&
                      _scroll.hasClients &&
                      _scroll.position.pixels <=
                          kCounselorNearBottomThreshold &&
                      !_scroll.position.isScrollingNotifier.value) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _settleBottom(),
                    );
                  }
                  return false;
                },
                child: ListView.builder(
                  key: const Key('counselor_thread_message_list'),
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AdminSpacing.md,
                    vertical: AdminSpacing.sm,
                  ),
                  itemCount: totalCount,
                  findChildIndexCallback: (key) {
                    if (key == const ValueKey('load_older_messages_header')) {
                      return showOlderControl ? latestFirst.length : null;
                    }
                    final index = latestFirst.indexWhere(
                      (m) => ValueKey(m.id) == key,
                    );
                    return index < 0 ? null : index;
                  },
                  itemBuilder: (context, index) {
                    if (showOlderControl && index == latestFirst.length) {
                      return Padding(
                        key: const ValueKey('load_older_messages_header'),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Center(
                          child: widget.loadingOlder
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Loading older messages…',
                                      style: TextStyle(
                                        color: AdminColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                )
                              : OutlinedButton.icon(
                                  onPressed: widget.onLoadOlder,
                                  icon: const Icon(Icons.history, size: 16),
                                  label: const Text('Load older messages'),
                                ),
                        ),
                      );
                    }

                    final message = latestFirst[index];
                    final time = message.createdAt;
                    final olderTime = index + 1 < latestFirst.length
                        ? latestFirst[index + 1].createdAt
                        : null;
                    final dateLabel = time == null
                        ? null
                        : counselorMessageDayLabel(time, now: now);
                    final showDate =
                        time != null &&
                        dateLabel != null &&
                        (olderTime == null ||
                            !isSameCounselorMessageDay(time, olderTime));

                    return Column(
                      key: ValueKey(message.id),
                      children: [
                        if (showDate)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AdminColors.surface,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AdminColors.border),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                child: Text(
                                  dateLabel,
                                  style: const TextStyle(
                                    color: AdminColors.muted,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        KeyedSubtree(
                          key: _keys.putIfAbsent(message.id, GlobalKey.new),
                          child: _CounselorTimelineBubble(
                            message: message,
                            studentLabel: widget.studentLabel,
                            use24HourFormat: use24Hour,
                            onRetry:
                                message.localId != null &&
                                    widget.onRetryFailed != null
                                ? () => widget.onRetryFailed!(message.localId!)
                                : null,
                            onDismiss:
                                message.localId != null &&
                                    widget.onDismissFailed != null
                                ? () =>
                                      widget.onDismissFailed!(message.localId!)
                                : null,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          if (_newMessages)
            Positioned(
              right: 14,
              bottom: 14,
              child: FilledButton.icon(
                key: const Key('counselor_new_messages_button'),
                onPressed: _scrollToBottom,
                icon: const Icon(Icons.arrow_downward, size: 16),
                label: const Text('New messages'),
              ),
            ),
        ],
      ),
    );
  }
}

class _CounselorTimelineBubble extends StatelessWidget {
  const _CounselorTimelineBubble({
    required this.message,
    required this.studentLabel,
    required this.use24HourFormat,
    this.onRetry,
    this.onDismiss,
  });

  final CounselorTimelineMessage message;
  final String studentLabel;
  final bool use24HourFormat;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final isCounselor = message.isCounselor;
    final deliveryState = message.deliveryState;
    final formattedTime = formatCounselorMessageTimestamp(
      message.createdAt,
      use24HourFormat: use24HourFormat,
      isSending: deliveryState == CounselorMessageDeliveryState.sending,
    );

    final bubbleColor = isCounselor ? AdminColors.ink : AdminColors.surface;
    final textColor = isCounselor ? Colors.white : AdminColors.ink;
    final metaColor = isCounselor
        ? const Color(0xFFD6D6D0)
        : AdminColors.muted;
    final senderLabel = isCounselor ? 'Counselor' : studentLabel;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isCounselor ? 14 : 4),
      bottomRight: Radius.circular(isCounselor ? 4 : 14),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth < 520
            ? constraints.maxWidth * 0.88
            : math.min(constraints.maxWidth * 0.76, 540.0);
        return Align(
          alignment: isCounselor ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: isCounselor
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: borderRadius,
                      border: isCounselor
                          ? (deliveryState ==
                                    CounselorMessageDeliveryState.failed
                                ? Border.all(
                                    color: AdminColors.danger,
                                    width: 1.5,
                                  )
                                : null)
                          : Border.all(color: AdminColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$senderLabel · $formattedTime',
                          style: TextStyle(
                            color: metaColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          message.text,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isCounselor)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, right: 2),
                      child: _buildSenderDeliveryFooter(deliveryState),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSenderDeliveryFooter(
    CounselorMessageDeliveryState deliveryState,
  ) {
    switch (deliveryState) {
      case CounselorMessageDeliveryState.sending:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 13, color: AdminColors.muted),
            SizedBox(width: 4),
            Text(
              'Sending…',
              style: TextStyle(
                color: AdminColors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      case CounselorMessageDeliveryState.confirmed:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 14, color: AdminColors.muted),
            SizedBox(width: 4),
            Text(
              'Sent',
              style: TextStyle(
                color: AdminColors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      case CounselorMessageDeliveryState.failed:
        return Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 14,
              color: AdminColors.danger,
            ),
            const Text(
              'Failed to send',
              style: TextStyle(
                color: AdminColors.danger,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry'),
              ),
            if (onDismiss != null)
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AdminColors.muted,
                ),
                child: const Text('Dismiss'),
              ),
          ],
        );
    }
  }
}
