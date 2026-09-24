import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/repositories/mood_repository.dart';

void main() {
  test('preserves a saved same-day mood during refresh', () async {
    final now = DateTime(2026, 7, 7, 12);
    final repository = _FakeMoodRepository(
      recentMoods: [
        MoodModel(id: 'incomplete', userId: 'user_1', level: 2, createdAt: now),
      ],
    );
    final provider = MoodProvider(repository, nowProvider: () => now);

    await provider.logDailyMood(
      userId: 'user_1',
      level: 2,
      label: 'Stressed',
      note: 'Exams feel heavy.',
    );
    await provider.loadRecentMoods('user_1');

    expect(provider.todayMood?.note, 'Exams feel heavy.');
  });

  test('clears the previous day when the injected clock advances', () async {
    var now = DateTime(2026, 7, 7, 12);
    final repository = _FakeMoodRepository();
    final provider = MoodProvider(repository, nowProvider: () => now);

    await provider.logDailyMood(userId: 'user_1', level: 3, label: 'Okay');
    expect(provider.todayMood, isNotNull);

    now = DateTime(2026, 7, 8, 12);
    await provider.loadRecentMoods('user_1');

    expect(provider.todayMood, isNull);
  });

  test('uses the injected clock for legacy mood timestamps', () async {
    final now = DateTime(2026, 7, 7, 12);
    final provider = MoodProvider(
      _FakeMoodRepository(),
      nowProvider: () => now,
    );

    await provider.logMood(userId: 'user_1', level: 4, label: 'Good');

    expect(provider.moods.single.createdAt, now);
  });

  test('same-day fetch failure preserves the current mood', () async {
    final now = DateTime(2026, 7, 7, 12);
    final repository = _FakeMoodRepository();
    final provider = MoodProvider(repository, nowProvider: () => now);
    await provider.logDailyMood(
      userId: 'user_1',
      level: 4,
      note: 'Still valid today',
    );
    repository.throwsOnFetchToday = true;

    await provider.loadTodayMood('user_1');

    expect(provider.todayMood?.note, 'Still valid today');
    expect(provider.errorMessage, 'Unable to load today\'s mood.');
  });

  test('failed fetch after midnight does not restore yesterday mood', () async {
    // Use UTC instants so this remains 11 PM / 1 AM in Manila on CI runners
    // (which run in UTC) as well as on developer machines in other zones.
    var now = DateTime.utc(2026, 7, 7, 15);
    final repository = _FakeMoodRepository();
    final provider = MoodProvider(repository, nowProvider: () => now);
    await provider.logDailyMood(userId: 'user_1', level: 3);
    repository.throwsOnFetchToday = true;
    now = DateTime.utc(2026, 7, 7, 17);

    await provider.loadTodayMood('user_1');

    expect(provider.todayMood, isNull);
    expect(provider.hasCheckedInToday, isFalse);
    expect(provider.errorMessage, 'Unable to load today\'s mood.');
  });

  test('legacy save samples the injected clock once', () async {
    var calls = 0;
    final beforeMidnight = DateTime.utc(2026, 7, 7, 15, 59, 59);
    final afterMidnight = DateTime.utc(2026, 7, 7, 16);
    final repository = _FakeMoodRepository();
    final provider = MoodProvider(
      repository,
      nowProvider: () => calls++ == 0 ? beforeMidnight : afterMidnight,
    );

    await provider.logMood(userId: 'user_1', level: 4);

    expect(calls, 1);
    expect(repository.createdNow, beforeMidnight);
    expect(provider.moods.single.createdAt, beforeMidnight);
    expect(provider.todayMood, isNotNull);
  });
}

class _FakeMoodRepository extends MoodRepository {
  _FakeMoodRepository({this.recentMoods = const []});

  final List<MoodModel> recentMoods;
  bool throwsOnFetchToday = false;
  DateTime? createdNow;

  @override
  Future<MoodModel?> fetchTodayMood(String userId, {DateTime? now}) async {
    if (throwsOnFetchToday) throw StateError('fetch failed');
    return null;
  }

  @override
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
    final instant = now ?? DateTime(2026, 7, 7, 12);
    return DailyMoodSaveResult(
      mood: MoodModel(
        id: 'daily_user_1_${MoodRepository.dateKeyFor(instant).replaceAll('-', '')}',
        userId: userId,
        level: level,
        label: label,
        note: note,
        dateKey: MoodRepository.dateKeyFor(instant),
        createdAt: instant,
      ),
      created: true,
    );
  }

  @override
  Future<List<MoodModel>> fetchRecentMoods(String userId, {int limit = 14}) {
    return Future.value(recentMoods);
  }

  @override
  Future<String> createMood({
    required String userId,
    required int level,
    String? label,
    String? note,
    DateTime? now,
  }) async {
    createdNow = now;
    return 'mood_1';
  }
}
