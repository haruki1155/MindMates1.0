import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/guidance_quick_replies.dart';

/// Guidance Assistance reply area: one approved reply at a time, an explicit
/// Send, and routes to a session request or urgent support. No free text.
class GuidanceQuickReplyComposer extends StatelessWidget {
  const GuidanceQuickReplyComposer({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onSend,
    required this.sending,
    required this.collapsed,
    required this.onExpand,
    required this.onRequestSession,
    required this.onUrgentSupport,
    this.notice,
    this.onDiscard,
  });

  final GuidanceQuickReply? selected;
  final ValueChanged<GuidanceQuickReply>? onSelected;

  /// Null disables Send (nothing selected, sending, or a message pending).
  final VoidCallback? onSend;
  final bool sending;
  final bool collapsed;
  final VoidCallback onExpand;
  final VoidCallback onRequestSession;
  final VoidCallback onUrgentSupport;

  /// Shown above the replies, with [onDiscard] as its action when given.
  final String? notice;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // The timeline keeps most of the screen; the reply area scrolls when tall.
    final maxHeight = math.min(360.0, MediaQuery.sizeOf(context).height * .45);
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (notice != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notice!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.error,
                            ),
                          ),
                        ),
                        if (onDiscard != null)
                          TextButton(
                            onPressed: onDiscard,
                            child: const Text('Discard'),
                          ),
                      ],
                    ),
                  // Replies and alternatives scroll; Send stays in view.
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (collapsed)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: onExpand,
                                icon: const Icon(Icons.reply),
                                label: const Text('Reply'),
                              ),
                            )
                          else ...[
                            Text(
                              'Choose a quick reply',
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final reply in guidanceQuickReplies)
                                  ChoiceChip(
                                    label: Text(reply.text),
                                    selected: selected?.id == reply.id,
                                    onSelected: onSelected == null
                                        ? null
                                        : (_) => onSelected!(reply),
                                  ),
                              ],
                            ),
                          ],
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: onRequestSession,
                                icon: const Icon(
                                  Icons.event_available_outlined,
                                ),
                                label: const Text(
                                  'Request a counseling session',
                                ),
                              ),
                              TextButton.icon(
                                onPressed: onUrgentSupport,
                                icon: const Icon(
                                  Icons.health_and_safety_outlined,
                                ),
                                label: const Text('Urgent support'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!collapsed)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Tooltip(
                        message: 'Send reply',
                        child: FilledButton.icon(
                          onPressed: onSend,
                          icon: sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                          label: Text(sending ? 'Sending…' : 'Send'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
