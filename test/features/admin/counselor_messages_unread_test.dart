import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/inquiry_sla.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/screens/counselor_messages_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/counseling/widgets/counselor_unread_badges.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/app_notification_model.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/appointment_queue_item.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

import '../counseling/fake_counselor_inbox_firebase.dart';

class _PortalRoleRepo extends AdminPortalRepository {
  _PortalRoleRepo(this.role, {this.uid = 'user-1'});

  final AccessRole role;
  final String uid;
  final _notifications =
      StreamController<List<AppNotificationModel>>.broadcast();
  final _appointments = StreamController<List<AppointmentModel>>.broadcast();
  final _myAppointments = StreamController<List<AppointmentModel>>.broadcast();
  final _inquiries = StreamController<List<AdminInquiryModel>>.broadcast();

  void dispose() {
    _notifications.close();
    _appointments.close();
    _myAppointments.close();
    _inquiries.close();
  }

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => false;

  @override
  String? get currentUserId => uid;

  @override
  User? get currentAuthUser => null;

  @override
  Stream<List<AppNotificationModel>> watchPortalNotifications() =>
      _notifications.stream;

  @override
  Stream<List<AppointmentQueueItem>> watchPortalAppointmentQueue() =>
      Stream<List<AppointmentQueueItem>>.value(const []).asBroadcastStream();

  @override
  Stream<PaccAvailabilityModel?> watchPaccAvailability() =>
      Stream<PaccAvailabilityModel?>.value(null).asBroadcastStream();

  @override
  Stream<List<AppointmentModel>> watchAppointments() async* {
    yield const [];
    yield* _appointments.stream;
  }

  @override
  Stream<List<AppointmentModel>> watchMyAssignedAppointments() async* {
    yield const [];
    yield* _myAppointments.stream;
  }

  @override
  Stream<List<AdminInquiryModel>> watchInquiries() async* {
    yield const [];
    yield* _inquiries.stream;
  }

  @override
  Stream<List<AdminInquiryModel>> watchInquiryStatuses() async* {
    yield const [];
    yield* _inquiries.stream;
  }

  @override
  Stream<List<UserModel>> watchUsers() =>
      Stream<List<UserModel>>.value(const []).asBroadcastStream();

  @override
  Stream<InquirySla> watchInquirySla() =>
      Stream<InquirySla>.value(const InquirySla(hours: null))
          .asBroadcastStream();
}

void main() {
  group('CounselorMessagesPage unread & read-receipt behavior', () {
    late FakeCounselorFirestore db;
    late FakeCounselorAuth auth;

    setUp(() {
      db = FakeCounselorFirestore();
      auth = FakeCounselorAuth(initialUid: 'counselor-a');
      db.seedDoc('colleges/CITE', {'code': 'CITE', 'name': 'Engineering', 'active': true});
      db.seedDoc('colleges/CBA', {'code': 'CBA', 'name': 'Business', 'active': true});
    });

    tearDown(() async {
      await db.dispose();
      await auth.dispose();
    });

    testWidgets(
      'multiple conversations show accurate badges, delayed receipts never flash 1, and tapping already-read thread performs zero writes',
      (tester) async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        final t2 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 5));

        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Read Student',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_threads/s1/messages/m1', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Already read hello',
          'createdAt': t1,
        });
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s1', {
          'readAt': t1,
        });

        db.seedDoc('counselor_threads/s2', {
          'userId': 's2',
          'collegeId': 'CBA',
          'studentName': 'Unread Student',
          'updatedAt': t2,
          'lastStudentMessageAt': t2,
          'lastStudentMessageId': 'm2',
        });
        db.seedDoc('counselor_threads/s2/messages/m2', {
          'senderId': 's2',
          'senderRole': 'user',
          'text': 'New unread message',
          'createdAt': t2,
        });

        db.holdReceiptsInitialEmission = true;

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: CounselorMessagesPage(firestore: db, auth: auth),
            ),
          ),
        );
        await tester.pump();

        // Waiting on receipts -> zero false '1' badges
        expect(find.byType(UnreadCountBadge), findsNothing);

        db.emitReceipts('counselor-a');
        await tester.pumpAndSettle();

        expect(find.text('Read Student'), findsOneWidget);
        expect(find.text('Unread Student'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);

        // Tap already-read thread s1 -> must perform ZERO Firestore writes!
        final writesBefore = db.writeLog.length;
        await tester.tap(find.text('Read Student'));
        await tester.pumpAndSettle();
        expect(db.writeLog.length, writesBefore);
        expect(find.text('Already read hello'), findsOneWidget);
      },
    );

    testWidgets(
      'rapid switching S1 -> S2 cancels S1 mark-read and still marks S2 read without single-slot lock drop',
      (tester) async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        final t2 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 5));
        db = FakeCounselorFirestore(
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: true,
        );
        db.seedDoc('colleges/CITE', {'code': 'CITE', 'name': 'Engineering', 'active': true});
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Student One',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_threads/s1/messages/m1', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Msg 1',
          'createdAt': t1,
        });
        db.seedDoc('counselor_threads/s2', {
          'userId': 's2',
          'collegeId': 'CITE',
          'studentName': 'Student Two',
          'updatedAt': t2,
          'lastStudentMessageAt': t2,
          'lastStudentMessageId': 'm2',
        });
        db.seedDoc('counselor_threads/s2/messages/m2', {
          'senderId': 's2',
          'senderRole': 'user',
          'text': 'Msg 2',
          'createdAt': t2,
        });
        db.holdMessagesInitialEmission = true;

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: CounselorMessagesPage(firestore: db, auth: auth),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap S1, then immediately tap S2 while S1 messages/write are pending
        await tester.tap(find.text('Student One'));
        await tester.pump();
        await tester.tap(find.text('Student Two'));
        await tester.pump();

        db.emitMessages('s2');
        await tester.pump();
        db.completeAllPendingWrites();
        await tester.pumpAndSettle();

        // S2 must be marked read (NOT dropped by a global _readingUser lock!)
        expect(
          db.writeLog.any(
            (w) => w.path == 'counselor_inbox_reads/counselor-a/threads/s2',
          ),
          isTrue,
        );
        expect(find.text('Msg 2'), findsOneWidget);
      },
    );

    testWidgets(
      'open thread receiving a new incoming student message marks read safely without marking other threads',
      (tester) async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        final t2 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 5));
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Open Student',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_threads/s1/messages/m1', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'First',
          'createdAt': t1,
        });
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s1', {
          'readAt': t1,
        });
        db.seedDoc('counselor_threads/s2', {
          'userId': 's2',
          'collegeId': 'CITE',
          'studentName': 'Other Unread',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm2',
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: CounselorMessagesPage(firestore: db, auth: auth),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Student'));
        await tester.pumpAndSettle();

        // Incoming message arrives on open thread s1
        db.putAndEmit('counselor_threads/s1/messages/m3', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Follow up while open',
          'createdAt': t2,
        });
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Open Student',
          'updatedAt': t2,
          'lastStudentMessageAt': t2,
          'lastStudentMessageId': 'm3',
        });
        await tester.pumpAndSettle();

        expect(find.text('Follow up while open'), findsOneWidget);
        // s1 should have a receipt write; s2 must remain unread and untouched
        expect(
          db.writeLog.any(
            (w) => w.path == 'counselor_inbox_reads/counselor-a/threads/s1',
          ),
          isTrue,
        );
        expect(
          db.writeLog.any(
            (w) => w.path == 'counselor_inbox_reads/counselor-a/threads/s2',
          ),
          isFalse,
        );
        expect(find.text('1'), findsOneWidget); // only s2 still has badge
      },
    );

    testWidgets(
      'counselor reply uses atomic 3-write batch and shows zero false badge during or after send',
      (tester) async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        db = FakeCounselorFirestore(
          initialServerTime: DateTime.utc(2026, 11, 22, 10, 0, 5),
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: true,
        );
        db.seedDoc('colleges/CITE', {'code': 'CITE', 'name': 'Engineering', 'active': true});
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Student One',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_threads/s1/messages/m1', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Question',
          'createdAt': t1,
        });
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s1', {
          'readAt': t1,
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: CounselorMessagesPage(firestore: db, auth: auth),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Student One'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'Counselor answer');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();

        // While batch is pending (readAt == null, hasPendingWrites == true): zero false badge
        expect(find.text('1'), findsNothing);

        db.completeAllPendingWrites();
        await tester.pumpAndSettle();

        expect(find.text('1'), findsNothing);
        expect(db.committedBatches, hasLength(1));
        expect(db.committedBatches.single, hasLength(3));
      },
    );

    testWidgets(
      'account switching (Counselor A -> Counselor B -> null) clears selection, draft, and unread without null crashes',
      (tester) async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Student One',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_threads/s1/messages/m1', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Msg 1',
          'createdAt': t1,
        });
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s1', {
          'readAt': t1,
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: CounselorMessagesPage(firestore: db, auth: auth),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Student One'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Draft for A');
        expect(find.text('1'), findsNothing);

        // Switch to Counselor B -> draft & selection clear, B sees unread 1
        auth.switchUser('counselor-b');
        await tester.pumpAndSettle();

        expect(find.text('Select a conversation'), findsOneWidget);
        expect(find.text('Draft for A'), findsNothing);
        expect(find.text('1'), findsOneWidget);

        // Switch to null (sign-out gap) -> no currentUser!.uid null exception!
        auth.switchUser(null);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('1'), findsNothing);
      },
    );

    testWidgets(
      'inbox stream error renders sanitized message without leaking internal exception details and recovers',
      (tester) async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Student One',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: CounselorMessagesPage(firestore: db, auth: auth),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Student One'), findsOneWidget);

        // Emit raw internal exception -> must NOT render raw exception or stack details
        db.emitThreadsError(
          Exception('firestore internal stack at projects/mindmate/databases/default'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Unable to load inbox.'), findsOneWidget);
        expect(find.textContaining('firestore internal stack'), findsNothing);
        expect(find.textContaining('projects/mindmate'), findsNothing);

        // Emit FirebaseException with permission-denied -> shows safe mapped message
        db.emitThreadsError(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Missing or insufficient permissions at /secret/path',
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('You do not have permission to complete this action.'),
          findsOneWidget,
        );
        expect(find.textContaining('/secret/path'), findsNothing);

        // Recovery snapshot restores thread list
        db.emitThreads();
        await tester.pumpAndSettle();
        expect(find.text('Student One'), findsOneWidget);
      },
    );

    testWidgets(
      'persistent markThreadRead failure while thread is open does not cause retry storm, preserves unread badge, and retries on explicit tap or newer message',
      (tester) async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        final t2 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 5));

        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_threads/s1/messages/m1', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Need help',
          'createdAt': t1,
        });
        db.persistentWriteError = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Denied',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: CounselorMessagesPage(firestore: db, auth: auth),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('1'), findsOneWidget);

        // Tap once and pump 8 frames -> must attempt at most 1 write and keep badge at '1'.
        await tester.tap(find.text('Ana'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(
          db.writeLog
              .where(
                (w) => w.path == 'counselor_inbox_reads/counselor-a/threads/s1',
              )
              .length,
          1,
        );
        expect(find.text('1'), findsOneWidget);
        expect(find.text('Need help'), findsOneWidget);

        // Explicit re-tap triggers 1 fresh attempt (still no loop across 8 frames).
        await tester.tap(find.text('Ana'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          db.writeLog
              .where(
                (w) => w.path == 'counselor_inbox_reads/counselor-a/threads/s1',
              )
              .length,
          2,
        );
        expect(find.text('1'), findsOneWidget);

        // Newer incoming student message (t2 > t1) triggers 1 fresh attempt (still no loop).
        db.putAndEmit('counselor_threads/s1/messages/m2', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Are you there?',
          'createdAt': t2,
        });
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana',
          'updatedAt': t2,
          'lastStudentMessageAt': t2,
          'lastStudentMessageId': 'm2',
        });
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          db.writeLog
              .where(
                (w) => w.path == 'counselor_inbox_reads/counselor-a/threads/s1',
              )
              .length,
          3,
        );
        expect(find.text('1'), findsOneWidget);

        // When permissions recover and user explicitly re-taps, receipt succeeds and clears badge.
        db.persistentWriteError = null;
        await tester.tap(find.text('Ana'));
        await tester.pumpAndSettle();
        expect(
          db.writeLog
              .where(
                (w) => w.path == 'counselor_inbox_reads/counselor-a/threads/s1',
              )
              .length,
          4,
        );
        expect(find.text('1'), findsNothing);
      },
    );

    testWidgets(
      'deactivating selected college falls back to All Colleges in both dropdown and thread list',
      (tester) async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Cite Student',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_threads/s2', {
          'userId': 's2',
          'collegeId': 'CBA',
          'studentName': 'Cba Student',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm2',
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: CounselorMessagesPage(firestore: db, auth: auth),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Filter to CITE
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('CITE — Engineering').last);
        await tester.pumpAndSettle();

        expect(find.text('Cite Student'), findsOneWidget);
        expect(find.text('Cba Student'), findsNothing);

        // Deactivate CITE -> dropdown displays All Colleges and thread list shows all threads.
        db.putAndEmit('colleges/CITE', {
          'code': 'CITE',
          'name': 'Engineering',
          'active': false,
        });
        await tester.pumpAndSettle();

        expect(find.text('All Colleges'), findsOneWidget);
        expect(find.text('Cite Student'), findsOneWidget);
        expect(find.text('Cba Student'), findsOneWidget);
      },
    );

    testWidgets(
      'in-flight send failure from previous UID does not reset new UID sending state or show stale error SnackBar',
      (tester) async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        db = FakeCounselorFirestore(
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: true,
        );
        db.seedDoc('colleges/CITE', {
          'code': 'CITE',
          'name': 'Engineering',
          'active': true,
        });
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Student One',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_threads/s1/messages/m1', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Hello',
          'createdAt': t1,
        });
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s1', {
          'readAt': t1,
        });
        db.seedDoc('counselor_inbox_reads/counselor-b/threads/s1', {
          'readAt': t1,
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: CounselorMessagesPage(firestore: db, auth: auth),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Counselor A opens s1 and starts sending.
        await tester.tap(find.text('Student One'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Reply from A');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        expect(db.pendingWrites, hasLength(1));

        // Switch account to Counselor B while A's send is still in flight.
        auth.switchUser('counselor-b');
        await tester.pumpAndSettle();

        // Counselor B opens s1 and starts sending.
        await tester.tap(find.text('Student One'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Reply from B');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        expect(db.pendingWrites, hasLength(2));

        // Counselor A's old send fails!
        db.failNextPendingWrite(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        );
        await tester.pumpAndSettle();

        // Counselor B must NOT see A's stale error SnackBar, and B's send button must stay disabled (sending == true).
        expect(
          find.text('Unable to send message. Check permissions or connection.'),
          findsNothing,
        );
        final sendButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.send),
        );
        expect(sendButton.onPressed, isNull);

        // Complete Counselor B's send cleanly.
        db.completeAllPendingWrites();
        await tester.pumpAndSettle();
      },
    );
  });

  group('Badge surface parity & role isolation', () {
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
      'expanded sidebar, collapsed sidebar (76px/80px), and CounselorInquiryWorkspace Messages tab share exact unread count without overflow',
      (tester) async {
        addTearDown(tester.view.reset);
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        for (var i = 0; i < 3; i++) {
          db.seedDoc('counselor_threads/s$i', {
            'userId': 's$i',
            'collegeId': 'CITE',
            'studentName': 'Student $i',
            'updatedAt': t1,
            'lastStudentMessageAt': t1,
            'lastStudentMessageId': 'm$i',
          });
        }

        final controller = CounselorInboxUnreadController(
          firestore: db,
          auth: auth,
        );
        addTearDown(controller.dispose);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(controller.unreadCount(), 3);

        // 1. Collapsed sidebar at 76px and 80px
        for (final width in [76.0, 80.0]) {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            MaterialApp(
              theme: AdminTheme.data,
              home: CounselorInboxScope(
                notifier: controller,
                child: Scaffold(
                  body: SizedBox(
                    width: width,
                    height: 900,
                    child: PortalWorkspaceNavigation(
                      page: AdminPortalPage.dashboard,
                      onChanged: (_) {},
                      collapsed: true,
                      accessRole: AccessRole.counselor,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('3'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        // 2. Expanded sidebar + CounselorInquiryWorkspace Messages tab inside AdminPortalHome
        tester.view.physicalSize = const Size(1280, 1400);
        tester.view.devicePixelRatio = 1;
        final repo = _PortalRoleRepo(AccessRole.counselor, uid: 'counselor-a');
        addTearDown(repo.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: AdminPortalHome(
              repository: repo,
              counselorInboxController: controller,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('3'), findsOneWidget);

        // Navigate to Inquiries -> Messages tab also shows '3'
        await tester.ensureVisible(find.text('Inquiries'));
        await tester.tap(find.text('Inquiries'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('Messages'), findsOneWidget);
        expect(find.text('3'), findsNWidgets(2));

        // Mark all 3 read -> all badges disappear
        for (var i = 0; i < 3; i++) {
          await controller.markThreadRead(
            studentId: 's$i',
            studentMessageAt: t1,
            expectedUid: 'counselor-a',
          );
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('3'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'non-counselor roles (admin, portalStaff) do NOT display badge or subscribe to counselor inbox streams',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        for (final role in [AccessRole.admin, AccessRole.portalStaff]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AdminTheme.data,
              home: PortalWorkspaceNavigation(
                page: AdminPortalPage.dashboard,
                onChanged: (_) {},
                collapsed: false,
                accessRole: role,
                isSuperAdmin: role == AccessRole.admin,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(CounselorInboxUnreadBadge), findsNothing);
        }
        expect(db.subscribedCollectionPaths, isEmpty);
      },
    );
  });
}
