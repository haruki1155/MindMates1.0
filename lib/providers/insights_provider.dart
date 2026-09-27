import 'package:flutter/foundation.dart';

import '../features/insights/models/insights_models.dart';
import '../repositories/insights_repository.dart';

class InsightsProvider extends ChangeNotifier {
  InsightsProvider(this._repository);

  final InsightsRepository _repository;

  InsightsDashboardData? _data;
  InsightRecommendationContext? _loadedContext;
  InsightRecommendationContext? _pendingContext;
  bool _isInvalidated = false;
  bool _isLoading = false;
  String? _errorMessage;

  InsightsDashboardData? get data => _data;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadInsights(
    InsightRecommendationContext context, {
    bool forceRefresh = false,
  }) async {
    if (_isLoading) {
      if (_loadedContext != context) _pendingContext = context;
      return;
    }
    if (!forceRefresh &&
        !_isInvalidated &&
        _data != null &&
        _loadedContext == context) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _data = await _repository.fetchInsights(context);
      _loadedContext = context;
      _isInvalidated = false;
    } catch (_) {
      _errorMessage = 'Unable to load insights.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    final pendingContext = _pendingContext;
    _pendingContext = null;
    if (pendingContext != null && pendingContext != context) {
      await loadInsights(pendingContext, forceRefresh: true);
    }
  }

  /// Makes the cached dashboard stale without fetching when it was never used.
  void invalidateForUser(String userId) {
    if (_loadedContext?.userId != userId) return;
    _isInvalidated = true;
  }

  /// Refreshes only a dashboard that was already loaded for this user.
  Future<void> refreshLoadedContext(String userId) async {
    final context = _loadedContext;
    if (context == null || context.userId != userId) return;
    _isInvalidated = true;
    await loadInsights(context, forceRefresh: true);
  }
}
