import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../services/firebase/firestore_service.dart';
import '../features/settings/models/reminder_preferences.dart';

class ReminderPreferencesRepository {
  ReminderPreferencesRepository({FirestoreService? firestoreService})
    : _firestoreService = firestoreService ?? FirestoreService();

  final FirestoreService _firestoreService;

  Future<ReminderPreferences> load(String userId) async {
    _validateUserId(userId);
    final data = await _firestoreService.getDocument(
      FirestoreCollections.reminderPreferences,
      userId,
    );
    return data == null
        ? const ReminderPreferences()
        : ReminderPreferences.fromJson(data);
  }

  Future<void> save(
    String userId,
    ReminderPreferences preferences,
  ) async {
    _validateUserId(userId);
    if (!ReminderPreferences.isValidTime(preferences.moodDailyTime) ||
        !ReminderPreferences.isValidTime(preferences.breathingDailyTime)) {
      throw ArgumentError('Reminder times must use HH:mm in 24-hour time.');
    }

    final collection = FirestoreCollections.reminderPreferences;
    final existing = await _firestoreService.getDocument(collection, userId);
    if (existing == null) {
      final data = preferences.toJson()
        ..['moodDailyUpdatedAt'] = FieldValue.serverTimestamp()
        ..['breathingDailyUpdatedAt'] = FieldValue.serverTimestamp()
        ..['updatedAt'] = FieldValue.serverTimestamp();
      await _firestoreService.setDocument(collection, userId, data);
      return;
    }

    final patch = <String, dynamic>{};
    _copyIfChanged(
      existing,
      patch,
      'appointment24HourEnabled',
      preferences.appointment24HourEnabled,
    );
    _copyIfChanged(
      existing,
      patch,
      'appointment1HourEnabled',
      preferences.appointment1HourEnabled,
    );

    final moodChanged =
        existing['moodDailyEnabled'] != preferences.moodDailyEnabled ||
        existing['moodDailyTime'] != preferences.moodDailyTime;
    if (existing['moodDailyEnabled'] != preferences.moodDailyEnabled) {
      patch['moodDailyEnabled'] = preferences.moodDailyEnabled;
    }
    if (existing['moodDailyTime'] != preferences.moodDailyTime) {
      patch['moodDailyTime'] = preferences.moodDailyTime;
    }
    if (moodChanged) {
      patch['moodDailyUpdatedAt'] = FieldValue.serverTimestamp();
    }

    final breathingChanged =
        existing['breathingDailyEnabled'] != preferences.breathingDailyEnabled ||
        existing['breathingDailyTime'] != preferences.breathingDailyTime;
    if (existing['breathingDailyEnabled'] != preferences.breathingDailyEnabled) {
      patch['breathingDailyEnabled'] = preferences.breathingDailyEnabled;
    }
    if (existing['breathingDailyTime'] != preferences.breathingDailyTime) {
      patch['breathingDailyTime'] = preferences.breathingDailyTime;
    }
    if (breathingChanged) {
      patch['breathingDailyUpdatedAt'] = FieldValue.serverTimestamp();
    }

    patch['updatedAt'] = FieldValue.serverTimestamp();
    await _firestoreService.updateDocument(collection, userId, patch);
  }

  void _copyIfChanged(
    Map<String, dynamic> existing,
    Map<String, dynamic> patch,
    String key,
    Object value,
  ) {
    if (existing[key] != value) patch[key] = value;
  }

  void _validateUserId(String userId) {
    if (userId.trim().isEmpty) throw ArgumentError.value(userId, 'userId');
  }
}
