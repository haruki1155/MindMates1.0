import 'package:firebase_auth/firebase_auth.dart';

import '../../../database/firestore_collections.dart';
import '../../../services/firebase/firestore_service.dart';
import '../models/insights_models.dart';

abstract class AdminInsightCatalogDataSource {
  Future<List<Map<String, dynamic>>> loadAll();

  /// Merges [data] into `insight_content/{id}`.
  Future<void> merge(String id, Map<String, dynamic> data);
}

class FirestoreAdminInsightCatalogDataSource
    implements AdminInsightCatalogDataSource {
  FirestoreAdminInsightCatalogDataSource([FirestoreService? service])
    : _service = service ?? FirestoreService();

  final FirestoreService _service;

  // Unordered on purpose: Firestore orderBy would drop docs lacking sortOrder.
  @override
  Future<List<Map<String, dynamic>>> loadAll() =>
      _service.getDocuments(FirestoreCollections.insightContent);

  @override
  Future<void> merge(String id, Map<String, dynamic> data) => _service
      .setDocument(FirestoreCollections.insightContent, id, data, merge: true);
}

class InsightCatalogValidationException implements Exception {
  const InsightCatalogValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Admin-only catalog management for `insight_content`. Firestore rules
/// (`isPortalAdmin()`) are the authority; these checks keep data well-formed
/// and stop unverified items from being approved for the Featured card.
class AdminInsightCatalogRepository {
  AdminInsightCatalogRepository({
    AdminInsightCatalogDataSource? dataSource,
    String? Function()? currentUid,
    DateTime Function()? now,
  }) : _dataSource = dataSource ?? FirestoreAdminInsightCatalogDataSource(),
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _now = now ?? DateTime.now;

  final AdminInsightCatalogDataSource _dataSource;
  final String? Function() _currentUid;
  final DateTime Function() _now;

  static final _idPattern = RegExp(r'^[a-z0-9_]{3,80}$');

  String? get currentUid => _currentUid();

  Future<List<InsightCardItem>> loadAllContent() async {
    final docs = await _dataSource.loadAll();
    final items = docs
        .map(InsightCardItem.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
    items.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.title.compareTo(b.title);
    });
    return items;
  }

  Future<void> saveContent(
    InsightCardItem draft, {
    required String reviewerUid,
  }) async {
    if (!_idPattern.hasMatch(draft.id)) {
      throw const InsightCatalogValidationException(
        'Use 3-80 lowercase letters, numbers, or underscores for the ID.',
      );
    }
    if (draft.title.trim().isEmpty) {
      throw const InsightCatalogValidationException('A title is required.');
    }
    if (draft.actionRoute != null && draft.validActionRoute == null) {
      throw const InsightCatalogValidationException(
        'Choose an in-app action from the allowed list.',
      );
    }
    if (!insightReviewStatuses.contains(draft.reviewStatus ?? 'draft')) {
      throw const InsightCatalogValidationException('Unknown review status.');
    }
    final data = draft.toCatalogJson()..['updatedAt'] = _now();
    if (draft.reviewStatus == 'approved') {
      _requireProvenance(draft, reviewerUid);
      data['reviewedAt'] = _now();
      data['reviewedBy'] = reviewerUid;
    }
    await _dataSource.merge(draft.id, data);
  }

  Future<void> setReviewStatus({
    required InsightCardItem item,
    required String reviewStatus,
    required String reviewerUid,
  }) async {
    if (!insightReviewStatuses.contains(reviewStatus)) {
      throw const InsightCatalogValidationException('Unknown review status.');
    }
    final data = <String, dynamic>{
      'reviewStatus': reviewStatus,
      'updatedAt': _now(),
    };
    if (reviewStatus == 'approved') {
      _requireProvenance(item, reviewerUid);
      data['reviewedAt'] = _now();
      data['reviewedBy'] = reviewerUid;
    }
    // Archived content leaves the mobile library; history is retained.
    if (reviewStatus == 'archived') data['isActive'] = false;
    await _dataSource.merge(item.id, data);
  }

  Future<void> setActive({required String id, required bool isActive}) =>
      _dataSource.merge(id, {'isActive': isActive, 'updatedAt': _now()});

  void _requireProvenance(InsightCardItem item, String reviewerUid) {
    if (reviewerUid.trim().isEmpty) {
      throw const InsightCatalogValidationException(
        'Sign in again before approving content.',
      );
    }
    final gaps = item.provenanceGaps;
    if (gaps.isNotEmpty) {
      throw InsightCatalogValidationException(
        'Approval needs: ${gaps.join(', ')}.',
      );
    }
  }
}
