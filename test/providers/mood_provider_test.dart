import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/repositories/mood_combined_history_repository.dart';
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

  test('V2 reader keeps same-day entries distinct from active days', () async {
    final history = MoodCombinedHistoryRepository(
      identity: const _MoodIdentity('user_1'),
      legacySource: _MoodSource(MoodEventSource.legacy, [
        _event(
          'legacy',
          DateTime.utc(2026, 7, 7, 16),
          2,
          MoodEventSource.legacy,
        ),
      ]),
      v2Source: _MoodSource(MoodEventSource.v2, [
        _event('v2-one', DateTime.utc(2026, 7, 7, 17), 4, MoodEventSource.v2),
        _event('v2-two', DateTime.utc(2026, 7, 7, 18), 5, MoodEventSource.v2),
      ]),
    );
    final provider = MoodProvider(
      _FakeMoodRepository(),
      combinedHistoryRepository: history,
      useMoodV2Read: true,
      nowProvider: () => DateTime.utc(2026, 7, 8),
    );

    await provider.loadMoodV2History('user_1');

    expect(provider.v2Analytics!.eventCount, 3);
    expect(provider.v2Analytics!.activeDayCount, 1);
    expect(provider.todayMood, isNull);
    expect(provider.hasCheckedInToday, isFalse);
  });

  test('V2 reader clears prior state and ignores a stale account result', () async {
    final identity = _MutableMoodIdentity('user_1');
    final delayedLegacy = Completer<MoodHistorySourcePage>();
    final history = MoodCombinedHistoryRepository(
      identity: identity,
      legacySource: _DeferredMoodSource(
        MoodEventSource.legacy,
        {'user_1': delayedLegacy},
      ),
      v2Source: _MoodSource(MoodEventSource.v2, const []),
    );
    final provider = MoodProvider(
      _FakeMoodRepository(),
      combinedHistoryRepository: history,
      useMoodV2Read: true,
    );

    final firstRequest = provider.loadMoodV2History('user_1');
    identity.currentUserId = 'user_2';
    await provider.loadMoodV2History('user_2');

    expect(provider.v2History, isNotNull);
    expect(provider.v2History!.uniqueEvents, isEmpty);
    delayedLegacy.complete(
      MoodHistorySourcePage(
        events: [_event('stale', DateTime.utc(2026, 7, 7), 1, MoodEventSource.legacy)],
      ),
    );
    await firstRequest;

    expect(provider.v2History!.uniqueEvents, isEmpty);
    expect(provider.v2HistoryErrorMessage, isNull);
  });
}

NormalizedMoodEvent _event(
  String id,
  DateTime at,
  int level,
  MoodEventSource source,
) => NormalizedMoodEvent(
  id: id,
  userId: 'user_1',
  level: level,
  dateKey: MoodManilaCalendar.dateKeyForInstant(at),
  occurredAt: at,
  source: source,
);

class _MoodIdentity implements MoodHistoryIdentity {
  const _MoodIdentity(this.currentUserId);
  @override
  final String? currentUserId;
}

class _MutableMoodIdentity implements MoodHistoryIdentity {
  _MutableMoodIdentity(this.currentUserId);
  @override
  String? currentUserId;
}

class _MoodSource implements MoodHistorySource {
  const _MoodSource(this.source, this.events);
  @override
  final MoodEventSource source;
  final List<NormalizedMoodEvent> events;
  @override
  Future<MoodHistorySourcePage> fetch(MoodHistorySourceRequest request) async =>
      MoodHistorySourcePage(events: events);
}

class _DeferredMoodSource implements MoodHistorySource {
  _DeferredMoodSource(this.source, this.responses);

  @override
  final MoodEventSource source;
  final Map<String, Completer<MoodHistorySourcePage>> responses;

  @override
  Future<MoodHistorySourcePage> fetch(MoodHistorySourceRequest request) {
    return responses[request.userId]?.future ??
        Future.value(const MoodHistorySourcePage(events: []));
  }
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
