import 'package:flutter/material.dart';

import '../../../core/widgets/mindmate_bottom_navigation.dart';

import '../../../models/secret_chat_model.dart';
import 'secret_chat_thread_screen.dart';
import '../widgets/secret_chat_background.dart';
import '../widgets/secret_chat_compose_sheet.dart';
import '../widgets/secret_chat_header.dart';
import '../widgets/secret_chat_post_card.dart';

typedef CreateSecretPost =
    Future<void> Function({
      required String message,
      required List<String> categories,
    });

typedef AddSecretComment =
    Future<void> Function({required String postId, required String message});

class SecretChatScreen extends StatefulWidget {
  const SecretChatScreen({
    super.key,
    required this.posts,
    required this.categories,
    required this.selectedFilter,
    required this.savedCount,
    required this.searchQuery,
    required this.isLoading,
    required this.errorMessage,
    required this.canCreate,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onCreatePost,
    required this.onToggleLike,
    required this.onToggleSave,
    required this.onFetchComments,
    required this.onAddComment,
    required this.onRetry,
    this.onProfile,
    this.onPostOpened,
    this.onRetryPost,
    this.onDeletePost,
  });

  final List<SecretChatModel> posts;
  final List<SecretChatCategory> categories;
  final SecretChatFilter selectedFilter;
  final int savedCount;
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;
  final bool canCreate;
  final ValueChanged<SecretChatFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final CreateSecretPost onCreatePost;
  final ValueChanged<String> onToggleLike;
  final ValueChanged<String> onToggleSave;
  final Future<List<SecretChatComment>> Function(String postId) onFetchComments;
  final AddSecretComment onAddComment;
  final VoidCallback onRetry;
  final VoidCallback? onProfile;
  final Future<void> Function(String postId)? onPostOpened;
  final Future<void> Function(String postId)? onRetryPost;
  final Future<void> Function(String postId)? onDeletePost;

  @override
  State<SecretChatScreen> createState() => _SecretChatScreenState();
}

class _SecretChatScreenState extends State<SecretChatScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _backgroundController;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SecretChatPalette.background,
      bottomNavigationBar: const MindMateBottomNavigation(
        active: MindMateNavDestination.secretChat,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: widget.canCreate ? _openComposeSheet : _showSignInRequired,
        backgroundColor: SecretChatPalette.sun,
        foregroundColor: SecretChatPalette.text,
        elevation: 5,
        child: const Icon(Icons.edit_rounded),
      ),
      body: Stack(
        children: [
          SecretChatBackground(animation: _backgroundController),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: SecretChatHeaderDelegate(
                    selectedFilter: widget.selectedFilter,
                    savedCount: widget.savedCount,
                    searchQuery: widget.searchQuery,
                    onSearchChanged: widget.onSearchChanged,
                    onFilterChanged: widget.onFilterChanged,
                    onProfile: widget.onProfile,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  sliver: _buildFeed(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeed() {
    if (widget.isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (widget.errorMessage != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _FeedMessage(
          title: 'Unable to load Secret Chat',
          message: widget.errorMessage!,
          actionLabel: 'Try again',
          onAction: widget.onRetry,
        ),
      );
    }

    if (widget.posts.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _FeedMessage(
          title: 'No thoughts found',
          message: 'No anonymous threads yet. Start a wellbeing conversation.',
        ),
      );
    }

    return SliverList.separated(
      itemCount: widget.posts.length + 1,
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 14 : 18),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const _PrivacyNotice();
        }

        final post = widget.posts[index - 1];
        return SecretChatPostCard(
          key: ValueKey(post.id),
          post: post,
          index: index - 1,
          categoryColor: _categoryColor(post.primaryCategory),
          onLike: () => widget.onToggleLike(post.id),
          onSave: () => widget.onToggleSave(post.id),
          onComments: () => _openCommentsSheet(post),
          onRetry: post.hasFailed && widget.onRetryPost != null
              ? () => widget.onRetryPost!(post.id)
              : null,
          onDelete: post.isMine && widget.onDeletePost != null
              ? () => _confirmDeletePost(post)
              : null,
        );
      },
    );
  }

  Color _categoryColor(String category) {
    return widget.categories
        .firstWhere(
          (item) => item.label == category,
          orElse: () => const SecretChatCategory(
            label: 'Mental Health',
            color: SecretChatPalette.sun,
          ),
        )
        .color;
  }

  Future<void> _openComposeSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SecretChatComposeSheet(
          categories: widget.categories,
          onSubmit: widget.onCreatePost,
        );
      },
    );
  }

  Future<void> _openCommentsSheet(SecretChatModel post) async {
    await widget.onPostOpened?.call(post.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SecretChatThreadScreen(
          post: post,
          categoryColor: _categoryColor(post.primaryCategory),
          fetchComments: widget.onFetchComments,
          addComment: widget.onAddComment,
          onToggleLike: widget.onToggleLike,
          onToggleSave: widget.onToggleSave,
          onDeletePost: widget.onDeletePost,
        ),
      ),
    );
  }

  Future<void> _confirmDeletePost(SecretChatModel post) async {
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
      await widget.onDeletePost?.call(post.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Secret Chat post deleted.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showSignInRequired() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please sign in to share anonymously.')),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_rounded, size: 16, color: SecretChatPalette.muted),
        SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Safe Space - ',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                TextSpan(
                  text:
                      'Share anonymously in a moderated space for mental health and wellbeing.',
                ),
              ],
            ),
            style: TextStyle(
              color: SecretChatPalette.text,
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedMessage extends StatelessWidget {
  const _FeedMessage({
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
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({
    required this.post,
    required this.fetchComments,
    required this.addComment,
  });

  final SecretChatModel post;
  final Future<List<SecretChatComment>> Function(String postId) fetchComments;
  final AddSecretComment addComment;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  late Future<List<SecretChatComment>> _commentsFuture;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _commentsFuture = widget.fetchComments(widget.post.id);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFE4D9B8),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Anonymous replies',
              style: TextStyle(
                color: SecretChatPalette.text,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<SecretChatComment>>(
                future: _commentsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final comments = snapshot.data!;
                  if (comments.isEmpty) {
                    return const Center(
                      child: Text('No replies yet. Be the first to respond.'),
                    );
                  }
                  return ListView.separated(
                    itemCount: comments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: SecretChatPalette.background,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            comments[index].message,
                            style: const TextStyle(
                              color: SecretChatPalette.text,
                              height: 1.3,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Reply anonymously...',
                      filled: true,
                      fillColor: SecretChatPalette.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: _isSending ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: SecretChatPalette.sun,
                    foregroundColor: SecretChatPalette.text,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;
    setState(() => _isSending = true);
    await widget.addComment(postId: widget.post.id, message: message);
    _controller.clear();
    setState(() {
      _isSending = false;
      _commentsFuture = widget.fetchComments(widget.post.id);
    });
  }
}
