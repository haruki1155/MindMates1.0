import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_assets.dart';
import '../../mind_aid/domain/mind_aid_integration_models.dart';

typedef MindAidFeedbackCallback = void Function(String messageId, bool helpful);

enum MindAidSender { assistant, user }

class MindAidMessage {
  const MindAidMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.createdAt,
    this.status,
    this.categoryLabel,
    this.supportCards = const [],
    this.actions = const [],
    this.source = 'local',
  });

  final String id;
  final MindAidSender sender;
  final String text;
  final DateTime createdAt;
  final String? status;
  final String? categoryLabel;
  final List<MindAidSupportCard> supportCards;
  final List<MindAidAction> actions;
  final String source;
}

class MindAidSupportCard {
  const MindAidSupportCard({
    required this.title,
    required this.description,
    this.icon = Icons.auto_awesome_rounded,
  });

  final String title;
  final String description;
  final IconData icon;
}

class MindAidSuggestion {
  const MindAidSuggestion({
    required this.id,
    required this.label,
    this.iconAsset,
  });

  final String id;
  final String label;
  final String? iconAsset;
}

class MindAidScreen extends StatefulWidget {
  const MindAidScreen({
    super.key,
    this.messages = const [],
    this.suggestions = const [],
    this.disclaimerText,
    this.errorText,
    this.isAssistantTyping = false,
    this.onSendMessage,
    this.onSuggestionSelected,
    this.onHomeTap,
    this.onNotificationTap,
    this.onActionSelected,
    this.onFeedback,
    this.onRetry,
    this.onClearHistory,
    this.onNewConversation,
    this.onPrivacyTap,
  });

  final List<MindAidMessage> messages;
  final List<MindAidSuggestion> suggestions;
  final String? disclaimerText;
  final String? errorText;
  final bool isAssistantTyping;
  final ValueChanged<String>? onSendMessage;
  final ValueChanged<MindAidSuggestion>? onSuggestionSelected;
  final VoidCallback? onHomeTap;
  final VoidCallback? onNotificationTap;
  final ValueChanged<MindAidAction>? onActionSelected;
  final MindAidFeedbackCallback? onFeedback;
  final VoidCallback? onRetry;
  final VoidCallback? onClearHistory;
  final VoidCallback? onNewConversation;
  final VoidCallback? onPrivacyTap;

  @override
  State<MindAidScreen> createState() => _MindAidScreenState();
}

class _MindAidScreenState extends State<MindAidScreen> {
  final TextEditingController _messageController = TextEditingController();

  bool get _canSend =>
      !widget.isAssistantTyping &&
      _messageController.text.trim().isNotEmpty &&
      _messageController.text.trim().length <= 1200;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_handleMessageChanged);
  }

  @override
  void dispose() {
    _messageController
      ..removeListener(_handleMessageChanged)
      ..dispose();
    super.dispose();
  }

  void _handleMessageChanged() {
    setState(() {});
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (!_canSend || message.isEmpty) return;

    widget.onSendMessage?.call(message);
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _MindAidColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _AnimatedMindAidSection(
              delay: 0,
              child: _MindAidHeader(
                onHomeTap: widget.onHomeTap,
                onNotificationTap: widget.onNotificationTap,
                onClearHistory: widget.onClearHistory,
                onNewConversation: widget.onNewConversation,
                onPrivacyTap: widget.onPrivacyTap,
              ),
            ),
            const _AnimatedMindAidSection(
              delay: 70,
              child: _AssistantProfileCard(),
            ),
            Expanded(
              child: _AnimatedMindAidSection(
                delay: 130,
                child: _MindAidConversation(
                  messages: widget.messages,
                  suggestions: widget.suggestions,
                  isAssistantTyping: widget.isAssistantTyping,
                  disclaimerText: widget.disclaimerText,
                  errorText: widget.errorText,
                  onSuggestionSelected: widget.onSuggestionSelected,
                  onActionSelected: widget.onActionSelected,
                  onFeedback: widget.onFeedback,
                  onRetry: widget.onRetry,
                ),
              ),
            ),
            _AnimatedMindAidSection(
              delay: 180,
              child: _MindAidComposer(
                controller: _messageController,
                canSend: _canSend,
                onSend: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MindAidHeader extends StatelessWidget {
  const _MindAidHeader({
    this.onHomeTap,
    this.onNotificationTap,
    this.onClearHistory,
    this.onNewConversation,
    this.onPrivacyTap,
  });

  final VoidCallback? onHomeTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onClearHistory;
  final VoidCallback? onNewConversation;
  final VoidCallback? onPrivacyTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_MindAidColors.sun, _MindAidColors.sunLight],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 15,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'Back to Home',
            child: IconButton(
              onPressed: onHomeTap,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(
                Icons.home_rounded,
                color: _MindAidColors.deepText,
                size: 24,
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'MindAid options',
            onSelected: (value) {
              switch (value) {
                case 'new':
                  onNewConversation?.call();
                  break;
                case 'clear':
                  onClearHistory?.call();
                  break;
                case 'privacy':
                  onPrivacyTap?.call();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('New conversation')),
              PopupMenuItem(value: 'clear', child: Text('Clear history')),
              PopupMenuItem(
                value: 'privacy',
                child: Text('AI privacy settings'),
              ),
            ],
            icon: const Icon(Icons.more_vert_rounded),
          ),
          const SizedBox(width: 4),
          const _MindAidAssetImage(
            assetName: 'creativity_15557951 1.png',
            width: 38,
            height: 38,
            fallbackIcon: Icons.psychology_alt_outlined,
          ),
          const SizedBox(width: 9),
          const _MindAidAssetImage(
            assetName: 'MindMate.png',
            width: 114,
            height: 27,
            fit: BoxFit.contain,
            fallbackText: 'MindMate',
          ),
          const Spacer(),
          Tooltip(
            message: 'Notifications',
            child: IconButton(
              onPressed: onNotificationTap,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const _MindAidAssetImage(
                assetName: 'Notification.png',
                width: 24,
                height: 30,
                fallbackIcon: Icons.notifications,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantProfileCard extends StatelessWidget {
  const _AssistantProfileCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 24, 24, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x13000000),
            blurRadius: 15,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: _MindAidColors.disclaimer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: _MindAidColors.deepText,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MindAid', style: _MindAidText.profileTitle),
                SizedBox(height: 3),
                Text(
                  'Always here to support you',
                  style: _MindAidText.profileSubtitle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MindAidConversation extends StatelessWidget {
  const _MindAidConversation({
    required this.messages,
    required this.suggestions,
    required this.isAssistantTyping,
    required this.disclaimerText,
    required this.errorText,
    required this.onSuggestionSelected,
    required this.onActionSelected,
    required this.onFeedback,
    required this.onRetry,
  });

  final List<MindAidMessage> messages;
  final List<MindAidSuggestion> suggestions;
  final bool isAssistantTyping;
  final String? disclaimerText;
  final String? errorText;
  final ValueChanged<MindAidSuggestion>? onSuggestionSelected;
  final ValueChanged<MindAidAction>? onActionSelected;
  final MindAidFeedbackCallback? onFeedback;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (errorText != null && errorText!.trim().isNotEmpty)
          SliverToBoxAdapter(
            child: _MindAidErrorBanner(text: errorText!.trim()),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 26),
          sliver: messages.isEmpty && !isAssistantTyping
              ? const SliverToBoxAdapter(child: _WelcomeConversation())
              : SliverList.separated(
                  itemCount: messages.length + (isAssistantTyping ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 18),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return const _TypingBubble();
                    }
                    return _MessageBubble(
                      message: messages[index],
                      onActionSelected: onActionSelected,
                      onFeedback: onFeedback,
                      onRetry: onRetry,
                    );
                  },
                ),
        ),
        if (suggestions.isNotEmpty)
          SliverToBoxAdapter(
            child: _SuggestionPanel(
              suggestions: suggestions,
              onSuggestionSelected: onSuggestionSelected,
            ),
          ),
        if (disclaimerText != null && disclaimerText!.trim().isNotEmpty)
          SliverToBoxAdapter(
            child: _DisclaimerPanel(text: disclaimerText!.trim()),
          ),
      ],
    );
  }
}

class _MindAidErrorBanner extends StatelessWidget {
  const _MindAidErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6A17A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: _MindAidText.cardBody)),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _MindAidColors.aiBubble,
          borderRadius: BorderRadius.circular(18),
          boxShadow: _MindAidShadows.bubble,
        ),
        child: const Text('MindAid is thinking...', style: _MindAidText.status),
      ),
    );
  }
}

class _WelcomeConversation extends StatelessWidget {
  const _WelcomeConversation();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: _MessageBubble(
        message: MindAidMessage(
          id: 'welcome',
          sender: MindAidSender.assistant,
          text:
              "Hi there! I'm your AI mental health companion. I'm here to:\n\n"
              "- Suggest coping strategies for anxiety and stress\n"
              "- Provide emotional support\n"
              "- Guide you through relaxation exercises\n"
              "- Listen without judgment\n\n"
              "How are you feeling today?",
          createdAt: DateTime(2026, 1, 1, 9, 12),
          status: '09:12 AM',
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.onActionSelected,
    this.onFeedback,
    this.onRetry,
  });

  final MindAidMessage message;
  final ValueChanged<MindAidAction>? onActionSelected;
  final MindAidFeedbackCallback? onFeedback;
  final VoidCallback? onRetry;

  bool get _isUser => message.sender == MindAidSender.user;

  @override
  Widget build(BuildContext context) {
    if (_isUser) {
      return _UserMessageBubble(message: message, onRetry: onRetry);
    }
    return _AssistantMessageBubble(
      message: message,
      onActionSelected: onActionSelected,
      onFeedback: onFeedback,
    );
  }
}

class _AssistantMessageBubble extends StatelessWidget {
  const _AssistantMessageBubble({
    required this.message,
    this.onActionSelected,
    this.onFeedback,
  });

  final MindAidMessage message;
  final ValueChanged<MindAidAction>? onActionSelected;
  final MindAidFeedbackCallback? onFeedback;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width < 420 ? width - 34 : 380,
          minWidth: width < 360 ? 0 : 260,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
              decoration: BoxDecoration(
                color: _MindAidColors.aiBubble,
                borderRadius: BorderRadius.circular(15),
                boxShadow: _MindAidShadows.bubble,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _AssistantBubbleHeader(),
                  const SizedBox(height: 20),
                  Text(message.text, style: _MindAidText.message),
                  if (message.supportCards.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final card in message.supportCards.take(3)) ...[
                      _MindAidSupportCardView(card: card),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (message.actions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final action in message.actions)
                          ActionChip(
                            avatar: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                            ),
                            label: Text(action.label),
                            onPressed: () => onActionSelected?.call(action),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  _AssistantBubbleMeta(message: message),
                  if (message.id != 'welcome') ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Copy response',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: message.text),
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 17),
                        ),
                        IconButton(
                          tooltip: 'Helpful',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onFeedback?.call(message.id, true),
                          icon: const Icon(
                            Icons.thumb_up_alt_outlined,
                            size: 17,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Not helpful',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onFeedback?.call(message.id, false),
                          icon: const Icon(
                            Icons.thumb_down_alt_outlined,
                            size: 17,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Positioned(
              bottom: -2,
              right: 70,
              child: _AssistantBubbleTail(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantBubbleMeta extends StatelessWidget {
  const _AssistantBubbleMeta({required this.message});

  final MindAidMessage message;

  @override
  Widget build(BuildContext context) {
    final category = message.categoryLabel?.trim();
    final hasCategory = category != null && category.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasCategory) ...[
          Text('Category: $category', style: _MindAidText.category),
          const SizedBox(height: 4),
        ],
        Text(_messageTime(message), style: _MindAidText.status),
        if (message.source == 'dialogflow')
          const Text('Dialogflow assisted', style: _MindAidText.status),
      ],
    );
  }
}

class _AssistantBubbleHeader extends StatelessWidget {
  const _AssistantBubbleHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.support_agent_rounded,
          color: _MindAidColors.deepText,
          size: 21,
        ),
        SizedBox(width: 8),
        Text('MindAid', style: _MindAidText.bubbleName),
      ],
    );
  }
}

class _AssistantBubbleTail extends StatelessWidget {
  const _AssistantBubbleTail();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(46, 36),
      painter: _AssistantBubbleTailPainter(),
    );
  }
}

class _AssistantBubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final paint = Paint()..color = _MindAidColors.aiBubble;
    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(
        size.width * .18,
        2,
        size.width * .28,
        size.height,
        size.width * .5,
        size.height,
      )
      ..cubicTo(
        size.width * .72,
        size.height,
        size.width * .82,
        2,
        size.width,
        0,
      )
      ..close();

    canvas.drawPath(path.shift(const Offset(0, 2)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _UserMessageBubble extends StatelessWidget {
  const _UserMessageBubble({required this.message, this.onRetry});

  final MindAidMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 270),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: const BoxDecoration(
                    color: _MindAidColors.sun,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 7,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    size: 18,
                    color: _MindAidColors.deepText,
                  ),
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _MindAidColors.userBubble,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: _MindAidShadows.chip,
                    ),
                    child: Text(message.text, style: _MindAidText.userMessage),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Text(_messageTime(message), style: _MindAidText.status),
            ),
            if (message.status == 'failed')
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MindAidSupportCardView extends StatelessWidget {
  const _MindAidSupportCardView({required this.card});

  final MindAidSupportCard card;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _MindAidColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(card.icon, size: 18, color: _MindAidColors.deepText),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.title, style: _MindAidText.cardTitle),
                const SizedBox(height: 3),
                Text(card.description, style: _MindAidText.cardBody),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.suggestions,
    required this.onSuggestionSelected,
  });

  final List<MindAidSuggestion> suggestions;
  final ValueChanged<MindAidSuggestion>? onSuggestionSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        children: [
          const Text(
            'Quick suggestions:',
            style: _MindAidText.suggestionsTitle,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth >= 320
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;

              return Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 10,
                children: [
                  for (final suggestion in suggestions.take(6))
                    SizedBox(
                      width: itemWidth.clamp(140, 176).toDouble(),
                      child: _SuggestionChip(
                        suggestion: suggestion,
                        onTap: () => onSuggestionSelected?.call(suggestion),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.suggestion, required this.onTap});

  final MindAidSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _MindAidColors.chip,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: _MindAidShadows.chip,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_hasIconAsset) ...[
                  _MindAidAssetImage(
                    assetName: suggestion.iconAsset!.trim(),
                    width: 14,
                    height: 14,
                    fallbackIcon: Icons.auto_awesome,
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    suggestion.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: _MindAidText.suggestion,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasIconAsset {
    final asset = suggestion.iconAsset;
    return asset != null && asset.trim().isNotEmpty;
  }
}

class _DisclaimerPanel extends StatelessWidget {
  const _DisclaimerPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(0, 6, 0, 0),
      padding: const EdgeInsets.fromLTRB(22, 13, 22, 13),
      decoration: const BoxDecoration(
        color: _MindAidColors.disclaimer,
        border: Border(top: BorderSide(color: Color(0x0D000000))),
      ),
      child: Text(text, style: _MindAidText.disclaimer),
    );
  }
}

class _MindAidComposer extends StatelessWidget {
  const _MindAidComposer({
    required this.controller,
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 14, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE3E3E3))),
          boxShadow: [
            BoxShadow(
              color: Color(0x16000000),
              blurRadius: 10,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 1200,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      required maxLength,
                    }) => currentLength >= 1100
                    ? Text('$currentLength/$maxLength')
                    : null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Type your message...',
                  hintStyle: _MindAidText.inputHint,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: _MindAidColors.inputBorder,
                      width: 2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: _MindAidColors.sun,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Voice input',
              child: IconButton(
                onPressed: null,
                icon: const Icon(
                  Icons.mic_rounded,
                  size: 26,
                  color: _MindAidColors.mic,
                ),
              ),
            ),
            const SizedBox(width: 2),
            _SendButton(canSend: canSend, onSend: onSend),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.canSend, required this.onSend});

  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Send message',
      child: AnimatedScale(
        scale: canSend ? 1 : .94,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: canSend ? _MindAidColors.sun : _MindAidColors.softSun,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: IconButton(
            onPressed: canSend ? onSend : null,
            icon: const Icon(
              Icons.send_outlined,
              color: Colors.black,
              size: 25,
            ),
          ),
        ),
      ),
    );
  }
}

String _messageTime(MindAidMessage message) {
  final status = message.status?.trim();
  if (status != null && status.isNotEmpty && status != 'sent') {
    return status;
  }

  final hour = message.createdAt.hour;
  final minute = message.createdAt.minute.toString().padLeft(2, '0');
  final period = hour >= 12 ? 'PM' : 'AM';
  final twelveHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$twelveHour:$minute $period';
}

class _MindAidAssetImage extends StatelessWidget {
  const _MindAidAssetImage({
    required this.assetName,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.fallbackIcon,
    this.fallbackText,
  });

  final String assetName;
  final double? width;
  final double? height;
  final BoxFit fit;
  final IconData? fallbackIcon;
  final String? fallbackText;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      '${AppAssets.messageImages}/$assetName',
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) {
        if (fallbackText != null) {
          return Text(fallbackText!, style: _MindAidText.brandFallback);
        }

        return SizedBox(
          width: width,
          height: height,
          child: Icon(
            fallbackIcon ?? Icons.image_not_supported_outlined,
            color: Colors.black87,
          ),
        );
      },
    );
  }
}

class _AnimatedMindAidSection extends StatelessWidget {
  const _AnimatedMindAidSection({required this.child, required this.delay});

  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, animatedChild) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 14),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
}

class _MindAidColors {
  const _MindAidColors._();

  static const background = Color(0xFFFAFAFA);
  static const sun = Color(0xFFFFCD3A);
  static const sunLight = Color(0xFFFFD84E);
  static const softSun = Color(0xFFFFE59A);
  static const aiBubble = Color(0xFFFFF4D8);
  static const userBubble = Color(0xFFE0E0E0);
  static const chip = Color(0xFFE2E2E2);
  static const disclaimer = Color(0xFFFFFAEE);
  static const inputBorder = Color(0xFF9F9F9F);
  static const text = Color(0xFF6F5613);
  static const deepText = Color(0xFF2D2308);
  static const muted = Color(0xFF8B8B8B);
  static const mic = Color(0xFF9D9D9D);
  static const cardBorder = Color(0x19A67C00);
}

class _MindAidShadows {
  const _MindAidShadows._();

  static const bubble = [
    BoxShadow(color: Color(0x2A000000), blurRadius: 9, offset: Offset(0, 4)),
  ];

  static const chip = [
    BoxShadow(color: Color(0x24000000), blurRadius: 7, offset: Offset(0, 3)),
  ];
}

class _MindAidText {
  const _MindAidText._();

  static const brandFallback = TextStyle(
    color: Colors.black,
    fontSize: 24,
    fontWeight: FontWeight.w900,
  );

  static const profileTitle = TextStyle(
    color: Color(0xFFFFB700),
    fontSize: 19,
    fontWeight: FontWeight.w900,
  );

  static const profileSubtitle = TextStyle(
    color: Color(0xFFFFB700),
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  static const message = TextStyle(
    color: _MindAidColors.text,
    fontSize: 11.6,
    height: 1.34,
    fontWeight: FontWeight.w500,
  );

  static const userMessage = TextStyle(
    color: _MindAidColors.text,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  static const bubbleName = TextStyle(
    color: Color(0xFFFFB700),
    fontSize: 11.5,
    fontWeight: FontWeight.w900,
  );

  static const cardTitle = TextStyle(
    color: _MindAidColors.deepText,
    fontSize: 11.5,
    height: 1.15,
    fontWeight: FontWeight.w900,
  );

  static const cardBody = TextStyle(
    color: _MindAidColors.text,
    fontSize: 10.5,
    height: 1.28,
    fontWeight: FontWeight.w600,
  );

  static const status = TextStyle(
    color: _MindAidColors.muted,
    fontSize: 10,
    fontWeight: FontWeight.w500,
  );

  static const category = TextStyle(
    color: _MindAidColors.muted,
    fontSize: 9.5,
    height: 1.15,
    fontWeight: FontWeight.w600,
  );

  static const suggestionsTitle = TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  static const suggestion = TextStyle(
    color: _MindAidColors.text,
    fontSize: 10.2,
    fontWeight: FontWeight.w600,
  );

  static const disclaimer = TextStyle(
    color: Colors.black,
    fontSize: 12,
    height: 1.32,
    fontWeight: FontWeight.w500,
  );

  static const inputHint = TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );
}
