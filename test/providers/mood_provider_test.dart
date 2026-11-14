import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/repositories/mood_combined_history_repository.dart';
import 'package:mind_mates/repositories/mood_repository.dart';

void main() {
  test(
    'private notes retry errors and discard completion after account switch',
    () async {
      final pending = Completer<Map<String, dynamic>?>();
      var fail = true;
      final repository = MoodCombinedHistoryRepository(
        identity: const _MoodIdentity('user_1'),
        legacySource: const _MoodSource(MoodEventSource.legacy, []),
        v2Source: _MoodSource(MoodEventSource.v2, [
          _event('note', DateTime.utc(2026, 11, 12), 3, MoodEventSource.v2),
        ]),
        ownerNoteDocumentReader: (source, id) async {
          if (fail) throw StateError('offline');
          return pending.future;
        },
      );
      final provider = MoodProvider(
        _FakeMoodRepository(),
        useMoodV2Read: true,
        combinedHistoryRepository: repository,
      );
      provider.bindAuthenticatedUser('user_1');
      await provider.loadMoodV2History('user_1');
      await provider.loadMoodV2DayNotes('user_1', '2026-11-12');
      expect(provider.v2NoteErrorDays, contains('2026-11-12'));
      expect(provider.v2PersonalNotes, isEmpty);
      fail = false;
      final request = provider.loadMoodV2DayNotes('user_1', '2026-11-12');
      provider.bindAuthenticatedUser('user_2');
      pending.complete({'userId': 'user_1', 'note': 'Private'});
      await request;
      expect(provider.v2PersonalNotes, isEmpty);
      expect(provider.v2NoteLoadingDays, isEmpty);
      expect(provider.v2NoteErrorDays, isEmpty);
    },
  );
  test(
    'latest V2 mood survives stale refresh and clears at midnight or account change',
    () async {
      var now = DateTime.utc(2026, 11, 12, 3);
      final provider = MoodProvider(
        _FakeMoodRepository(),
        nowProvider: () => now,
        useMoodV2Read: true,
        combinedHistoryRepository: MoodCombinedHistoryRepository(
          identity: const _MoodIdentity('user_1'),
          legacySource: const _MoodSource(MoodEventSource.legacy, []),
          v2Source: _MoodSource(MoodEventSource.v2, [
            _event(
              'old',
              now.subtract(const Duration(hours: 1)),
              2,
              MoodEventSource.v2,
            ),
          ]),
        ),
      );
      provider.bindAuthenticatedUser('user_1');
      await provider.loadMoodV2History('user_1');
      expect(provider.latestMoodForToday()?.id, 'old');
      for (final id in ['first', 'second']) {
        provider.recordConfirmedMoodV2Entry(
          MoodV2Event(
            id: id,
            userId: 'user_1',
            level: 5,
            dateKey: '2026-11-12',
            occurredAt: now,
            clientRequestId: id,
            label: id,
          ),
        );
      }
      await provider.loadMoodV2History('user_1');
      expect(provider.latestMoodForToday()?.label, 'second');
      now = DateTime.utc(2026, 11, 12, 16);
      expect(provider.latestMoodForToday(), isNull);
      provider.bindAuthenticatedUser('user_2');
      now = DateTime.utc(2026, 11, 12, 3);
      expect(provider.latestMoodForToday(), isNull);
    },
  );
  test(
    'legacy pending load cannot enter a new authenticated session',
    () async {
      final repo = _PendingLegacyRepository();
      final provider = MoodProvider(repo);
      provider.bindAuthenticatedUser('old');
      final load = provider.loadTodayMood('old');
      provider.bindAuthenticatedUser('new');
      repo.pending.complete(
        MoodModel(
          id: 'old-record',
          userId: 'old',
          level: 2,
          createdAt: DateTime.now(),
        ),
      );
      await load;
      expect(provider.todayMood, isNull);
      expect(provider.isLoadingToday, isFalse);
    },
  );
  test('legacy pending save cannot enter a logged-out session', () async {
    final repo = _PendingLegacyRepository();
    final provider = MoodProvider(repo);
    provider.bindAuthenticatedUser('old');
    final save = provider.logDailyMood(userId: 'old', level: 2);
    provider.bindAuthenticatedUser(null);
    repo.save.complete(
      DailyMoodSaveResult(
        mood: MoodModel(
          id: 'old-record',
          userId: 'old',
          level: 2,
          createdAt: DateTime.now(),
        ),
        created: true,
      ),
    );
    expect(await save, isFalse);
    expect(provider.todayMood, isNull);
  });
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

  test(
    'V2 reader appends bounded pages without duplicate identities',
    () async {
      final history = MoodCombinedHistoryRepository(
        identity: const _MoodIdentity('user_1'),
        legacySource: _PagedMoodSource(MoodEventSource.legacy, {
          null: MoodHistorySourcePage(
            events: [
              _event(
                'legacy-new',
                DateTime.utc(2026, 7, 10),
                2,
                MoodEventSource.legacy,
              ),
            ],
            nextCursor: 'legacy-page-2',
          ),
          'legacy-page-2': MoodHistorySourcePage(
            events: [
              _event(
                'legacy-new',
                DateTime.utc(2026, 7, 10),
                2,
                MoodEventSource.legacy,
              ),
              _event(
                'legacy-old',
                DateTime.utc(2026, 7, 8),
                3,
                MoodEventSource.legacy,
              ),
            ],
          ),
        }),
        v2Source: _PagedMoodSource(MoodEventSource.v2, {
          null: MoodHistorySourcePage(
            events: [
              _event(
                'v2-new',
                DateTime.utc(2026, 7, 10, 1),
                4,
                MoodEventSource.v2,
              ),
            ],
            nextCursor: 'v2-page-2',
          ),
          'v2-page-2': MoodHistorySourcePage(
            events: [
              _event('v2-old', DateTime.utc(2026, 7, 9), 5, MoodEventSource.v2),
            ],
          ),
        }),
      );
      final provider = MoodProvider(
        _FakeMoodRepository(),
        combinedHistoryRepository: history,
        useMoodV2Read: true,
        nowProvider: () => DateTime.utc(2026, 7, 11),
      );

      await provider.loadMoodV2History('user_1');
      expect(provider.v2History!.uniqueEvents, hasLength(2));
      expect(provider.v2History!.coverage, MoodHistoryCoverage.partial);
      expect(provider.canLoadMoreMoodV2History, isTrue);

      await provider.loadMoreMoodV2History('user_1');

      expect(provider.v2History!.uniqueEvents, hasLength(4));
      expect(provider.v2History!.uniqueEvents.map((event) => event.id), [
        'legacy-old',
        'v2-old',
        'legacy-new',
        'v2-new',
      ]);
      expect(provider.v2History!.coverage, MoodHistoryCoverage.complete);
      expect(provider.canLoadMoreMoodV2History, isFalse);
      expect(provider.v2PaginationErrorMessage, isNull);
    },
  );

  test(
    'V2 failed page retains loaded history and retries its cursor',
    () async {
      final legacy = _PagedMoodSource(MoodEventSource.legacy, {
        null: MoodHistorySourcePage(
          events: [
            _event(
              'legacy-new',
              DateTime.utc(2026, 7, 10),
              2,
              MoodEventSource.legacy,
            ),
          ],
          nextCursor: 'legacy-page-2',
        ),
        'legacy-page-2': MoodHistorySourcePage(
          events: [
            _event(
              'legacy-old',
              DateTime.utc(2026, 7, 8),
              3,
              MoodEventSource.legacy,
            ),
          ],
        ),
      })..failCursors.add('legacy-page-2');
      final history = MoodCombinedHistoryRepository(
        identity: const _MoodIdentity('user_1'),
        legacySource: legacy,
        v2Source: _PagedMoodSource(MoodEventSource.v2, {
          null: MoodHistorySourcePage(
            events: [
              _event(
                'v2-new',
                DateTime.utc(2026, 7, 10, 1),
                4,
                MoodEventSource.v2,
              ),
            ],
            nextCursor: 'v2-page-2',
          ),
          'v2-page-2': MoodHistorySourcePage(
            events: [
              _event('v2-old', DateTime.utc(2026, 7, 9), 5, MoodEventSource.v2),
            ],
          ),
        }),
      );
      final provider = MoodProvider(
        _FakeMoodRepository(),
        combinedHistoryRepository: history,
        useMoodV2Read: true,
      );

      await provider.loadMoodV2History('user_1');
      await provider.loadMoreMoodV2History('user_1');

      expect(
        provider.v2History!.uniqueEvents.map((event) => event.id),
        contains('v2-old'),
      );
      expect(provider.v2History!.coverage, MoodHistoryCoverage.partial);
      expect(provider.v2PaginationErrorMessage, isNotNull);
      expect(provider.canLoadMoreMoodV2History, isTrue);

      legacy.failCursors.clear();
      await provider.loadMoreMoodV2History('user_1');

      expect(provider.v2History!.uniqueEvents, hasLength(4));
      expect(provider.v2History!.coverage, MoodHistoryCoverage.complete);
      expect(provider.v2PaginationErrorMessage, isNull);
      expect(provider.canLoadMoreMoodV2History, isFalse);
    },
  );

  test(
    'V2 history loads more than 100 entries without inflating active days',
    () async {
      final first = List.generate(
        100,
        (index) => _event(
          'v2-$index',
          DateTime.utc(
            2026,
            7,
            12,
            12,
          ).subtract(Duration(days: index ~/ 2, minutes: index)),
          3,
          MoodEventSource.v2,
        ),
      );
      final history = MoodCombinedHistoryRepository(
        identity: const _MoodIdentity('user_1'),
        legacySource: _PagedMoodSource(MoodEventSource.legacy, {
          null: const MoodHistorySourcePage(events: []),
        }),
        v2Source: _PagedMoodSource(MoodEventSource.v2, {
          null: MoodHistorySourcePage(events: first, nextCursor: 'older'),
          'older': MoodHistorySourcePage(
            events: [
              _event(
                'v2-100',
                DateTime.utc(2026, 5, 23, 12),
                4,
                MoodEventSource.v2,
              ),
            ],
          ),
        }),
      );
      final provider = MoodProvider(
        _FakeMoodRepository(),
        combinedHistoryRepository: history,
        useMoodV2Read: true,
        nowProvider: () => DateTime.utc(2026, 7, 12),
      );

      await provider.loadMoodV2History('user_1');
      expect(provider.v2History!.uniqueEvents, hasLength(100));
      expect(provider.v2History!.coverage, MoodHistoryCoverage.partial);
      expect(provider.v2Analytics!.streak.isLongestWindowed, isTrue);
      expect(provider.v2Analytics!.activeDayCount, 50);

      await provider.loadMoreMoodV2History('user_1');
      expect(provider.v2History!.uniqueEvents, hasLength(101));
      expect(provider.v2Analytics!.activeDayCount, 51);
      expect(provider.v2Analytics!.streak.isLongestWindowed, isFalse);
      expect(provider.v2History!.coverage, MoodHistoryCoverage.complete);
      expect(provider.canLoadMoreMoodV2History, isFalse);
    },
  );

  test('V2 empty final page exhausts the cursor', () async {
    final history = MoodCombinedHistoryRepository(
      identity: const _MoodIdentity('user_1'),
      legacySource: _PagedMoodSource(MoodEventSource.legacy, {
        null: MoodHistorySourcePage(
          events: [
            _event('one', DateTime.utc(2026, 7, 10), 3, MoodEventSource.legacy),
          ],
          nextCursor: 'empty',
        ),
        'empty': const MoodHistorySourcePage(events: []),
      }),
      v2Source: _PagedMoodSource(MoodEventSource.v2, {
        null: const MoodHistorySourcePage(events: []),
      }),
    );
    final provider = MoodProvider(
      _FakeMoodRepository(),
      combinedHistoryRepository: history,
      useMoodV2Read: true,
    );

    await provider.loadMoodV2History('user_1');
    expect(provider.canLoadMoreMoodV2History, isTrue);
    await provider.loadMoreMoodV2History('user_1');
    expect(provider.v2History!.uniqueEvents.single.id, 'one');
    expect(provider.v2History!.coverage, MoodHistoryCoverage.complete);
    expect(provider.canLoadMoreMoodV2History, isFalse);
  });

  test('V2 pending page is invalidated by logout', () async {
    final identity = _MutableMoodIdentity('user_1');
    final delayedPage = Completer<MoodHistorySourcePage>();
    final history = MoodCombinedHistoryRepository(
      identity: identity,
      legacySource: _PagedMoodSource(MoodEventSource.legacy, {
        null: MoodHistorySourcePage(
          events: [
            _event(
              'legacy-new',
              DateTime.utc(2026, 7, 10),
              2,
              MoodEventSource.legacy,
            ),
          ],
          nextCursor: 'legacy-page-2',
        ),
        'legacy-page-2': delayedPage.future,
      }),
      v2Source: _PagedMoodSource(MoodEventSource.v2, {
        null: MoodHistorySourcePage(
          events: [
            _event(
              'v2-new',
              DateTime.utc(2026, 7, 10, 1),
              4,
              MoodEventSource.v2,
            ),
          ],
          nextCursor: 'v2-page-2',
        ),
        'v2-page-2': const MoodHistorySourcePage(events: []),
      }),
    );
    final provider = MoodProvider(
      _FakeMoodRepository(),
      combinedHistoryRepository: history,
      useMoodV2Read: true,
    );
    provider.bindAuthenticatedUser('user_1');
    await provider.loadMoodV2History('user_1');

    final pending = provider.loadMoreMoodV2History('user_1');
    identity.currentUserId = null;
    provider.bindAuthenticatedUser(null);
    delayedPage.complete(
      MoodHistorySourcePage(
        events: [
          _event(
            'stale-page',
            DateTime.utc(2026, 7, 8),
            1,
            MoodEventSource.legacy,
          ),
        ],
      ),
    );
    await pending;

    expect(provider.v2History, isNull);
    expect(provider.canLoadMoreMoodV2History, isFalse);
  });

  test('V2 pending page cannot enter the next authenticated account', () async {
    final identity = _MutableMoodIdentity('user_1');
    final delayedPage = Completer<MoodHistorySourcePage>();
    final history = MoodCombinedHistoryRepository(
      identity: identity,
      legacySource: _PagedMoodSource(MoodEventSource.legacy, {
        null: MoodHistorySourcePage(
          events: [
            _event(
              'first',
              DateTime.utc(2026, 7, 10),
              2,
              MoodEventSource.legacy,
            ),
          ],
          nextCursor: 'older',
        ),
        'older': delayedPage.future,
      }),
      v2Source: _PagedMoodSource(MoodEventSource.v2, {
        null: const MoodHistorySourcePage(events: []),
      }),
    );
    final provider = MoodProvider(
      _FakeMoodRepository(),
      combinedHistoryRepository: history,
      useMoodV2Read: true,
    );
    provider.bindAuthenticatedUser('user_1');
    await provider.loadMoodV2History('user_1');

    final pending = provider.loadMoreMoodV2History('user_1');
    identity.currentUserId = 'user_2';
    provider.bindAuthenticatedUser('user_2');
    expect(provider.v2History, isNull);
    await provider.loadMoodV2History('user_2');
    delayedPage.complete(
      MoodHistorySourcePage(
        events: [
          _event('stale', DateTime.utc(2026, 7, 8), 1, MoodEventSource.legacy),
        ],
      ),
    );
    await pending;

    expect(provider.v2History!.uniqueEvents, isEmpty);
    expect(provider.v2HistoryErrorMessage, isNull);
  });

  test(
    'V2 reader clears prior state and ignores a stale account result',
    () async {
      final identity = _MutableMoodIdentity('user_1');
      final delayedLegacy = Completer<MoodHistorySourcePage>();
      final history = MoodCombinedHistoryRepository(
        identity: identity,
        legacySource: _DeferredMoodSource(MoodEventSource.legacy, {
          'user_1': delayedLegacy,
        }),
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
          events: [
            _event(
              'stale',
              DateTime.utc(2026, 7, 7),
              1,
              MoodEventSource.legacy,
            ),
          ],
        ),
      );
      await firstRequest;

      expect(provider.v2History!.uniqueEvents, isEmpty);
      expect(provider.v2HistoryErrorMessage, isNull);
    },
  );

  // --- Task 4: the read surfaces with legacy-only and mixed history ----------
  //
  // The headline goal is that a staging build turns the five readers on for
  // ordinary accounts whose mood history lives entirely in the legacy store.
  // These pin that; without them a V2-only reader would pass CI.

  test('legacy-only history yields entries and a streak', () async {
    final provider = MoodProvider(
      _FakeMoodRepository(),
      nowProvider: () => DateTime.utc(2026, 11, 12, 3),
      useMoodV2Read: true,
      combinedHistoryRepository: MoodCombinedHistoryRepository(
        identity: const _MoodIdentity('user_1'),
        legacySource: _MoodSource(MoodEventSource.legacy, [
          _event(
            'l-today',
            DateTime.utc(2026, 11, 12, 1),
            4,
            MoodEventSource.legacy,
          ),
          _event(
            'l-yesterday',
            DateTime.utc(2026, 11, 11, 1),
            3,
            MoodEventSource.legacy,
          ),
          _event(
            'l-earlier',
            DateTime.utc(2026, 11, 10, 1),
            5,
            MoodEventSource.legacy,
          ),
        ]),
        v2Source: const _MoodSource(MoodEventSource.v2, []),
      ),
    );
    provider.bindAuthenticatedUser('user_1');
    await provider.loadMoodV2History('user_1');

    expect(provider.v2History, isNotNull);
    expect(provider.v2History!.events, hasLength(3));
    expect(
      provider.v2History!.events.every(
        (e) => e.source == MoodEventSource.legacy,
      ),
      isTrue,
    );
    // The Journey, profile and insights all read this snapshot.
    expect(provider.v2Analytics, isNotNull);
    expect(provider.v2Analytics!.streak.currentDays, 3);
    // The home card's today lookup finds the legacy entry.
    expect(
      provider.latestMoodForToday(now: DateTime.utc(2026, 11, 12, 3))?.id,
      'l-today',
    );
  });

  test('legacy and V2 history merge in order without duplicates', () async {
    final provider = MoodProvider(
      _FakeMoodRepository(),
      nowProvider: () => DateTime.utc(2026, 11, 12, 3),
      useMoodV2Read: true,
      combinedHistoryRepository: MoodCombinedHistoryRepository(
        identity: const _MoodIdentity('user_1'),
        legacySource: _MoodSource(MoodEventSource.legacy, [
          _event(
            'l-10',
            DateTime.utc(2026, 11, 10, 1),
            3,
            MoodEventSource.legacy,
          ),
          _event(
            'l-12',
            DateTime.utc(2026, 11, 12, 1),
            4,
            MoodEventSource.legacy,
          ),
        ]),
        v2Source: _MoodSource(MoodEventSource.v2, [
          _event('v-11', DateTime.utc(2026, 11, 11, 1), 5, MoodEventSource.v2),
        ]),
      ),
    );
    provider.bindAuthenticatedUser('user_1');
    await provider.loadMoodV2History('user_1');

    final ids = provider.v2History!.events.map((e) => e.id).toList();
    expect(ids, hasLength(3));
    expect(ids.toSet(), hasLength(ids.length), reason: 'no duplicates');
    expect(ids, containsAll(<String>['l-10', 'l-12', 'v-11']));
    // A pilot account keeps both sources, not one.
    expect(
      provider.v2History!.events.map((e) => e.source).toSet().containsAll(
        <MoodEventSource>{MoodEventSource.legacy, MoodEventSource.v2},
      ),
      isTrue,
    );
  });

  test('another account history never reaches the readers', () async {
    final identity = _MutableMoodIdentity('user_1');
    final provider = MoodProvider(
      _FakeMoodRepository(),
      nowProvider: () => DateTime.utc(2026, 11, 12, 3),
      useMoodV2Read: true,
      combinedHistoryRepository: MoodCombinedHistoryRepository(
        identity: identity,
        legacySource: _MoodSource(MoodEventSource.legacy, [
          _event(
            'l-today',
            DateTime.utc(2026, 11, 12, 1),
            4,
            MoodEventSource.legacy,
          ),
        ]),
        v2Source: const _MoodSource(MoodEventSource.v2, []),
      ),
    );
    provider.bindAuthenticatedUser('user_1');
    await provider.loadMoodV2History('user_1');
    expect(provider.v2History!.events, isNotEmpty);

    // Switching account must not leave the previous account's history behind.
    identity.currentUserId = 'user_2';
    provider.bindAuthenticatedUser('user_2');
    expect(provider.v2History?.events ?? const [], isEmpty);
    expect(
      provider.latestMoodForToday(now: DateTime.utc(2026, 11, 12, 3)),
      isNull,
    );
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

class _PagedMoodSource implements MoodHistorySource {
  _PagedMoodSource(this.source, this.pages);

  @override
  final MoodEventSource source;
  final Map<Object?, dynamic> pages;
  final Set<Object?> failCursors = {};

  @override
  Future<MoodHistorySourcePage> fetch(MoodHistorySourceRequest request) async {
    if (failCursors.contains(request.cursor)) {
      throw StateError('page unavailable');
    }
    final page = pages[request.cursor];
    if (page is Future<MoodHistorySourcePage>) return page;
    return page as MoodHistorySourcePage? ??
        const MoodHistorySourcePage(events: []);
  }
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

class _PendingLegacyRepository extends MoodRepository {
  final pending = Completer<MoodModel?>();
  final save = Completer<DailyMoodSaveResult>();
  @override
  Future<MoodModel?> fetchTodayMood(String userId, {DateTime? now}) =>
      pending.future;
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
  }) => save.future;
}
