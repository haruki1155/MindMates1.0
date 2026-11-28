import 'package:flutter/foundation.dart';

import '../features/settings/models/reminder_preferences.dart';
import '../repositories/reminder_preferences_repository.dart';

class ReminderPreferencesProvider extends ChangeNotifier {
  ReminderPreferencesProvider(this._repository);

  final ReminderPreferencesRepository _repository;
  String? userId;
  ReminderPreferences? preferences;
  Object? error;
  bool isLoading = false;
  bool isSaving = false;
  int _loadGeneration = 0;

  Future<void> load(String nextUserId) async {
    final generation = ++_loadGeneration;
    if (userId != nextUserId) {
      userId = nextUserId;
      preferences = null;
      error = null;
    }
    isLoading = true;
    notifyListeners();
    try {
      final loaded = await _repository.load(nextUserId);
      if (generation == _loadGeneration && userId == nextUserId) {
        preferences = loaded;
        error = null;
      }
    } catch (caught) {
      if (generation == _loadGeneration && userId == nextUserId) {
        preferences = null;
        error = caught;
      }
    } finally {
      if (generation == _loadGeneration && userId == nextUserId) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> save(
    String targetUserId,
    ReminderPreferences next,
  ) async {
    if (userId != targetUserId || preferences == null) {
      throw StateError('Load reminder preferences before saving.');
    }
    isSaving = true;
    error = null;
    notifyListeners();
    try {
      await _repository.save(targetUserId, next);
      if (userId == targetUserId) preferences = next;
    } catch (caught) {
      error = caught;
      rethrow;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }
}
