import 'package:flutter/foundation.dart';

import '../features/insights/models/insights_models.dart';
import '../repositories/insights_repository.dart';

class InsightsProvider extends ChangeNotifier {
  InsightsProvider(this._repository);

  final InsightsRepository _repository;

  InsightsDashboardData? _data;
  InsightRecommendationContext? _loadedContext;
  InsightRecommendationContext? _activeRequestContext;
  InsightRecommendationContext? _pendingContext;
  bool _isInvalidated = false;
  bool _isLoading = false;
  String? _errorMessage;
  int _requestGeneration = 0;

  InsightsDashboardData? get data => _data;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadInsights(
    InsightRecommendationContext context, {
    bool forceRefresh = false,
  }) async {
    if (_isLoading) {
      if ((_loadedContext ?? _activeRequestContext)?.userId != context.userId) {
        // Never render one account's cached recommendations while another
        // account is waiting. Same-user refreshes intentionally keep data.
        _data = null;
        _loadedContext = null;
        _errorMessage = null;
        notifyListeners();
      }
      if (_loadedContext != context) _pendingContext = context;
      return;
    }
    if (!forceRefresh &&
        !_isInvalidated &&
        _data != null &&
        _loadedContext == context) {
      return;
    }

    if (_loadedContext?.userId != null &&
        _loadedContext!.userId != context.userId) {
      _data = null;
      _loadedContext = null;
    }
    final generation = ++_requestGeneration;
    _activeRequestContext = context;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _repository.fetchInsights(context);
      final hasNewerUserRequest =
          _pendingContext?.userId != null &&
          _pendingContext!.userId != context.userId;
      if (generation == _requestGeneration && !hasNewerUserRequest) {
        _data = data;
        _loadedContext = context;
        _isInvalidated = false;
      }
    } catch (_) {
      if (generation == _requestGeneration) {
        _errorMessage = 'Unable to load insights.';
      }
    } finally {
      if (generation == _requestGeneration) {
        _isLoading = false;
        _activeRequestContext = null;
        notifyListeners();
      }
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

  /// Hook for the future trusted Mood V2 writer. It is deliberately callable
  /// only after the server has confirmed creation or an idempotent replay.
  void invalidateForConfirmedMoodV2Write(String userId) {
    invalidateForUser(userId);
  }

  /// Removes data tied to a signed-out user without affecting another session.
  void clearForUser(String userId) {
    if (_loadedContext?.userId != userId &&
        _activeRequestContext?.userId != userId &&
        _pendingContext?.userId != userId) {
      return;
    }
    _requestGeneration++;
    _data = null;
    _loadedContext = null;
    _activeRequestContext = null;
    _pendingContext = null;
    _isInvalidated = false;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Refreshes only a dashboard that was already loaded for this user.
  Future<void> refreshLoadedContext(String userId) async {
    final context = _loadedContext;
    if (context == null || context.userId != userId) return;
    _isInvalidated = true;
    await loadInsights(context, forceRefresh: true);
  }
}
