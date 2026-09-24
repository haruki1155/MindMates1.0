import 'package:flutter/foundation.dart';

import '../models/mood_model.dart';
import '../repositories/mood_repository.dart';

class MoodProvider extends ChangeNotifier {
  MoodProvider(this._repository, {DateTime Function()? nowProvider})
    : _nowProvider = nowProvider ?? DateTime.now;

  final MoodRepository _repository;
  final DateTime Function() _nowProvider;

  List<MoodModel> _moods = [];
  bool _isLoading = false;
  bool _isLoadingToday = false;
  String? _errorMessage;
  MoodModel? _todayMood;
  DailyMoodSaveResult? _dailySaveResult;

  List<MoodModel> get moods => List.unmodifiable(_moods);
  bool get isLoading => _isLoading;
  bool get isLoadingToday => _isLoadingToday;
  String? get errorMessage => _errorMessage;
  MoodModel? get todayMood => _todayMood;
  bool get hasCheckedInToday => _todayMood != null;
  DailyMoodSaveResult? get dailySaveResult => _dailySaveResult;

  Future<void> loadRecentMoods(String userId, {DateTime? now}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final referenceNow = now ?? _nowProvider();
      _moods = await _repository.fetchRecentMoods(userId);
      if (_todayMood == null ||
          !_matchesToday(_todayMood!, now: referenceNow)) {
        _todayMood = _moodForToday(_moods, now: referenceNow);
      }
    } catch (error) {
      _errorMessage = 'Unable to load moods.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadTodayMood(String userId, {DateTime? now}) async {
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
      _todayMood = fetched != null && _matchesToday(fetched, now: referenceNow)
          ? fetched
          : null;
      if (_todayMood != null) _insertMood(_todayMood!);
    } catch (_) {
      _errorMessage = 'Unable to load today\'s mood.';
    } finally {
      _isLoadingToday = false;
      notifyListeners();
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
      _dailySaveResult = result;
      _todayMood = result.mood;
      _insertMood(result.mood);
      notifyListeners();
      return true;
    } catch (_) {
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
