import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../database/firestore_collections.dart';
import '../features/mood/domain/mood_v2_analytics.dart';

/// A bounded, source-aware read request. Limits apply independently to each
/// source, so a combined page contains at most twice [pageSize] events.
class MoodCombinedHistoryRequest {
  const MoodCombinedHistoryRequest({
    required this.userId,
    this.startInclusive,
    this.endExclusive,
    this.pageSize = 50,
    this.cursor,
  }) : assert(pageSize > 0 && pageSize <= 100);

  final String userId;
  final DateTime? startInclusive;
  final DateTime? endExclusive;
  final int pageSize;
  final MoodCombinedHistoryCursor? cursor;

  factory MoodCombinedHistoryRequest.forManilaDateRange({
    required String userId,
    required String startDateKey,
    required String endExclusiveDateKey,
    int pageSize = 50,
    MoodCombinedHistoryCursor? cursor,
  }) {
    final start = MoodManilaCalendar.dateForKey(
      startDateKey,
    ).subtract(const Duration(hours: 8));
    final end = MoodManilaCalendar.dateForKey(
      endExclusiveDateKey,
    ).subtract(const Duration(hours: 8));
    return MoodCombinedHistoryRequest(
      userId: userId,
      startInclusive: start,
      endExclusive: end,
      pageSize: pageSize,
      cursor: cursor,
    );
  }
}

/// Opaque per-source pagination state. A cursor is valid only for the same
/// user and date range that produced it.
class MoodCombinedHistoryCursor {
  const MoodCombinedHistoryCursor(
    this._sourceCursors, {
    this.bufferedEvents = const [],
  });

  final Map<MoodEventSource, Object?> _sourceCursors;
  final List<NormalizedMoodEvent> bufferedEvents;

  Object? forSource(MoodEventSource source) => _sourceCursors[source];

  bool wasFetched(MoodEventSource source) => _sourceCursors.containsKey(source);

  bool get hasMore =>
      bufferedEvents.isNotEmpty ||
      _sourceCursors.values.any((value) => value != null);
}

class MoodCombinedHistoryPage {
  const MoodCombinedHistoryPage({
    required this.window,
    required this.nextCursor,
    required this.failedSources,
  });

  final MoodHistoryWindow window;
  final MoodCombinedHistoryCursor? nextCursor;

  /// A source failure is explicit: callers must not present this as complete
  /// combined history or derive an all-time longest streak from it.
  final Set<MoodEventSource> failedSources;

  bool get hasMore => nextCursor?.hasMore ?? false;
}

class MoodHistorySourceRequest {
  const MoodHistorySourceRequest({
    required this.userId,
    required this.limit,
    this.startInclusive,
    this.endExclusive,
    this.cursor,
  });

  final String userId;
  final int limit;
  final DateTime? startInclusive;
  final DateTime? endExclusive;
  final Object? cursor;
}

class MoodHistorySourcePage {
  const MoodHistorySourcePage({required this.events, this.nextCursor});

  final List<NormalizedMoodEvent> events;
  final Object? nextCursor;
}

abstract class MoodHistorySource {
  MoodEventSource get source;

  Future<MoodHistorySourcePage> fetch(MoodHistorySourceRequest request);
}

abstract class MoodHistoryIdentity {
  String? get currentUserId;
}

class FirebaseMoodHistoryIdentity implements MoodHistoryIdentity {
  FirebaseMoodHistoryIdentity([FirebaseAuth? auth])
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  String? get currentUserId => _auth.currentUser?.uid;
}

/// Read-only compatibility layer. It is intentionally not wired into existing
/// UI consumers; they remain on legacy reads until their separate rollout.
class MoodCombinedHistoryRepository {
  MoodCombinedHistoryRepository({
    FirebaseFirestore? firestore,
    MoodHistoryIdentity? identity,
    MoodHistorySource? legacySource,
    MoodHistorySource? v2Source,
  }) : _identity = identity ?? FirebaseMoodHistoryIdentity(),
       _legacySource =
           legacySource ??
           FirebaseMoodHistorySource(
             firestore: firestore ?? FirebaseFirestore.instance,
             source: MoodEventSource.legacy,
           ),
       _v2Source =
           v2Source ??
           FirebaseMoodHistorySource(
             firestore: firestore ?? FirebaseFirestore.instance,
             source: MoodEventSource.v2,
           );

  final MoodHistoryIdentity _identity;
  final MoodHistorySource _legacySource;
  final MoodHistorySource _v2Source;

  Future<MoodCombinedHistoryPage> fetch(
    MoodCombinedHistoryRequest request,
  ) async {
    _requireCurrentUser(request.userId);
    if (request.startInclusive != null &&
        request.endExclusive != null &&
        !request.startInclusive!.isBefore(request.endExclusive!)) {
      throw ArgumentError.value(
        request.endExclusive,
        'endExclusive',
        'Must be after startInclusive.',
      );
    }

    final sources = <MoodHistorySource>[_legacySource, _v2Source];
    final responses = await Future.wait(
      sources.map((source) async {
        // An explicit null cursor means this source was exhausted on an
        // earlier page. Do not restart it from its newest record.
        if (request.cursor?.wasFetched(source.source) == true &&
            request.cursor?.forSource(source.source) == null) {
          return MapEntry<MoodEventSource, MoodHistorySourcePage?>(
            source.source,
            const MoodHistorySourcePage(events: []),
          );
        }
        try {
          return MapEntry<MoodEventSource, MoodHistorySourcePage?>(
            source.source,
            await source.fetch(
              MoodHistorySourceRequest(
                userId: request.userId,
                limit: request.pageSize,
                startInclusive: request.startInclusive,
                endExclusive: request.endExclusive,
                cursor: request.cursor?.forSource(source.source),
              ),
            ),
          );
        } catch (_) {
          return MapEntry<MoodEventSource, MoodHistorySourcePage?>(
            source.source,
            null,
          );
        }
      }),
    );

    // Auth may have changed while either source was pending. Never hand an
    // earlier account's history to the new session.
    _requireCurrentUser(request.userId);

    final failedSources = <MoodEventSource>{};
    final events = <NormalizedMoodEvent>[...?request.cursor?.bufferedEvents];
    final cursors = <MoodEventSource, Object?>{};
    for (final response in responses) {
      final page = response.value;
      if (page == null) {
        failedSources.add(response.key);
        continue;
      }
      events.addAll(
        page.events.where((event) => event.userId == request.userId),
      );
      cursors[response.key] = page.nextCursor;
    }

    final orderedEvents = _sortAndDeduplicate(events);
    final pageEvents = orderedEvents
        .take(request.pageSize)
        .toList(growable: false);
    final bufferedEvents = orderedEvents
        .skip(request.pageSize)
        .toList(growable: false);
    final hasSourceMore = cursors.values.any((value) => value != null);
    final hasMore = bufferedEvents.isNotEmpty || hasSourceMore;
    final window = MoodHistoryWindow(
      events: pageEvents,
      coverage: failedSources.isEmpty && !hasMore
          ? MoodHistoryCoverage.complete
          : MoodHistoryCoverage.partial,
    );
    final cursor = hasMore
        ? MoodCombinedHistoryCursor(
            Map.unmodifiable(cursors),
            bufferedEvents: List.unmodifiable(bufferedEvents),
          )
        : null;
    return MoodCombinedHistoryPage(
      window: window,
      nextCursor: cursor,
      failedSources: Set.unmodifiable(failedSources),
    );
  }

  void _requireCurrentUser(String userId) {
    final currentUserId = _identity.currentUserId;
    if (currentUserId == null || currentUserId != userId) {
      throw StateError(
        'Mood history is available only to the authenticated owner.',
      );
    }
  }

  List<NormalizedMoodEvent> _sortAndDeduplicate(
    List<NormalizedMoodEvent> events,
  ) {
    final byIdentity = <String, NormalizedMoodEvent>{};
    for (final event in events) {
      byIdentity.putIfAbsent(event.stableIdentity, () => event);
    }
    final result = byIdentity.values.toList(growable: false)
      ..sort((left, right) {
        final timestamp = right.occurredAt.compareTo(left.occurredAt);
        return timestamp != 0
            ? timestamp
            : left.stableIdentity.compareTo(right.stableIdentity);
      });
    return result;
  }
}

/// Firebase implementation for a single history source. It reads only the
/// fields needed by the analytics projection; notes and expression metadata
/// are deliberately omitted from the normalized events.
class FirebaseMoodHistorySource implements MoodHistorySource {
  FirebaseMoodHistorySource({required this.firestore, required this.source});

  final FirebaseFirestore firestore;
  @override
  final MoodEventSource source;

  @override
  Future<MoodHistorySourcePage> fetch(MoodHistorySourceRequest request) async {
    final collection = source == MoodEventSource.legacy
        ? FirestoreCollections.moods
        : FirestoreCollections.moodEntries;
    final timestampField = source == MoodEventSource.legacy
        ? 'createdAt'
        : 'occurredAt';
    Query<Map<String, dynamic>> query = firestore
        .collection(collection)
        .where('userId', isEqualTo: request.userId)
        .orderBy(timestampField, descending: true);
    if (request.startInclusive != null) {
      query = query.where(
        timestampField,
        isGreaterThanOrEqualTo: Timestamp.fromDate(request.startInclusive!),
      );
    }
    if (request.endExclusive != null) {
      query = query.where(
        timestampField,
        isLessThan: Timestamp.fromDate(request.endExclusive!),
      );
    }
    if (request.cursor
        case final DocumentSnapshot<Map<String, dynamic>> cursor) {
      query = query.startAfterDocument(cursor);
    }
    final snapshot = await query.limit(request.limit).get();
    return MoodHistorySourcePage(
      events: snapshot.docs
          .map((document) => _normalize(document, timestampField))
          .whereType<NormalizedMoodEvent>()
          .toList(growable: false),
      nextCursor:
          snapshot.docs.length == request.limit && snapshot.docs.isNotEmpty
          ? snapshot.docs.last
          : null,
    );
  }

  NormalizedMoodEvent? _normalize(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    String timestampField,
  ) {
    final data = document.data();
    final userId = data['userId']?.toString().trim() ?? '';
    final level = data['level'] is num ? (data['level'] as num).toInt() : null;
    final timestamp = _timestamp(data[timestampField]);
    if (userId.isEmpty ||
        level == null ||
        level < 1 ||
        level > 5 ||
        timestamp == null) {
      return null;
    }
    final storedDateKey = data['dateKey']?.toString().trim();
    final dateKey = _validDateKey(storedDateKey)
        ? storedDateKey!
        : MoodManilaCalendar.dateKeyForInstant(timestamp);
    return NormalizedMoodEvent(
      id: document.id,
      userId: userId,
      level: level,
      dateKey: dateKey,
      occurredAt: timestamp,
      source: source,
      label: data['label']?.toString(),
      // Do not project raw notes or expression metadata into analytics.
    );
  }

  DateTime? _timestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  bool _validDateKey(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    try {
      MoodManilaCalendar.dateForKey(value);
      return true;
    } on FormatException {
      return false;
    }
  }
}
