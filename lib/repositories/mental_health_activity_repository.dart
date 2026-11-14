import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/firestore_mapper.dart';
import '../database/firestore_collections.dart';
import '../models/mental_health_activity_summary.dart';
import '../services/firebase/firestore_service.dart';
import 'user_repository.dart';

abstract class MentalHealthActivityDataSource {
  Future<Map<String, dynamic>?> getUserDocument(String userId);

  Future<List<Map<String, dynamic>>> fetchUserActivities({
    required String userId,
    required DateTime since,
    required DateTime before,
  });

  Future<List<Map<String, dynamic>>> fetchMoods({
    required String userId,
    required DateTime since,
    required DateTime before,
  });

  Future<List<Map<String, dynamic>>> fetchBreathingSessions({
    required String userId,
    required DateTime since,
    required DateTime before,
  });
}

class FirestoreMentalHealthActivityDataSource
    implements MentalHealthActivityDataSource {
  FirestoreMentalHealthActivityDataSource(this._firestoreService);

  final FirestoreService _firestoreService;

  @override
  Future<Map<String, dynamic>?> getUserDocument(String userId) {
    return _firestoreService.getDocument(FirestoreCollections.users, userId);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUserActivities({
    required String userId,
    required DateTime since,
    required DateTime before,
  }) {
    return _fetchDateWindow(
      collection: FirestoreCollections.userActivities,
      userField: 'userId',
      userId: userId,
      dateField: 'occurredAt',
      since: since,
      before: before,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMoods({
    required String userId,
    required DateTime since,
    required DateTime before,
  }) {
    return _fetchDateWindow(
      collection: FirestoreCollections.moods,
      userField: 'userId',
      userId: userId,
      dateField: 'createdAt',
      since: since,
      before: before,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBreathingSessions({
    required String userId,
    required DateTime since,
    required DateTime before,
  }) {
    return _fetchDateWindow(
      collection: FirestoreCollections.breathingSessions,
      userField: 'userId',
      userId: userId,
      dateField: 'completedAt',
      since: since,
      before: before,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchDateWindow({
    required String collection,
    required String userField,
    required String userId,
    required String dateField,
    required DateTime since,
    required DateTime before,
  }) async {
    final snapshot = await _firestoreService.firestore
        .collection(collection)
        .where(userField, isEqualTo: userId)
        .where(dateField, isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .where(dateField, isLessThan: Timestamp.fromDate(before))
        .get();

    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList(growable: false);
  }
}

class MentalHealthActivityRepository {
  MentalHealthActivityRepository({
    FirestoreService? firestoreService,
    MentalHealthActivityDataSource? dataSource,
  }) : _firestoreService = firestoreService ?? FirestoreService() {
    _dataSource =
        dataSource ??
        FirestoreMentalHealthActivityDataSource(_firestoreService);
  }

  final FirestoreService _firestoreService;
  late final MentalHealthActivityDataSource _dataSource;

  Future<MentalHealthActivitySummary> fetchDailySummary(
    String userId, {
    DateTime? date,
  }) async {
    final targetDate = date ?? DateTime.now();
    final dayStart = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));

    final userDoc = await _dataSource.getUserDocument(userId);
    final activities = await _dataSource.fetchUserActivities(
      userId: userId,
      since: dayStart,
      before: dayEnd,
    );
    final moods = await _tryFetch(
      () => _dataSource.fetchMoods(
        userId: userId,
        since: dayStart,
        before: dayEnd,
      ),
      label: 'moods',
    );
    final breathingSessions = await _tryFetch(
      () => _dataSource.fetchBreathingSessions(
        userId: userId,
        since: dayStart,
        before: dayEnd,
      ),
      label: 'breathing sessions',
    );

    final counts = <String, int>{};
    for (final activity in activities) {
      final type = activity['type']?.toString().trim() ?? '';
      if (type.isEmpty) continue;
      counts[type] = (counts[type] ?? 0) + 1;
    }

    final moodLevels = moods
        .map((mood) => intFromFirestore(mood['level']))
        .where((level) => level > 0)
        .toList(growable: false);
    final averageMood = moodLevels.isEmpty
        ? null
        : moodLevels.fold<int>(0, (total, level) => total + level) /
              moodLevels.length;

    final completedBreathing = breathingSessions.where(
      (session) => session['completed'] == true,
    );
    final breathingSeconds = completedBreathing.fold<int>(
      0,
      (total, session) => total + intFromFirestore(session['completedSeconds']),
    );

    final recentActivities = [...activities]
      ..sort((left, right) {
        final leftDate = dateTimeFromFirestore(left['occurredAt']) ?? dayStart;
        final rightDate =
            dateTimeFromFirestore(right['occurredAt']) ?? dayStart;
        return rightDate.compareTo(leftDate);
      });

    return MentalHealthActivitySummary(
      date: dayStart,
      moodCheckIns: counts['moodCheckIn'] ?? moodLevels.length,
      averageMoodLevel: averageMood,
      mindAidMessages: counts['mindAidMessage'] ?? 0,
      breathingSessions:
          counts['breathingSession'] ?? completedBreathing.length,
      breathingMinutes: (breathingSeconds / 60).round(),
      secretChatPosts: counts['secretChatPost'] ?? 0,
      secretChatComments: counts['secretChatComment'] ?? 0,
      secretChatInteractions: counts['secretChatInteraction'] ?? 0,
      assessmentCount:
          (counts['quickAssessment'] ?? 0) + (counts['fullAssessment'] ?? 0),
      currentStreak: StreakCalculator.effectiveStreak(
        storedStreak: intFromFirestore(userDoc?['dayStreak']),
        lastActivityDateKey: userDoc?['lastActivityDateKey']?.toString(),
        now: targetDate,
      ),
      recentActivities: recentActivities
          .map(_activityItemFromJson)
          .take(8)
          .toList(growable: false),
    );
  }

  Future<List<Map<String, dynamic>>> _tryFetch(
    Future<List<Map<String, dynamic>>> Function() fetch, {
    required String label,
  }) async {
    try {
      return await fetch();
    } catch (error, stackTrace) {
      debugPrint('Unable to enrich daily summary with $label: $error');
      debugPrintStack(stackTrace: stackTrace);
      return const [];
    }
  }

  MentalHealthActivityItem _activityItemFromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString().trim() ?? '';
    return MentalHealthActivityItem(
      type: type,
      label: _labelForType(type),
      occurredAt: dateTimeFromFirestore(json['occurredAt']) ?? DateTime.now(),
    );
  }

  String _labelForType(String type) {
    switch (type) {
      case 'moodCheckIn':
        return 'Logged mood';
      case 'mindAidMessage':
        return 'Used MindAid';
      case 'breathingSession':
        return 'Completed breathing';
      case 'secretChatPost':
        return 'Posted in Secret Chat';
      case 'secretChatComment':
        return 'Replied in Secret Chat';
      case 'secretChatInteraction':
        return 'Supported a Secret Chat post';
      case 'quickAssessment':
        return 'Completed quick assessment';
      case 'fullAssessment':
        return 'Completed full assessment';
      case 'journalEntry':
        return 'Added journal entry';
      default:
        return 'Recorded activity';
    }
  }
}
