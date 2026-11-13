import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../home/widgets/home_dashboard_widgets.dart';
import '../repositories/counselor_chat_repository.dart';
import '../controllers/counselor_send_controller.dart';

String counselorDateLabel(BuildContext context, DateTime date, DateTime now) {
  final local = date.toLocal();
  final today = DateUtils.dateOnly(now.toLocal());
  final day = DateUtils.dateOnly(local);
  if (day == today) return 'Today';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  return MaterialLocalizations.of(context).formatMediumDate(local);
}

class CounselorMessageTimeline extends StatefulWidget {
  const CounselorMessageTimeline({
    super.key,
    required this.uid,
    required this.messages,
    this.pending,
    this.showEmptyState = true,
    this.sending = false,
    this.error,
    this.onRetry,
    this.onAtBottom,
    this.now,
  });
  final String uid;
  final bool showEmptyState;

  /// Chronological server history; adding older pages does not change the bottom anchor.
  final List<CounselorMessage> messages;
  final OutgoingInquiry? pending;
  final bool sending;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onAtBottom;
  final DateTime Function()? now;
  @override
  State<CounselorMessageTimeline> createState() =>
      _CounselorMessageTimelineState();
}

class _CounselorMessageTimelineState extends State<CounselorMessageTimeline>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  bool _newMessages = false;
  bool _followingLatest = true;
  final _deferred = <String>{};
  static const _nearBottom = 96.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAtBottom?.call();
    });
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentBefore <= _nearBottom) {
      if (_newMessages) {
        setState(() {
          _newMessages = false;
          _deferred.clear();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _bottom();
        });
      }
      widget.onAtBottom?.call();
    }
  }

  Future<void> _bottom({bool smooth = true}) async {
    if (!_scroll.hasClients) return;
    _followingLatest = true;
    if (_deferred.isNotEmpty) {
      setState(() {
        _deferred.clear();
        _newMessages = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bottom(smooth: smooth);
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
        _scroll.position.pixels <= _nearBottom) {
      if (!_scroll.position.isScrollingNotifier.value &&
          _scroll.position.pixels != 0) {
        _scroll.jumpTo(0);
      }
      setState(() => _newMessages = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _settleBottom());
      widget.onAtBottom?.call();
    }
  }

  void _settleBottom() {
    if (mounted &&
        _followingLatest &&
        _scroll.hasClients &&
        _scroll.position.pixels != 0) {
      _scroll.jumpTo(0);
    }
  }

  // Keep a visible message at its current screen coordinate when newer items
  // arrive below it. This also handles variable heights and older history pages.
  (GlobalKey, double)? _visibleAnchor() {
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    for (final key in _keys.values) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y >= top && y < bottom) return (key, y);
    }
    return null;
  }

  void _restoreAnchor((GlobalKey, double)? anchor) {
    if (!mounted || anchor == null || !_scroll.hasClients) return;
    final box = anchor.$1.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final delta = box.localToGlobal(Offset.zero).dy - anchor.$2;
    final position = _scroll.position;
    if (delta.abs() > .5) {
      _scroll.jumpTo(
        (position.pixels - delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(CounselorMessageTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.messages.map((m) => m.id).toSet();
    final additions = widget.messages
        .where((m) => !previous.contains(m.id))
        .toList();
    final ownAttempt =
        widget.pending?.id != null &&
        widget.pending?.id != oldWidget.pending?.id;
    final previousLatest = oldWidget.messages.isEmpty
        ? null
        : oldWidget.messages.last.createdAt;
    final newAtEnd = additions
        .where(
          (m) =>
              previousLatest == null ||
              m.createdAt == null ||
              !m.createdAt!.isBefore(previousLatest),
        )
        .toList();
    final near = !_scroll.hasClients || _scroll.position.pixels <= _nearBottom;
    final anchor = !near ? _visibleAnchor() : null;
    if (ownAttempt ||
        newAtEnd.any((m) => m.senderId == widget.uid) ||
        (newAtEnd.isNotEmpty && near)) {
      _deferred.clear();
      _newMessages = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bottom();
      });
    } else if (!near &&
        (additions.isNotEmpty || widget.pending?.id != oldWidget.pending?.id)) {
      if (newAtEnd.isNotEmpty) {
        _newMessages = true;
        _deferred.addAll(newAtEnd.map((m) => m.id));
      }
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _restoreAnchor(anchor),
      );
    }
    final ids = widget.messages.map((m) => m.id).toSet()
      ..addAll([if (widget.pending != null) widget.pending!.id]);
    _keys.removeWhere((id, _) => !ids.contains(id));
  }

  @override
  void didChangeMetrics() {
    final near = !_scroll.hasClients || _scroll.position.pixels <= _nearBottom;
    final anchor = near ? null : _visibleAnchor();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (near) {
        _bottom(smooth: false);
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
    final messages = widget.messages
        .where((m) => !_deferred.contains(m.id))
        .toList();
    final pending = widget.pending;
    if (pending != null && !messages.any((m) => m.id == pending.id)) {
      messages.add(
        CounselorMessage(
          id: pending.id,
          text: pending.text,
          senderId: widget.uid,
          pendingWrites: true,
        ),
      );
    }
    final latestFirst = messages.reversed.toList();
    final now = widget.now?.call() ?? DateTime.now();
    return Stack(
      children: [
        if (messages.isEmpty && widget.showEmptyState)
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(HomeMetrics.cardPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.support_agent_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No messages yet. Start a conversation with PACC.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle) {
              _followingLatest = false;
            } else if (_scroll.hasClients &&
                _scroll.position.pixels <= _nearBottom) {
              _followingLatest = true;
            }
            return false;
          },
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              if (_followingLatest &&
                  _scroll.hasClients &&
                  !_scroll.position.isScrollingNotifier.value) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _settleBottom(),
                );
              }
              return false;
            },
            child: ListView.builder(
              key: const Key('counselor_message_list'),
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: latestFirst.length,
              findChildIndexCallback: (key) {
                final index = latestFirst.indexWhere(
                  (m) => ValueKey(m.id) == key,
                );
                return index < 0 ? null : index;
              },
              itemBuilder: (context, index) {
                final message = latestFirst[index];
                final time = message.createdAt;
                final olderTime = index + 1 < latestFirst.length
                    ? latestFirst[index + 1].createdAt
                    : null;
                final date = time == null
                    ? null
                    : counselorDateLabel(context, time, now);
                final showDate =
                    date != null &&
                    (olderTime == null ||
                        !DateUtils.isSameDay(
                          time!.toLocal(),
                          olderTime.toLocal(),
                        ));
                return Column(
                  key: ValueKey(message.id),
                  children: [
                    if (showDate)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(
                              HomeMetrics.radius,
                            ),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Text(
                              date,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                      ),
                    KeyedSubtree(
                      key: _keys.putIfAbsent(message.id, GlobalKey.new),
                      child: CounselorMessageBubble(
                        message: message,
                        own: message.senderId == widget.uid,
                        failed:
                            pending?.id == message.id && widget.error != null,
                        sending: pending?.id == message.id
                            ? widget.sending
                            : message.pendingWrites ||
                                  (time == null && !message.acknowledged),
                        onRetry: widget.onRetry,
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
            right: 12,
            bottom: 12,
            child: FilledButton.icon(
              onPressed: _bottom,
              icon: const Icon(Icons.arrow_downward, size: 18),
              label: const Text('New messages'),
            ),
          ),
      ],
    );
  }
}

class CounselorMessageBubble extends StatelessWidget {
  const CounselorMessageBubble({
    super.key,
    required this.message,
    required this.own,
    this.failed = false,
    this.sending = false,
    this.onRetry,
  });
  final CounselorMessage message;
  final bool own;
  final bool failed;
  final bool sending;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = own ? colors.onPrimary : colors.onSurface;
    final time = message.createdAt?.toLocal();
    final formatted = time == null
        ? 'Time pending'
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(time),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .85,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: own
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: own ? colors.primary : colors.surface,
                  border: own ? null : Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(HomeMetrics.radiusLarge),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatted,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
              if (own)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: failed
                      ? Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 16,
                              color: colors.error,
                            ),
                            Text(
                              ' Not confirmed',
                              style: theme.textTheme.labelSmall,
                            ),
                            TextButton(
                              onPressed: onRetry,
                              child: const Text('Retry'),
                            ),
                          ],
                        )
                      : sending
                      ? const Tooltip(
                          message: 'Sending',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text('Sending…'),
                            ],
                          ),
                        )
                      : Tooltip(
                          message: 'Sent',
                          child: Icon(
                            Icons.check,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
