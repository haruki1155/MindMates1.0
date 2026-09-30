import 'package:flutter/material.dart';

import '../../../core/widgets/mindmate_bottom_navigation.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_assets.dart';
import '../../mind_aid/domain/mind_aid_integration_models.dart';
import '../../mind_aid/widgets/mind_aid_formatted_text.dart';

typedef MindAidFeedbackCallback = void Function(String messageId, bool helpful);
typedef MindAidActionCallback =
    void Function(String messageId, MindAidAction action);

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
  final VoidCallback? onNotificationTap;
  final MindAidActionCallback? onActionSelected;
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
  final ScrollController _conversationController = ScrollController();
  bool _isNearLatest = true;
  bool _isAutoScrolling = false;

  bool get _canSend =>
      !widget.isAssistantTyping &&
      _messageController.text.trim().isNotEmpty &&
      _messageController.text.trim().length <= 1200;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_handleMessageChanged);
    _conversationController.addListener(_handleConversationScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
  }

  @override
  void didUpdateWidget(covariant MindAidScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.length != widget.messages.length ||
        oldWidget.isAssistantTyping != widget.isAssistantTyping) {
      final followLatest = _isNearLatest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && followLatest) {
          _scrollToLatest(animated: oldWidget.messages.isNotEmpty);
        }
      });
    }
  }

  @override
  void dispose() {
    _messageController
      ..removeListener(_handleMessageChanged)
      ..dispose();
    _conversationController
      ..removeListener(_handleConversationScroll)
      ..dispose();
    super.dispose();
  }

  void _handleMessageChanged() {
    setState(() {});
  }

  void _handleConversationScroll() {
    if (_isAutoScrolling || !_conversationController.hasClients) return;
    final position = _conversationController.position;
    final nearLatest = position.maxScrollExtent - position.pixels <= 80;
    if (nearLatest != _isNearLatest && mounted) {
      setState(() => _isNearLatest = nearLatest);
    }
  }

  Future<void> _scrollToLatest({bool animated = false}) async {
    if (!_conversationController.hasClients) return;
    _isAutoScrolling = true;
    _isNearLatest = true;
    final target = _conversationController.position.maxScrollExtent;
    try {
      if (animated) {
        await _conversationController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _conversationController.jumpTo(target);
      }
      // Lazy slivers refine their extent as newer messages are laid out.
      // Recheck after layout rather than stopping at the old estimate.
      for (var attempt = 0; attempt < 8; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_conversationController.hasClients) return;
        final position = _conversationController.position;
        if (position.maxScrollExtent - position.pixels <= 1) break;
        _conversationController.jumpTo(position.maxScrollExtent);
      }
    } finally {
      _isAutoScrolling = false;
    }
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (!_canSend || message.isEmpty) return;

    _isNearLatest = true;
    widget.onSendMessage?.call(message);
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _MindAidColors.background,
      bottomNavigationBar: const MindMateBottomNavigation(
        active: MindMateNavDestination.message,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _MindAidHeader(
              onNotificationTap: widget.onNotificationTap,
              onClearHistory: widget.onClearHistory,
              onNewConversation: widget.onNewConversation,
              onPrivacyTap: widget.onPrivacyTap,
            ),
            Expanded(
              child: Stack(
                children: [
                  _MindAidConversation(
                    controller: _conversationController,
                    messages: widget.messages,
                    isAssistantTyping: widget.isAssistantTyping,
                    errorText: widget.errorText,
                    onActionSelected: widget.onActionSelected,
                    onFeedback: widget.onFeedback,
                    onRetry: widget.onRetry,
                  ),
                  if (!_isNearLatest && widget.messages.isNotEmpty)
                    Positioned(
                      right: 16,
                      bottom: 14,
                      child: FloatingActionButton.small(
                        heroTag: 'mindaid_latest',
                        tooltip: 'Latest messages',
                        onPressed: () => _scrollToLatest(animated: true),
                        backgroundColor: _MindAidColors.sun,
                        child: const Icon(Icons.south_rounded),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.messages.isEmpty && widget.suggestions.isNotEmpty)
              _SuggestionPanel(
                suggestions: widget.suggestions,
                onSuggestionSelected: widget.onSuggestionSelected,
              ),
            if (widget.messages.isEmpty &&
                widget.disclaimerText != null &&
                widget.disclaimerText!.trim().isNotEmpty)
              _DisclaimerPanel(text: widget.disclaimerText!.trim()),
            _MindAidComposer(
              controller: _messageController,
              canSend: _canSend,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _MindAidHeader extends StatelessWidget {
  const _MindAidHeader({
    this.onNotificationTap,
    this.onClearHistory,
    this.onNewConversation,
    this.onPrivacyTap,
  });

  final VoidCallback? onNotificationTap;
  final VoidCallback? onClearHistory;
  final VoidCallback? onNewConversation;
  final VoidCallback? onPrivacyTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEAE4D7))),
      ),
      child: Row(
        children: [
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
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: _MindAidColors.disclaimer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: _MindAidColors.deepText,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MindAid', style: _MindAidText.headerTitle),
                SizedBox(height: 1),
                Text(
                  'AI wellness assistant',
                  style: _MindAidText.headerSubtitle,
                ),
              ],
            ),
          ),
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

class _MindAidConversation extends StatelessWidget {
  const _MindAidConversation({
    required this.controller,
    required this.messages,
    required this.isAssistantTyping,
    required this.errorText,
    required this.onActionSelected,
    required this.onFeedback,
    required this.onRetry,
  });

  final ScrollController controller;
  final List<MindAidMessage> messages;
  final bool isAssistantTyping;
  final String? errorText;
  final MindAidActionCallback? onActionSelected;
  final MindAidFeedbackCallback? onFeedback;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (errorText != null && errorText!.trim().isNotEmpty)
          SliverToBoxAdapter(
            child: _MindAidErrorBanner(text: errorText!.trim()),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          sliver: messages.isEmpty && !isAssistantTyping
              ? const SliverToBoxAdapter(child: _WelcomeConversation())
              : SliverList.separated(
                  itemCount: messages.length + (isAssistantTyping ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
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
  final MindAidActionCallback? onActionSelected;
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
  final MindAidActionCallback? onActionSelected;
  final MindAidFeedbackCallback? onFeedback;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final emergency = message.status == 'urgent';

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width < 600 ? width * .84 : 520),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
              decoration: BoxDecoration(
                color: emergency
                    ? const Color(0xFFFFFBF3)
                    : _MindAidColors.aiBubble,
                borderRadius: BorderRadius.circular(15),
                border: emergency
                    ? Border.all(color: const Color(0xFFE3A43A))
                    : null,
                boxShadow: _MindAidShadows.bubble,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  emergency
                      ? const _EmergencyBubbleHeader()
                      : const _AssistantBubbleHeader(),
                  const SizedBox(height: 8),
                  MindAidFormattedText(
                    message.text,
                    style: _MindAidText.message,
                  ),
                  if (message.supportCards.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final card in message.supportCards.take(3)) ...[
                      _MindAidSupportCardView(card: card),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (message.actions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _MindAidActionArea(
                      message: message,
                      emergency: emergency,
                      onActionSelected: onActionSelected,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _AssistantBubbleMeta(message: message),
                  if (message.id != 'welcome') ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Copy response',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: message.text),
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 17),
                        ),
                        IconButton(
                          tooltip: 'Helpful',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          onPressed: () => onFeedback?.call(message.id, true),
                          icon: const Icon(
                            Icons.thumb_up_alt_outlined,
                            size: 17,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Not helpful',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
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
          ],
        ),
      ),
    );
  }
}

class _EmergencyBubbleHeader extends StatelessWidget {
  const _EmergencyBubbleHeader();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.warning_amber_rounded, color: Color(0xFFAD6D00), size: 20),
      SizedBox(width: 7),
      Text(
        'Emergency Support',
        style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF6B4700)),
      ),
    ],
  );
}

class _MindAidActionArea extends StatelessWidget {
  const _MindAidActionArea({
    required this.message,
    required this.emergency,
    required this.onActionSelected,
  });

  final MindAidMessage message;
  final bool emergency;
  final MindAidActionCallback? onActionSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final action in message.actions) ...[
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
            side: BorderSide(
              color: emergency ? const Color(0xFFE3A43A) : _MindAidColors.sun,
            ),
          ),
          onPressed: () => onActionSelected?.call(message.id, action),
          icon: Icon(
            emergency
                ? Icons.support_agent_rounded
                : Icons.arrow_forward_rounded,
            size: 18,
          ),
          label: Text(action.label, textAlign: TextAlign.left),
        ),
        const SizedBox(height: 8),
      ],
      if (!emergency)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => onActionSelected?.call(
              message.id,
              const MindAidAction(
                type: MindAidActionType.dismissPending,
                label: 'Not now',
              ),
            ),
            child: const Text('Not now'),
          ),
        ),
    ],
  );
}

class _AssistantBubbleMeta extends StatelessWidget {
  const _AssistantBubbleMeta({required this.message});

  final MindAidMessage message;

  @override
  Widget build(BuildContext context) {
    final category = message.categoryLabel?.trim() ?? '';
    final hasCategory = category.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasCategory)
              Flexible(child: Text(category, style: _MindAidText.category)),
            if (hasCategory) const SizedBox(width: 6),
            Text(_messageTime(message), style: _MindAidText.status),
          ],
        ),
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

class _UserMessageBubble extends StatelessWidget {
  const _UserMessageBubble({required this.message, this.onRetry});

  final MindAidMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width < 600
              ? MediaQuery.sizeOf(context).width * .84
              : 520,
        ),
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
                      horizontal: 14,
                      vertical: 9,
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
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: suggestions.take(6).length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final suggestion = suggestions[index];
            return _SuggestionChip(
              suggestion: suggestion,
              onTap: () => onSuggestionSelected?.call(suggestion),
            );
          },
        ),
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
      borderRadius: BorderRadius.circular(19),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(19)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                    maxLines: 1,
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
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const BoxDecoration(
        color: _MindAidColors.disclaimer,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'MindAid provides non-clinical wellness support.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _MindAidText.disclaimer,
            ),
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('About MindAid'),
                content: Text(text),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            child: const Text('Learn more'),
          ),
        ],
      ),
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE3E3E3))),
          boxShadow: [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 6,
              offset: Offset(0, -2),
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
                    horizontal: 14,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: _MindAidColors.inputBorder,
                      width: 2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: _MindAidColors.sun,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
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
    this.fallbackIcon,
  });

  final String assetName;
  final double? width;
  final double? height;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      '${AppAssets.messageImages}/$assetName',
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) {
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

class _MindAidColors {
  const _MindAidColors._();

  static const background = Color(0xFFFAFAFA);
  static const sun = Color(0xFFFFCD3A);
  static const softSun = Color(0xFFFFE59A);
  static const aiBubble = Color(0xFFFFF4D8);
  static const userBubble = Color(0xFFE0E0E0);
  static const chip = Color(0xFFE2E2E2);
  static const disclaimer = Color(0xFFFFFAEE);
  static const inputBorder = Color(0xFF9F9F9F);
  static const text = Color(0xFF6F5613);
  static const deepText = Color(0xFF2D2308);
  static const muted = Color(0xFF8B8B8B);
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

  static const headerTitle = TextStyle(
    color: _MindAidColors.deepText,
    fontSize: 17,
    fontWeight: FontWeight.w800,
  );

  static const headerSubtitle = TextStyle(
    color: _MindAidColors.muted,
    fontSize: 11,
    fontWeight: FontWeight.w600,
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
