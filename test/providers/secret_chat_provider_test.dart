import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/secret_chat/domain/secret_chat_safety_validator.dart';
import 'package:mind_mates/models/secret_chat_model.dart';
import 'package:mind_mates/models/secret_chat_profile.dart';
import 'package:mind_mates/providers/secret_chat_provider.dart';
import 'package:mind_mates/repositories/secret_chat_repository.dart';

void main() {
  test('blocked post does not call repository write', () async {
    final repository = _FakeSecretChatRepository();
    final provider = SecretChatProvider(repository);

    await expectLater(
      provider.createPost(
        message: 'Selling shoes today',
        categories: ['Support'],
      ),
      throwsA(isA<SecretChatValidationException>()),
    );

    expect(repository.createdMessages, isEmpty);
    expect(provider.errorMessage, contains('mental health'));
  });

  test('allowed post is added to Mine', () async {
    final repository = _FakeSecretChatRepository();
    final provider = SecretChatProvider(repository);

    await provider.createPost(
      message: 'I feel stressed about exams and need support.',
      categories: ['Stress'],
    );

    expect(provider.posts, hasLength(1));
    expect(provider.selectedFilter, SecretChatFilter.mine);
    expect(provider.visiblePosts.single.isMine, isTrue);
    expect(repository.createdMessages.single, contains('stressed'));
  });

  test('post appears optimistically while Firestore is pending', () async {
    final gate = Completer<void>();
    final repository = _FakeSecretChatRepository(createGate: gate);
    final provider = SecretChatProvider(repository);

    final completion = provider.createPost(
      message: 'I feel stressed about exams and need support.',
      categories: ['Stress', 'Support'],
    );

    expect(provider.posts.single.isPending, isTrue);
    expect(provider.posts.single.categoryList, ['Stress', 'Support']);
    gate.complete();
    await completion;
    expect(provider.posts.single.isPending, isFalse);
  });

  test('rejects missing duplicate or more than three categories', () async {
    final provider = SecretChatProvider(_FakeSecretChatRepository());
    const message = 'I feel stressed about exams and need support.';

    await expectLater(
      provider.createPost(message: message, categories: []),
      throwsArgumentError,
    );
    await expectLater(
      provider.createPost(message: message, categories: ['Stress', 'Stress']),
      throwsArgumentError,
    );
    await expectLater(
      provider.createPost(
        message: message,
        categories: ['Stress', 'Support', 'Anxiety', 'Gratitude'],
      ),
      throwsArgumentError,
    );
  });

  test('allowed comment increments local count', () async {
    final repository = _FakeSecretChatRepository();
    final provider = SecretChatProvider(repository);
    await provider.loadPosts();

    await provider.addComment(
      postId: 'post_1',
      message: 'I feel this too. Rest and support matter.',
    );

    expect(provider.posts.single.commentCount, 1);
    expect(repository.comments.single.message, contains('support'));
  });

  test('ordinary comment without wellness keywords is accepted', () async {
    final repository = _FakeSecretChatRepository();
    final provider = SecretChatProvider(repository);
    await provider.loadPosts();

    await provider.addComment(postId: 'post_1', message: 'Same here!');

    expect(repository.comments.single.message, 'Same here!');
  });

  test('unavailable thread exposes friendly comment error', () async {
    final repository = _FakeSecretChatRepository(
      commentError: const SecretChatThreadUnavailableException(),
    );
    final provider = SecretChatProvider(repository);
    await provider.loadPosts();

    await expectLater(
      provider.addComment(
        postId: 'post_1',
        message: 'I feel this too. Support helps a lot.',
      ),
      throwsA(isA<SecretChatActionException>()),
    );

    expect(provider.posts.single.commentCount, 0);
    expect(repository.comments, isEmpty);
    expect(
      provider.errorMessage,
      'This thread is no longer available for replies.',
    );
  });

  test('profile remains available when activity loading fails', () async {
    final repository = _FakeSecretChatRepository(
      profile: _profile('Calm Owl'),
      activityError: StateError('missing index'),
    );
    final provider = SecretChatProvider(repository);

    await provider.loadProfile();

    expect(provider.profile?.alias, 'Calm Owl');
    expect(provider.profileError, isNull);
    expect(provider.profileActivityError, isNotNull);
    expect(provider.isProfileLoading, isFalse);
    expect(provider.isProfileActivityLoading, isFalse);
  });

  test(
    'recent-post failure preserves successfully refreshed statistics',
    () async {
      final repository = _FakeSecretChatRepository(
        stats: const SecretChatProfileStats(
          reads: 8,
          reactions: 3,
          comments: 2,
        ),
        recentPostsError: StateError('missing index'),
      );
      final provider = SecretChatProvider(repository);

      await provider.loadProfileActivity();

      expect(provider.profileStats.reads, 8);
      expect(provider.profileStatsError, isNull);
      expect(provider.recentPostsError, isNotNull);
      expect(provider.recentPosts, isEmpty);
    },
  );

  test(
    'statistics failure preserves successfully refreshed recent posts',
    () async {
      final repository = _FakeSecretChatRepository(
        statsError: StateError('stats unavailable'),
        recentPosts: [_recentPost()],
      );
      final provider = SecretChatProvider(repository);

      await provider.loadProfileActivity();

      expect(provider.profileStatsError, isNotNull);
      expect(provider.recentPostsError, isNull);
      expect(provider.recentPosts.single.id, 'recent_1');
    },
  );

  test('retry clears only the recovered recent-post error', () async {
    final repository = _FakeSecretChatRepository(
      stats: const SecretChatProfileStats(reads: 4, reactions: 1, comments: 1),
      recentPostsError: StateError('offline'),
    );
    final provider = SecretChatProvider(repository);
    await provider.loadProfileActivity();
    repository.recentPostsError = null;
    repository.recentPosts = [_recentPost()];

    await provider.loadRecentPosts();

    expect(provider.recentPostsError, isNull);
    expect(provider.recentPosts.single.id, 'recent_1');
    expect(provider.profileStats.reads, 4);
  });

  test('profile save is not failed by unrelated activity refresh', () async {
    final repository = _FakeSecretChatRepository(
      profile: _profile('Calm Owl'),
      activityError: StateError('activity unavailable'),
    );
    final provider = SecretChatProvider(repository);
    await provider.loadProfile();

    await provider.saveProfile('Quiet Fox');

    expect(provider.profile?.alias, 'Quiet Fox');
    expect(provider.profileSaveError, isNull);
    expect(repository.activityLoads, 1);
  });

  test('post owner delete removes the post from the local feed', () async {
    final repository = _FakeSecretChatRepository();
    final provider = SecretChatProvider(repository);
    await provider.loadPosts();

    await provider.deletePost('post_1');

    expect(provider.posts, isEmpty);
    expect(repository.deletedPostIds, ['post_1']);
  });

  test('failed post delete restores the post for retry', () async {
    final repository = _FakeSecretChatRepository(
      deleteError: StateError('offline'),
    );
    final provider = SecretChatProvider(repository);
    await provider.loadPosts();

    await expectLater(
      provider.deletePost('post_1'),
      throwsA(isA<SecretChatActionException>()),
    );

    expect(provider.posts.single.id, 'post_1');
    expect(provider.errorMessage, isNotNull);
  });

  test('a post the server refuses is removed, not left as failed', () async {
    final repository = _FakeSecretChatRepository(
      createError: const SecretChatValidationException(
        SecretChatValidationResult(
          code: SecretChatValidationCode.inappropriateLanguage,
          message: 'refused',
        ),
      ),
    );
    final provider = SecretChatProvider(repository);
    await expectLater(
      provider.createPost(
        message: 'I feel stressed about exams and need support.',
        categories: ['Stress'],
      ),
      throwsA(isA<SecretChatValidationException>()),
    );
    expect(provider.posts, isEmpty);
  });
}

SecretChatProfile _profile(String alias) => SecretChatProfile(
  userId: 'user_1',
  alias: alias,
  aliasKey: SecretChatProfile.aliasKeyFor(alias),
);

SecretChatModel _recentPost() => SecretChatModel(
  id: 'recent_1',
  message: 'I feel supported after sharing today.',
  createdAt: DateTime(2026, 7, 4),
  category: 'Support',
  likeCount: 1,
  commentCount: 2,
  authorId: 'user_1',
  isMine: true,
);

class _FakeSecretChatRepository extends SecretChatRepository {
  _FakeSecretChatRepository({
    this.commentError,
    this.createError,
    this.createGate,
    this.profile,
    this.activityError,
    this.statsError,
    this.recentPostsError,
    this.stats = SecretChatProfileStats.empty,
    List<SecretChatModel>? recentPosts,
    this.deleteError,
  }) : recentPosts = recentPosts ?? [];

  final Object? commentError;
  final Object? createError;
  final Completer<void>? createGate;
  SecretChatProfile? profile;
  final Object? activityError;
  Object? statsError;
  Object? recentPostsError;
  final SecretChatProfileStats stats;
  List<SecretChatModel> recentPosts;
  final Object? deleteError;
  int activityLoads = 0;
  final deletedPostIds = <String>[];
  final createdMessages = <String>[];
  final comments = <SecretChatComment>[];

  @override
  bool get hasSignedInUser => true;

  @override
  String? get currentUserId => 'user_1';

  @override
  Future<SecretChatProfile?> fetchCurrentProfile({
    bool forceServer = false,
  }) async {
    return profile;
  }

  @override
  Future<SecretChatProfileStats> fetchProfileStats() async {
    activityLoads++;
    final error = statsError ?? activityError;
    if (error != null) throw error;
    return stats;
  }

  @override
  Future<List<SecretChatModel>> fetchRecentPosts({int limit = 3}) async {
    final error = recentPostsError ?? activityError;
    if (error != null) throw error;
    return recentPosts.take(limit).toList(growable: false);
  }

  @override
  Future<SecretChatProfile> saveProfile({required String alias}) async {
    profile = _profile(SecretChatProfile.normalizeAlias(alias));
    return profile!;
  }

  @override
  Future<void> deletePost(SecretChatModel post) async {
    if (deleteError != null) throw deleteError!;
    deletedPostIds.add(post.id);
  }

  @override
  String newPostId() => 'post_created';

  @override
  Future<List<SecretChatModel>> fetchPosts() async {
    return [
      SecretChatModel(
        id: 'post_1',
        message: 'I feel anxious about school.',
        createdAt: DateTime(2026, 7, 3),
        category: 'Anxiety',
        likeCount: 0,
        commentCount: 0,
        authorId: 'user_1',
        isMine: true,
      ),
    ];
  }

  @override
  Future<SecretChatModel> createPost({
    required String message,
    required List<String> categories,
    String? postId,
    List<String> safetyLabels = const [],
  }) async {
    await createGate?.future;
    if (createError != null) throw createError!;
    createdMessages.add(message);
    return SecretChatModel(
      id: 'post_created',
      message: message,
      createdAt: DateTime(2026, 7, 3),
      category: categories.first,
      categories: categories,
      likeCount: 0,
      commentCount: 0,
      authorId: 'user_1',
      safetyLabels: safetyLabels,
      isMine: true,
    );
  }

  @override
  Future<SecretChatComment> addComment({
    required String postId,
    required String message,
    String? commentId,
    List<String> safetyLabels = const [],
  }) async {
    final error = commentError;
    if (error != null) throw error;

    final comment = SecretChatComment(
      id: 'comment_1',
      postId: postId,
      message: message,
      createdAt: DateTime(2026, 7, 3),
      authorId: 'user_1',
      safetyLabels: safetyLabels,
    );
    comments.add(comment);
    return comment;
  }
}
