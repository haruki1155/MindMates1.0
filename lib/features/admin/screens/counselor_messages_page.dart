import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../services/firebase/firebase_error_message.dart';
import '../../counseling/widgets/counselor_unread_badges.dart';
import '../domain/counselor_message_presentation.dart';
import '../theme/admin_theme.dart';
import '../widgets/counselor_thread_timeline.dart';

/// Approved counselor-only inbox. AI history is never merged into this thread.
/// Human-readable label only. Never use the Firestore student UID as a label.
String counselorConversationStudentLabel(String? name) {
  final displayName = name?.trim() ?? '';
  return displayName.isEmpty ? 'Student (name unavailable)' : displayName;
}

class CounselorMessagesPage extends StatefulWidget {
  const CounselorMessagesPage({
    super.key,
    this.embedded = false,
    this.firestore,
    this.auth,
    this.unreadController,
    this.messagePageSize = kCounselorMessagesPageSize,
    this.now,
  });

  /// Hide the standalone page heading when the inbox is inside Inquiries.
  final bool embedded;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final CounselorInboxUnreadController? unreadController;
  final int messagePageSize;
  final DateTime Function()? now;

  @override
  State<CounselorMessagesPage> createState() => _CounselorMessagesPageState();
}

class _CounselorMessagesPageState extends State<CounselorMessagesPage> {
  String? selectedUser;
  String selectedCollege = 'all';
  final messageController = TextEditingController();
  bool sending = false;

  CounselorInboxUnreadController? _ownedController;
  CounselorInboxUnreadController? _activeController;
  String? _lastObservedUid;
  int _sendSeq = 0;
  int _localSeq = 0;

  String? _failedAutoMarkUid;
  final Map<String, Timestamp?> _failedAutoMarkWatermarkByStudent = {};
  String? _pendingPostFrameMarkKey;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _collegesStream;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;
  String? _messagesStreamKey;
  late int _messagePageLimit;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = const [];
  bool _messagesLoading = false;
  bool _messagesError = false;
  bool _loadingOlder = false;
  bool _hasMoreOlder = false;

  final Map<String, List<LocalCounselorOutgoingMessage>> _outgoingByThreadKey =
      {};

  FirebaseFirestore? get _db =>
      widget.firestore ??
      (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);

  @override
  void initState() {
    super.initState();
    _messagePageLimit = widget.messagePageSize;
    _collegesStream = _db?.collection('colleges').snapshots();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachController();
  }

  @override
  void didUpdateWidget(covariant CounselorMessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messagePageSize != oldWidget.messagePageSize) {
      _messagePageLimit = widget.messagePageSize;
    }
    if (widget.firestore != oldWidget.firestore) {
      _collegesStream = _db?.collection('colleges').snapshots();
      _clearMessagesSubscription();
    }
    if (widget.firestore != oldWidget.firestore ||
        widget.auth != oldWidget.auth ||
        widget.unreadController != oldWidget.unreadController) {
      _attachController(forceRebuildOwned: true);
    }
  }

  void _attachController({bool forceRebuildOwned = false}) {
    final scoped = CounselorInboxScope.maybeOf(context);
    final external = widget.unreadController ?? scoped;
    CounselorInboxUnreadController next;
    if (external != null) {
      if (_ownedController != null) {
        _ownedController!.dispose();
        _ownedController = null;
      }
      next = external;
    } else {
      if (forceRebuildOwned && _ownedController != null) {
        if (_activeController == _ownedController) {
          _activeController!.removeListener(_onControllerChanged);
          _activeController = null;
        }
        _ownedController!.dispose();
        _ownedController = null;
      }
      next = _ownedController ??= CounselorInboxUnreadController(
        firestore: widget.firestore,
        auth: widget.auth,
      );
    }

    if (_activeController == next) return;
    _activeController?.removeListener(_onControllerChanged);
    _activeController = next;
    _lastObservedUid = next.activeUid;
    _ensureMessagesSubscription(_lastObservedUid, selectedUser);
    next.addListener(_onControllerChanged);
  }

  void _clearMessagesSubscription() {
    _messagesSub?.cancel();
    _messagesSub = null;
    _messagesStreamKey = null;
    _docs = const [];
    _messagesLoading = false;
    _messagesError = false;
    _loadingOlder = false;
    _hasMoreOlder = false;
    _messagePageLimit = widget.messagePageSize;
  }

  void _onControllerChanged() {
    final controller = _activeController;
    if (!mounted || controller == null) return;
    final currentUid = controller.activeUid;
    if (currentUid != _lastObservedUid) {
      ++_sendSeq;
      _failedAutoMarkUid = currentUid;
      _failedAutoMarkWatermarkByStudent.clear();
      _pendingPostFrameMarkKey = null;
      _outgoingByThreadKey.clear();
      _clearMessagesSubscription();
      setState(() {
        _lastObservedUid = currentUid;
        selectedUser = null;
        selectedCollege = 'all';
        sending = false;
        messageController.clear();
      });
      return;
    }
    final openStudent = selectedUser;
    if (currentUid != null && openStudent != null) {
      final observedAt = controller.stateFor(openStudent)?.lastStudentMessageAt;
      if (!_isAutoMarkSuppressed(
            studentId: openStudent,
            uid: currentUid,
            observedAt: observedAt,
          ) &&
          controller.needsMarkRead(
            openStudent,
            observedStudentMessageAt: observedAt,
          )) {
        _scheduleMarkReadIfOpen(
          controller: controller,
          studentId: openStudent,
          expectedUid: currentUid,
          observedAt: observedAt,
        );
      }
    }
  }

  bool _isAutoMarkSuppressed({
    required String studentId,
    required String uid,
    required Timestamp? observedAt,
  }) {
    if (_failedAutoMarkUid != uid) return false;
    final failedAt = _failedAutoMarkWatermarkByStudent[studentId];
    if (failedAt == null || observedAt == null) return false;
    if (observedAt.compareTo(failedAt) > 0) {
      _failedAutoMarkWatermarkByStudent.remove(studentId);
      return false;
    }
    return true;
  }

  void _triggerMarkRead({
    required CounselorInboxUnreadController controller,
    required String studentId,
    required String expectedUid,
    required Timestamp? observedAt,
  }) {
    final effectiveObservedAt = maxTimestamp(
      observedAt,
      controller.stateFor(studentId)?.lastStudentMessageAt,
    );
    if (effectiveObservedAt == null) return;
    if (!controller.needsMarkRead(
      studentId,
      observedStudentMessageAt: effectiveObservedAt,
    )) {
      return;
    }
    unawaited(
      controller
          .markThreadRead(
            studentId: studentId,
            studentMessageAt: effectiveObservedAt,
            expectedUid: expectedUid,
          )
          .then((_) {
            if (!mounted || _failedAutoMarkUid != expectedUid) return;
            final recorded = _failedAutoMarkWatermarkByStudent[studentId];
            if (recorded != null &&
                effectiveObservedAt.compareTo(recorded) >= 0) {
              _failedAutoMarkWatermarkByStudent.remove(studentId);
            }
          })
          .catchError((Object error) {
            if (mounted && controller.activeUid == expectedUid) {
              if (_failedAutoMarkUid != expectedUid) {
                _failedAutoMarkUid = expectedUid;
                _failedAutoMarkWatermarkByStudent.clear();
              }
              _failedAutoMarkWatermarkByStudent[studentId] = maxTimestamp(
                _failedAutoMarkWatermarkByStudent[studentId],
                effectiveObservedAt,
              );
            }
            debugPrint('COUNSELOR_READ_ERROR: $error');
          }),
    );
  }

  void _ensureMessagesSubscription(
    String? uid,
    String? studentId, {
    bool resetLimit = false,
  }) {
    final db = _db;
    if (uid == null || studentId == null || db == null) {
      _clearMessagesSubscription();
      return;
    }
    if (resetLimit) {
      _messagePageLimit = widget.messagePageSize;
      _docs = const [];
      _loadingOlder = false;
      _hasMoreOlder = false;
    }
    final key = '$uid::$studentId::$_messagePageLimit';
    if (_messagesStreamKey == key && _messagesSub != null) return;

    _messagesSub?.cancel();
    _messagesStreamKey = key;
    if (_docs.isEmpty) {
      _messagesLoading = true;
    }
    _messagesError = false;

    final stream = db
        .collection('counselor_threads')
        .doc(studentId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(_messagePageLimit)
        .snapshots(includeMetadataChanges: true);

    _messagesSub = stream.listen(
      (snapshot) {
        if (!mounted || _messagesStreamKey != key) return;
        final controller = _activeController;
        final docs = snapshot.docs;
        final threadKey = '$uid::$studentId';
        final localItems = _outgoingByThreadKey[threadKey];
        if (localItems != null && localItems.isNotEmpty) {
          final serverModels = docs
              .map(
                (doc) => counselorTimelineMessageFromMap(
                  id: doc.id,
                  data: doc.data(),
                  hasPendingWrites: doc.metadata.hasPendingWrites,
                ),
              )
              .toList();
          final resolved = resolvedLocalOutgoingIds(
            serverMessages: serverModels,
            localOutgoing: localItems,
          );
          if (resolved.isNotEmpty) {
            localItems.removeWhere((item) => resolved.contains(item.localId));
            if (localItems.isEmpty) {
              _outgoingByThreadKey.remove(threadKey);
            }
          }
        }

        if (controller != null &&
            selectedUser == studentId &&
            controller.activeUid == uid) {
          var hasStudentMessages = false;
          Timestamp? maxMessageStudentAt;
          for (final doc in docs) {
            final data = doc.data();
            if (data['senderRole'] == 'user') {
              hasStudentMessages = true;
              final createdAt = data['createdAt'];
              if (createdAt is Timestamp) {
                maxMessageStudentAt = maxTimestamp(
                  maxMessageStudentAt,
                  createdAt,
                );
              }
            }
          }
          if (hasStudentMessages) {
            final observedAt = maxTimestamp(
              maxMessageStudentAt,
              controller.stateFor(studentId)?.lastStudentMessageAt,
            );
            if (!_isAutoMarkSuppressed(
                  studentId: studentId,
                  uid: uid,
                  observedAt: observedAt,
                ) &&
                controller.needsMarkRead(
                  studentId,
                  observedStudentMessageAt: observedAt,
                )) {
              _scheduleMarkReadIfOpen(
                controller: controller,
                studentId: studentId,
                expectedUid: uid,
                observedAt: observedAt,
              );
            }
          }
        }

        setState(() {
          _docs = docs;
          _messagesLoading = false;
          _messagesError = false;
          _loadingOlder = false;
          _hasMoreOlder = docs.length >= _messagePageLimit;
        });
      },
      onError: (_) {
        if (!mounted || _messagesStreamKey != key) return;
        setState(() {
          _messagesLoading = false;
          _loadingOlder = false;
          _messagesError = true;
        });
      },
    );
  }

  void _loadOlderMessages() {
    final uid = _activeController?.activeUid;
    final studentId = selectedUser;
    if (uid == null || studentId == null || _loadingOlder || !_hasMoreOlder) {
      return;
    }
    setState(() {
      _loadingOlder = true;
      _messagePageLimit += widget.messagePageSize;
      _ensureMessagesSubscription(uid, studentId);
    });
  }

  void _scheduleMarkReadIfOpen({
    required CounselorInboxUnreadController controller,
    required String studentId,
    required String expectedUid,
    required Timestamp? observedAt,
  }) {
    final effectiveObservedAt = maxTimestamp(
      observedAt,
      controller.stateFor(studentId)?.lastStudentMessageAt,
    );
    if (effectiveObservedAt == null) return;
    if (_isAutoMarkSuppressed(
      studentId: studentId,
      uid: expectedUid,
      observedAt: effectiveObservedAt,
    )) {
      return;
    }
    final key =
        '$expectedUid::$studentId::${effectiveObservedAt.seconds}:${effectiveObservedAt.nanoseconds}';
    if (_pendingPostFrameMarkKey == key) return;
    _pendingPostFrameMarkKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pendingPostFrameMarkKey == key) {
        _pendingPostFrameMarkKey = null;
      }
      if (!mounted ||
          selectedUser != studentId ||
          controller.activeUid != expectedUid) {
        return;
      }
      final latestObservedAt = maxTimestamp(
        effectiveObservedAt,
        controller.stateFor(studentId)?.lastStudentMessageAt,
      );
      if (_isAutoMarkSuppressed(
        studentId: studentId,
        uid: expectedUid,
        observedAt: latestObservedAt,
      )) {
        return;
      }
      _triggerMarkRead(
        controller: controller,
        studentId: studentId,
        expectedUid: expectedUid,
        observedAt: latestObservedAt,
      );
    });
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _activeController?.removeListener(_onControllerChanged);
    _ownedController?.dispose();
    messageController.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final controller = _activeController;
    final uid = controller?.activeUid;
    final userId = selectedUser;
    final text = messageController.text.trim();
    if (controller == null ||
        uid == null ||
        userId == null ||
        text.isEmpty ||
        text.length > 1600 ||
        sending) {
      return;
    }
    await _dispatchOutgoingSend(
      controller: controller,
      uid: uid,
      studentId: userId,
      text: text,
      clearComposerOnSuccess: true,
    );
  }

  Future<void> _retryFailedMessage(String localId) async {
    final controller = _activeController;
    final uid = controller?.activeUid;
    final studentId = selectedUser;
    if (controller == null || uid == null || studentId == null || sending) {
      return;
    }
    final threadKey = '$uid::$studentId';
    final list = _outgoingByThreadKey[threadKey];
    if (list == null) return;
    final index = list.indexWhere((m) => m.localId == localId);
    if (index < 0) return;
    final item = list[index];
    await _dispatchOutgoingSend(
      controller: controller,
      uid: uid,
      studentId: studentId,
      text: item.text,
      existingLocalId: localId,
      clearComposerOnSuccess: messageController.text.trim() == item.text,
    );
  }

  void _dismissFailedMessage(String localId) {
    final uid = _activeController?.activeUid;
    final studentId = selectedUser;
    if (uid == null || studentId == null) return;
    final threadKey = '$uid::$studentId';
    final list = _outgoingByThreadKey[threadKey];
    if (list == null) return;
    setState(() {
      list.removeWhere((m) => m.localId == localId);
      if (list.isEmpty) {
        _outgoingByThreadKey.remove(threadKey);
      }
    });
  }

  Future<void> _dispatchOutgoingSend({
    required CounselorInboxUnreadController controller,
    required String uid,
    required String studentId,
    required String text,
    String? existingLocalId,
    required bool clearComposerOnSuccess,
  }) async {
    final sendToken = ++_sendSeq;
    final threadKey = '$uid::$studentId';
    final knownIds = _docs.map((d) => d.id).toSet();
    final nowTime = widget.now?.call() ?? DateTime.now();
    final localId = existingLocalId ?? 'out_${++_localSeq}';

    setState(() {
      sending = true;
      final list = _outgoingByThreadKey.putIfAbsent(threadKey, () => []);
      final existingIndex = list.indexWhere((m) => m.localId == localId);
      final updated = LocalCounselorOutgoingMessage(
        localId: localId,
        uid: uid,
        studentId: studentId,
        text: text,
        queuedAt: nowTime,
        knownServerIdsAtSend: knownIds,
        status: CounselorOutgoingStatus.sending,
      );
      if (existingIndex >= 0) {
        list[existingIndex] = updated;
      } else {
        list.add(updated);
      }
    });

    try {
      await controller.sendCounselorReply(
        studentId: studentId,
        text: text,
        expectedUid: uid,
      );
      if (mounted && _sendSeq == sendToken && controller.activeUid == uid) {
        if (_failedAutoMarkUid == uid) {
          _failedAutoMarkWatermarkByStudent.remove(studentId);
        }
        if (clearComposerOnSuccess && selectedUser == studentId) {
          messageController.clear();
        }
      }
    } catch (_) {
      if (mounted && _sendSeq == sendToken && controller.activeUid == uid) {
        final list = _outgoingByThreadKey[threadKey];
        if (list != null) {
          final index = list.indexWhere((m) => m.localId == localId);
          if (index >= 0) {
            list[index] = list[index].copyWith(
              status: CounselorOutgoingStatus.failed,
            );
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to send message. Check permissions or connection.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && _sendSeq == sendToken && controller.activeUid == uid) {
        setState(() => sending = false);
      }
    }
  }

  void _selectThread(
    CounselorInboxUnreadController controller,
    CounselorThreadReadState threadState,
  ) {
    final capturedUid = controller.activeUid;
    final isSelectionChange = selectedUser != threadState.studentId;
    if (isSelectionChange) {
      _failedAutoMarkWatermarkByStudent.clear();
      _pendingPostFrameMarkKey = null;
    } else if (_failedAutoMarkUid == capturedUid) {
      _failedAutoMarkWatermarkByStudent.remove(threadState.studentId);
    }
    setState(() {
      selectedUser = threadState.studentId;
      _ensureMessagesSubscription(
        capturedUid,
        threadState.studentId,
        resetLimit: isSelectionChange,
      );
    });
    if (capturedUid != null) {
      _triggerMarkRead(
        controller: controller,
        studentId: threadState.studentId,
        expectedUid: capturedUid,
        observedAt: threadState.lastStudentMessageAt,
      );
    }
  }

  void _closeSelectedThread() {
    setState(() {
      selectedUser = null;
      _pendingPostFrameMarkKey = null;
      _clearMessagesSubscription();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _activeController!;
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final outerPadding = widget.embedded
            ? 0.0
            : (outerConstraints.maxWidth < 600
                  ? AdminSpacing.md
                  : AdminSpacing.lg);
        return Padding(
          padding: EdgeInsets.all(outerPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.embedded) ...[
                const Text(
                  'Counselor Messages',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AdminColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Direct student conversations. MindAid AI history is separate.',
                  style: TextStyle(color: AdminColors.muted),
                ),
                const SizedBox(height: AdminSpacing.md),
              ],
              if (_collegesStream != null)
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _collegesStream,
                    builder: (context, collegeSnapshot) {
                      Widget header;
                      String? effectiveCollege = selectedCollege == 'all'
                          ? null
                          : selectedCollege;
                      final collegeCodeById = <String, String>{};
                      final collegeLabelById = <String, String>{};

                      if (collegeSnapshot.hasError) {
                        header = const Text(
                          'Unable to load academic structure.',
                        );
                        effectiveCollege = null;
                      } else if (!collegeSnapshot.hasData) {
                        header = const LinearProgressIndicator();
                      } else {
                        for (final doc in collegeSnapshot.data!.docs) {
                          final data = doc.data();
                          final code = (data['code'] ?? '').toString().trim();
                          final name = (data['name'] ?? '').toString().trim();
                          if (code.isNotEmpty && name.isNotEmpty) {
                            collegeCodeById[doc.id] = code;
                            collegeLabelById[doc.id] = '$code — $name';
                          } else if (code.isNotEmpty) {
                            collegeCodeById[doc.id] = code;
                            collegeLabelById[doc.id] = code;
                          } else if (name.isNotEmpty) {
                            collegeCodeById[doc.id] = name;
                            collegeLabelById[doc.id] = name;
                          }
                        }

                        final colleges =
                            collegeSnapshot.data!.docs
                                .where((doc) => doc.data()['active'] != false)
                                .toList()
                              ..sort(
                                (a, b) => (a.data()['name'] ?? '')
                                    .toString()
                                    .compareTo(
                                      (b.data()['name'] ?? '').toString(),
                                    ),
                              );
                        final values = <String>{
                          'all',
                          ...colleges.map((e) => e.id),
                        };
                        final current = values.contains(selectedCollege)
                            ? selectedCollege
                            : 'all';
                        effectiveCollege = current == 'all' ? null : current;
                        header = DropdownButtonFormField<String>(
                          key: ValueKey(current),
                          isExpanded: true,
                          initialValue: current,
                          decoration: const InputDecoration(
                            labelText: 'College / Academic Structure',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text(
                                'All Colleges',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            for (final college in colleges)
                              DropdownMenuItem(
                                value: college.id,
                                child: Text(
                                  '${college.data()['code'] ?? ''} — ${college.data()['name'] ?? 'College not available'}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(() {
                            selectedCollege = value ?? 'all';
                            selectedUser = null;
                            _failedAutoMarkWatermarkByStudent.clear();
                            _pendingPostFrameMarkKey = null;
                            _clearMessagesSubscription();
                          }),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          const SizedBox(height: AdminSpacing.md),
                          Expanded(
                            child: _buildInboxBody(
                              controller: controller,
                              collegeFilter: effectiveCollege,
                              collegeCodeById: collegeCodeById,
                              collegeLabelById: collegeLabelById,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                )
              else
                Expanded(
                  child: _buildInboxBody(
                    controller: controller,
                    collegeFilter: selectedCollege == 'all'
                        ? null
                        : selectedCollege,
                    collegeCodeById: const {},
                    collegeLabelById: const {},
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInboxBody({
    required CounselorInboxUnreadController controller,
    required String? collegeFilter,
    required Map<String, String> collegeCodeById,
    required Map<String, String> collegeLabelById,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final singlePane = constraints.maxWidth < 640;
        final hasOpenThread =
            selectedUser != null &&
            controller.activeUid != null &&
            _messagesSub != null;

        if (singlePane) {
          if (hasOpenThread) {
            return _buildThreadPane(
              controller: controller,
              collegeLabelById: collegeLabelById,
              singlePane: true,
            );
          }
          return _buildConversationListPanel(
            controller: controller,
            collegeFilter: collegeFilter,
            collegeCodeById: collegeCodeById,
          );
        }

        final listWidth = constraints.maxWidth >= 1000 ? 310.0 : 256.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: listWidth,
              child: _buildConversationListPanel(
                controller: controller,
                collegeFilter: collegeFilter,
                collegeCodeById: collegeCodeById,
              ),
            ),
            const SizedBox(width: AdminSpacing.md),
            Expanded(
              child: _buildThreadPane(
                controller: controller,
                collegeLabelById: collegeLabelById,
                singlePane: false,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConversationListPanel({
    required CounselorInboxUnreadController controller,
    required String? collegeFilter,
    required Map<String, String> collegeCodeById,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final activeUid = controller.activeUid;
          final threads = activeUid == null
              ? const <CounselorThreadReadState>[]
              : controller.threadsForCollege(collegeFilter);
          final unreadTotal = threads.where((t) => t.isUnread).length;
          final now = widget.now?.call() ?? DateTime.now();
          final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AdminColors.border)),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Conversations',
                      style: TextStyle(
                        color: AdminColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (activeUid != null &&
                        !controller.isLoading &&
                        !controller.hasError &&
                        threads.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${threads.length} total',
                            style: const TextStyle(
                              color: AdminColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (unreadTotal > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AdminColors.accentSoft,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: AdminColors.accentStrong.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                              child: Text(
                                '$unreadTotal unread',
                                style: const TextStyle(
                                  color: AdminColors.ink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Expanded(
                child: () {
                  if (activeUid == null) {
                    return const Center(child: Text('No messages'));
                  }
                  if (controller.hasError) {
                    final error = controller.error;
                    final message = error == null
                        ? 'Unable to load inbox.'
                        : FirebaseErrorMessage.describe(
                            error,
                            fallback: 'Unable to load inbox.',
                          );
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AdminSpacing.md),
                        child: SelectableText(
                          message,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (controller.isLoading) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            'Loading conversations…',
                            style: TextStyle(color: AdminColors.muted),
                          ),
                        ],
                      ),
                    );
                  }
                  if (threads.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AdminSpacing.md),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 32,
                              color: AdminColors.muted,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'No messages',
                              style: TextStyle(
                                color: AdminColors.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Student conversations will appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AdminColors.muted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: threads.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final threadState = threads[index];
                      final collegeCode = threadState.collegeId == null
                          ? null
                          : collegeCodeById[threadState.collegeId!];
                      return _ConversationThreadTile(
                        key: ValueKey('${activeUid}_${threadState.studentId}'),
                        threadState: threadState,
                        selected: selectedUser == threadState.studentId,
                        collegeLabel: collegeCode,
                        activityTime: formatCounselorThreadActivityTime(
                          counselorThreadLastActivityAt(threadState),
                          now: now,
                          use24HourFormat: use24Hour,
                        ),
                        onTap: () => _selectThread(controller, threadState),
                      );
                    },
                  );
                }(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildThreadPane({
    required CounselorInboxUnreadController controller,
    required Map<String, String> collegeLabelById,
    required bool singlePane,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final activeUid = controller.activeUid;
          final studentId = selectedUser;
          if (studentId == null || activeUid == null || _messagesSub == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AdminSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mark_chat_unread_outlined,
                      size: 36,
                      color: AdminColors.muted,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Select a conversation',
                      style: TextStyle(
                        color: AdminColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Choose a student thread to read and reply.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AdminColors.muted),
                    ),
                  ],
                ),
              ),
            );
          }

          final threadState = controller.stateFor(studentId);
          final studentLabel = counselorConversationStudentLabel(
            threadState?.studentName,
          );
          final collegeDisplay = threadState?.collegeId == null
              ? null
              : collegeLabelById[threadState!.collegeId!];

          final serverModels = _docs
              .map(
                (doc) => counselorTimelineMessageFromMap(
                  id: doc.id,
                  data: doc.data(),
                  hasPendingWrites: doc.metadata.hasPendingWrites,
                ),
              )
              .toList();
          final localOutgoing =
              _outgoingByThreadKey['$activeUid::$studentId'] ?? const [];
          final timelineMessages = mergeAndSortCounselorMessages(
            serverMessages: serverModels,
            localOutgoing: localOutgoing,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ThreadHeader(
                studentLabel: studentLabel,
                collegeDisplay: collegeDisplay,
                threadState: threadState,
                showBack: singlePane,
                onBack: _closeSelectedThread,
              ),
              Expanded(
                child: () {
                  if (_messagesError) {
                    return const Center(
                      child: Text('Unable to load messages.'),
                    );
                  }
                  if (_messagesLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return CounselorThreadTimeline(
                    key: ValueKey('$activeUid::$studentId'),
                    uid: activeUid,
                    studentLabel: studentLabel,
                    messages: timelineMessages,
                    hasMoreOlder: _hasMoreOlder,
                    loadingOlder: _loadingOlder,
                    onLoadOlder: _loadOlderMessages,
                    onRetryFailed: _retryFailedMessage,
                    onDismissFailed: _dismissFailedMessage,
                    now: widget.now,
                    studentReadAt: controller
                        .stateFor(studentId)
                        ?.studentReadAt
                        ?.toDate(),
                  );
                }(),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: const BoxDecoration(
                  color: AdminColors.surface,
                  border: Border(top: BorderSide(color: AdminColors.border)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sending)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: AdminColors.muted,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Sending reply…',
                              style: TextStyle(
                                color: AdminColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: messageController,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 1600,
                            textInputAction: TextInputAction.newline,
                            decoration: const InputDecoration(
                              hintText: 'Reply to student',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: IconButton(
                            onPressed: sending ? null : send,
                            icon: const Icon(Icons.send),
                            tooltip: 'Send reply',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConversationThreadTile extends StatelessWidget {
  const _ConversationThreadTile({
    super.key,
    required this.threadState,
    required this.selected,
    required this.collegeLabel,
    required this.activityTime,
    required this.onTap,
  });

  final CounselorThreadReadState threadState;
  final bool selected;
  final String? collegeLabel;
  final String activityTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUnread = threadState.isUnread;
    final isPendingSync = threadState.isPendingSync;
    final studentLabel = counselorConversationStudentLabel(
      threadState.studentName,
    );
    final statusLabel = counselorThreadStatusLabel(threadState);

    final backgroundColor = selected
        ? AdminColors.accentFaint
        : isUnread
        ? AdminColors.accentFaint.withValues(alpha: 0.45)
        : AdminColors.surface;
    final borderColor = selected
        ? AdminColors.accentStrong
        : isUnread
        ? AdminColors.accent
        : AdminColors.border;
    final borderWidth = selected ? 1.5 : 1.0;

    return Material(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (isUnread) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AdminColors.accentStrong,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      studentLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AdminColors.ink,
                        fontSize: 14,
                        fontWeight: (isUnread || selected)
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    activityTime,
                    style: TextStyle(
                      color: isUnread ? AdminColors.ink : AdminColors.muted,
                      fontSize: 11.5,
                      fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (collegeLabel != null && collegeLabel!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AdminColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              collegeLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AdminColors.ink,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: isUnread
                                ? AdminColors.amberFg
                                : isPendingSync
                                ? AdminColors.blueFg
                                : AdminColors.muted,
                            fontSize: 11.5,
                            fontWeight: isUnread || isPendingSync
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  UnreadCountBadge(count: isUnread ? 1 : 0),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({
    required this.studentLabel,
    required this.collegeDisplay,
    required this.threadState,
    required this.showBack,
    required this.onBack,
  });

  final String studentLabel;
  final String? collegeDisplay;
  final CounselorThreadReadState? threadState;
  final bool showBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final status = threadState?.status ?? CounselorReadStatus.unknown;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AdminColors.surface,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showBack) ...[
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to conversations',
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Conversation with $studentLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdminColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (collegeDisplay != null && collegeDisplay!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    collegeDisplay!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (status != CounselorReadStatus.unknown && threadState != null) ...[
            const SizedBox(width: 8),
            _ConversationReadStatusPill(state: threadState!),
          ],
        ],
      ),
    );
  }
}

class _ConversationReadStatusPill extends StatelessWidget {
  const _ConversationReadStatusPill({required this.state});

  final CounselorThreadReadState state;

  @override
  Widget build(BuildContext context) {
    final label = counselorThreadStatusLabel(state);
    final (bg, fg, border) = switch (state.status) {
      CounselorReadStatus.unread => (
        AdminColors.amberBg,
        AdminColors.amberFg,
        AdminColors.amberBorder,
      ),
      CounselorReadStatus.pendingRead => (
        AdminColors.blueBg,
        AdminColors.blueFg,
        AdminColors.blueBorder,
      ),
      CounselorReadStatus.read => (
        AdminColors.greenBg,
        AdminColors.greenFg,
        AdminColors.greenBorder,
      ),
      CounselorReadStatus.unknown => (
        AdminColors.neutralBg,
        AdminColors.neutralFg,
        AdminColors.neutralBorder,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
