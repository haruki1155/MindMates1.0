import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/repositories/mind_aid_repository_screen.dart';
import 'package:mind_mates/services/firebase/firestore_service.dart';

class _UnavailableFirestore extends FirestoreService {
  @override
  FirebaseFirestore get firestore => throw StateError('History query failed');
}

void main() {
  test('history query failures are reported instead of returning empty history', () async {
    final repository = MindAidRepository(
      firestoreService: _UnavailableFirestore(),
    );
    await expectLater(
      repository.fetchMessages('owner', conversationId: 'conversation'),
      throwsStateError,
    );
  });
}
