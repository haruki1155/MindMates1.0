import 'package:flutter/foundation.dart';

import '../models/mood_model.dart';
import '../features/mood/config/mood_v2_feature_flag.dart';
import '../features/mood/domain/mood_v2_analytics.dart';
import '../repositories/mood_combined_history_repository.dart';
import '../repositories/mood_repository.dart';

class MoodProvider extends ChangeNotifier {
  MoodProvider(
    this._repository, {
    DateTime Function()? nowProvider,
    MoodCombinedHistoryRepository? combinedHistoryRepository,
    bool useMoodV2Read = MoodV2FeatureFlag.providerRead,
  }) : _nowProvider = nowProvider ?? DateTime.now,
       // ignore: prefer_initializing_formals
       _combinedHistoryRepository = combinedHistoryRepository,
       // ignore: prefer_initializing_formals
       _useMoodV2Read = useMoodV2Read;

  final MoodRepository _repository;
  final DateTime Function() _nowProvider;
  final MoodCombinedHistoryRepository? _combinedHistoryRepository;
  final bool _useMoodV2Read;

  int _legacySessionGeneration = 0;
  bool _isLegacySessionCurrent(String uid, int generation) =>
      generation == _legacySessionGeneration &&
      (!_isBoundToAuthentication || _authenticatedUserId == uid);

  List<MoodModel> _moods = [];
  bool _isLoading = false;
  bool _isLoadingToday = false;
  String? _errorMessage;
  MoodModel? _todayMood;
  DailyMoodSaveResult? _dailySaveResult;
  MoodHistoryWindow? _v2History;
  MoodAnalyticsSnapshot? _v2Analytics;
  String? _v2HistoryUserId;
  String? _authenticatedUserId;
  bool _isBoundToAuthentication = false;
  MoodCombinedHistoryCursor? _v2NextCursor;
  MoodCombinedHistoryCursor? _v2RetryCursor;
  bool _hasV2Retry = false;
  bool _isLoadingV2History = false;
  bool _isLoadingMoreV2History = false;
  String? _v2HistoryErrorMessage;
  String? _v2PaginationErrorMessage;
  int _v2RequestGeneration = 0;

  List<MoodModel> get moods => List.unmodifiable(_moods);
  bool get isLoading => _isLoading;
  bool get isLoadingToday => _isLoadingToday;
  String? get errorMessage => _errorMessage;
  MoodModel? get todayMood => _todayMood;
  bool get hasCheckedInToday => _todayMood != null;
  DailyMoodSaveResult? get dailySaveResult => _dailySaveResult;
  MoodHistoryWindow? get v2History => _v2History;
  MoodAnalyticsSnapshot? get v2Analytics => _v2Analytics;
  bool get isLoadingV2History => _isLoadingV2History;
  bool get isLoadingMoreV2History => _isLoadingMoreV2History;
  String? get v2HistoryErrorMessage => _v2HistoryErrorMessage;
  String? get v2PaginationErrorMessage => _v2PaginationErrorMessage;
  bool get canLoadMoreMoodV2History => _v2NextCursor != null || _hasV2Retry;
  bool get isMoodV2ReadEnabled =>
      _useMoodV2Read && _combinedHistoryRepository != null;

  /// Invalidate account-scoped V2 reads as soon as Auth changes, including
  /// while an older page is still pending.
  void bindAuthenticatedUser(String? userId) {
    final next = userId?.trim();
    final normalized = next == null || next.isEmpty ? null : next;
    if (_isBoundToAuthentication && _authenticatedUserId == normalized) return;
    _isBoundToAuthentication = true;
    _authenticatedUserId = normalized;
    _legacySessionGeneration++;
    _moods = [];
    _todayMood = null;
    _dailySaveResult = null;
    _errorMessage = null;
    _isLoading = false;
    _isLoadingToday = false;
    clearMoodV2History();
  }

  /// Read-only V2 state is kept separate from the legacy public fields.
  /// A user/session change invalidates pending results before they can surface.
  Future<void> loadMoodV2History(String userId, {DateTime? now}) async {
    final repository = _combinedHistoryRepository;
    if (!_useMoodV2Read ||
        repository == null ||
        userId.trim().isEmpty ||
        (_isBoundToAuthentication && _authenticatedUserId != userId)) {
      return;
    }
    final generation = ++_v2RequestGeneration;
    // Do not briefly display the prior account's read-only history while the
    // authenticated session changes and the new request is pending.
    if (_v2HistoryUserId != userId) {
      _v2History = null;
      _v2Analytics = null;
    }
    _v2HistoryUserId = userId;
    _isLoadingV2History = true;
    _isLoadingMoreV2History = false;
    _v2HistoryErrorMessage = null;
    _v2PaginationErrorMessage = null;
    _v2NextCursor = null;
    _v2RetryCursor = null;
    _hasV2Retry = false;
    notifyListeners();
    try {
      final page = await repository.fetch(
        MoodCombinedHistoryRequest(userId: userId, pageSize: 100),
      );
      if (generation != _v2RequestGeneration || _v2HistoryUserId != userId) {
        return;
      }
      _applyMoodV2Page(page, now: now, previousEvents: const []);
    } catch (_) {
      if (generation != _v2RequestGeneration || _v2HistoryUserId != userId) {
        return;
      }
      _v2History = null;
      _v2Analytics = null;
      _v2HistoryErrorMessage = 'Unable to load mood history.';
    } finally {
      if (generation == _v2RequestGeneration && _v2HistoryUserId == userId) {
        _isLoadingV2History = false;
        notifyListeners();
      }
    }
  }

  /// Appends one bounded older page. A source failure leaves loaded entries in
  /// place and retains the same cursor for an explicit retry.
  Future<void> loadMoreMoodV2History(String userId, {DateTime? now}) async {
    final repository = _combinedHistoryRepository;
    final history = _v2History;
    if (!_useMoodV2Read ||
        repository == null ||
        history == null ||
        _isLoadingMoreV2History ||
        userId.trim().isEmpty ||
        (_isBoundToAuthentication && _authenticatedUserId != userId) ||
        userId != _v2HistoryUserId ||
        !canLoadMoreMoodV2History) {
      return;
    }

    final retrying = _hasV2Retry;
    final cursor = retrying ? _v2RetryCursor : _v2NextCursor;
    final generation = ++_v2RequestGeneration;
    _isLoadingMoreV2History = true;
    _v2PaginationErrorMessage = null;
    notifyListeners();
    try {
      final page = await repository.fetch(
        MoodCombinedHistoryRequest(
          userId: userId,
          pageSize: 100,
          cursor: cursor,
        ),
      );
      if (generation != _v2RequestGeneration || _v2HistoryUserId != userId) {
        return;
      }
      _applyMoodV2Page(
        page,
        now: now,
        previousEvents: history.uniqueEvents,
        retryCursor: cursor,
      );
    } catch (_) {
      if (generation != _v2RequestGeneration || _v2HistoryUserId != userId) {
        return;
      }
      _hasV2Retry = true;
      _v2RetryCursor = cursor;
      _v2PaginationErrorMessage = 'Unable to load more mood history.';
    } finally {
      if (generation == _v2RequestGeneration && _v2HistoryUserId == userId) {
        _isLoadingMoreV2History = false;
        notifyListeners();
      }
    }
  }

  void _applyMoodV2Page(
    MoodCombinedHistoryPage page, {
    required DateTime? now,
    required List<NormalizedMoodEvent> previousEvents,
    MoodCombinedHistoryCursor? retryCursor,
  }) {
    final combined = MoodHistoryWindow(
      events: [...previousEvents, ...page.window.uniqueEvents],
      coverage: MoodHistoryCoverage.partial,
    ).uniqueEvents;
    final hasFailedSource = page.failedSources.isNotEmpty;
    _hasV2Retry = hasFailedSource;
    _v2RetryCursor = hasFailedSource ? retryCursor : null;
    _v2NextCursor = hasFailedSource ? null : page.nextCursor;
    final isComplete = !hasFailedSource && page.nextCursor == null;
    _v2History = MoodHistoryWindow(
      events: combined,
      coverage: isComplete
          ? MoodHistoryCoverage.complete
          : MoodHistoryCoverage.partial,
    );
    _v2Analytics = MoodAnalytics.summarize(
      _v2History!,
      referenceInstant: now ?? _nowProvider(),
    );
    _v2PaginationErrorMessage = hasFailedSource
        ? 'Some mood history could not be loaded. Try again.'
        : null;
  }

  void clearMoodV2History() {
    _v2RequestGeneration++;
    _v2HistoryUserId = null;
    _v2History = null;
    _v2Analytics = null;
    _v2HistoryErrorMessage = null;
    _isLoadingV2History = false;
    _isLoadingMoreV2History = false;
    _v2NextCursor = null;
    _v2RetryCursor = null;
    _hasV2Retry = false;
    _v2PaginationErrorMessage = null;
    notifyListeners();
  }

  Future<void> loadRecentMoods(String userId, {DateTime? now}) async {
    final generation = _legacySessionGeneration;
    if (!_isLegacySessionCurrent(userId, generation)) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final referenceNow = now ?? _nowProvider();
      final fetchedMoods = await _repository.fetchRecentMoods(userId);
      if (!_isLegacySessionCurrent(userId, generation)) return;
      _moods = fetchedMoods;
      if (_todayMood == null ||
          !_matchesToday(_todayMood!, now: referenceNow)) {
        _todayMood = _moodForToday(_moods, now: referenceNow);
      }
    } catch (error) {
      if (!_isLegacySessionCurrent(userId, generation)) return;
      _errorMessage = 'Unable to load moods.';
    } finally {
      if (_isLegacySessionCurrent(userId, generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadTodayMood(String userId, {DateTime? now}) async {
    final generation = _legacySessionGeneration;
    if (!_isLegacySessionCurrent(userId, generation)) return;
    final referenceNow = now ?? _nowProvider();
    if (_todayMood != null && !_matchesToday(_todayMood!, now: referenceNow)) {
      _todayMood = null;
      _dailySaveResult = null;
    }
    _isLoadingToday = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final fetched = await _repository.fetchTodayMood(
        userId,
        now: referenceNow,
      );
      if (!_isLegacySessionCurrent(userId, generation)) return;
      _todayMood = fetched != null && _matchesToday(fetched, now: referenceNow)
          ? fetched
          : null;
      if (_todayMood != null) _insertMood(_todayMood!);
    } catch (_) {
      if (!_isLegacySessionCurrent(userId, generation)) return;
      _errorMessage = 'Unable to load today\'s mood.';
    } finally {
      if (_isLegacySessionCurrent(userId, generation)) {
        _isLoadingToday = false;
        notifyListeners();
      }
    }
  }

  Future<bool> logDailyMood({
    required String userId,
    required int level,
    String? label,
    String? note,
    String? entryMethod,
    bool? expressionAssistUsed,
    bool? expressionSuggestionAccepted,
    String? expressionModelVersion,
    DateTime? now,
  }) async {
    final generation = _legacySessionGeneration;
    if (!_isLegacySessionCurrent(userId, generation)) return false;
    final referenceNow = now ?? _nowProvider();
    _errorMessage = null;
    try {
      final result = await _repository.saveDailyMood(
        userId: userId,
        level: level,
        label: label,
        note: note,
        entryMethod: entryMethod,
        expressionAssistUsed: expressionAssistUsed,
        expressionSuggestionAccepted: expressionSuggestionAccepted,
        expressionModelVersion: expressionModelVersion,
        now: referenceNow,
      );
      if (!_isLegacySessionCurrent(userId, generation)) return false;
      _dailySaveResult = result;
      _todayMood = result.mood;
      _insertMood(result.mood);
      notifyListeners();
      return true;
    } catch (_) {
      if (!_isLegacySessionCurrent(userId, generation)) return false;
      _errorMessage = 'Unable to save mood.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> logMood({
    required String userId,
    required int level,
    String? label,
    String? note,
  }) async {
    final referenceNow = _nowProvider();
    try {
      final id = await _repository.createMood(
        userId: userId,
        level: level,
        label: label,
        note: note,
        now: referenceNow,
      );
      _moods = [
        MoodModel(
          id: id,
          userId: userId,
          level: level,
          label: label,
          note: note,
          createdAt: referenceNow,
        ),
        ..._moods,
      ];
      _todayMood = _moodForToday(_moods, now: referenceNow);
      notifyListeners();
      return true;
    } catch (error) {
      _errorMessage = 'Unable to save mood.';
      notifyListeners();
      return false;
    }
  }

  void _insertMood(MoodModel mood) {
    _moods = [mood, ..._moods.where((item) => item.id != mood.id)];
  }

  MoodModel? _moodForToday(List<MoodModel> moods, {DateTime? now}) {
    final today = MoodRepository.dateKeyFor(now ?? _nowProvider());
    for (final mood in moods) {
      final key = (mood.dateKey ?? '').trim().isNotEmpty
          ? mood.dateKey
          : MoodRepository.dateKeyFor(mood.createdAt);
      if (key == today) return mood;
    }
    return null;
  }

  bool _matchesToday(MoodModel mood, {DateTime? now}) {
    final today = MoodRepository.dateKeyFor(now ?? _nowProvider());
    final key = (mood.dateKey ?? '').trim().isNotEmpty
        ? mood.dateKey
        : MoodRepository.dateKeyFor(mood.createdAt);
    return key == today;
  }
}
