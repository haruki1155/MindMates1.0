import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/widgets/counselor_unread_badges.dart';

import 'fake_counselor_inbox_firebase.dart';

void main() {
  group('resolveCounselorReadStatus & pure helpers', () {
    final t100 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 0));
    final t105 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 5));
    final t110 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 10));

    test('returns unknown while streams are not ready or on error', () {
      expect(
        resolveCounselorReadStatus(
          streamsReady: false,
          hasError: false,
          lastStudentMessageAt: t100,
          serverReadAt: null,
          lastConfirmedReadAt: null,
          pendingStudentMessageWatermark: null,
          receiptExists: false,
          receiptHasPendingWrites: false,
          writeInFlight: false,
        ),
        CounselorReadStatus.unknown,
      );
      expect(
        resolveCounselorReadStatus(
          streamsReady: true,
          hasError: true,
          lastStudentMessageAt: t100,
          serverReadAt: null,
          lastConfirmedReadAt: null,
          pendingStudentMessageWatermark: null,
          receiptExists: false,
          receiptHasPendingWrites: false,
          writeInFlight: false,
        ),
        CounselorReadStatus.unknown,
      );
    });

    test('returns read when there is no student message', () {
      expect(
        resolveCounselorReadStatus(
          streamsReady: true,
          hasError: false,
          lastStudentMessageAt: null,
          serverReadAt: null,
          lastConfirmedReadAt: null,
          pendingStudentMessageWatermark: null,
          receiptExists: false,
          receiptHasPendingWrites: false,
          writeInFlight: false,
        ),
        CounselorReadStatus.read,
      );
    });

    test(
      'uses non-regressing server/confirmed timestamps and detects newer student msg',
      () {
        expect(
          resolveCounselorReadStatus(
            streamsReady: true,
            hasError: false,
            lastStudentMessageAt: t100,
            serverReadAt: null,
            lastConfirmedReadAt: t105,
            pendingStudentMessageWatermark: null,
            receiptExists: true,
            receiptHasPendingWrites: true,
            writeInFlight: false,
          ),
          CounselorReadStatus.read,
        );

        expect(
          resolveCounselorReadStatus(
            streamsReady: true,
            hasError: false,
            lastStudentMessageAt: t110,
            serverReadAt: t105,
            lastConfirmedReadAt: t105,
            pendingStudentMessageWatermark: t105,
            receiptExists: true,
            receiptHasPendingWrites: true,
            writeInFlight: true,
          ),
          CounselorReadStatus.unread,
        );
      },
    );

    test(
      'pending watermark prevents false unread during serverTimestamp null snapshot',
      () {
        expect(
          resolveCounselorReadStatus(
            streamsReady: true,
            hasError: false,
            lastStudentMessageAt: t105,
            serverReadAt: null,
            lastConfirmedReadAt: t100,
            pendingStudentMessageWatermark: t105,
            receiptExists: true,
            receiptHasPendingWrites: true,
            writeInFlight: true,
          ),
          CounselorReadStatus.pendingRead,
        );
        expect(
          resolveCounselorReadStatus(
            streamsReady: true,
            hasError: false,
            lastStudentMessageAt: t105,
            serverReadAt: null,
            lastConfirmedReadAt: t100,
            pendingStudentMessageWatermark: t105,
            receiptExists: false,
            receiptHasPendingWrites: false,
            writeInFlight: false,
            awaitingReceiptConfirmation: true,
          ),
          CounselorReadStatus.pendingRead,
        );
        expect(
          resolveCounselorReadStatus(
            streamsReady: true,
            hasError: false,
            lastStudentMessageAt: t110,
            serverReadAt: null,
            lastConfirmedReadAt: t100,
            pendingStudentMessageWatermark: t105,
            receiptExists: false,
            receiptHasPendingWrites: false,
            writeInFlight: false,
            awaitingReceiptConfirmation: true,
          ),
          CounselorReadStatus.unread,
        );
      },
    );

    test('countUnreadCounselorThreads filters by optional collegeId', () {
      final states = [
        CounselorThreadReadState(
          studentId: 's1',
          collegeId: 'CITE',
          studentName: 'Ana',
          updatedAt: t105,
          lastStudentMessageAt: t105,
          lastStudentMessageId: 'm1',
          lastCounselorMessageAt: null,
          serverReadAt: null,
          receiptHasPendingWrites: false,
          status: CounselorReadStatus.unread,
        ),
        CounselorThreadReadState(
          studentId: 's2',
          collegeId: 'CBA',
          studentName: 'Ben',
          updatedAt: t105,
          lastStudentMessageAt: t105,
          lastStudentMessageId: 'm2',
          lastCounselorMessageAt: null,
          serverReadAt: null,
          receiptHasPendingWrites: false,
          status: CounselorReadStatus.unread,
        ),
        CounselorThreadReadState(
          studentId: 's3',
          collegeId: 'CITE',
          studentName: 'Cara',
          updatedAt: t100,
          lastStudentMessageAt: t100,
          lastStudentMessageId: 'm3',
          lastCounselorMessageAt: t105,
          serverReadAt: t105,
          receiptHasPendingWrites: false,
          status: CounselorReadStatus.read,
        ),
      ];

      expect(countUnreadCounselorThreads(states), 2);
      expect(countUnreadCounselorThreads(states, collegeId: 'CITE'), 1);
      expect(countUnreadCounselorThreads(states, collegeId: 'all'), 2);
    });

    test('counselorThreadUnread handles Timestamp comparisons accurately', () {
      expect(
        counselorThreadUnread({'lastStudentMessageAt': t105}, null),
        isTrue,
      );
      expect(
        counselorThreadUnread({'lastStudentMessageAt': t105}, t100),
        isTrue,
      );
      expect(
        counselorThreadUnread({'lastStudentMessageAt': t105}, t105),
        isFalse,
      );
      expect(
        counselorThreadUnread({'lastStudentMessageAt': t100}, t105),
        isFalse,
      );
      expect(counselorThreadUnread({}, null), isFalse);
    });
  });

  group('CounselorInboxUnreadController & CounselorInboxUnreadBadge', () {
    late FakeCounselorFirestore db;
    late FakeCounselorAuth auth;

    setUp(() {
      db = FakeCounselorFirestore();
      auth = FakeCounselorAuth(initialUid: 'counselor-a');
    });

    tearDown(() async {
      await db.dispose();
      await auth.dispose();
    });

    testWidgets(
      'multiple conversations: counts only unread threads (unread, already-read, counselor-replied-last, no-student-msg)',
      (tester) async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 9, 0));
        final t2 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 9, 5));
        final t3 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 9, 10));

        // s1: unread (student msg at t2, no receipt)
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Student One',
          'updatedAt': t2,
          'lastStudentMessageAt': t2,
          'lastStudentMessageId': 'm1',
        });
        // s2: already read (student msg at t1, receipt at t2)
        db.seedDoc('counselor_threads/s2', {
          'userId': 's2',
          'collegeId': 'CITE',
          'studentName': 'Student Two',
          'updatedAt': t2,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm2',
          'lastCounselorMessageAt': t2,
        });
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s2', {
          'readAt': t2,
        });
        // s3: counselor-replied-last AND student had no newer message, receipt covers t1; wait: also test thread with NO student message at all
        db.seedDoc('counselor_threads/s3', {
          'userId': 's3',
          'collegeId': 'CBA',
          'studentName': 'Student Three',
          'updatedAt': t3,
          'lastCounselorMessageAt': t3,
        });
        // s4: unread (student msg at t3 > receipt t2)
        db.seedDoc('counselor_threads/s4', {
          'userId': 's4',
          'collegeId': 'CBA',
          'studentName': 'Student Four',
          'updatedAt': t3,
          'lastStudentMessageAt': t3,
          'lastStudentMessageId': 'm4',
        });
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s4', {
          'readAt': t2,
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CounselorInboxUnreadBadge(firestore: db, auth: auth),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('2'), findsOneWidget);
      },
    );

    testWidgets(
      'delayed and out-of-order snapshots (threads before receipts and receipts before threads) never flash false badge',
      (tester) async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 9, 0));
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Already Read',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s1', {
          'readAt': t1,
        });

        // Case A: threads arrive before receipts
        db.holdThreadsInitialEmission = true;
        db.holdReceiptsInitialEmission = true;

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CounselorInboxUnreadBadge(controller: controller),
            ),
          ),
        );
        await tester.pump();
        expect(controller.isLoading, isTrue);
        expect(controller.unreadCount(), 0);
        expect(find.text('1'), findsNothing);

        db.emitThreads();
        await tester.pump();
        // Receipts still pending -> must NOT flash '1'!
        expect(controller.unreadCount(), 0);
        expect(find.text('1'), findsNothing);

        db.emitReceipts('counselor-a');
        await tester.pumpAndSettle();
        expect(controller.isReady, isTrue);
        expect(controller.unreadCount(), 0);
        expect(find.text('1'), findsNothing);

        // Case B: receipts arrive before threads
        final db2 = FakeCounselorFirestore()
          ..holdThreadsInitialEmission = true
          ..holdReceiptsInitialEmission = true;
        db2.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Unread',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        addTearDown(db2.dispose);
        final controller2 = CounselorInboxUnreadController(
          firestore: db2,
          auth: auth,
        );
        addTearDown(controller2.dispose);
        await tester.pump();
        db2.emitReceipts('counselor-a');
        await tester.pump();
        expect(controller2.unreadCount(), 0);
        db2.emitThreads();
        await tester.pump();
        expect(controller2.unreadCount(), 1);
      },
    );

    test(
      'pending serverTimestamp write (readAt == null, hasPendingWrites == true) does not flash unread, handles clock skew, and rolls back on failure',
      () async {
        final tStudent = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        // Set server clock BEHIND client clock or ahead; watermark uses server-authored student timestamp so clock skew cannot break it.
        db = FakeCounselorFirestore(
          initialServerTime: DateTime.utc(2026, 11, 22, 10, 0, 5),
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: true,
        );
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': tStudent,
          'lastStudentMessageAt': tStudent,
          'lastStudentMessageId': 'm1',
        });

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);

        expect(controller.unreadCount(), 1);

        final countsObserved = <int>[];
        controller.addListener(
          () => countsObserved.add(controller.unreadCount()),
        );

        // Mark read -> emits local pending snapshot with readAt == null and hasPendingWrites == true
        final markFuture = controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: tStudent,
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          db
              .getEntry('counselor_inbox_reads/counselor-a/threads/s1')
              ?.data['readAt'],
          isNull,
        );
        expect(
          db
              .getEntry('counselor_inbox_reads/counselor-a/threads/s1')
              ?.hasPendingWrites,
          isTrue,
        );
        expect(
          controller.stateFor('s1')?.status,
          CounselorReadStatus.pendingRead,
        );
        expect(controller.unreadCount(), 0);
        expect(countsObserved, everyElement(0));

        // Complete server write -> settles cleanly to read with server Timestamp
        db.completeNextPendingWrite();
        await markFuture;
        await Future<void>.delayed(Duration.zero);
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.read);
        expect(controller.unreadCount(), 0);

        // Now a newer student message arrives -> becomes unread, and failing markThreadRead rolls back to unread
        final tStudent2 = Timestamp.fromDate(
          DateTime.utc(2026, 11, 22, 10, 0, 20),
        );
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': tStudent2,
          'lastStudentMessageAt': tStudent2,
          'lastStudentMessageId': 'm2',
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.unreadCount(), 1);

        final failedMark = controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: tStudent2,
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);
        expect(controller.unreadCount(), 0); // optimistic while in flight

        db.failNextPendingWrite(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        );
        await expectLater(failedMark, throwsA(isA<FirebaseException>()));
        await Future<void>.delayed(Duration.zero);
        expect(controller.unreadCount(), 1); // rolled back cleanly!
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.unread);
      },
    );

    test(
      'counselor reply uses atomic 3-write batch and never flashes unread during or after reply',
      () async {
        final tStudent = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        db = FakeCounselorFirestore(
          initialServerTime: DateTime.utc(2026, 11, 22, 10, 0, 5),
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: true,
        );
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': tStudent,
          'lastStudentMessageAt': tStudent,
          'lastStudentMessageId': 'm1',
        });

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);

        expect(controller.unreadCount(), 1);
        final observed = <int>[];
        controller.addListener(() => observed.add(controller.unreadCount()));

        final sendFuture = controller.sendCounselorReply(
          studentId: 's1',
          text: 'Hello Ana',
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);

        expect(observed, everyElement(0));
        expect(controller.unreadCount(), 0);

        db.completeNextPendingWrite();
        await sendFuture;
        await Future<void>.delayed(Duration.zero);

        expect(controller.unreadCount(), 0);
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.read);
        expect(db.committedBatches, hasLength(1));
        expect(db.committedBatches.single, hasLength(3));
        expect(db.committedBatches.single.map((w) => w.path).toList(), [
          'counselor_threads/s1',
          startsWith('counselor_threads/s1/messages/'),
          'counselor_inbox_reads/counselor-a/threads/s1',
        ]);
      },
    );

    test(
      'concurrent incoming student message arriving while earlier mark-read is pending stays unread',
      () async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 0));
        final t2 = Timestamp.fromDate(
          DateTime.utc(2026, 11, 22, 10, 0, 1, 500),
        );
        db = FakeCounselorFirestore(
          initialServerTime: DateTime.utc(2026, 11, 22, 10, 0, 1),
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: true,
        );
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);

        final markFuture = controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t1,
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);
        expect(controller.unreadCount(), 0);

        // Newer incoming student message m2 arrives at t2 while m1's mark-read is pending
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t2,
          'lastStudentMessageAt': t2,
          'lastStudentMessageId': 'm2',
        });
        await Future<void>.delayed(Duration.zero);

        // Must immediately show unread again because t2 > t1 watermark!
        expect(controller.unreadCount(), 1);
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.unread);

        // The server commits after t2 arrived. Only the observed t1 was read.
        db.completeNextPendingWrite();
        await markFuture;
        await Future<void>.delayed(Duration.zero);
        expect(controller.unreadCount(), 1);
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.unread);
      },
    );

    test(
      'account switching clears prior state immediately and in-flight writes from Counselor A never write under Counselor B',
      () async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 0));
        db = FakeCounselorFirestore(
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: true,
        );
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_threads/s2', {
          'userId': 's2',
          'collegeId': 'CITE',
          'studentName': 'Ben',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm2',
        });
        // Counselor A has read s1 (so A has 1 unread: s2). Counselor B has read s2 (so B has 1 unread: s1).
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s1', {
          'readAt': t1,
        });
        db.seedDoc('counselor_inbox_reads/counselor-b/threads/s2', {
          'readAt': t1,
        });

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);

        expect(controller.activeUid, 'counselor-a');
        expect(controller.unreadCount(), 1);
        expect(controller.isThreadUnread('s2'), isTrue);
        expect(controller.isThreadUnread('s1'), isFalse);

        // Start markThreadRead for s2 as Counselor A, then switch account mid-flight to Counselor B
        final writeCountBeforeSwitch = db.writeLog.length;
        final pendingA = controller.markThreadRead(
          studentId: 's2',
          studentMessageAt: t1,
          expectedUid: 'counselor-a',
        );
        auth.switchUser('counselor-b');
        await Future<void>.delayed(Duration.zero);

        // Counselor B must ONLY see s1 unread, NOT s2 read leaked from A, and NO writes under counselor-b!
        expect(controller.activeUid, 'counselor-b');
        expect(controller.isThreadUnread('s1'), isTrue);
        expect(controller.isThreadUnread('s2'), isFalse);
        expect(
          db.writeLog
              .skip(writeCountBeforeSwitch)
              .where(
                (w) => w.path.contains('counselor_inbox_reads/counselor-b'),
              ),
          isEmpty,
        );

        // Complete pending write from A -> must NOT poison B's state
        db.completeAllPendingWrites();
        await pendingA;
        await Future<void>.delayed(Duration.zero);
        expect(controller.isThreadUnread('s1'), isTrue);

        // Calling markThreadRead with stale expectedUid 'counselor-a' while active is 'counselor-b' is a strict no-op!
        final writesBeforeStaleCall = db.writeLog.length;
        await controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t1,
          expectedUid: 'counselor-a',
        );
        expect(db.writeLog.length, writesBeforeStaleCall);

        // Sign out to null -> clears everything cleanly; then sign in null -> counselor-a
        auth.switchUser(null);
        await Future<void>.delayed(Duration.zero);
        expect(controller.activeUid, isNull);
        expect(controller.unreadCount(), 0);
        expect(controller.threads, isEmpty);

        auth.switchUser('counselor-a');
        await Future<void>.delayed(Duration.zero);
        expect(controller.activeUid, 'counselor-a');
      },
    );

    test(
      'stream error shows zero unread (no false badge) and recovers accurately on reconnection',
      () async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 0));
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);
        expect(controller.unreadCount(), 1);

        db.emitReceiptsError(
          'counselor-a',
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(controller.hasError, isTrue);
        expect(controller.unreadCount(), 0);

        // Recovery snapshot arrives
        db.emitReceipts('counselor-a');
        await Future<void>.delayed(Duration.zero);
        expect(controller.hasError, isFalse);
        expect(controller.unreadCount(), 1);
      },
    );

    test(
      'incoming student message during in-flight sendCounselorReply queues follow-up markThreadRead and drains on completion',
      () async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 0));
        final t2 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 7));
        db = FakeCounselorFirestore(
          initialServerTime: DateTime.utc(2026, 11, 22, 10, 0, 5),
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: true,
        );
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);
        expect(controller.unreadCount(), 1);

        final sendFuture = controller.sendCounselorReply(
          studentId: 's1',
          text: 'On it!',
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);
        expect(controller.unreadCount(), 0);

        // Newer incoming student message arrives while sendCounselorReply is in flight
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t2,
          'lastStudentMessageAt': t2,
          'lastStudentMessageId': 'm2',
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.unreadCount(), 1);

        // Caller marks thread read while sendCounselorReply is still in flight -> queued
        await controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t2,
          expectedUid: 'counselor-a',
        );
        expect(
          db.writeLog
              .where(
                (w) => w.path == 'counselor_inbox_reads/counselor-a/threads/s1',
              )
              .length,
          1, // only the initial batch receipt write so far
        );

        // Complete sendCounselorReply at 10:00:06 (< t2 10:00:07) -> drains follow-up markThreadRead!
        db.completeNextPendingWrite();
        await sendFuture;
        await Future<void>.delayed(Duration.zero);

        // Follow-up markThreadRead should now be in flight (pendingRead)
        expect(
          db.writeLog
              .where(
                (w) => w.path == 'counselor_inbox_reads/counselor-a/threads/s1',
              )
              .length,
          2,
        );
        expect(
          controller.stateFor('s1')?.status,
          CounselorReadStatus.pendingRead,
        );
        expect(controller.unreadCount(), 0);

        // Complete follow-up markThreadRead at 10:00:07 (>= t2) -> settled read
        db.completeNextPendingWrite();
        await Future<void>.delayed(Duration.zero);
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.read);
        expect(controller.unreadCount(), 0);
      },
    );

    test(
      'account switch or sign-out mid-flight during sendCounselorReply does not leak queued follow-ups',
      () async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 0));
        final t2 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 7));
        db = FakeCounselorFirestore(
          initialServerTime: DateTime.utc(2026, 11, 22, 10, 0, 5),
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: true,
        );
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);

        final sendFuture = controller.sendCounselorReply(
          studentId: 's1',
          text: 'Hello',
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);

        // Incoming message arrives and queues follow-up for counselor-a
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t2,
          'lastStudentMessageAt': t2,
          'lastStudentMessageId': 'm2',
        });
        await Future<void>.delayed(Duration.zero);
        await controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t2,
          expectedUid: 'counselor-a',
        );

        final writesBeforeSwitch = db.writeLog.length;
        // Switch to counselor-b before sendCounselorReply finishes
        auth.switchUser('counselor-b');
        await Future<void>.delayed(Duration.zero);

        db.completeAllPendingWrites();
        await sendFuture;
        await Future<void>.delayed(Duration.zero);

        // No writes under counselor-b, and counselor-b still sees s1 unread
        expect(
          db.writeLog
              .skip(writesBeforeSwitch)
              .where(
                (w) => w.path.contains('counselor_inbox_reads/counselor-b'),
              ),
          isEmpty,
        );
        expect(controller.activeUid, 'counselor-b');
        expect(controller.isThreadUnread('s1'), isTrue);
        expect(controller.unreadCount(), 1);

        // Also verify sign-out mid-flight drops queued follow-ups safely
        final sendB = controller.sendCounselorReply(
          studentId: 's1',
          text: 'Reply B',
          expectedUid: 'counselor-b',
        );
        await Future<void>.delayed(Duration.zero);
        final t3 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 12));
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t3,
          'lastStudentMessageAt': t3,
          'lastStudentMessageId': 'm3',
        });
        await Future<void>.delayed(Duration.zero);
        await controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t3,
          expectedUid: 'counselor-b',
        );
        final writesBeforeSignOut = db.writeLog.length;
        auth.switchUser(null);
        await Future<void>.delayed(Duration.zero);
        db.completeAllPendingWrites();
        await sendB;
        await Future<void>.delayed(Duration.zero);

        expect(db.writeLog.length, writesBeforeSignOut);
        expect(controller.activeUid, isNull);
        expect(controller.unreadCount(), 0);
      },
    );

    test(
      'PROBE 2A: overlapping markThreadRead(t1) completing first does not flash unread while sendCounselorReply(t2) is in flight',
      () async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 0));
        final t2 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 3));
        db = FakeCounselorFirestore(
          initialServerTime: DateTime.utc(2026, 11, 22, 10, 0, 1),
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: false,
        );
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);
        expect(controller.unreadCount(), 1);

        final markFuture = controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t1,
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          controller.stateFor('s1')?.status,
          CounselorReadStatus.pendingRead,
        );

        // Newer incoming message t2 arrives, then counselor starts reply covering t2.
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t2,
          'lastStudentMessageAt': t2,
          'lastStudentMessageId': 'm2',
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.unread);

        final sendFuture = controller.sendCounselorReply(
          studentId: 's1',
          text: 'Got your second message',
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          controller.stateFor('s1')?.status,
          CounselorReadStatus.pendingRead,
        );
        expect(controller.unreadCount(), 0);

        // markThreadRead(t1) completes at server time 10:00:02 (< t2) while reply is still in flight.
        db.completeNextPendingWrite();
        await markFuture;
        await Future<void>.delayed(Duration.zero);

        expect(
          controller.stateFor('s1')?.status,
          CounselorReadStatus.pendingRead,
        );
        expect(controller.unreadCount(), 0);

        // Reply completes at server time 10:00:04 (>= t2) -> settles cleanly to read.
        db.setServerClock(DateTime.utc(2026, 11, 22, 10, 0, 3));
        db.completeNextPendingWrite();
        await sendFuture;
        await Future<void>.delayed(Duration.zero);

        expect(controller.stateFor('s1')?.status, CounselorReadStatus.read);
        expect(controller.unreadCount(), 0);
      },
    );

    test(
      'PROBE 2B: overlapping markThreadRead(t1) failing does not flash unread while sendCounselorReply is in flight',
      () async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 0));
        db = FakeCounselorFirestore(
          initialServerTime: DateTime.utc(2026, 11, 22, 10, 0, 5),
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: false,
        );
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);

        final markFuture = controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t1,
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);

        final sendFuture = controller.sendCounselorReply(
          studentId: 's1',
          text: 'Reply in flight',
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          controller.stateFor('s1')?.status,
          CounselorReadStatus.pendingRead,
        );

        // First write (markThreadRead) fails while sendCounselorReply is still pending.
        db.failNextPendingWrite(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        );
        await expectLater(markFuture, throwsA(isA<FirebaseException>()));
        await Future<void>.delayed(Duration.zero);

        expect(
          controller.stateFor('s1')?.status,
          CounselorReadStatus.pendingRead,
        );
        expect(controller.unreadCount(), 0);

        // Reply completes -> settles to read.
        db.completeNextPendingWrite();
        await sendFuture;
        await Future<void>.delayed(Duration.zero);

        expect(controller.stateFor('s1')?.status, CounselorReadStatus.read);
        expect(controller.unreadCount(), 0);
      },
    );

    test(
      'PROBE 2D: queued follow-up markThreadRead does not drain until ALL overlapping writes complete',
      () async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 0));
        final t2 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 5));
        db = FakeCounselorFirestore(
          initialServerTime: DateTime.utc(2026, 11, 22, 10, 0, 1),
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: false,
        );
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);

        final markFuture = controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t1,
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);

        final sendFuture = controller.sendCounselorReply(
          studentId: 's1',
          text: 'Hello',
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);
        // 1 receipt from markThreadRead + 3 batch writes from sendCounselorReply = 4 writes.
        expect(db.writeLog, hasLength(4));

        // Incoming message t2 arrives while both writes are in flight -> queued, not executed yet.
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t2,
          'lastStudentMessageAt': t2,
          'lastStudentMessageId': 'm2',
        });
        await Future<void>.delayed(Duration.zero);

        await controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t2,
          expectedUid: 'counselor-a',
        );
        expect(db.writeLog, hasLength(4));

        // First write finishes while sendCounselorReply is still in flight -> must NOT drain follow-up yet!
        db.completeNextPendingWrite();
        await markFuture;
        await Future<void>.delayed(Duration.zero);
        expect(db.writeLog, hasLength(4));

        // Now sendCounselorReply finishes (at 10:00:03 < t2 10:00:05) -> drains follow-up markThreadRead(t2)!
        db.completeNextPendingWrite();
        await sendFuture;
        await Future<void>.delayed(Duration.zero);
        expect(db.writeLog, hasLength(5));
        expect(
          controller.stateFor('s1')?.status,
          CounselorReadStatus.pendingRead,
        );

        // Follow-up markThreadRead(t2) finishes at 10:00:05 (>= t2) -> settles to read.
        db.setServerClock(DateTime.utc(2026, 11, 22, 10, 0, 4));
        db.completeNextPendingWrite();
        await Future<void>.delayed(Duration.zero);
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.read);
        expect(controller.unreadCount(), 0);
      },
    );

    test(
      'post-commit / pre-snapshot window (Flutter Web hasPendingWrites == false) keeps pendingRead until receipt snapshot arrives',
      () async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 0));
        final t2 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 10));
        db = FakeCounselorFirestore(
          initialServerTime: DateTime.utc(2026, 11, 22, 10, 0, 5),
          deferWriteCompletion: false,
          simulatePendingServerTimestamp: false,
          deferSnapshotNotifications: true,
        );
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);
        expect(controller.unreadCount(), 1);

        final observedCounts = <int>[];
        controller.addListener(
          () => observedCounts.add(controller.unreadCount()),
        );

        // Commit resolves immediately while snapshot delivery is still deferred (hasPendingWrites == false).
        await controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t1,
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);

        expect(db.pendingSnapshotCount, 1);
        expect(
          controller.stateFor('s1')?.status,
          CounselorReadStatus.pendingRead,
        );
        expect(controller.unreadCount(), 0);
        expect(controller.needsMarkRead('s1'), isFalse);
        expect(observedCounts, everyElement(0));

        // Duplicate markThreadRead call during the pre-snapshot window is a no-op.
        await controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t1,
          expectedUid: 'counselor-a',
        );
        expect(db.writeLog, hasLength(1));

        // Receipt snapshot finally arrives -> settles cleanly to read.
        db.flushPendingSnapshots();
        await Future<void>.delayed(Duration.zero);
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.read);
        expect(controller.unreadCount(), 0);

        // If a newer message t2 arrives during the pre-snapshot gap of a subsequent mark-read,
        // it immediately transitions to unread and allows marking t2 read.
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t2,
          'lastStudentMessageAt': t2,
          'lastStudentMessageId': 'm2',
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.unread);
        expect(controller.needsMarkRead('s1'), isTrue);

        await controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: t2,
          expectedUid: 'counselor-a',
        );
        expect(
          controller.stateFor('s1')?.status,
          CounselorReadStatus.pendingRead,
        );
        expect(controller.needsMarkRead('s1'), isFalse);

        final t3 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0, 20));
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t3,
          'lastStudentMessageAt': t3,
          'lastStudentMessageId': 'm3',
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.unread);
        expect(controller.needsMarkRead('s1'), isTrue);

        db.flushPendingSnapshots();
        await Future<void>.delayed(Duration.zero);
        expect(controller.stateFor('s1')?.status, CounselorReadStatus.unread);
      },
    );

    group('counselorReadAt for the student Read indicator', () {
      final tStudent = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
      void seedThread() => db.seedDoc('counselor_threads/s1', {
        'userId': 's1',
        'collegeId': 'CITE',
        'studentName': 'Ana',
        'updatedAt': tStudent,
        'lastStudentMessageAt': tStudent,
        'lastStudentMessageId': 'm1',
      });

      test('markThreadRead stamps counselorReadAt after the receipt', () async {
        seedThread();
        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await Future<void>.delayed(Duration.zero);
        await controller.markThreadRead(
          studentId: 's1',
          studentMessageAt: tStudent,
          expectedUid: 'counselor-a',
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          db.getEntry('counselor_threads/s1')?.data['counselorReadAt'],
          isA<Timestamp>(),
        );
      });

      test(
        'a refused counselorReadAt update leaves the receipt and badge intact',
        () async {
          seedThread();
          db.updateErrors['counselor_threads/s1'] = FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
          final controller = CounselorInboxUnreadController(
            firestore: db,
            auth: auth,
          );
          addTearDown(controller.dispose);
          await Future<void>.delayed(Duration.zero);
          await controller.markThreadRead(
            studentId: 's1',
            studentMessageAt: tStudent,
            expectedUid: 'counselor-a',
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            db.getEntry('counselor_inbox_reads/counselor-a/threads/s1'),
            isNotNull,
          );
          expect(controller.stateFor('s1')?.status, CounselorReadStatus.read);
          expect(controller.unreadCount(), 0);
        },
      );

      test(
        'sendCounselorReply commits and stamps counselorReadAt, and still commits when refused',
        () async {
          seedThread();
          final controller = CounselorInboxUnreadController(
            firestore: db,
            auth: auth,
          );
          addTearDown(controller.dispose);
          await Future<void>.delayed(Duration.zero);
          await controller.sendCounselorReply(
            studentId: 's1',
            text: 'Please visit PACC on Monday.',
            expectedUid: 'counselor-a',
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            db.getEntry('counselor_threads/s1')?.data['counselorReadAt'],
            isA<Timestamp>(),
          );
          expect(db.committedBatches.last, hasLength(3));

          db.updateErrors['counselor_threads/s1'] = FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
          await controller.sendCounselorReply(
            studentId: 's1',
            text: 'See you then.',
            expectedUid: 'counselor-a',
          );
          expect(db.committedBatches, hasLength(2));
        },
      );
    });
  });
}
