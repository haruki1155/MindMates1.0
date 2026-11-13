import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/admin_theme.dart';
import '../../counseling/widgets/counselor_unread_badges.dart';

/// Approved counselor-only inbox. AI history is never merged into this thread.
class CounselorMessagesPage extends StatefulWidget {
  const CounselorMessagesPage({super.key});

  @override
  State<CounselorMessagesPage> createState() => _CounselorMessagesPageState();
}

class _CounselorMessagesPageState extends State<CounselorMessagesPage> {
  String? selectedUser;
  String selectedCollege = 'all';
  final messageController = TextEditingController();
  bool sending = false;
  String? _readingUser;

  Future<void> _markRead(String studentId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _readingUser == studentId) return;
    _readingUser = studentId;
    try {
      await FirebaseFirestore.instance
          .collection('counselor_inbox_reads')
          .doc(uid)
          .collection('threads')
          .doc(studentId)
          .set({'readAt': FieldValue.serverTimestamp()});
    } catch (error) {
      debugPrint('COUNSELOR_READ_ERROR: $error');
    } finally {
      _readingUser = null;
    }
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final userId = selectedUser;
    final text = messageController.text.trim();
    if (uid == null ||
        userId == null ||
        text.isEmpty ||
        text.length > 1600 ||
        sending) {
      return;
    }
    setState(() => sending = true);
    try {
      final db = FirebaseFirestore.instance;
      final thread = db.collection('counselor_threads').doc(userId);
      final batch = db.batch();
      final message = thread.collection('messages').doc();
      batch.update(thread, {
        'updatedAt': FieldValue.serverTimestamp(),
        'lastCounselorMessageAt': FieldValue.serverTimestamp(),
        'lastCounselorMessageId': message.id,
      });
      batch.set(message, {
        'senderId': uid,
        'senderRole': 'counselor',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      messageController.clear();
      await _markRead(userId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to send message. Check permissions or connection.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('colleges').snapshots(),
            builder: (context, collegeSnapshot) {
              if (collegeSnapshot.hasError) {
                return const Text('Unable to load academic structure.');
              }
              if (!collegeSnapshot.hasData) {
                return const LinearProgressIndicator();
              }
              final colleges =
                  collegeSnapshot.data!.docs
                      .where((doc) => doc.data()['active'] != false)
                      .toList()
                    ..sort(
                      (a, b) => (a.data()['name'] ?? '').toString().compareTo(
                        (b.data()['name'] ?? '').toString(),
                      ),
                    );
              final values = <String>{'all', ...colleges.map((e) => e.id)};
              final current = values.contains(selectedCollege)
                  ? selectedCollege
                  : 'all';
              return DropdownButtonFormField<String>(
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
                        '${college.data()['code'] ?? ''} — ${college.data()['name'] ?? college.id}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  selectedCollege = value ?? 'all';
                  selectedUser = null;
                }),
              );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 270,
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: db
                        .collection('counselor_threads')
                        .orderBy('updatedAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: SelectableText(
                            'Unable to load inbox: ${snapshot.error}',
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text('No messages'));
                      }
                      final threads = snapshot.data!.docs
                          .where(
                            (thread) =>
                                selectedCollege == 'all' ||
                                thread.data()['collegeId'] == selectedCollege,
                          )
                          .toList();
                      if (threads.isEmpty) {
                        return const Center(child: Text('No messages'));
                      }
                      return ListView(
                        children: [
                          for (final thread in threads)
                            ListTile(
                              selected: selectedUser == thread.id,
                              title: Text(
                                (thread.data()['studentName'] as String?)
                                            ?.trim()
                                            .isNotEmpty ==
                                        true
                                    ? thread.data()['studentName'] as String
                                    : 'Student ${thread.id.length > 10 ? '${thread.id.substring(0, 10)}…' : thread.id}',
                              ),
                              subtitle: Text(
                                (thread.data()['collegeId'] ??
                                        'Unassigned college')
                                    .toString(),
                              ),
                              trailing:
                                  StreamBuilder<
                                    DocumentSnapshot<Map<String, dynamic>>
                                  >(
                                    stream: db
                                        .collection('counselor_inbox_reads')
                                        .doc(
                                          FirebaseAuth
                                              .instance
                                              .currentUser!
                                              .uid,
                                        )
                                        .collection('threads')
                                        .doc(thread.id)
                                        .snapshots(),
                                    builder: (context, receipt) =>
                                        UnreadCountBadge(
                                          count:
                                              counselorThreadUnread(
                                                thread.data(),
                                                receipt.data?.data()?['readAt'],
                                              )
                                              ? 1
                                              : 0,
                                        ),
                                  ),
                              onTap: () {
                                setState(() => selectedUser = thread.id);
                                _markRead(thread.id);
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 24),
                Expanded(
                  child: selectedUser == null
                      ? const Center(child: Text('Select a conversation'))
                      : Column(
                          children: [
                            Expanded(
                              child:
                                  StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>
                                  >(
                                    key: ValueKey(selectedUser),
                                    stream: db
                                        .collection('counselor_threads')
                                        .doc(selectedUser)
                                        .collection('messages')
                                        .orderBy('createdAt')
                                        .snapshots(),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasError) {
                                        return const Center(
                                          child: Text(
                                            'Unable to load messages.',
                                          ),
                                        );
                                      }
                                      if (!snapshot.hasData) {
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      }
                                      final hasStudentMessages = snapshot
                                          .data!
                                          .docs
                                          .any(
                                            (doc) =>
                                                doc.data()['senderRole'] ==
                                                'user',
                                          );
                                      if (hasStudentMessages &&
                                          selectedUser != null) {
                                        final studentId = selectedUser!;
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) async {
                                              if (!mounted ||
                                                  selectedUser != studentId ||
                                                  _readingUser != null) {
                                                return;
                                              }
                                              final thread = await db
                                                  .collection(
                                                    'counselor_threads',
                                                  )
                                                  .doc(studentId)
                                                  .get();
                                              final uid = FirebaseAuth
                                                  .instance
                                                  .currentUser
                                                  ?.uid;
                                              if (uid == null) return;
                                              final receipt = await db
                                                  .collection(
                                                    'counselor_inbox_reads',
                                                  )
                                                  .doc(uid)
                                                  .collection('threads')
                                                  .doc(studentId)
                                                  .get();
                                              if (counselorThreadUnread(
                                                thread.data() ?? {},
                                                receipt.data()?['readAt'],
                                              )) {
                                                await _markRead(studentId);
                                              }
                                            });
                                      }
                                      return ListView(
                                        children: [
                                          for (final doc in snapshot.data!.docs)
                                            Align(
                                              alignment:
                                                  doc.data()['senderRole'] ==
                                                      'counselor'
                                                  ? Alignment.centerRight
                                                  : Alignment.centerLeft,
                                              child: Card(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  child: Text(
                                                    doc.data()['text']
                                                            as String? ??
                                                        '',
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
            ),
          ),
        ],
      ),
    );
  }
}
