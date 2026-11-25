import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/guidance_quick_replies.dart';

/// Guidance Assistance reply bar: one approved reply or PACC service inquiry
/// at a time, then an explicit Send. No free text.
class GuidanceQuickReplyComposer extends StatelessWidget {
  const GuidanceQuickReplyComposer({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onPickService,
    required this.onClear,
    required this.onSend,
    required this.sending,
    this.notice,
    this.onDiscard,
  });

  final GuidanceQuickReply? selected;
  final ValueChanged<GuidanceQuickReply>? onSelected;
  final VoidCallback? onPickService;
  final VoidCallback? onClear;

  /// Null disables Send (nothing selected, sending, or a message pending).
  final VoidCallback? onSend;
  final bool sending;

  /// Shown above the replies, with [onDiscard] as its action when given.
  final String? notice;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final chosen = selected;
    // A service inquiry is long; show it in full above the bar.
    final showPreview =
        chosen != null && !isGuidanceQuickReplyText(chosen.text);
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (notice != null || showPreview)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(
                        96,
                        MediaQuery.sizeOf(context).height * .22,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (notice != null)
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  notice!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.error,
                                  ),
                                ),
                                if (onDiscard != null)
                                  TextButton(
                                    onPressed: onDiscard,
                                    child: const Text('Discard'),
                                  ),
                              ],
                            ),
                          if (showPreview)
                            Container(
                              key: const Key('guidance_selected_preview'),
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      chosen.text,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Clear',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: onClear,
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                SingleChildScrollView(
                  key: const Key('guidance_quick_replies'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final reply in guidanceQuickReplies)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(reply.text),
                            selected: chosen?.id == reply.id,
                            onSelected: onSelected == null
                                ? null
                                : (_) => onSelected!(reply),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Two equal buttons keep the bar uniform at any text size.
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onPickService,
                        icon: const Icon(Icons.list_alt),
                        label: const Text('Services'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
