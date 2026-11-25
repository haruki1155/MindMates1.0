// Test doubles for FirebaseFirestore and FirebaseAuth without adding mocking dependencies.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCounselorUser extends Fake implements User {
  FakeCounselorUser(this.uid);

  @override
  final String uid;
}

class FakeCounselorAuth extends Fake implements FirebaseAuth {
  FakeCounselorAuth({String? initialUid}) : _uid = initialUid;

  String? _uid;
  final StreamController<User?> _controller =
      StreamController<User?>.broadcast();

  @override
  User? get currentUser => _uid == null ? null : FakeCounselorUser(_uid!);

  @override
  Stream<User?> authStateChanges() async* {
    yield currentUser;
    yield* _controller.stream;
  }

  void switchUser(String? uid) {
    _uid = uid;
    if (!_controller.isClosed) {
      _controller.add(currentUser);
    }
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

class FakeSnapshotMetadata extends Fake implements SnapshotMetadata {
  FakeSnapshotMetadata({
    this.hasPendingWrites = false,
    this.isFromCache = false,
  });

  @override
  final bool hasPendingWrites;

  @override
  final bool isFromCache;
}

class FakeDocEntry {
  FakeDocEntry(
    Map<String, dynamic> data, {
    this.hasPendingWrites = false,
    this.isFromCache = false,
  }) : data = Map<String, dynamic>.from(data);

  final Map<String, dynamic> data;
  final bool hasPendingWrites;
  final bool isFromCache;

  FakeDocEntry copy() => FakeDocEntry(
    data,
    hasPendingWrites: hasPendingWrites,
    isFromCache: isFromCache,
  );
}

class FakeQueryDocumentSnapshot extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  FakeQueryDocumentSnapshot(this.id, FakeDocEntry? entry)
    : _data = entry == null ? const {} : Map<String, dynamic>.from(entry.data),
      exists = entry != null,
      metadata = entry == null
          ? FakeSnapshotMetadata()
          : FakeSnapshotMetadata(
              hasPendingWrites: entry.hasPendingWrites,
              isFromCache: entry.isFromCache,
            );

  @override
  final String id;

  @override
  final bool exists;

  @override
  final SnapshotMetadata metadata;

  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => Map<String, dynamic>.from(_data);
}

class FakeDocumentSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  FakeDocumentSnapshot(this.id, FakeDocEntry? entry)
    : _data = entry == null ? null : Map<String, dynamic>.from(entry.data),
      exists = entry != null,
      metadata = entry == null
          ? FakeSnapshotMetadata()
          : FakeSnapshotMetadata(
              hasPendingWrites: entry.hasPendingWrites,
              isFromCache: entry.isFromCache,
            );

  @override
  final String id;

  @override
  final bool exists;

  @override
  final SnapshotMetadata metadata;

  final Map<String, dynamic>? _data;

  @override
  Map<String, dynamic>? data() =>
      _data == null ? null : Map<String, dynamic>.from(_data);
}

class FakeQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  FakeQuerySnapshot(this.docs, {SnapshotMetadata? metadata})
    : metadata = metadata ?? FakeSnapshotMetadata();

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  final SnapshotMetadata metadata;
}

class RecordedWrite {
  RecordedWrite({
    required this.type,
    required this.path,
    required this.data,
    this.batchSize = 1,
  });

  final String type;
  final String path;
  final Map<String, dynamic> data;
  final int batchSize;
}

class PendingWriteOperation {
  PendingWriteOperation(this._completer, this._onComplete, this._onFail);

  final Completer<void> _completer;
  final void Function() _onComplete;
  final void Function(Object error) _onFail;

  void complete() {
    if (_completer.isCompleted) return;
    _onComplete();
    _completer.complete();
  }

  void fail(Object error) {
    if (_completer.isCompleted) return;
    _onFail(error);
    _completer.completeError(error);
  }
}

class _CollectionWatch {
  _CollectionWatch(
    this.path, {
    this.orderByField,
    this.descending = false,
    this.limitCount,
    this.limitToLastCount,
    this.startAfterDocId,
    this.startAfterData,
  }) : controller =
           StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();

  final String path;
  final String? orderByField;
  final bool descending;
  final int? limitCount;
  final int? limitToLastCount;
  final String? startAfterDocId;
  final Map<String, dynamic>? startAfterData;
  final StreamController<QuerySnapshot<Map<String, dynamic>>> controller;
}

class _DocWatch {
  _DocWatch(this.path)
    : controller =
          StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();

  final String path;
  final StreamController<DocumentSnapshot<Map<String, dynamic>>> controller;
}

class FakeCounselorFirestore extends Fake implements FirebaseFirestore {
  FakeCounselorFirestore({
    DateTime? initialServerTime,
    this.deferWriteCompletion = false,
    this.simulatePendingServerTimestamp = true,
    this.deferSnapshotNotifications = false,
  }) : _serverClock = initialServerTime ?? DateTime.utc(2026, 11, 22, 10, 0);

  DateTime _serverClock;
  final bool deferWriteCompletion;
  final bool simulatePendingServerTimestamp;
  bool deferSnapshotNotifications;

  bool holdThreadsInitialEmission = false;
  bool holdReceiptsInitialEmission = false;
  bool holdCollegesInitialEmission = false;
  bool holdMessagesInitialEmission = false;
  Object? nextWriteError;
  Object? persistentWriteError;

  /// Errors thrown by `DocumentReference.update` for a path (rules refusal).
  final Map<String, Object> updateErrors = {};

  int _autoId = 0;
  final Map<String, FakeDocEntry> _docs = {};
  final List<RecordedWrite> writeLog = [];
  final List<List<RecordedWrite>> committedBatches = [];
  final List<String> subscribedCollectionPaths = [];
  final List<PendingWriteOperation> pendingWrites = [];
  final List<String> _deferredSnapshotPaths = [];

  int get pendingSnapshotCount => _deferredSnapshotPaths.length;

  void flushPendingSnapshots() {
    if (_deferredSnapshotPaths.isEmpty) return;
    final paths = _deferredSnapshotPaths.toSet().toList();
    _deferredSnapshotPaths.clear();
    for (final path in paths) {
      _notifyPath(path);
    }
  }

  final List<_CollectionWatch> _collectionWatches = [];
  final List<_DocWatch> _docWatches = [];

  Timestamp nextServerTimestamp() {
    _serverClock = _serverClock.add(const Duration(seconds: 1));
    return Timestamp.fromDate(_serverClock);
  }

  void setServerClock(DateTime dt) {
    _serverClock = dt;
  }

  void seedDoc(
    String path,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
    bool isFromCache = false,
  }) {
    _docs[path] = FakeDocEntry(
      data,
      hasPendingWrites: hasPendingWrites,
      isFromCache: isFromCache,
    );
  }

  FakeDocEntry? getEntry(String path) => _docs[path]?.copy();

  void putAndEmit(
    String path,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
    bool isFromCache = false,
  }) {
    _docs[path] = FakeDocEntry(
      data,
      hasPendingWrites: hasPendingWrites,
      isFromCache: isFromCache,
    );
    _notifyPath(path);
  }

  void removeAndEmit(String path) {
    _docs.remove(path);
    _notifyPath(path);
  }

  void emitCollection(String collectionPath) {
    for (final watch in _collectionWatches) {
      if (watch.path == collectionPath && !watch.controller.isClosed) {
        watch.controller.add(_buildQuerySnapshot(watch));
      }
    }
  }

  void emitCollectionError(String collectionPath, Object error) {
    for (final watch in _collectionWatches) {
      if (watch.path == collectionPath && !watch.controller.isClosed) {
        watch.controller.addError(error);
      }
    }
  }

  void emitThreads() => emitCollection('counselor_threads');

  void emitThreadsError(Object error) =>
      emitCollectionError('counselor_threads', error);

  void emitReceipts(String uid) =>
      emitCollection('counselor_inbox_reads/$uid/threads');

  void emitReceiptsError(String uid, Object error) =>
      emitCollectionError('counselor_inbox_reads/$uid/threads', error);

  void emitColleges() => emitCollection('colleges');

  void emitMessages(String studentId) =>
      emitCollection('counselor_threads/$studentId/messages');

  void completeNextPendingWrite() {
    if (pendingWrites.isNotEmpty) {
      pendingWrites.removeAt(0).complete();
    }
  }

  void completeAllPendingWrites() {
    while (pendingWrites.isNotEmpty) {
      pendingWrites.removeAt(0).complete();
    }
  }

  void failNextPendingWrite(Object error) {
    if (pendingWrites.isNotEmpty) {
      pendingWrites.removeAt(0).fail(error);
    }
  }

  Future<void> dispose() async {
    for (final w in _collectionWatches) {
      await w.controller.close();
    }
    for (final w in _docWatches) {
      await w.controller.close();
    }
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _FakeCollectionReference(this, collectionPath);

  @override
  WriteBatch batch() => _FakeWriteBatch(this);

  String _nextDocId() => 'msg_${++_autoId}';

  bool _isImmediateParent(String docPath, String collectionPath) {
    if (!docPath.startsWith('$collectionPath/')) return false;
    final rest = docPath.substring(collectionPath.length + 1);
    return !rest.contains('/');
  }

  QuerySnapshot<Map<String, dynamic>> _buildQuerySnapshot(
    _CollectionWatch watch,
  ) {
    var matching = _docs.entries
        .where((e) => _isImmediateParent(e.key, watch.path))
        .toList();

    if (watch.orderByField != null) {
      final field = watch.orderByField!;
      matching.sort((a, b) {
        final va = a.value.data[field];
        final vb = b.value.data[field];
        final cmp = _compareValues(va, vb);
        if (cmp != 0) {
          return watch.descending ? -cmp : cmp;
        }
        final idCmp = a.key.split('/').last.compareTo(b.key.split('/').last);
        return watch.descending ? -idCmp : idCmp;
      });
    } else {
      matching.sort((a, b) => a.key.compareTo(b.key));
    }

    if (watch.startAfterDocId != null) {
      final idx = matching.indexWhere(
        (e) => e.key.split('/').last == watch.startAfterDocId,
      );
      if (idx >= 0) {
        matching = matching.sublist(idx + 1);
      } else if (watch.orderByField != null && watch.startAfterData != null) {
        final field = watch.orderByField!;
        final anchorVal = watch.startAfterData![field];
        final anchorId = watch.startAfterDocId!;
        matching = matching.where((e) {
          final cmp = _compareValues(e.value.data[field], anchorVal);
          final directed = watch.descending ? -cmp : cmp;
          if (directed != 0) return directed > 0;
          final idCmp = e.key.split('/').last.compareTo(anchorId);
          return (watch.descending ? -idCmp : idCmp) > 0;
        }).toList();
      }
    }

    if (watch.limitCount != null && matching.length > watch.limitCount!) {
      matching = matching.sublist(0, watch.limitCount!);
    } else if (watch.limitToLastCount != null &&
        matching.length > watch.limitToLastCount!) {
      matching = matching.sublist(matching.length - watch.limitToLastCount!);
    }

    final docs = matching
        .map((e) => FakeQueryDocumentSnapshot(e.key.split('/').last, e.value))
        .toList();

    final anyPending = matching.any((e) => e.value.hasPendingWrites);
    final allCached =
        matching.isNotEmpty && matching.every((e) => e.value.isFromCache);
    return FakeQuerySnapshot(
      docs,
      metadata: FakeSnapshotMetadata(
        hasPendingWrites: anyPending,
        isFromCache: allCached,
      ),
    );
  }

  int _compareValues(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    // Match Cloud Firestore ordering: null sorts before non-null values.
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is Timestamp && b is Timestamp) return a.compareTo(b);
    if (a is Comparable && b is Comparable) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _watchCollection(
    String path, {
    String? orderByField,
    bool descending = false,
    int? limitCount,
    int? limitToLastCount,
    String? startAfterDocId,
    Map<String, dynamic>? startAfterData,
  }) {
    subscribedCollectionPaths.add(path);
    final watch = _CollectionWatch(
      path,
      orderByField: orderByField,
      descending: descending,
      limitCount: limitCount,
      limitToLastCount: limitToLastCount,
      startAfterDocId: startAfterDocId,
      startAfterData: startAfterData,
    );
    _collectionWatches.add(watch);

    final hold = switch (path) {
      'counselor_threads' => holdThreadsInitialEmission,
      'colleges' => holdCollegesInitialEmission,
      _ when path.startsWith('counselor_inbox_reads/') =>
        holdReceiptsInitialEmission,
      _ when path.endsWith('/messages') => holdMessagesInitialEmission,
      _ => false,
    };

    return Stream<QuerySnapshot<Map<String, dynamic>>>.multi((multi) {
      if (!hold) {
        multi.add(_buildQuerySnapshot(watch));
      }
      final sub = watch.controller.stream.listen(
        multi.add,
        onError: multi.addError,
      );
      multi.onCancel = sub.cancel;
    });
  }

  QuerySnapshot<Map<String, dynamic>> _getCollectionSnapshot(
    String path, {
    String? orderByField,
    bool descending = false,
    int? limitCount,
    int? limitToLastCount,
    String? startAfterDocId,
    Map<String, dynamic>? startAfterData,
  }) {
    final watch = _CollectionWatch(
      path,
      orderByField: orderByField,
      descending: descending,
      limitCount: limitCount,
      limitToLastCount: limitToLastCount,
      startAfterDocId: startAfterDocId,
      startAfterData: startAfterData,
    );
    return _buildQuerySnapshot(watch);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _watchDocument(String path) {
    final watch = _DocWatch(path);
    _docWatches.add(watch);
    return Stream<DocumentSnapshot<Map<String, dynamic>>>.multi((multi) {
      final id = path.split('/').last;
      multi.add(FakeDocumentSnapshot(id, _docs[path]));
      final sub = watch.controller.stream.listen(
        multi.add,
        onError: multi.addError,
      );
      multi.onCancel = sub.cancel;
    });
  }

  void _notifyPath(String docPath) {
    final id = docPath.split('/').last;
    for (final watch in _docWatches) {
      if (watch.path == docPath && !watch.controller.isClosed) {
        watch.controller.add(FakeDocumentSnapshot(id, _docs[docPath]));
      }
    }
    final lastSlash = docPath.lastIndexOf('/');
    if (lastSlash > 0) {
      final colPath = docPath.substring(0, lastSlash);
      emitCollection(colPath);
    }
  }

  Map<String, dynamic> _resolvePendingData(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      if (value is FieldValue) {
        // cloud_firestore 6.7.1 has no ServerTimestampBehavior.estimate:
        // unresolved FieldValue.serverTimestamp() reads back as null locally.
        out[key] = null;
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  Map<String, dynamic> _resolveServerData(
    Map<String, dynamic> raw,
    Timestamp serverTime,
  ) {
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      if (value is FieldValue) {
        out[key] = serverTime;
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  Future<void> _executeWrites(List<_PendingWriteItem> items) async {
    final batchRecorded = <RecordedWrite>[];
    for (final item in items) {
      final rec = RecordedWrite(
        type: item.isUpdate ? 'update' : 'set',
        path: item.path,
        data: Map<String, dynamic>.from(item.data),
        batchSize: items.length,
      );
      writeLog.add(rec);
      batchRecorded.add(rec);
    }
    if (items.length > 1) {
      committedBatches.add(batchRecorded);
    }

    final previous = <String, FakeDocEntry?>{
      for (final item in items) item.path: _docs[item.path]?.copy(),
    };

    if (simulatePendingServerTimestamp) {
      for (final item in items) {
        final merged = item.isUpdate
            ? <String, dynamic>{
                ...?previous[item.path]?.data,
                ..._resolvePendingData(item.data),
              }
            : _resolvePendingData(item.data);
        _docs[item.path] = FakeDocEntry(merged, hasPendingWrites: true);
      }
      for (final item in items) {
        _notifyPath(item.path);
      }
    }

    void commitToServer() {
      final serverTime = nextServerTimestamp();
      for (final item in items) {
        final resolved = _resolveServerData(item.data, serverTime);
        final baseData = _docs[item.path]?.data ?? previous[item.path]?.data;
        final merged = item.isUpdate
            ? <String, dynamic>{...?baseData, ...resolved}
            : resolved;
        _docs[item.path] = FakeDocEntry(merged, hasPendingWrites: false);
      }
      if (deferSnapshotNotifications) {
        for (final item in items) {
          _deferredSnapshotPaths.add(item.path);
        }
      } else {
        for (final item in items) {
          _notifyPath(item.path);
        }
      }
    }

    void revertOnFailure() {
      for (final entry in previous.entries) {
        if (entry.value == null) {
          _docs.remove(entry.key);
        } else {
          _docs[entry.key] = entry.value!;
        }
      }
      for (final item in items) {
        _notifyPath(item.path);
      }
    }

    final error = persistentWriteError ?? nextWriteError;
    if (error != null) {
      if (persistentWriteError == null) {
        nextWriteError = null;
      }
      if (deferWriteCompletion) {
        final completer = Completer<void>();
        pendingWrites.add(
          PendingWriteOperation(
            completer,
            commitToServer,
            (_) => revertOnFailure(),
          ),
        );
        return completer.future;
      }
      revertOnFailure();
      throw error;
    }

    if (deferWriteCompletion) {
      final completer = Completer<void>();
      pendingWrites.add(
        PendingWriteOperation(
          completer,
          commitToServer,
          (_) => revertOnFailure(),
        ),
      );
      return completer.future;
    }

    commitToServer();
  }
}

class _PendingWriteItem {
  _PendingWriteItem({
    required this.path,
    required this.data,
    required this.isUpdate,
  });

  final String path;
  final Map<String, dynamic> data;
  final bool isUpdate;
}

class _FakeCollectionReference extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _FakeCollectionReference(this.db, this.path);

  final FakeCounselorFirestore db;

  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final docId = path ?? db._nextDocId();
    return _FakeDocumentReference(db, '${this.path}/$docId');
  }

  @override
  Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) => _FakeQuery(
    db,
    path,
    orderByField: field.toString(),
    descending: descending,
  );

  @override
  Query<Map<String, dynamic>> limit(int limit) =>
      _FakeQuery(db, path, limitCount: limit);

  @override
  Query<Map<String, dynamic>> limitToLast(int limit) =>
      _FakeQuery(db, path, limitToLastCount: limit);

  @override
  Query<Map<String, dynamic>> startAfterDocument(
    DocumentSnapshot<Object?> documentSnapshot,
  ) => _FakeQuery(
    db,
    path,
    startAfterDocId: documentSnapshot.id,
    startAfterData: _extractDocData(documentSnapshot),
  );

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => db._getCollectionSnapshot(path);

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => db._watchCollection(path);
}

Map<String, dynamic>? _extractDocData(DocumentSnapshot<Object?> snapshot) {
  final raw = snapshot.data();
  if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
  return null;
}

class _FakeQuery extends Fake implements Query<Map<String, dynamic>> {
  _FakeQuery(
    this.db,
    this.path, {
    this.orderByField,
    this.descending = false,
    this.limitCount,
    this.limitToLastCount,
    this.startAfterDocId,
    this.startAfterData,
  });

  final FakeCounselorFirestore db;
  final String path;
  final String? orderByField;
  final bool descending;
  final int? limitCount;
  final int? limitToLastCount;
  final String? startAfterDocId;
  final Map<String, dynamic>? startAfterData;

  @override
  Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) => _FakeQuery(
    db,
    path,
    orderByField: field.toString(),
    descending: descending,
    limitCount: limitCount,
    limitToLastCount: limitToLastCount,
    startAfterDocId: startAfterDocId,
    startAfterData: startAfterData,
  );

  @override
  Query<Map<String, dynamic>> limit(int limit) => _FakeQuery(
    db,
    path,
    orderByField: orderByField,
    descending: descending,
    limitCount: limit,
    limitToLastCount: null,
    startAfterDocId: startAfterDocId,
    startAfterData: startAfterData,
  );

  @override
  Query<Map<String, dynamic>> limitToLast(int limit) => _FakeQuery(
    db,
    path,
    orderByField: orderByField,
    descending: descending,
    limitCount: null,
    limitToLastCount: limit,
    startAfterDocId: startAfterDocId,
    startAfterData: startAfterData,
  );

  @override
  Query<Map<String, dynamic>> startAfterDocument(
    DocumentSnapshot<Object?> documentSnapshot,
  ) => _FakeQuery(
    db,
    path,
    orderByField: orderByField,
    descending: descending,
    limitCount: limitCount,
    limitToLastCount: limitToLastCount,
    startAfterDocId: documentSnapshot.id,
    startAfterData: _extractDocData(documentSnapshot),
  );

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => db._getCollectionSnapshot(
    path,
    orderByField: orderByField,
    descending: descending,
    limitCount: limitCount,
    limitToLastCount: limitToLastCount,
    startAfterDocId: startAfterDocId,
    startAfterData: startAfterData,
  );

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => db._watchCollection(
    path,
    orderByField: orderByField,
    descending: descending,
    limitCount: limitCount,
    limitToLastCount: limitToLastCount,
    startAfterDocId: startAfterDocId,
    startAfterData: startAfterData,
  );
}

class _FakeDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _FakeDocumentReference(this.db, this.path);

  final FakeCounselorFirestore db;

  @override
  final String path;

  @override
  String get id => path.split('/').last;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _FakeCollectionReference(db, '$path/$collectionPath');

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      db._executeWrites([
        _PendingWriteItem(path: path, data: data, isUpdate: false),
      ]);

  /// Only the best-effort counselorReadAt stamp uses this: applied at once,
  /// outside the deferred write queue and write log the badge tests drive.
  @override
  Future<void> update(Map<Object, Object?> data) async {
    final error = db.updateErrors[path];
    if (error != null) throw error;
    final resolved = db._resolveServerData(
      data.map((k, v) => MapEntry(k.toString(), v)),
      db.nextServerTimestamp(),
    );
    db.putAndEmit(path, {...?db.getEntry(path)?.data, ...resolved});
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => FakeDocumentSnapshot(id, db.getEntry(path));

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => db._watchDocument(path);
}

class _FakeWriteBatch extends Fake implements WriteBatch {
  _FakeWriteBatch(this.db);

  final FakeCounselorFirestore db;
  final List<_PendingWriteItem> _items = [];

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    _items.add(
      _PendingWriteItem(
        path: document.path,
        data: Map<String, dynamic>.from(data as Map),
        isUpdate: false,
      ),
    );
  }

  @override
  void update<T>(DocumentReference<T> document, T data) {
    _items.add(
      _PendingWriteItem(
        path: document.path,
        data: Map<Object?, Object?>.from(
          data as Map,
        ).map((k, v) => MapEntry(k.toString(), v)),
        isUpdate: true,
      ),
    );
  }

  @override
  Future<void> commit() => db._executeWrites(_items);
}
