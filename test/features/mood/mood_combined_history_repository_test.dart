import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/repositories/mood_combined_history_repository.dart';

void main() {
  NormalizedMoodEvent event(
    MoodEventSource source,
    String id,
    DateTime timestamp, {
    String userId = 'owner',
    int level = 3,
  }) => NormalizedMoodEvent(
    id: id,
    userId: userId,
    level: level,
    dateKey: MoodManilaCalendar.dateKeyForInstant(timestamp),
    occurredAt: timestamp,
    source: source,
  );

  group('MoodCombinedHistoryRepository', () {
    test(
      'combines legacy and V2 events without collapsing a shared day or level',
      () async {
        final repository = repositoryFor(
          legacy: [
            event(
              MoodEventSource.legacy,
              'daily_one',
              DateTime.utc(2026, 8, 1, 16),
              level: 4,
            ),
          ],
          v2: [
            event(
              MoodEventSource.v2,
              'entry_one',
              DateTime.utc(2026, 8, 1, 17),
              level: 4,
            ),
            event(
              MoodEventSource.v2,
              'entry_two',
              DateTime.utc(2026, 8, 1, 18),
              level: 4,
            ),
          ],
        );

        final page = await repository.fetch(
          const MoodCombinedHistoryRequest(userId: 'owner'),
        );

        expect(page.window.events.map((item) => item.stableIdentity), [
          'v2:entry_two',
          'v2:entry_one',
          'legacy:daily_one',
        ]);
        expect(
          MoodAnalytics.dailyAggregates(page.window.events).single.entryCount,
          3,
        );
        expect(page.window.coverage, MoodHistoryCoverage.complete);
      },
    );

    test(
      'orders equal timestamps by source-qualified identity and removes only duplicate identities',
      () async {
        final timestamp = DateTime.utc(2026, 8, 1, 16);
        final repository = repositoryFor(
          legacy: [
            event(MoodEventSource.legacy, 'same', timestamp),
            event(MoodEventSource.legacy, 'same', timestamp),
          ],
          v2: [event(MoodEventSource.v2, 'same', timestamp)],
        );

        final page = await repository.fetch(
          const MoodCombinedHistoryRequest(userId: 'owner'),
        );

        expect(page.window.events.map((item) => item.stableIdentity), [
          'legacy:same',
          'v2:same',
        ]);
      },
    );

    test(
      'preserves missing optional legacy fields and derives a Manila date from its timestamp',
      () async {
        final legacy = event(
          MoodEventSource.legacy,
          'daily_missing_fields',
          DateTime.utc(2026, 8, 1, 15, 59),
        );
        final repository = repositoryFor(legacy: [legacy]);

        final page = await repository.fetch(
          const MoodCombinedHistoryRequest(userId: 'owner'),
        );

        expect(page.window.events.single.dateKey, '2026-08-01');
        expect(page.window.events.single.note, isNull);
        expect(page.window.events.single.entryMethod, isNull);
      },
    );

    test(
      'keeps Manila rollover, date bounds, and page boundaries deterministic',
      () async {
        final older = event(
          MoodEventSource.v2,
          'older',
          DateTime.utc(2026, 8, 1, 16),
        );
        final newest = event(
          MoodEventSource.v2,
          'newest',
          DateTime.utc(2026, 8, 1, 17),
        );
        final source = FakeSource(MoodEventSource.v2, [older, newest]);
        final repository = MoodCombinedHistoryRepository(
          identity: FakeIdentity('owner'),
          legacySource: FakeSource(MoodEventSource.legacy, const []),
          v2Source: source,
        );

        final request = MoodCombinedHistoryRequest.forManilaDateRange(
          userId: 'owner',
          startDateKey: '2026-08-02',
          endExclusiveDateKey: '2026-08-03',
          pageSize: 1,
        );
        final first = await repository.fetch(request);
        final second = await repository.fetch(
          MoodCombinedHistoryRequest(
            userId: 'owner',
            startInclusive: request.startInclusive,
            endExclusive: request.endExclusive,
            pageSize: 1,
            cursor: first.nextCursor,
          ),
        );

        expect(first.window.events.single.id, 'newest');
        expect(first.window.events.single.dateKey, '2026-08-02');
        expect(first.window.coverage, MoodHistoryCoverage.partial);
        expect(second.window.events.single.id, 'older');
        expect(second.window.coverage, MoodHistoryCoverage.complete);
        expect(source.requests, hasLength(2));
      },
    );

    test(
      'retains cross-source overflow so later pages never become newer than an earlier page',
      () async {
        final legacy = FakeSource(MoodEventSource.legacy, [
          event(
            MoodEventSource.legacy,
            'legacy_old',
            DateTime.utc(2026, 8, 1, 1),
          ),
        ]);
        final v2 = FakeSource(MoodEventSource.v2, [
          event(MoodEventSource.v2, 'v2_newest', DateTime.utc(2026, 8, 1, 4)),
          event(MoodEventSource.v2, 'v2_middle', DateTime.utc(2026, 8, 1, 3)),
          event(MoodEventSource.v2, 'v2_older', DateTime.utc(2026, 8, 1, 2)),
        ]);
        final repository = MoodCombinedHistoryRepository(
          identity: FakeIdentity('owner'),
          legacySource: legacy,
          v2Source: v2,
        );

        final first = await repository.fetch(
          const MoodCombinedHistoryRequest(userId: 'owner', pageSize: 2),
        );
        final second = await repository.fetch(
          MoodCombinedHistoryRequest(
            userId: 'owner',
            pageSize: 2,
            cursor: first.nextCursor,
          ),
        );

        expect(first.window.events.map((item) => item.id), [
          'v2_newest',
          'v2_middle',
        ]);
        expect(second.window.events.map((item) => item.id), [
          'v2_older',
          'legacy_old',
        ]);
        expect(second.window.coverage, MoodHistoryCoverage.complete);
      },
    );

    test(
      'marks history partial and identifies a failed source without discarding the other source',
      () async {
        final repository = MoodCombinedHistoryRepository(
          identity: FakeIdentity('owner'),
          legacySource: FakeSource(MoodEventSource.legacy, [
            event(MoodEventSource.legacy, 'daily', DateTime.utc(2026, 8, 1)),
          ]),
          v2Source: FakeSource(
            MoodEventSource.v2,
            const [],
            error: StateError('permission denied'),
          ),
        );

        final page = await repository.fetch(
          const MoodCombinedHistoryRequest(userId: 'owner'),
        );

        expect(page.window.events.single.stableIdentity, 'legacy:daily');
        expect(page.window.coverage, MoodHistoryCoverage.partial);
        expect(page.failedSources, {MoodEventSource.v2});
        expect(
          MoodAnalytics.streak(
            page.window,
            referenceInstant: DateTime.utc(2026, 8, 1),
          ).isLongestWindowed,
          isTrue,
        );
      },
    );

    test(
      'rejects unauthenticated, cross-user, and account-switched requests',
      () async {
        final identity = FakeIdentity('owner');
        final repository = MoodCombinedHistoryRepository(
          identity: identity,
          legacySource: FakeSource(MoodEventSource.legacy, const []),
          v2Source: FakeSource(
            MoodEventSource.v2,
            const [],
            onFetch: () => identity.uid = 'other',
          ),
        );

        await expectLater(
          repository.fetch(const MoodCombinedHistoryRequest(userId: 'other')),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          repository.fetch(const MoodCombinedHistoryRequest(userId: 'owner')),
          throwsA(isA<StateError>()),
        );
        identity.uid = null;
        await expectLater(
          repository.fetch(const MoodCombinedHistoryRequest(userId: 'owner')),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'empty history is complete and does not write legacy records or activity streaks',
      () async {
        final legacy = FakeSource(MoodEventSource.legacy, const []);
        final v2 = FakeSource(MoodEventSource.v2, const []);
        final repository = MoodCombinedHistoryRepository(
          identity: FakeIdentity('owner'),
          legacySource: legacy,
          v2Source: v2,
        );

        final page = await repository.fetch(
          const MoodCombinedHistoryRequest(userId: 'owner'),
        );

        expect(page.window.events, isEmpty);
        expect(page.window.coverage, MoodHistoryCoverage.complete);
        expect(legacy.writeAttempts + v2.writeAttempts, 0);
      },
    );
  });
}

MoodCombinedHistoryRepository repositoryFor({
  List<NormalizedMoodEvent> legacy = const [],
  List<NormalizedMoodEvent> v2 = const [],
}) => MoodCombinedHistoryRepository(
  identity: FakeIdentity('owner'),
  legacySource: FakeSource(MoodEventSource.legacy, legacy),
  v2Source: FakeSource(MoodEventSource.v2, v2),
);

class FakeIdentity implements MoodHistoryIdentity {
  FakeIdentity(this.uid);

  String? uid;

  @override
  String? get currentUserId => uid;
}

class FakeSource implements MoodHistorySource {
  FakeSource(this.source, this.events, {this.error, this.onFetch});

  @override
  final MoodEventSource source;
  final List<NormalizedMoodEvent> events;
  final Object? error;
  final void Function()? onFetch;
  final List<MoodHistorySourceRequest> requests = [];
  int writeAttempts = 0;

  @override
  Future<MoodHistorySourcePage> fetch(MoodHistorySourceRequest request) async {
    requests.add(request);
    onFetch?.call();
    if (error != null) throw error!;
    final after = request.cursor as String?;
    final sorted =
        events
            .where((item) => item.userId == request.userId)
            .where(
              (item) =>
                  request.startInclusive == null ||
                  !item.occurredAt.isBefore(request.startInclusive!),
            )
            .where(
              (item) =>
                  request.endExclusive == null ||
                  item.occurredAt.isBefore(request.endExclusive!),
            )
            .toList()
          ..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    final start = after == null
        ? 0
        : sorted.indexWhere((item) => item.id == after) + 1;
    final items = start < 0
        ? <NormalizedMoodEvent>[]
        : sorted.skip(start).take(request.limit).toList();
    final hasMore = start + items.length < sorted.length;
    return MoodHistorySourcePage(
      events: items,
      nextCursor: hasMore && items.isNotEmpty ? items.last.id : null,
    );
  }
}
