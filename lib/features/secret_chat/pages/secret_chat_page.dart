import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/report_provider.dart';
import '../../../providers/secret_chat_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../routes/route_names.dart';
import '../screens/secret_chat_screen.dart';

class SecretChatPage extends StatefulWidget {
  const SecretChatPage({super.key});

  @override
  State<SecretChatPage> createState() => _SecretChatPageState();
}

class _SecretChatPageState extends State<SecretChatPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SecretChatProvider>().loadPosts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SecretChatProvider>();

    return SecretChatScreen(
      posts: provider.visiblePosts,
      categories: provider.categories,
      selectedFilter: provider.selectedFilter,
      savedCount: provider.savedCount,
      searchQuery: provider.searchQuery,
      isLoading: provider.isLoading,
      errorMessage: provider.errorMessage,
      canCreate: provider.canCreate,
      onFilterChanged: provider.setFilter,
      onSearchChanged: provider.setSearchQuery,
      onCreatePost: _createPost,
      onToggleLike: (postId) => _toggleLike(postId),
      onToggleSave: (postId) => _toggleSave(postId),
      onFetchComments: provider.fetchComments,
      onAddComment: _addComment,
      onRetry: provider.loadPosts,
      onProfile: () =>
          Navigator.pushNamed(context, RouteNames.secretChatProfile),
      onPostOpened: provider.recordUniqueRead,
      onRetryPost: provider.retryPost,
      onDeletePost: provider.deletePost,
    );
  }

  Future<void> _createPost({
    required String message,
    required List<String> categories,
  }) async {
    await context.read<SecretChatProvider>().createPost(
      message: message,
      categories: categories,
    );
    _refreshProfileAndReport();
  }

  Future<void> _addComment({
    required String postId,
    required String message,
  }) async {
    await context.read<SecretChatProvider>().addComment(
      postId: postId,
      message: message,
    );
    _refreshProfileAndReport();
  }

  Future<void> _toggleLike(String postId) async {
    await context.read<SecretChatProvider>().toggleLike(postId);
    _refreshProfileAndReport();
  }

  Future<void> _toggleSave(String postId) async {
    await context.read<SecretChatProvider>().toggleSave(postId);
    _refreshProfileAndReport();
  }

  Future<void> _refreshProfileAndReport() async {
    final userProvider = _readProviderOrNull<UserProvider>();
    final userId = userProvider?.user?.id;
    if (userId == null || userId.trim().isEmpty) return;

    try {
      await userProvider?.loadProfile(userId);
      await _readProviderOrNull<ReportProvider>()?.refreshWeeklyReport(userId);
    } catch (_) {
      // Secret Chat changes remain saved even if the summary refresh is delayed.
    }
  }

  T? _readProviderOrNull<T>() {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}
