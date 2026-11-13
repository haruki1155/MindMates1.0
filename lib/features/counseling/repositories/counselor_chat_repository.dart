import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../services/firebase/firebase_callable_router.dart';
import '../widgets/counselor_unread_badges.dart';

class CounselorMessage {
  const CounselorMessage({
    required this.id,
    required this.text,
    required this.senderId,
    this.createdAt,
    this.pendingWrites = false,
    this.acknowledged = false,
  });
  final String id;
  final String text;
  final String senderId;
  final DateTime? createdAt;
  final bool pendingWrites;
  final bool acknowledged;
}

abstract class CounselorChatRepository {
  Stream<List<CounselorMessage>> watch(String uid);
  String newMessageId(String uid);
  Future<void> send(String uid, String id, String text);
  Future<void> markRepliesRead(String uid);
}

class FirestoreCounselorChatRepository implements CounselorChatRepository {
  FirestoreCounselorChatRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  @override
  Stream<List<CounselorMessage>> watch(String uid) => _db
      .collection('counselor_threads')
      .doc(uid)
      .collection('messages')
      .orderBy('createdAt')
      .snapshots(includeMetadataChanges: true)
      .map((snapshot) {
        final messages = snapshot.docs.map((doc) {
          final data = doc.data();
          final timestamp = data['createdAt'];
          return CounselorMessage(
            id: doc.id,
            text: data['text'] is String ? data['text'] as String : '',
            senderId: data['senderId'] is String
                ? data['senderId'] as String
                : '',
            createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
            pendingWrites: doc.metadata.hasPendingWrites,
          );
        }).toList();
        messages.sort((a, b) {
          if (a.createdAt == null) {
            return b.createdAt == null ? a.id.compareTo(b.id) : 1;
          }
          if (b.createdAt == null) return -1;
          final order = a.createdAt!.compareTo(b.createdAt!);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
        return messages;
      });

  @override
  String newMessageId(String uid) => _db
      .collection('counselor_threads')
      .doc(uid)
      .collection('messages')
      .doc()
      .id;

  @override
  Future<void> send(String uid, String id, String text) async {
    if (_auth.currentUser?.uid != uid) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unauthenticated',
      );
    }
    if (text.trim().isEmpty || text.length > 1600) {
      throw ArgumentError('Invalid message');
    }
    final db = _db;
    final thread = db.collection('counselor_threads').doc(uid);
    final message = thread.collection('messages').doc(id);
    // Transactions fail offline instead of claiming queued writes are Sent.
    // An ambiguous acknowledgment is safe to retry using the same ID.
    await db.runTransaction((transaction) async {
      final existing = await transaction.get(message);
      if (existing.exists) {
        final data = existing.data()!;
        if (data['senderId'] != uid ||
            data['senderRole'] != 'user' ||
            data['text'] != text) {
          throw StateError('Message ID conflict');
        }
        return;
      }
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
      // Store only the registered display name in the counselor-visible thread;
      // never expose the full private users/{uid} document to counselors.
      final verifiedProfile = await db.collection('users').doc(uid).get();
      final profileData = verifiedProfile.data() ?? <String, dynamic>{};
      final registeredName = (profileData['name'] as String?) ?? '';
      final first = (profileData['firstName'] as String?)?.trim() ?? '';
      final middle = (profileData['middleName'] as String?)?.trim() ?? '';
      final last = (profileData['lastName'] as String?)?.trim() ?? '';
      final parts = [first, middle, last].where((v) => v.isNotEmpty).toList();
      final studentName = first.isNotEmpty && last.isNotEmpty
          ? parts.join(' ')
          : registeredName;
      transaction.set(thread, {
        'userId': uid,
        'collegeId': collegeId,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastStudentMessageAt': FieldValue.serverTimestamp(),
        'lastStudentMessageId': message.id,
        if (studentName.isNotEmpty) 'studentName': studentName,
      }, SetOptions(merge: true));
      transaction.set(message, {
        'senderId': uid,
        'senderRole': 'user',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> markRepliesRead(String uid) async {
    if (_auth.currentUser?.uid != uid) return;
    final thread = _db.collection('counselor_threads').doc(uid);
    final snapshot = await thread.get();
    if (studentThreadUnread(snapshot.data() ?? {})) {
      await thread.update({'studentReadAt': FieldValue.serverTimestamp()});
    }
  }
}
