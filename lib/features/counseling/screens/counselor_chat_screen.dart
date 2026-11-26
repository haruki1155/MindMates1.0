import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../services/firebase/firebase_callable_router.dart';
import 'package:flutter/material.dart';

/// Human counselor inbox. This never reads or writes MindAid history.
class CounselorChatScreen extends StatefulWidget {
  const CounselorChatScreen({super.key});

  @override
  State<CounselorChatScreen> createState() => _CounselorChatScreenState();
}

class _CounselorChatScreenState extends State<CounselorChatScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(String uid) async {
    final text = _controller.text.trim();
    if (text.isEmpty || text.length > 1600 || _sending) return;
    setState(() => _sending = true);
    try {
      final db = FirebaseFirestore.instance;
      final thread = db.collection('counselor_threads').doc(uid);
      final message = thread.collection('messages').doc();
      final profile = await db.collection('users').doc(uid).get();
      String collegeId =
          (profile.data()?['collegeId'] as String?)?.trim() ?? '';

      if (collegeId.isEmpty) {
        await FirebaseFunctions.instance
            .routedCallable('repairMyStudentCollege')
            .call<void>();

        final refreshedProfile = await db
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server));

        collegeId =
            (refreshedProfile.data()?['collegeId'] as String?)?.trim() ?? '';

        if (collegeId.isEmpty) {
          throw StateError(
            'College assignment could not be verified. Contact PACC.',
          );
        }
      }
      final batch = db.batch();
      batch.set(thread, {
        'userId': uid,
        'collegeId': collegeId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(message, {
        'senderId': uid,
        'senderRole': 'user',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      _controller.clear();
    } on FirebaseException catch (e) {
      debugPrint('COUNSELOR_SEND_ERROR: code=${e.code}, message=${e.message}');
      if (mounted) {
        final message = switch (e.code) {
          'permission-denied' =>
            'Firestore permission denied. Please contact PACC support.',
          'unavailable' => 'Connection unavailable. Please try again.',
          'unauthenticated' => 'Please sign in again.',
          _ => 'Unable to send message. Error: ${e.code}',
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      debugPrint('COUNSELOR_SEND_ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to send message. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Guidance Counselor')),
        body: const Center(
          child: Text('Please sign in to message a counselor.'),
        ),
      );
    }
    final stream = FirebaseFirestore.instance
        .collection('counselor_threads')
        .doc(uid)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots();
    return Scaffold(
      appBar: AppBar(title: const Text('Guidance Counselor')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Messages are sent to the PACC counselor inbox. This is not a live emergency service.',
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Unable to load messages.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet. Start a conversation with PACC.',
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final own = data['senderId'] == uid;
                    return Align(
                      alignment: own
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            data['text'] is String
                                ? data['text'] as String
                                : '',
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLength: 1600,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Message a counselor',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send message',
                    onPressed: _sending ? null : () => _send(uid),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
