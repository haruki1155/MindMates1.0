import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../services/firebase/firebase_error_message.dart';
import '../../counseling/widgets/counselor_unread_badges.dart';
import '../theme/admin_theme.dart';

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
  });

  /// Hide the standalone page heading when the inbox is inside Inquiries.
  final bool embedded;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final CounselorInboxUnreadController? unreadController;

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

  String? _failedAutoMarkUid;
  final Map<String, Timestamp?> _failedAutoMarkWatermarkByStudent = {};
  String? _pendingPostFrameMarkKey;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _collegesStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _messagesStream;
  String? _messagesStreamKey;

  FirebaseFirestore? get _db =>
      widget.firestore ??
      (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);

  @override
  void initState() {
    super.initState();
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
    if (widget.firestore != oldWidget.firestore) {
      _collegesStream = _db?.collection('colleges').snapshots();
      _messagesStream = null;
      _messagesStreamKey = null;
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
    _ensureMessagesStream(_lastObservedUid, selectedUser);
    next.addListener(_onControllerChanged);
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
      setState(() {
        _lastObservedUid = currentUid;
        selectedUser = null;
        selectedCollege = 'all';
        sending = false;
        messageController.clear();
        _messagesStream = null;
        _messagesStreamKey = null;
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

  void _ensureMessagesStream(String? uid, String? studentId) {
    final db = _db;
    if (uid == null || studentId == null || db == null) {
      _messagesStream = null;
      _messagesStreamKey = null;
      return;
    }
    final key = '$uid::$studentId';
    if (_messagesStreamKey == key && _messagesStream != null) return;
    _messagesStreamKey = key;
    _messagesStream = db
        .collection('counselor_threads')
        .doc(studentId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots();
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
    final sendToken = ++_sendSeq;
    setState(() => sending = true);
    try {
      await controller.sendCounselorReply(
        studentId: userId,
        text: text,
        expectedUid: uid,
      );
      if (mounted &&
          _sendSeq == sendToken &&
          controller.activeUid == uid) {
        if (_failedAutoMarkUid == uid) {
          _failedAutoMarkWatermarkByStudent.remove(userId);
        }
        if (selectedUser == userId) {
          messageController.clear();
        }
      }
    } catch (_) {
      if (mounted &&
          _sendSeq == sendToken &&
          controller.activeUid == uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to send message. Check permissions or connection.',
            ),
          ),
        );
      }
    } finally {
      if (mounted &&
          _sendSeq == sendToken &&
          controller.activeUid == uid) {
        setState(() => sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _activeController!;
    return Padding(
      padding: EdgeInsets.all(widget.embedded ? 0 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.embedded) ...[
            const Text(
              'Counselor Messages',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Direct student conversations. MindAid AI history is separate.',
              style: TextStyle(color: AdminColors.muted),
            ),
            const SizedBox(height: 20),
          ],
          if (_collegesStream != null)
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _collegesStream,
                builder: (context, collegeSnapshot) {
                  Widget header;
                  String? effectiveCollege =
                      selectedCollege == 'all' ? null : selectedCollege;
                  if (collegeSnapshot.hasError) {
                    header = const Text('Unable to load academic structure.');
                    effectiveCollege = null;
                  } else if (!collegeSnapshot.hasData) {
                    header = const LinearProgressIndicator();
                  } else {
                    final colleges =
                        collegeSnapshot.data!.docs
                            .where((doc) => doc.data()['active'] != false)
                            .toList()
                          ..sort(
                            (a, b) => (a.data()['name'] ?? '')
                                .toString()
                                .compareTo((b.data()['name'] ?? '').toString()),
                          );
                    final values = <String>{'all', ...colleges.map((e) => e.id)};
                    final current = values.contains(selectedCollege)
                        ? selectedCollege
                        : 'all';
                    effectiveCollege = current == 'all' ? null : current;
                    header = DropdownButtonFormField<String>(
                      key: ValueKey(current),
                      initialValue: current,
                      decoration: const InputDecoration(
                        labelText: 'College / Academic Structure',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('All Colleges'),
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
                        _messagesStream = null;
                        _messagesStreamKey = null;
                      }),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header,
                      const SizedBox(height: 16),
                      Expanded(
                        child: _buildInboxBody(
                          controller: controller,
                          collegeFilter: effectiveCollege,
                        ),
                      ),
                    ],
                  );
                },
              ),
            )
          else ...[
            const SizedBox(height: 16),
            Expanded(
              child: _buildInboxBody(
                controller: controller,
                collegeFilter:
                    selectedCollege == 'all' ? null : selectedCollege,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInboxBody({
    required CounselorInboxUnreadController controller,
    required String? collegeFilter,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 270,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final activeUid = controller.activeUid;
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
                  child: SelectableText(message),
                );
              }
              if (controller.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              final threads = controller.threadsForCollege(collegeFilter);
              if (threads.isEmpty) {
                return const Center(child: Text('No messages'));
              }
              return ListView.builder(
                itemCount: threads.length,
                itemBuilder: (context, index) {
                  final threadState = threads[index];
                  return ListTile(
                    key: ValueKey('${activeUid}_${threadState.studentId}'),
                    selected: selectedUser == threadState.studentId,
                    title: Text(
                      counselorConversationStudentLabel(
                        threadState.studentName,
                      ),
                    ),
                    trailing: UnreadCountBadge(
                      count: threadState.isUnread ? 1 : 0,
                    ),
                    onTap: () {
                      final capturedUid = controller.activeUid;
                      final isSelectionChange =
                          selectedUser != threadState.studentId;
                      if (isSelectionChange) {
                        _failedAutoMarkWatermarkByStudent.clear();
                        _pendingPostFrameMarkKey = null;
                      } else if (_failedAutoMarkUid == capturedUid) {
                        _failedAutoMarkWatermarkByStudent.remove(
                          threadState.studentId,
                        );
                      }
                      setState(() {
                        selectedUser = threadState.studentId;
                        _ensureMessagesStream(
                          capturedUid,
                          threadState.studentId,
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
                    },
                  );
                },
              );
            },
          ),
        ),
        const VerticalDivider(width: 24),
        Expanded(
          child: selectedUser == null ||
                  controller.activeUid == null ||
                  _messagesStream == null
              ? const Center(child: Text('Select a conversation'))
              : Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        key: ValueKey(_messagesStreamKey),
                        stream: _messagesStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const Center(
                              child: Text('Unable to load messages.'),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final docs = snapshot.data!.docs;
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
                          final openStudentId = selectedUser;
                          final activeUid = controller.activeUid;
                          if (hasStudentMessages &&
                              openStudentId != null &&
                              activeUid != null) {
                            final observedAt = maxTimestamp(
                              maxMessageStudentAt,
                              controller
                                  .stateFor(openStudentId)
                                  ?.lastStudentMessageAt,
                            );
                            if (!_isAutoMarkSuppressed(
                                  studentId: openStudentId,
                                  uid: activeUid,
                                  observedAt: observedAt,
                                ) &&
                                controller.needsMarkRead(
                                  openStudentId,
                                  observedStudentMessageAt: observedAt,
                                )) {
                              _scheduleMarkReadIfOpen(
                                controller: controller,
                                studentId: openStudentId,
                                expectedUid: activeUid,
                                observedAt: observedAt,
                              );
                            }
                          }
                          return ListView(
                            children: [
                              for (final doc in docs)
                                Align(
                                  alignment:
                                      doc.data()['senderRole'] == 'counselor'
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        doc.data()['text'] as String? ?? '',
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: messageController,
                            maxLength: 1600,
                            decoration: const InputDecoration(
                              hintText: 'Reply to student',
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: sending ? null : send,
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
