// SDK document types are intentionally doubled here without adding mocking dependencies.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/repositories/counselor_chat_repository.dart';

// Small SDK doubles exercise the actual repository transaction and schema.
class TestAuth extends Fake implements FirebaseAuth {
  String? signedIn = 'student';
  @override
  User? get currentUser => signedIn == null ? null : TestUser(signedIn!);
}

class TestUser extends Fake implements User {
  TestUser(this.uid);
  @override
  final String uid;
}

class TestSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  TestSnapshot(this.value);
  final Map<String, dynamic>? value;
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic>? data() => value;
}

class TestReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  TestReference(this.db, this.path);
  final TestFirestore db;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      TestCollection(db, '${this.path}/$path');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => TestSnapshot(db.documents[path]);
}

class TestCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  TestCollection(this.db, this.path);
  final TestFirestore db;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      TestReference(db, '${this.path}/${path ?? 'generated'}');
}

class TestTransaction extends Fake implements Transaction {
  TestTransaction(this.db);
  final TestFirestore db;
  final writes = <String, Map<String, dynamic>>{};
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async =>
      TestSnapshot(db.documents[documentReference.path]) as DocumentSnapshot<T>;
  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    writes[documentReference.path] = {
      ...?db.documents[documentReference.path],
      ...data as Map<String, dynamic>,
    };
    return this;
  }
}

class TestFirestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{
    'users/student': {'collegeId': 'college-1', 'name': 'Student Name'},
  };
  int committedMessages = 0;
  bool loseAcknowledgment = false;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      TestCollection(this, path);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final transaction = TestTransaction(this);
    final result = await transactionHandler(transaction);
    committedMessages += transaction.writes.keys
        .where((path) => path.contains('/messages/'))
        .length;
    documents.addAll(transaction.writes);
    if (loseAcknowledgment) {
      loseAcknowledgment = false;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return result;
  }
}

void main() {
  test(
    'lost acknowledgment retries the same document without duplicate message or badge writes',
    () async {
      final db = TestFirestore()..loseAcknowledgment = true;
      final repo = FirestoreCounselorChatRepository(
        firestore: db,
        auth: TestAuth(),
      );
      await expectLater(
        repo.send('student', 'stable-id', 'PACC inquiry'),
        throwsA(isA<FirebaseException>()),
      );
      final thread = Map<String, dynamic>.from(
        db.documents['counselor_threads/student']!,
      );
      await repo.send('student', 'stable-id', 'PACC inquiry');
      expect(db.committedMessages, 1);
      expect(db.documents['counselor_threads/student'], thread);
      expect(thread['collegeId'], 'college-1');
      expect(thread['lastStudentMessageId'], 'stable-id');
      expect(
        db.documents['counselor_threads/student/messages/stable-id']!.keys,
        unorderedEquals(['senderId', 'senderRole', 'text', 'createdAt']),
      );
    },
  );
  test(
    'rejects changed payload for an existing ID and unauthenticated writes',
    () async {
      final db = TestFirestore();
      final auth = TestAuth();
      final repo = FirestoreCounselorChatRepository(firestore: db, auth: auth);
      await repo.send('student', 'id', 'Original');
      await expectLater(
        repo.send('student', 'id', 'Changed'),
        throwsStateError,
      );
      auth.signedIn = null;
      await expectLater(
        repo.send('student', 'other-id', 'Original'),
        throwsA(isA<FirebaseException>()),
      );
      expect(db.committedMessages, 1);
    },
  );
}
