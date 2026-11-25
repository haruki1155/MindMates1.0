import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../features/secret_chat/domain/secret_chat_safety_validator.dart';
export '../features/secret_chat/domain/secret_chat_safety_validator.dart'
    show SecretChatValidationException;
import '../models/secret_chat_model.dart';
import '../models/secret_chat_profile.dart';
import '../repositories/secret_chat_repository.dart';

class SecretChatProvider extends ChangeNotifier {
  SecretChatProvider(
    this.repository, {
    this.validator = const SecretChatSafetyValidator(),
  });

  final SecretChatRepository repository;
  final SecretChatSafetyValidator validator;

  final categories = const [
    SecretChatCategory(label: 'Mental Health', color: Color(0xFFFFC414)),
    SecretChatCategory(label: 'Anxiety', color: Color(0xFFFF7BA5)),
    SecretChatCategory(label: 'Stress', color: Color(0xFFFF9D76)),
    SecretChatCategory(label: 'Gratitude', color: Color(0xFF76A9FF)),
    SecretChatCategory(label: 'Self-care', color: Color(0xFF71D6A4)),
    SecretChatCategory(label: 'School Pressure', color: Color(0xFFB8A7FF)),
    SecretChatCategory(label: 'Support', color: Color(0xFF78C7E8)),
  ];

  List<SecretChatModel> _posts = [];
  SecretChatFilter _selectedFilter = SecretChatFilter.popular;
  String _searchQuery = '';
  bool _isLoading = false;
  String? _errorMessage;
  SecretChatProfile? _profile;
  SecretChatProfileStats _profileStats = SecretChatProfileStats.empty;
  bool _isProfileLoading = false;
  bool _isProfileStatsLoading = false;
  bool _isRecentPostsLoading = false;
  bool _isProfileSaving = false;
  String? _profileError;
  String? _profileStatsError;
  String? _recentPostsError;
  String? _profileSaveError;
  List<SecretChatModel> _recentPosts = [];
  String? _profileUserId;
  final Set<String> _pendingLikes = {};
  final Set<String> _pendingSaves = {};

  List<SecretChatModel> get posts => List.unmodifiable(_posts);
  SecretChatFilter get selectedFilter => _selectedFilter;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get canCreate => repository.hasSignedInUser;
  int get savedCount => _posts.where((post) => post.isSaved).length;
  SecretChatProfile? get profile => _profile;
  SecretChatProfileStats get profileStats => _profileStats;
  bool get isProfileLoading => _isProfileLoading;
  bool get isProfileStatsLoading => _isProfileStatsLoading;
  bool get isRecentPostsLoading => _isRecentPostsLoading;
  bool get isProfileActivityLoading =>
      _isProfileStatsLoading || _isRecentPostsLoading;
  bool get isProfileSaving => _isProfileSaving;
  String? get profileError => _profileError;
  String? get profileStatsError => _profileStatsError;
  String? get recentPostsError => _recentPostsError;
  String? get profileActivityError => _profileStatsError ?? _recentPostsError;
  String? get profileSaveError => _profileSaveError;
  List<SecretChatModel> get recentPosts => List.unmodifiable(_recentPosts);

  List<SecretChatModel> get visiblePosts {
    Iterable<SecretChatModel> result = _posts;
    switch (_selectedFilter) {
      case SecretChatFilter.popular:
        result = result.toList()
          ..sort((a, b) => b.likeCount.compareTo(a.likeCount));
      case SecretChatFilter.mine:
        result = result.where((post) => post.isMine);
      case SecretChatFilter.saved:
        result = result.where((post) => post.isSaved);
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((post) {
        return post.message.toLowerCase().contains(query) ||
            post.categoryList.any(
              (category) => category.toLowerCase().contains(query),
            );
      });
    }

    return result.toList();
  }

  Future<void> loadPosts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _posts = await repository.fetchPosts();
    } catch (error) {
      _posts = [];
      _errorMessage = _friendlyError(error);
    }

    _isLoading = false;
    notifyListeners();
  }

  void setFilter(SecretChatFilter filter) {
    if (_selectedFilter == filter) return;
    _selectedFilter = filter;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> createPost({
    required String message,
    required List<String> categories,
  }) async {
    final validation = validator.validatePost(message);
    if (!validation.isAllowed) {
      _errorMessage = validation.message;
      notifyListeners();
      throw SecretChatValidationException(validation);
    }

    if (categories.isEmpty ||
        categories.length > 3 ||
        categories.toSet().length != categories.length) {
      throw ArgumentError('Choose between 1 and 3 unique categories.');
    }
    // Posting the same text again after a lost response retries the failed
    // post's ID, which the server treats idempotently: never a duplicate.
    for (final post in _posts) {
      if (post.isMine &&
          post.hasFailed &&
          !post.isPending &&
          post.message == message.trim()) {
        return retryPost(post.id);
      }
    }
    final id = repository.newPostId();
    final optimistic = SecretChatModel(
      id: id,
      message: message.trim(),
      createdAt: DateTime.now(),
      category: categories.first,
      categories: categories,
      likeCount: 0,
      commentCount: 0,
      authorId: _profile?.userId,
      authorAlias: _profile?.alias ?? 'Anonymous',
      authorPhotoUrl: _profile?.photoUrl,
      safetyLabels: validation.labels,
      isMine: true,
      isPending: true,
    );
    _posts = [optimistic, ..._posts];
    _selectedFilter = SecretChatFilter.mine;
    _errorMessage = null;
    notifyListeners();
    try {
      await repository.createPost(
        message: message,
        categories: categories,
        postId: id,
        safetyLabels: validation.labels,
      );
      _replacePost(optimistic.copyWith(isPending: false, hasFailed: false));
    } on SecretChatValidationException catch (error) {
      // Refused by moderation: drop it so the author can fix the draft.
      _posts = [
        for (final post in _posts)
          if (post.id != id) post,
      ];
      _errorMessage = error.result.message;
      notifyListeners();
      rethrow;
    } catch (error) {
      _replacePost(optimistic.copyWith(isPending: false, hasFailed: true));
      rethrow;
    }
  }

  Future<void> toggleLike(String postId) async {
    final post = _findPost(postId);
    if (post == null || _pendingLikes.contains(postId)) return;
    _pendingLikes.add(postId);
    final optimistic = post.copyWith(
      isLiked: !post.isLiked,
      likeCount: (post.likeCount + (post.isLiked ? -1 : 1)).clamp(0, 1 << 31),
      isPending: true,
    );
    _replacePost(optimistic);
    try {
      await repository.toggleLike(post);
      _replacePost(optimistic.copyWith(isPending: false, hasFailed: false));
    } catch (_) {
      _replacePost(post.copyWith(hasFailed: true));
      rethrow;
    } finally {
      _pendingLikes.remove(postId);
    }
  }

  Future<void> retryPost(String postId) async {
    final post = _findPost(postId);
    if (post == null || !post.hasFailed || post.isPending) return;
    _replacePost(post.copyWith(isPending: true, hasFailed: false));
    try {
      await repository.createPost(
        message: post.message,
        categories: post.categoryList,
        postId: post.id,
        safetyLabels: post.safetyLabels,
      );
      _replacePost(post.copyWith(isPending: false, hasFailed: false));
    } catch (_) {
      _replacePost(post.copyWith(isPending: false, hasFailed: true));
      rethrow;
    }
  }

  Future<void> deletePost(String postId) async {
    final post = _findPost(postId);
    if (post == null) return;
    if (!post.isMine) {
      throw const SecretChatActionException(
        'Only the post owner can delete it.',
      );
    }
    if (post.isPending) {
      throw const SecretChatActionException(
        'Wait for this post to finish syncing before deleting it.',
      );
    }

    final index = _posts.indexWhere((item) => item.id == postId);
    _posts = _posts.where((item) => item.id != postId).toList();
    _errorMessage = null;
    notifyListeners();
    try {
      await repository.deletePost(post);
      _recentPosts = _recentPosts
          .where((item) => item.id != postId)
          .toList(growable: false);
      notifyListeners();
    } catch (error) {
      final restored = [..._posts];
      restored.insert(index.clamp(0, restored.length), post);
      _posts = restored;
      _errorMessage = _friendlyError(error);
      notifyListeners();
      throw SecretChatActionException(_errorMessage!);
    }
  }

  Future<void> recordUniqueRead(String postId) async {
    final post = _findPost(postId);
    if (post == null) return;
    final updated = await repository.recordUniqueRead(post);
    _replacePost(updated);
  }

  Future<void> loadProfile() async {
    _resetProfileForChangedUser();
    _isProfileLoading = true;
    _profileError = null;
    notifyListeners();
    try {
      _profile = await repository.fetchCurrentProfile(forceServer: true);
    } catch (error) {
      _profileError = _friendlyError(error);
    }
    _isProfileLoading = false;
    notifyListeners();
    await loadProfileActivity();
  }

  Future<void> loadProfileActivity() async {
    _resetProfileForChangedUser();
    await Future.wait([loadProfileStats(), loadRecentPosts()]);
  }

  Future<void> loadProfileStats() async {
    _resetProfileForChangedUser();
    _isProfileStatsLoading = true;
    _profileStatsError = null;
    notifyListeners();
    try {
      _profileStats = await repository.fetchProfileStats();
    } catch (error) {
      _profileStatsError = _friendlyError(error);
    }
    _isProfileStatsLoading = false;
    notifyListeners();
  }

  Future<void> loadRecentPosts() async {
    _resetProfileForChangedUser();
    _isRecentPostsLoading = true;
    _recentPostsError = null;
    notifyListeners();
    try {
      _recentPosts = await repository.fetchRecentPosts();
    } catch (error) {
      _recentPostsError = _friendlyError(error);
    }
    _isRecentPostsLoading = false;
    notifyListeners();
  }

  Future<void> saveProfile(String alias) async {
    await _runProfileSave(() => repository.saveProfile(alias: alias));
  }

  Future<void> uploadProfilePhoto(Uint8List bytes, String contentType) async {
    await _runProfileSave(
      () => repository.uploadProfilePhoto(bytes, contentType: contentType),
    );
  }

  Future<void> removeProfilePhoto() async {
    await _runProfileSave(repository.removeProfilePhoto);
  }

  Future<void> _runProfileSave(
    Future<SecretChatProfile?> Function() action,
  ) async {
    _resetProfileForChangedUser();
    _isProfileSaving = true;
    _profileSaveError = null;
    notifyListeners();
    try {
      _profile = await action();
      final cleanupWarning = repository.takePhotoCleanupWarning();
      if (cleanupWarning != null) _profileSaveError = cleanupWarning;
    } catch (error) {
      _profileSaveError = error.toString().replaceFirst(
        'Invalid argument(s): ',
        '',
      );
      rethrow;
    } finally {
      _isProfileSaving = false;
      notifyListeners();
    }
  }

  void _resetProfileForChangedUser() {
    final userId = repository.currentUserId;
    if (_profileUserId == userId) return;
    _profileUserId = userId;
    _profile = null;
    _profileStats = SecretChatProfileStats.empty;
    _recentPosts = [];
    _profileError = null;
    _profileStatsError = null;
    _recentPostsError = null;
    _profileSaveError = null;
  }

  Future<void> toggleSave(String postId) async {
    final post = _findPost(postId);
    if (post == null || _pendingSaves.contains(postId)) return;
    _pendingSaves.add(postId);
    final optimistic = post.copyWith(isSaved: !post.isSaved, isPending: true);
    _replacePost(optimistic);
    try {
      await repository.toggleSave(post);
      _replacePost(optimistic.copyWith(isPending: false, hasFailed: false));
    } catch (_) {
      _replacePost(post.copyWith(hasFailed: true));
      rethrow;
    } finally {
      _pendingSaves.remove(postId);
    }
  }

  Future<List<SecretChatComment>> fetchComments(String postId) {
    return repository.fetchComments(postId);
  }

  Future<void> addComment({
    required String postId,
    required String message,
  }) async {
    final validation = validator.validateComment(message);
    if (!validation.isAllowed) {
      _errorMessage = validation.message;
      notifyListeners();
      throw SecretChatValidationException(validation);
    }

    final original = _findPost(postId);
    if (original != null) {
      _replacePost(original.copyWith(commentCount: original.commentCount + 1));
    }
    try {
      await repository.addComment(
        postId: postId,
        message: message,
        safetyLabels: validation.labels,
      );
    } catch (error, stackTrace) {
      if (original != null) _replacePost(original);
      debugPrint('Unable to send Secret Chat reply: $error');
      debugPrintStack(stackTrace: stackTrace);
      final message = _friendlyError(error);
      _errorMessage = message;
      notifyListeners();
      throw SecretChatActionException(message);
    }

    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _replacePost(SecretChatModel updated) {
    _posts = [
      for (final post in _posts) post.id == updated.id ? updated : post,
    ];
    notifyListeners();
  }

  SecretChatModel? _findPost(String postId) {
    for (final post in _posts) {
      if (post.id == postId) return post;
    }
    return null;
  }

  String _friendlyError(Object error) {
    if (error is SecretChatAuthException) {
      return 'Please sign in to use Secret Chat.';
    }
    if (error is SecretChatValidationException) {
      return error.result.message;
    }
    if (error is SecretChatThreadUnavailableException) {
      return 'This thread is no longer available for replies.';
    }
    if (error is SecretChatAliasTakenException) return error.toString();
    return 'Secret Chat is unavailable right now. Please try again.';
  }
}

class SecretChatActionException implements Exception {
  const SecretChatActionException(this.message);

  final String message;

  @override
  String toString() => message;
}
