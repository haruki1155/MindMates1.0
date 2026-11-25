import 'package:flutter/material.dart';

import '../../../models/secret_chat_model.dart';
import '../../../providers/secret_chat_provider.dart';
import '../domain/secret_chat_safety_validator.dart';
import '../widgets/secret_chat_background.dart';
import '../widgets/secret_chat_post_card.dart';
import '../widgets/secret_chat_avatar.dart';

class SecretChatThreadScreen extends StatefulWidget {
  const SecretChatThreadScreen({
    super.key,
    required this.post,
    required this.categoryColor,
    required this.fetchComments,
    required this.addComment,
    required this.onToggleLike,
    required this.onToggleSave,
    this.onDeletePost,
  });

  final SecretChatModel post;
  final Color categoryColor;
  final Future<List<SecretChatComment>> Function(String postId) fetchComments;
  final Future<void> Function({required String postId, required String message})
  addComment;
  final ValueChanged<String> onToggleLike;
  final ValueChanged<String> onToggleSave;
  final Future<void> Function(String postId)? onDeletePost;

  @override
  State<SecretChatThreadScreen> createState() => _SecretChatThreadScreenState();
}

class _SecretChatThreadScreenState extends State<SecretChatThreadScreen> {
  final _controller = TextEditingController();
  final _validator = const SecretChatSafetyValidator();
  List<SecretChatComment> _comments = [];
  bool _isLoadingComments = true;
  bool _commentsFailed = false;
  SecretChatValidationResult? _validation;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: SecretChatPalette.background,
      appBar: AppBar(
        title: const Text('Anonymous Thread'),
        backgroundColor: SecretChatPalette.sun,
        foregroundColor: SecretChatPalette.text,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                    sliver: SliverToBoxAdapter(
                      child: SecretChatPostCard(
                        post: widget.post,
                        index: 0,
                        categoryColor: widget.categoryColor,
                        onLike: () => widget.onToggleLike(widget.post.id),
                        onSave: () => widget.onToggleSave(widget.post.id),
                        onComments: () {},
                        onDelete:
                            widget.post.isMine && widget.onDeletePost != null
                            ? _confirmDeletePost
                            : null,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: _ThreadSafetyNotice()),
                  Builder(
                    builder: (context) {
                      if (_isLoadingComments) {
                        return const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (_commentsFailed) {
                        return SliverFillRemaining(
                          hasScrollBody: false,
                          child: _ThreadMessage(
                            title: 'Unable to load replies',
                            message: 'Please try opening this thread again.',
                            actionLabel: 'Retry',
                            onAction: _refreshComments,
                          ),
                        );
                      }
                      if (_comments.isEmpty) {
                        return const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _ThreadMessage(
                            title: 'No replies yet',
                            message:
                                'Be the first to respond with support or encouragement.',
                          ),
                        );
                      }
                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                        sliver: SliverList.separated(
                          itemCount: _comments.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _CommentBubble(comment: _comments[index]);
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: _ReplyComposer(
                controller: _controller,
                validation: _validation,
                isSending: _isSending,
                onChanged: _validateReply,
                onSend: _sendReply,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text(
          'This permanently removes the post and its replies from Secret Chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.onDeletePost?.call(widget.post.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _refreshComments() {
    _loadComments();
  }

  Future<void> _loadComments() async {
    if (mounted) {
      setState(() {
        _isLoadingComments = true;
        _commentsFailed = false;
      });
    }
    try {
      final comments = await widget.fetchComments(widget.post.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoadingComments = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
          _commentsFailed = true;
        });
      }
    }
  }

  void _validateReply(String value) {
    if (value.trim().isEmpty) {
      setState(() => _validation = null);
      return;
    }
    setState(() => _validation = _validator.validateComment(value));
  }

  Future<void> _sendReply() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;
    final validation = _validator.validateComment(message);
    if (!validation.isAllowed) {
      setState(() => _validation = validation);
      _showReplyMessage(validation.message);
      return;
    }

    final optimistic = SecretChatComment(
      id: 'pending_${DateTime.now().microsecondsSinceEpoch}',
      postId: widget.post.id,
      message: message,
      createdAt: DateTime.now(),
      isPending: true,
    );
    setState(() {
      _isSending = true;
      _comments = [..._comments, optimistic];
      _controller.clear();
      _validation = null;
    });
    try {
      await widget.addComment(postId: widget.post.id, message: message);
      setState(() {
        _comments = [
          for (final comment in _comments)
            if (comment.id == optimistic.id)
              comment.copyWith(isPending: false)
            else
              comment,
        ];
      });
      _showReplyMessage('Reply posted anonymously.');
    } on SecretChatValidationException catch (error) {
      _restoreDraft(optimistic.id, message, error.result);
      _showReplyMessage(error.result.message);
    } on SecretChatActionException catch (error) {
      _restoreDraft(
        optimistic.id,
        message,
        SecretChatValidationResult(
          code: SecretChatValidationCode.unsafe,
          message: error.message,
        ),
      );
      _showReplyMessage(error.message);
    } catch (_) {
      const failure = 'Unable to send this reply. Please try again.';
      _restoreDraft(
        optimistic.id,
        message,
        const SecretChatValidationResult(
          code: SecretChatValidationCode.unsafe,
          message: failure,
        ),
      );
      _showReplyMessage(failure);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// A reply that was not saved leaves the thread and goes back into the box.
  void _restoreDraft(
    String optimisticId,
    String message,
    SecretChatValidationResult result,
  ) {
    if (!mounted) return;
    setState(() {
      _comments = [
        for (final comment in _comments)
          if (comment.id != optimisticId) comment,
      ];
      if (_controller.text.isEmpty) {
        _controller.text = message;
        _controller.selection = TextSelection.collapsed(offset: message.length);
      }
      _validation = result;
    });
  }

  void _showReplyMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ThreadSafetyNotice extends StatelessWidget {
  const _ThreadSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 16, color: SecretChatPalette.muted),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Keep replies respectful and protect personal information.',
              style: TextStyle(
                color: SecretChatPalette.muted,
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.comment});

  final SecretChatComment comment;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8DDAF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SecretChatAvatar(
                  alias: comment.authorAlias,
                  photoUrl: comment.authorPhotoUrl,
                  radius: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    comment.authorAlias,
                    style: const TextStyle(
                      color: SecretChatPalette.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (comment.isPending)
                  const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              comment.message,
              style: const TextStyle(
                color: SecretChatPalette.text,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (comment.hasFailed) ...[
              const SizedBox(height: 6),
              const Text(
                'Not sent. Copy the message and try again.',
                style: TextStyle(color: Color(0xFFB45309), fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.validation,
    required this.isSending,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final SecretChatValidationResult? validation;
  final bool isSending;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 14,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: SecretChatSafetyValidator.commentMaxLength,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Reply anonymously...',
                    filled: true,
                    fillColor: SecretChatPalette.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed:
                    isSending ||
                        validation?.code ==
                            SecretChatValidationCode.inappropriateLanguage
                    ? null
                    : onSend,
                icon: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: SecretChatPalette.sun,
                  foregroundColor: SecretChatPalette.text,
                ),
              ),
            ],
          ),
          if (validation != null) ...[
            const SizedBox(height: 6),
            Text(
              validation!.message,
              style: TextStyle(
                color: validation!.isAllowed
                    ? const Color(0xFF167A56)
                    : const Color(0xFFB45309),
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThreadMessage extends StatelessWidget {
  const _ThreadMessage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SecretChatPalette.text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SecretChatPalette.muted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
