import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../domain/counselor_inbox_read_state.dart';

export '../domain/counselor_inbox_read_state.dart';

/// Shared single-source-of-truth controller for counselor inbox unread counts,
/// per-thread read status, atomic reply writes, and UID-scoped read receipts.
class CounselorInboxUnreadController extends ChangeNotifier {
  CounselorInboxUnreadController({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    bool autoBind = true,
  }) : _firestore =
           firestore ??
           (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null),
       _auth = auth ?? (Firebase.apps.isNotEmpty ? FirebaseAuth.instance : null) {
    if (autoBind) {
      bind();
    }
  }

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _threadsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _receiptsSub;

  bool _bound = false;
  bool _disposed = false;
  int _authEpoch = 0;
  int _writeSeq = 0;
  String? _activeUid;

  bool _threadsReady = false;
  bool _receiptsReady = false;
  Object? _threadsError;
  Object? _receiptsError;

  final Map<String, Map<String, dynamic>> _threadDocs = {};
  final Map<String, Timestamp?> _receiptReadAt = {};
  final Map<String, bool> _receiptExists = {};
  final Map<String, bool> _receiptPendingWrites = {};
  final Map<String, Timestamp> _lastConfirmedReadAtByStudent = {};
  final Map<String, Timestamp> _committedAwaitingReceiptByStudent = {};
  final Map<String, Timestamp> _pendingWatermarkByStudent = {};
  final Map<String, Map<int, Timestamp?>> _inFlightWatermarksByStudent = {};
  final Map<String, Timestamp?> _queuedFollowUpByStudent = {};

  final Map<String, CounselorThreadReadState> _statesByStudent = {};
  List<CounselorThreadReadState> _sortedStates = const [];

  bool _hasInFlightWrite(String studentId) =>
      _inFlightWatermarksByStudent[studentId]?.isNotEmpty ?? false;

  void _recomputePendingWatermark(String studentId) {
    Timestamp? best = _committedAwaitingReceiptByStudent[studentId];
    final inFlight = _inFlightWatermarksByStudent[studentId];
    if (inFlight != null) {
      for (final wm in inFlight.values) {
        best = maxTimestamp(best, wm);
      }
    }
    if (best == null) {
      _pendingWatermarkByStudent.remove(studentId);
    } else {
      _pendingWatermarkByStudent[studentId] = best;
    }
  }

  void _removeInFlightToken(String studentId, int token) {
    final active = _inFlightWatermarksByStudent[studentId];
    active?.remove(token);
    if (active != null && active.isEmpty) {
      _inFlightWatermarksByStudent.remove(studentId);
    }
    _recomputePendingWatermark(studentId);
  }

  void _recordCommittedWatermark(String studentId, Timestamp? watermark) {
    if (watermark == null) return;
    final nonPendingReceiptReadAt = (_receiptPendingWrites[studentId] ?? false)
        ? null
        : _receiptReadAt[studentId];
    final confirmed = maxTimestamp(
      nonPendingReceiptReadAt,
      _lastConfirmedReadAtByStudent[studentId],
    );
    if (confirmed == null || confirmed.compareTo(watermark) < 0) {
      final merged = maxTimestamp(
        _committedAwaitingReceiptByStudent[studentId],
        watermark,
      );
      if (merged != null) {
        _committedAwaitingReceiptByStudent[studentId] = merged;
      }
    }
    _recomputePendingWatermark(studentId);
  }

  String? get activeUid => _activeUid;

  bool get hasError => _threadsError != null || _receiptsError != null;

  Object? get error => _threadsError ?? _receiptsError;

  bool get isReady =>
      _activeUid != null && !hasError && _threadsReady && _receiptsReady;

  bool get isLoading =>
      _activeUid != null && !hasError && (!_threadsReady || !_receiptsReady);

  List<CounselorThreadReadState> get threads => _sortedStates;

  List<CounselorThreadReadState> threadsForCollege(String? collegeId) {
    if (collegeId == null || collegeId.isEmpty || collegeId == 'all') {
      return _sortedStates;
    }
    return _sortedStates
        .where((thread) => thread.collegeId == collegeId)
        .toList(growable: false);
  }

  CounselorThreadReadState? stateFor(String studentId) =>
      _statesByStudent[studentId];

  int unreadCount({String? collegeId}) {
    if (!isReady) return 0;
    return countUnreadCounselorThreads(_sortedStates, collegeId: collegeId);
  }

  bool isThreadUnread(String studentId) =>
      _statesByStudent[studentId]?.isUnread ?? false;

  bool needsMarkRead(
    String studentId, {
    Timestamp? observedStudentMessageAt,
  }) {
    if (!isReady) return false;
    final state = _statesByStudent[studentId];
    final targetStudentMsgAt = maxTimestamp(
      state?.lastStudentMessageAt,
      observedStudentMessageAt,
    );
    if (targetStudentMsgAt == null) return false;

    final effectiveConfirmed = maxTimestamp(
      state?.serverReadAt,
      _lastConfirmedReadAtByStudent[studentId],
    );
    if (effectiveConfirmed != null &&
        targetStudentMsgAt.compareTo(effectiveConfirmed) <= 0) {
      return false;
    }

    final pendingWatermark = _pendingWatermarkByStudent[studentId];
    final pendingActive =
        _hasInFlightWrite(studentId) ||
        (_receiptPendingWrites[studentId] ?? false) ||
        _committedAwaitingReceiptByStudent.containsKey(studentId);
    if (pendingActive &&
        pendingWatermark != null &&
        targetStudentMsgAt.compareTo(pendingWatermark) <= 0) {
      return false;
    }

    return true;
  }

  void bind() {
    if (_bound || _disposed) return;
    _bound = true;
    final auth = _auth;
    if (auth == null) return;
    _handleAuthChanged(auth.currentUser, notify: false);
    _authSub = auth.authStateChanges().listen(
      (user) => _handleAuthChanged(user, notify: true),
    );
  }

  void syncAuthUser() {
    if (_disposed || _auth == null) return;
    _handleAuthChanged(_auth.currentUser, notify: true);
  }

  void _handleAuthChanged(User? user, {required bool notify}) {
    if (_disposed) return;
    final nextUid = user?.uid;
    if (nextUid == _activeUid &&
        (_threadsSub != null || _receiptsSub != null || nextUid == null)) {
      return;
    }

    _authEpoch++;
    unawaited(_threadsSub?.cancel());
    unawaited(_receiptsSub?.cancel());
    _threadsSub = null;
    _receiptsSub = null;

    _activeUid = nextUid;
    _threadsReady = false;
    _receiptsReady = false;
    _threadsError = null;
    _receiptsError = null;
    _threadDocs.clear();
    _receiptReadAt.clear();
    _receiptExists.clear();
    _receiptPendingWrites.clear();
    _lastConfirmedReadAtByStudent.clear();
    _committedAwaitingReceiptByStudent.clear();
    _pendingWatermarkByStudent.clear();
    _inFlightWatermarksByStudent.clear();
    _queuedFollowUpByStudent.clear();
    _statesByStudent.clear();
    _sortedStates = const [];

    final db = _firestore;
    if (nextUid == null || db == null) {
      if (notify) notifyListeners();
      return;
    }

    if (notify) notifyListeners();

    final epoch = _authEpoch;
    _threadsSub = db
        .collection('counselor_threads')
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (_disposed || epoch != _authEpoch) return;
            _threadsError = null;
            _threadsReady = true;
            _threadDocs
              ..clear()
              ..addEntries(
                snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())),
              );
            _recomputeStates();
            notifyListeners();
          },
          onError: (Object error, StackTrace _) {
            if (_disposed || epoch != _authEpoch) return;
            _threadsError = error;
            _recomputeStates();
            notifyListeners();
          },
        );

    _receiptsSub = db
        .collection('counselor_inbox_reads')
        .doc(nextUid)
        .collection('threads')
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (_disposed || epoch != _authEpoch) return;
            _receiptsError = null;
            _receiptsReady = true;
            _receiptReadAt.clear();
            _receiptExists.clear();
            _receiptPendingWrites.clear();
            for (final doc in snapshot.docs) {
              final data = doc.data();
              final rawReadAt = data['readAt'];
              final readAt = rawReadAt is Timestamp ? rawReadAt : null;
              final pending = doc.metadata.hasPendingWrites;
              _receiptReadAt[doc.id] = readAt;
              _receiptExists[doc.id] = true;
              _receiptPendingWrites[doc.id] = pending;
              if (readAt != null && !pending) {
                final confirmed = maxTimestamp(
                  _lastConfirmedReadAtByStudent[doc.id],
                  readAt,
                );
                if (confirmed != null) {
                  _lastConfirmedReadAtByStudent[doc.id] = confirmed;
                  final committed = _committedAwaitingReceiptByStudent[doc.id];
                  if (committed != null &&
                      confirmed.compareTo(committed) >= 0) {
                    _committedAwaitingReceiptByStudent.remove(doc.id);
                  }
                  _recomputePendingWatermark(doc.id);
                }
              }
            }
            _recomputeStates();
            notifyListeners();
          },
          onError: (Object error, StackTrace _) {
            if (_disposed || epoch != _authEpoch) return;
            _receiptsError = error;
            _recomputeStates();
            notifyListeners();
          },
        );
  }

  void _recomputeStates() {
    _statesByStudent.clear();
    final streamsReady = _activeUid != null && _threadsReady && _receiptsReady;
    final hasAnyError = hasError;

    final list = <CounselorThreadReadState>[];
    for (final entry in _threadDocs.entries) {
      final studentId = entry.key;
      final data = entry.value;
      final lastStudentMessageAt = data['lastStudentMessageAt'] is Timestamp
          ? data['lastStudentMessageAt'] as Timestamp
          : null;
      final lastCounselorMessageAt = data['lastCounselorMessageAt'] is Timestamp
          ? data['lastCounselorMessageAt'] as Timestamp
          : null;
      final updatedAt = data['updatedAt'] is Timestamp
          ? data['updatedAt'] as Timestamp
          : null;
      final serverReadAt = _receiptReadAt[studentId];
      final receiptExists = _receiptExists[studentId] ?? false;
      final receiptPending = _receiptPendingWrites[studentId] ?? false;
      final writeInFlight = _hasInFlightWrite(studentId);
      final awaitingReceiptConfirmation =
          _committedAwaitingReceiptByStudent.containsKey(studentId);

      final status = resolveCounselorReadStatus(
        streamsReady: streamsReady,
        hasError: hasAnyError,
        lastStudentMessageAt: lastStudentMessageAt,
        serverReadAt: serverReadAt,
        lastConfirmedReadAt: _lastConfirmedReadAtByStudent[studentId],
        pendingStudentMessageWatermark: _pendingWatermarkByStudent[studentId],
        receiptExists: receiptExists,
        receiptHasPendingWrites: receiptPending,
        writeInFlight: writeInFlight,
        awaitingReceiptConfirmation: awaitingReceiptConfirmation,
      );

      final state = CounselorThreadReadState(
        studentId: studentId,
        collegeId: data['collegeId'] as String?,
        studentName: data['studentName'] as String?,
        updatedAt: updatedAt,
        lastStudentMessageAt: lastStudentMessageAt,
        lastStudentMessageId: data['lastStudentMessageId'] as String?,
        lastCounselorMessageAt: lastCounselorMessageAt,
        serverReadAt: serverReadAt,
        receiptHasPendingWrites: receiptPending,
        status: status,
      );
      _statesByStudent[studentId] = state;
      list.add(state);
    }

    list.sort(compareCounselorThreadReadStates);
    _sortedStates = List.unmodifiable(list);
  }

  Future<void> markThreadRead({
    required String studentId,
    Timestamp? studentMessageAt,
    String? expectedUid,
  }) async {
    if (_disposed) return;
    final uid = _activeUid;
    final db = _firestore;
    final epoch = _authEpoch;
    if (uid == null || db == null) return;
    if (expectedUid != null && expectedUid != uid) return;

    final watermark = maxTimestamp(
      _statesByStudent[studentId]?.lastStudentMessageAt,
      studentMessageAt,
    );
    if (!needsMarkRead(studentId, observedStudentMessageAt: watermark)) {
      return;
    }

    if (_hasInFlightWrite(studentId)) {
      _queuedFollowUpByStudent[studentId] = maxTimestamp(
        _queuedFollowUpByStudent[studentId],
        watermark,
      );
      return;
    }

    await _executeMarkRead(
      studentId: studentId,
      watermark: watermark,
      uid: uid,
      epoch: epoch,
      db: db,
    );
  }

  Future<void> _executeMarkRead({
    required String studentId,
    required Timestamp? watermark,
    required String uid,
    required int epoch,
    required FirebaseFirestore db,
  }) async {
    final token = ++_writeSeq;
    _inFlightWatermarksByStudent.putIfAbsent(
      studentId,
      () => <int, Timestamp?>{},
    )[token] = watermark;
    _recomputePendingWatermark(studentId);
    _recomputeStates();
    notifyListeners();

    try {
      await db
          .collection('counselor_inbox_reads')
          .doc(uid)
          .collection('threads')
          .doc(studentId)
          .set({'readAt': FieldValue.serverTimestamp()});
      if (!_disposed && epoch == _authEpoch && _activeUid == uid) {
        _recordCommittedWatermark(studentId, watermark);
      }
    } catch (_) {
      if (!_disposed && epoch == _authEpoch && _activeUid == uid) {
        _removeInFlightToken(studentId, token);
        _recomputeStates();
        notifyListeners();
      }
      rethrow;
    } finally {
      if (!_disposed && epoch == _authEpoch && _activeUid == uid) {
        _removeInFlightToken(studentId, token);
        final followUp = _hasInFlightWrite(studentId)
            ? null
            : _queuedFollowUpByStudent.remove(studentId);
        _recomputeStates();
        notifyListeners();
        if (followUp != null &&
            needsMarkRead(studentId, observedStudentMessageAt: followUp)) {
          unawaited(
            markThreadRead(
              studentId: studentId,
              studentMessageAt: followUp,
              expectedUid: uid,
            ).catchError((Object error) {
              debugPrint('COUNSELOR_READ_ERROR: $error');
            }),
          );
        }
      }
    }
  }

  /// Sends a counselor reply and records the counselor's read receipt in a
  /// single atomic 3-write batch so `lastCounselorMessageAt == readAt`.
  Future<void> sendCounselorReply({
    required String studentId,
    required String text,
    String? expectedUid,
  }) async {
    if (_disposed) return;
    final trimmed = text.trim();
    final uid = _activeUid;
    final db = _firestore;
    final epoch = _authEpoch;
    if (uid == null ||
        db == null ||
        trimmed.isEmpty ||
        trimmed.length > 1600) {
      return;
    }
    if (expectedUid != null && expectedUid != uid) return;

    final watermark = _statesByStudent[studentId]?.lastStudentMessageAt;
    final token = ++_writeSeq;
    _inFlightWatermarksByStudent.putIfAbsent(
      studentId,
      () => <int, Timestamp?>{},
    )[token] = watermark;
    _recomputePendingWatermark(studentId);
    _recomputeStates();
    notifyListeners();

    try {
      final thread = db.collection('counselor_threads').doc(studentId);
      final message = thread.collection('messages').doc();
      final receipt = db
          .collection('counselor_inbox_reads')
          .doc(uid)
          .collection('threads')
          .doc(studentId);

      final batch = db.batch();
      batch.update(thread, {
        'updatedAt': FieldValue.serverTimestamp(),
        'lastCounselorMessageAt': FieldValue.serverTimestamp(),
        'lastCounselorMessageId': message.id,
      });
      batch.set(message, {
        'senderId': uid,
        'senderRole': 'counselor',
        'text': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(receipt, {'readAt': FieldValue.serverTimestamp()});
      await batch.commit();
      if (!_disposed &&
          epoch == _authEpoch &&
          _activeUid == uid &&
          (expectedUid == null || _activeUid == expectedUid)) {
        _recordCommittedWatermark(studentId, watermark);
      }
    } catch (_) {
      if (!_disposed && epoch == _authEpoch && _activeUid == uid) {
        _removeInFlightToken(studentId, token);
        _recomputeStates();
        notifyListeners();
      }
      rethrow;
    } finally {
      if (!_disposed &&
          epoch == _authEpoch &&
          _activeUid == uid &&
          (expectedUid == null || _activeUid == expectedUid)) {
        _removeInFlightToken(studentId, token);
        final followUp = _hasInFlightWrite(studentId)
            ? null
            : _queuedFollowUpByStudent.remove(studentId);
        _recomputeStates();
        notifyListeners();
        if (followUp != null &&
            needsMarkRead(studentId, observedStudentMessageAt: followUp)) {
          unawaited(
            markThreadRead(
              studentId: studentId,
              studentMessageAt: followUp,
              expectedUid: uid,
            ).catchError((Object error) {
              debugPrint('COUNSELOR_READ_ERROR: $error');
            }),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_authSub?.cancel());
    unawaited(_threadsSub?.cancel());
    unawaited(_receiptsSub?.cancel());
    super.dispose();
  }
}

class CounselorInboxScope
    extends InheritedNotifier<CounselorInboxUnreadController> {
  const CounselorInboxScope({
    super.key,
    required CounselorInboxUnreadController super.notifier,
    required super.child,
  });

  static CounselorInboxUnreadController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CounselorInboxScope>()
          ?.notifier;

  static CounselorInboxUnreadController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No CounselorInboxScope found in context');
    return controller!;
  }
}

/// A badge counts conversations, not individual messages.
class CounselorInboxUnreadBadge extends StatefulWidget {
  const CounselorInboxUnreadBadge({
    super.key,
    this.firestore,
    this.auth,
    this.controller,
    this.collegeId,
    this.compact = false,
    this.margin,
  });

  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final CounselorInboxUnreadController? controller;
  final String? collegeId;
  final bool compact;
  final EdgeInsetsGeometry? margin;

  @override
  State<CounselorInboxUnreadBadge> createState() =>
      _CounselorInboxUnreadBadgeState();
}

class _CounselorInboxUnreadBadgeState extends State<CounselorInboxUnreadBadge> {
  CounselorInboxUnreadController? _ownedController;

  CounselorInboxUnreadController _resolveController(BuildContext context) {
    final external = widget.controller ?? CounselorInboxScope.maybeOf(context);
    if (external != null) {
      if (_ownedController != null) {
        _ownedController!.dispose();
        _ownedController = null;
      }
      return external;
    }
    return _ownedController ??= CounselorInboxUnreadController(
      firestore: widget.firestore,
      auth: widget.auth,
    );
  }

  @override
  void didUpdateWidget(covariant CounselorInboxUnreadBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.firestore != oldWidget.firestore ||
        widget.auth != oldWidget.auth ||
        widget.controller != oldWidget.controller) {
      _ownedController?.dispose();
      _ownedController = null;
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _resolveController(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final count = controller.unreadCount(collegeId: widget.collegeId);
        if (count < 1) {
          return const SizedBox.shrink();
        }
        final badge = UnreadCountBadge(
          count: count,
          compact: widget.compact,
        );
        if (widget.margin != null) {
          return Padding(padding: widget.margin!, child: badge);
        }
        return badge;
      },
    );
  }
}

bool studentThreadUnread(Map<String, dynamic> data) {
  final last = data['lastCounselorMessageAt'];
  final seen = data['studentReadAt'];
  return last is Timestamp && (seen is! Timestamp || last.compareTo(seen) > 0);
}

class StudentCounselorUnreadBadge extends StatelessWidget {
  const StudentCounselorUnreadBadge({
    super.key,
    this.backgroundColor,
    this.foregroundColor,
  });
  final Color? backgroundColor;
  final Color? foregroundColor;
  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) {
      return const SizedBox.shrink();
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('counselor_threads')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          return const SizedBox.shrink();
        }
        return UnreadCountBadge(
          count: studentThreadUnread(snapshot.data!.data() ?? {}) ? 1 : 0,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        );
      },
    );
  }
}

class UnreadCountBadge extends StatelessWidget {
  const UnreadCountBadge({
    super.key,
    required this.count,
    this.backgroundColor,
    this.foregroundColor,
    this.compact = false,
  });
  final Color? backgroundColor;
  final Color? foregroundColor;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count < 1) return const SizedBox.shrink();
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1)
          : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.red.shade700,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
      ),
      constraints: compact
          ? const BoxConstraints(minWidth: 17, minHeight: 17)
          : const BoxConstraints(minWidth: 19, minHeight: 19),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: foregroundColor ?? Colors.white,
            fontSize: compact ? 9 : 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
