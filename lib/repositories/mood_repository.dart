import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../models/mood_model.dart';
import '../services/firebase/firestore_service.dart';
import 'user_repository.dart';

class MoodRepository {
  MoodRepository({
    FirestoreService? firestoreService,
    DateTime Function()? nowProvider,
  }) : _firestoreService = firestoreService ?? FirestoreService(),
       _nowProvider = nowProvider ?? DateTime.now;

  final FirestoreService _firestoreService;
  final DateTime Function() _nowProvider;

  static const timezone = 'Asia/Manila';

  static DateTime manilaWallClock(DateTime instant) {
    final shifted = instant.toUtc().add(const Duration(hours: 8));
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
      shifted.millisecond,
      shifted.microsecond,
    );
  }

  static String dateKeyFor(DateTime instant) {
    final date = manilaWallClock(instant);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String dailyDocumentId(String userId, DateTime instant) {
    return 'daily_${userId}_${dateKeyFor(instant).replaceAll('-', '')}';
  }

  Future<MoodModel?> fetchTodayMood(String userId, {DateTime? now}) async {
    final instant = now ?? _nowProvider();
    final dateKey = dateKeyFor(instant);
    final documentId = dailyDocumentId(userId, instant);
    final deterministic = await _firestoreService.getDocument(
      FirestoreCollections.moods,
      documentId,
    );
    if (deterministic != null) {
      return MoodModel.fromJson(deterministic, id: documentId);
    }

    final recent = await fetchRecentMoods(userId, limit: 50);
    for (final mood in recent) {
      final moodDateKey = (mood.dateKey ?? '').trim().isNotEmpty
          ? mood.dateKey
          : dateKeyFor(mood.createdAt);
      if (moodDateKey == dateKey) return mood;
    }
    return null;
  }

  Future<DailyMoodSaveResult> saveDailyMood({
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
    final instant = now ?? _nowProvider();
    final existing = await fetchTodayMood(userId, now: instant);
    if (existing != null) {
      return DailyMoodSaveResult(mood: existing, created: false);
    }

    final dateKey = dateKeyFor(instant);
    final wallClock = manilaWallClock(instant);
    final documentId = dailyDocumentId(userId, instant);
    final firestore = _firestoreService.firestore;
    final moodRef = firestore
        .collection(FirestoreCollections.moods)
        .doc(documentId);
    final userRef = firestore
        .collection(FirestoreCollections.users)
        .doc(userId);
    final activityRef = firestore
        .collection(FirestoreCollections.userActivities)
        .doc('mood_${userId}_${dateKey.replaceAll('-', '')}');

    final created = await firestore.runTransaction((transaction) async {
      final moodSnapshot = await transaction.get(moodRef);
      if (moodSnapshot.exists) return false;

      final userSnapshot = await transaction.get(userRef);
      final userData = userSnapshot.data();
      final streak = StreakCalculator.calculate(
        occurredAt: wallClock,
        previousDateKey:
            userData?['lastActivityDateKey']?.toString() ??
            userData?['lastCheckInDate']?.toString(),
        currentStreak: _intOrZero(userData?['dayStreak']),
        longestStreak: _intOrZero(userData?['longestStreak']),
        activeDateKeys: _stringList(userData?['activeDateKeys']),
      );

      final moodData = <String, dynamic>{
        'userId': userId,
        'level': level,
        'label': label?.trim() ?? '',
        'note': note?.trim() ?? '',
        'dateKey': dateKey,
        'timezone': timezone,
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (expressionAssistUsed == true) {
        moodData.addAll({
          'entryMethod': entryMethod ?? 'expression_assisted',
          'expressionAssistUsed': true,
          'expressionSuggestionAccepted': expressionSuggestionAccepted ?? false,
        });
        if (expressionModelVersion case final version?) {
          moodData['expressionModelVersion'] = version;
        }
      }
      transaction.set(moodRef, moodData);
      transaction.set(activityRef, {
        'userId': userId,
        'type': UserActivityType.moodCheckIn.storedValue,
        'dateKey': dateKey,
        'occurredAt': Timestamp.fromDate(instant),
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(userRef, {
        'lastActiveAt': FieldValue.serverTimestamp(),
        'lastActivityDateKey': streak.lastActivityDateKey,
        'activeDateKeys': streak.activeDateKeys,
        'streakUpdatedAt': FieldValue.serverTimestamp(),
        'dayStreak': streak.dayStreak,
        'longestStreak': streak.longestStreak,
      }, SetOptions(merge: true));
      return true;
    });

    if (!created) {
      final concurrent = await fetchTodayMood(userId, now: instant);
      if (concurrent != null) {
        return DailyMoodSaveResult(mood: concurrent, created: false);
      }
      throw StateError('Daily mood exists but could not be loaded.');
    }

    return DailyMoodSaveResult(
      mood: MoodModel(
        id: documentId,
        userId: userId,
        level: level,
        label: label?.trim(),
        note: note?.trim(),
        dateKey: dateKey,
        timezone: timezone,
        entryMethod: expressionAssistUsed == true
            ? entryMethod ?? 'expression_assisted'
            : null,
        expressionAssistUsed: expressionAssistUsed == true ? true : null,
        expressionSuggestionAccepted: expressionAssistUsed == true
            ? expressionSuggestionAccepted ?? false
            : null,
        expressionModelVersion: expressionAssistUsed == true
            ? expressionModelVersion
            : null,
        createdAt: instant,
      ),
      created: true,
    );
  }

  Future<List<MoodModel>> fetchRecentMoods(String userId, {int limit = 14}) {
    return _firestoreService
        .getDocuments(
          FirestoreCollections.moods,
          whereEquals: {'userId': userId},
          orderBy: 'createdAt',
          limit: limit,
        )
        .then(
          (docs) => docs
              .map((doc) => MoodModel.fromJson(doc, id: doc['id']?.toString()))
              .toList(growable: false),
        );
  }

  Stream<List<MoodModel>> watchRecentMoods(String userId, {int limit = 14}) {
    return _firestoreService
        .watchDocuments(
          FirestoreCollections.moods,
          whereEquals: {'userId': userId},
          orderBy: 'createdAt',
          limit: limit,
        )
        .map(
          (docs) => docs
              .map((doc) => MoodModel.fromJson(doc, id: doc['id']?.toString()))
              .toList(growable: false),
        );
  }

  Future<String> createMood({
    required String userId,
    required int level,
    String? label,
    String? note,
    DateTime? now,
  }) async {
    final result = await saveDailyMood(
      userId: userId,
      level: level,
      label: label,
      note: note,
      now: now ?? _nowProvider(),
    );
    return result.mood.id;
  }

  static int _intOrZero(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
  }
}

class DailyMoodSaveResult {
  const DailyMoodSaveResult({required this.mood, required this.created});

  final MoodModel mood;
  final bool created;
}
