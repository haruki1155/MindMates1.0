import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/counselor_message_presentation.dart';
import 'package:mind_mates/features/admin/widgets/counselor_thread_timeline.dart';
import 'package:mind_mates/features/counseling/widgets/counselor_unread_badges.dart';

import '../counseling/fake_counselor_inbox_firebase.dart';

void main() {
  testWidgets(
    "a counselor's own message shows Seen once studentReadAt passes it",
    (tester) async {
      final readAt = DateTime(2026, 11, 22, 10, 30);
      CounselorTimelineMessage counselorMessage(String id, DateTime at) =>
          CounselorTimelineMessage(
            id: id,
            text: 'Guidance $id',
            senderId: 'counselor-a',
            senderRole: 'counselor',
            createdAt: at,
          );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CounselorThreadTimeline(
              uid: 'counselor-a',
              studentLabel: 'Ana',
              studentReadAt: readAt,
              messages: [
                counselorMessage(
                  'before',
                  readAt.subtract(const Duration(minutes: 1)),
                ),
                counselorMessage(
                  'after',
                  readAt.add(const Duration(minutes: 1)),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Seen'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
    },
  );

  test('thread read state exposes the student read time', () async {
    final db = FakeCounselorFirestore();
    final auth = FakeCounselorAuth(initialUid: 'counselor-a');
    addTearDown(() async {
      await db.dispose();
      await auth.dispose();
    });
    final studentReadAt = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 11));
    db.seedDoc('counselor_threads/s1', {
      'userId': 's1',
      'collegeId': 'CITE',
      'studentReadAt': studentReadAt,
    });
    final controller = CounselorInboxUnreadController(
      firestore: db,
      auth: auth,
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(controller.stateFor('s1')?.studentReadAt, studentReadAt);
  });
}
