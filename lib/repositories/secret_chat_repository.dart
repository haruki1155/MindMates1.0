import 'dart:typed_data';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../database/firestore_collections.dart';
import '../features/secret_chat/domain/secret_chat_safety_validator.dart';
import '../models/secret_chat_model.dart';
import '../models/secret_chat_profile.dart';
import '../models/secret_chat_profile_upload_exception.dart';
import '../services/firebase/firestore_service.dart';
import 'user_repository.dart';

class SecretChatAuthException implements Exception {
  const SecretChatAuthException();

  @override
  String toString() => 'Please sign in to use Secret Chat.';
}

class SecretChatThreadUnavailableException implements Exception {
  const SecretChatThreadUnavailableException();

  @override
  String toString() => 'This thread is no longer available for replies.';
}

/// Turns a refusal from the moderated publishing callables into the errors the
/// Forum screens already handle; anything else is passed through.
Object secretChatPublishError(FirebaseFunctionsException error) {
  final details = error.details;
  final reason = details is Map ? details['reason'] : null;
  return switch (reason) {
    'inappropriate_language' => SecretChatValidationException(
      SecretChatValidationResult(
        code: SecretChatValidationCode.inappropriateLanguage,
        message: error.message ?? forumLanguageWarning,
      ),
    ),
    'crisis_support' => SecretChatValidationException(
      SecretChatValidationResult(
        code: SecretChatValidationCode.crisisSupport,
        labels: const ['crisis_support'],
        message: error.message ?? 'Please use MindAid or contact PACC.',
      ),
    ),
    'thread_unavailable' => const SecretChatThreadUnavailableException(),
    _ => error,
  };
}

class SecretChatRepository {
  SecretChatRepository({
    FirestoreService? firestoreService,
    UserRepository? userRepository,
    this.firebaseAuth,
    FirebaseStorage? firebaseStorage,
    FirebaseFunctions? firebaseFunctions,
  }) : _firestoreService = firestoreService ?? FirestoreService(),
       _userRepository = userRepository ?? UserRepository(),
       _storage = firebaseStorage,
       _functions = firebaseFunctions;

  final FirestoreService _firestoreService;
  final UserRepository _userRepository;
  final FirebaseAuth? firebaseAuth;
  final FirebaseStorage? _storage;
  final FirebaseFunctions? _functions;
  final Map<String, SecretChatProfile?> _profileCache = {};
  String? _photoCleanupWarning;

  String? takePhotoCleanupWarning() {
    final warning = _photoCleanupWarning;
    _photoCleanupWarning = null;
    return warning;
  }

  FirebaseStorage get storage => _storage ?? FirebaseStorage.instance;
  FirebaseFunctions get functions => _functions ?? FirebaseFunctions.instance;

  FirebaseAuth get _auth => firebaseAuth ?? FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;
  bool get hasSignedInUser => currentUserId != null;
  String newPostId() => _firestoreService.firestore
      .collection(FirestoreCollections.secretChats)
      .doc()
      .id;
  String newCommentId() => _firestoreService.firestore
      .collection(FirestoreCollections.secretChatComments)
      .doc()
      .id;

  String _requireUserId() {
    final uid = currentUserId;
    if (uid == null || uid.trim().isEmpty) {
      throw const SecretChatAuthException();
    }
    return uid;
  }

  Future<List<SecretChatModel>> fetchPosts() async {
    final uid = _requireUserId();
    final results = await Future.wait([
      _firestoreService.getDocuments(
        FirestoreCollections.secretChats,
        whereEquals: {'moderationStatus': 'active'},
        orderBy: 'createdAt',
        limit: 50,
      ),
      _fetchInteractions(uid),
    ]);
    final docs = results[0] as List<Map<String, dynamic>>;
    final interactions = results[1] as Map<String, Map<String, dynamic>>;
    final posts = docs
        .map((doc) {
          final id = doc['id']?.toString() ?? '';
          final interaction = interactions[id];
          return SecretChatModel.fromJson(
            doc,
            id: id,
            currentUserId: uid,
            isLiked: interaction?['liked'] == true,
            isSaved: interaction?['saved'] == true,
          );
        })
        .toList(growable: false);
    return _resolvePostProfiles(posts);
  }

  Future<SecretChatModel> createPost({
    required String message,
    required List<String> categories,
    String? postId,
    List<String> safetyLabels = const [],
  }) async {
    final uid = _requireUserId();
    final createdAt = DateTime.now();
    final result = await _publish('createSecretChatPost', {
      'postId': ?postId,
      'message': message.trim(),
      'categories': categories,
      'safetyLabels': safetyLabels,
    });
    final reference = _firestoreService.firestore
        .collection(FirestoreCollections.secretChats)
        .doc(result['postId'] as String? ?? postId);
    unawaited(_tryRecordActivity(uid, UserActivityType.secretChatPost));
    final profile = _profileCache[uid];
    return SecretChatModel(
      id: reference.id,
      message: message.trim(),
      category: categories.first,
      categories: categories,
      createdAt: createdAt,
      likeCount: 0,
      commentCount: 0,
      readCount: 0,
      authorId: uid,
      safetyLabels: safetyLabels,
      isAnonymous: true,
      isMine: true,
      authorAlias: profile?.alias ?? 'Anonymous',
      authorPhotoUrl: profile?.photoUrl,
    );
  }

  Future<Map<String, dynamic>> _publish(
    String name,
    Map<String, Object?> data,
  ) async {
    try {
      final result = await functions.httpsCallable(name).call<Object?>(data);
      final value = result.data;
      return value is Map ? Map<String, dynamic>.from(value) : const {};
    } on FirebaseFunctionsException catch (error) {
      throw secretChatPublishError(error);
    }
  }

  Future<void> deletePost(SecretChatModel post) async {
    final uid = _requireUserId();
    if (!post.isMine || (post.authorId != null && post.authorId != uid)) {
      throw StateError('Only the post owner can delete it.');
    }
    if (post.isPending) {
      throw StateError(
        'Wait for this post to finish syncing before deleting it.',
      );
    }
    await functions.httpsCallable('deleteSecretChatPost').call({
      'postId': post.id,
    });
  }

  Future<SecretChatModel> toggleLike(SecretChatModel post) async {
    final uid = _requireUserId();
    final nextLiked = !post.isLiked;
    final interactionId = _interactionId(uid, post.id);
    final interactionRef = _firestoreService.firestore
        .collection(FirestoreCollections.secretChatInteractions)
        .doc(interactionId);

    await interactionRef.set({
      'userId': uid,
      'postId': post.id,
      'liked': nextLiked,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    unawaited(_tryRecordActivity(uid, UserActivityType.secretChatInteraction));

    return post.copyWith(
      isLiked: nextLiked,
      likeCount: (post.likeCount + (nextLiked ? 1 : -1)).clamp(0, 1 << 31),
    );
  }

  Future<SecretChatModel> toggleSave(SecretChatModel post) async {
    final uid = _requireUserId();
    final nextSaved = !post.isSaved;
    await _firestoreService.setDocument(
      FirestoreCollections.secretChatInteractions,
      _interactionId(uid, post.id),
      {
        'userId': uid,
        'postId': post.id,
        'saved': nextSaved,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      merge: true,
    );
    unawaited(_tryRecordActivity(uid, UserActivityType.secretChatInteraction));
    return post.copyWith(isSaved: nextSaved);
  }

  Future<List<SecretChatComment>> fetchComments(String postId) async {
    _requireUserId();
    final docs = await _firestoreService.getDocuments(
      FirestoreCollections.secretChatComments,
      whereEquals: {'postId': postId, 'moderationStatus': 'active'},
      orderBy: 'createdAt',
      descending: false,
    );
    final comments = docs
        .map(
          (doc) => SecretChatComment.fromJson(doc, id: doc['id']?.toString()),
        )
        .toList(growable: false);
    return _resolveCommentProfiles(comments);
  }

  Future<SecretChatComment> addComment({
    required String postId,
    required String message,
    String? commentId,
    List<String> safetyLabels = const [],
  }) async {
    final uid = _requireUserId();
    final createdAt = DateTime.now();
    final result = await _publish('addSecretChatComment', {
      'postId': postId,
      'commentId': ?commentId,
      'message': message.trim(),
      'safetyLabels': safetyLabels,
    });
    final commentRef = _firestoreService.firestore
        .collection(FirestoreCollections.secretChatComments)
        .doc(result['commentId'] as String? ?? commentId);
    unawaited(_tryRecordActivity(uid, UserActivityType.secretChatComment));

    return SecretChatComment(
      id: commentRef.id,
      postId: postId,
      authorId: uid,
      message: message.trim(),
      createdAt: createdAt,
      moderationStatus: 'active',
      safetyLabels: safetyLabels,
      isAnonymous: true,
    );
  }

  Future<SecretChatProfile?> fetchCurrentProfile({
    bool forceServer = false,
  }) async {
    final uid = _requireUserId();
    if (!forceServer && _profileCache.containsKey(uid)) {
      return _profileCache[uid];
    }
    final snapshot = await _firestoreService.firestore
        .collection(FirestoreCollections.secretChatProfiles)
        .doc(uid)
        .get(
          forceServer
              ? const GetOptions(source: Source.server)
              : const GetOptions(source: Source.serverAndCache),
        );
    final data = snapshot.data();
    final profile = data == null ? null : SecretChatProfile.fromJson(data);
    _profileCache[uid] = profile;
    return profile;
  }

  Future<SecretChatProfile> saveProfile({required String alias}) async {
    final uid = _requireUserId();
    final normalized = SecretChatProfile.normalizeAlias(alias);
    final validation = SecretChatProfile.validateAlias(normalized);
    if (validation != null) throw ArgumentError(validation);
    try {
      final result = await functions
          .httpsCallable('saveSecretChatProfile')
          .call({'alias': normalized});
      return _cacheCallableProfile(uid, result.data);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'already-exists') {
        throw const SecretChatAliasTakenException();
      }
      rethrow;
    }
  }

  Future<SecretChatProfile> uploadProfilePhoto(
    Uint8List bytes, {
    required String contentType,
  }) async {
    final uid = _requireUserId();
    _photoCleanupWarning = null;
    if (bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Choose a JPEG or PNG image smaller than 5 MB.');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != uid) {
      throw const SecretChatProfileUploadException(
        SecretChatProfileUploadError.authenticationRequired,
        'Your session has expired. Sign in again before uploading a photo.',
      );
    }
    try {
      await currentUser.getIdToken(true);
    } catch (error) {
      throw SecretChatProfileUploadException(
        SecretChatProfileUploadError.authenticationRequired,
        'MindMate could not refresh your sign-in. Check your connection and sign in again.',
        error,
      );
    }
    final extension = contentType == 'image/png' ? 'png' : 'jpg';
    final path =
        'secret_chat_profiles/$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final reference = storage.ref(path);
    try {
      await reference.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );
    } on FirebaseException catch (error) {
      final denied =
          error.code == 'unauthorized' ||
          error.code == 'permission-denied' ||
          error.code == 'unauthenticated';
      throw SecretChatProfileUploadException(
        denied
            ? SecretChatProfileUploadError.storageDenied
            : _uploadError(error),
        _uploadMessage(error, denied: denied),
        error,
      );
    }
    try {
      final result = await functions
          .httpsCallable('finalizeSecretChatProfilePhoto')
          .call({'photoPath': path});
      return _cacheCallableProfile(uid, result.data);
    } on FirebaseFunctionsException catch (error) {
      await reference.delete().catchError((_) {});
      throw SecretChatProfileUploadException(
        error.code == 'unauthenticated'
            ? SecretChatProfileUploadError.authenticationRequired
            : SecretChatProfileUploadError.profileUpdateDenied,
        error.message ??
            'The image uploaded, but your Secret Chat profile could not be updated. Your previous photo was kept.',
        error,
      );
    } catch (error) {
      await reference.delete().catchError((_) {});
      throw SecretChatProfileUploadException(
        SecretChatProfileUploadError.profileUpdateDenied,
        'The uploaded image could not be linked to your profile. Your previous photo was kept.',
        error,
      );
    }
  }

  Future<SecretChatProfile?> removeProfilePhoto() async {
    final uid = _requireUserId();
    final result = await functions
        .httpsCallable('removeSecretChatProfilePhoto')
        .call();
    return _cacheCallableProfile(uid, result.data);
  }

  SecretChatProfile _cacheCallableProfile(String uid, Object? resultData) {
    if (resultData is! Map || resultData['profile'] is! Map) {
      throw StateError('Secret Chat returned an invalid profile response.');
    }
    final profile = SecretChatProfile.fromJson(
      Map<String, dynamic>.from(resultData['profile'] as Map),
    );
    if (profile.userId != uid) {
      throw StateError('Secret Chat returned a profile for another account.');
    }
    _profileCache[uid] = profile;
    return profile;
  }

  SecretChatProfileUploadError _uploadError(FirebaseException error) {
    return error.code.contains('app-check')
        ? SecretChatProfileUploadError.appCheckRejected
        : SecretChatProfileUploadError.uploadFailed;
  }

  String _uploadMessage(FirebaseException error, {required bool denied}) {
    if (error.code.contains('app-check')) {
      return 'Device verification was rejected. Confirm this app is registered with Firebase App Check and retry.';
    }
    if (denied) {
      return 'Firebase Storage denied this profile photo. Refresh your sign-in and try again.';
    }
    if (error.code == 'retry-limit-exceeded' || error.code == 'canceled') {
      return 'The photo upload was interrupted. Check your connection and retry.';
    }
    return 'The photo could not be uploaded. Please check your connection and retry.';
  }

  Future<SecretChatProfileStats> fetchProfileStats() async {
    final uid = _requireUserId();
    var data = await _firestoreService.getDocument(
      FirestoreCollections.secretChatProfileStats,
      uid,
    );
    if (data == null) {
      await functions.httpsCallable('rebuildMySecretChatStats').call<void>();
      data = await _firestoreService.getDocument(
        FirestoreCollections.secretChatProfileStats,
        uid,
      );
      if (data == null) {
        throw StateError(
          'Secret Chat statistics were not available after rebuilding.',
        );
      }
    }
    return SecretChatProfileStats(
      reads: (data['reads'] as num?)?.toInt() ?? 0,
      reactions: (data['reactions'] as num?)?.toInt() ?? 0,
      comments: (data['comments'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<SecretChatModel>> fetchRecentPosts({int limit = 3}) async {
    final uid = _requireUserId();
    final docs = await _firestoreService.getDocuments(
      FirestoreCollections.secretChats,
      whereEquals: {'authorId': uid, 'moderationStatus': 'active'},
      orderBy: 'createdAt',
      limit: limit,
    );
    return docs
        .map(
          (doc) => SecretChatModel.fromJson(
            doc,
            id: doc['id']?.toString(),
            currentUserId: uid,
          ),
        )
        .toList(growable: false);
  }

  Future<SecretChatModel> recordUniqueRead(SecretChatModel post) async {
    final uid = _requireUserId();
    if (post.authorId == uid) return post;
    final firestore = _firestoreService.firestore;
    final interactionRef = firestore
        .collection(FirestoreCollections.secretChatInteractions)
        .doc(_interactionId(uid, post.id));
    var incremented = false;
    await firestore.runTransaction((transaction) async {
      final interaction = await transaction.get(interactionRef);
      if (interaction.data()?['readAt'] != null) return;
      transaction.set(interactionRef, {
        'userId': uid,
        'postId': post.id,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      incremented = true;
    });
    return incremented ? post.copyWith(readCount: post.readCount + 1) : post;
  }

  Future<Map<String, SecretChatProfile>> _fetchProfiles(
    Iterable<String?> ids,
  ) async {
    final uniqueIds = ids
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final missing = uniqueIds
        .where((id) => !_profileCache.containsKey(id))
        .toList();
    for (var start = 0; start < missing.length; start += 30) {
      final chunk = missing.skip(start).take(30).toList();
      final snapshots = await _firestoreService.firestore
          .collection(FirestoreCollections.secretChatProfiles)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      final found = {for (final doc in snapshots.docs) doc.id: doc.data()};
      for (final id in chunk) {
        final data = found[id];
        _profileCache[id] = data == null
            ? null
            : SecretChatProfile.fromJson(data);
      }
    }
    return {
      for (final id in uniqueIds)
        if (_profileCache[id] != null) id: _profileCache[id]!,
    };
  }

  Future<List<SecretChatModel>> _resolvePostProfiles(
    List<SecretChatModel> posts,
  ) async {
    final profiles = await _fetchProfiles(posts.map((post) => post.authorId));
    return [
      for (final post in posts)
        post.copyWith(
          authorAlias: profiles[post.authorId]?.alias ?? 'Anonymous',
          authorPhotoUrl: profiles[post.authorId]?.photoUrl,
        ),
    ];
  }

  Future<List<SecretChatComment>> _resolveCommentProfiles(
    List<SecretChatComment> comments,
  ) async {
    final profiles = await _fetchProfiles(
      comments.map((comment) => comment.authorId),
    );
    return [
      for (final comment in comments)
        SecretChatComment(
          id: comment.id,
          postId: comment.postId,
          message: comment.message,
          createdAt: comment.createdAt,
          authorId: comment.authorId,
          authorAlias: profiles[comment.authorId]?.alias ?? 'Anonymous',
          authorPhotoUrl: profiles[comment.authorId]?.photoUrl,
          moderationStatus: comment.moderationStatus,
          safetyLabels: comment.safetyLabels,
          isAnonymous: comment.isAnonymous,
        ),
    ];
  }

  Future<Map<String, Map<String, dynamic>>> _fetchInteractions(
    String uid,
  ) async {
    final docs = await _firestoreService.getDocuments(
      FirestoreCollections.secretChatInteractions,
      whereEquals: {'userId': uid},
      limit: 200,
    );
    return {
      for (final doc in docs)
        if ((doc['postId']?.toString() ?? '').isNotEmpty)
          doc['postId'].toString(): doc,
    };
  }

  String _interactionId(String uid, String postId) => '${uid}_$postId';

  Future<void> _tryRecordActivity(String userId, UserActivityType type) async {
    try {
      await _userRepository.recordActivity(userId, type);
    } catch (_) {
      // Secret Chat should remain usable even if activity sync is unavailable.
    }
  }
}

extension SecretChatValidationCodeLabel on SecretChatValidationCode {
  String get storedValue => name;
}
