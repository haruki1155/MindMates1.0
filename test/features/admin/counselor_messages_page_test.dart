import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/counselor_messages_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/counselor_inquiry_workspace.dart';
import 'package:mind_mates/features/counseling/widgets/counselor_unread_badges.dart';

import '../counseling/fake_counselor_inbox_firebase.dart';

void main() {
  group('CounselorMessagesPage UI, bubbles, states & scroll', () {
    late FakeCounselorFirestore db;
    late FakeCounselorAuth auth;

    // 2026-11-22 12:00 UTC == 2026-11-22 20:00 Asia/Manila
    final fixedNow = DateTime.utc(2026, 11, 22, 12, 0);

    setUp(() {
      db = FakeCounselorFirestore(
        initialServerTime: DateTime.utc(2026, 11, 22, 10, 10),
      );
      auth = FakeCounselorAuth(initialUid: 'counselor-a');
      db.seedDoc('colleges/CITE', {
        'code': 'CITE',
        'name': 'College of Information Technology and Engineering',
        'active': true,
      });
      db.seedDoc('colleges/CBA', {
        'code': 'CBA',
        'name': 'College of Business and Accountancy',
        'active': true,
      });
    });

    tearDown(() async {
      await db.dispose();
      await auth.dispose();
    });

    Widget buildHarness({
      Key? pageKey,
      Size? size,
      double textScale = 1.0,
      bool embedded = false,
      int messagePageSize = 30,
    }) {
      final page = CounselorMessagesPage(
        key: pageKey,
        embedded: embedded,
        firestore: db,
        auth: auth,
        messagePageSize: messagePageSize,
        now: () => fixedNow,
      );
      final Widget child = textScale == 1.0
          ? page
          : Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: page,
              ),
            );
      return MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(body: child),
      );
    }

    testWidgets(
      'conversation list shows unread/selected highlighting, metadata, isExpanded dropdown, and Task 4 read/unread sync',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final tOld = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 9, 0));
        final tNew = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 5));

        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana Reyes',
          'updatedAt': tNew,
          'lastStudentMessageAt': tNew,
          'lastStudentMessageId': 'm2',
        });
        db.seedDoc('counselor_threads/s1/messages/m2', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Hello counselor',
          'createdAt': tNew,
        });

        db.seedDoc('counselor_threads/s2', {
          'userId': 's2',
          'collegeId': 'CBA',
          'studentName': 'Ben Cruz',
          'updatedAt': tOld,
          'lastStudentMessageAt': tOld,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_threads/s2/messages/m1', {
          'senderId': 's2',
          'senderRole': 'user',
          'text': 'Already answered',
          'createdAt': tOld,
        });
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s2', {
          'readAt': tOld,
        });

        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        // Header summary & expanded dropdown
        expect(find.text('Conversations'), findsOneWidget);
        expect(find.text('2 total'), findsOneWidget);
        expect(find.text('1 unread'), findsOneWidget);
        final dropdown = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>),
        );
        expect(dropdown.isExpanded, isTrue);

        // Unread row bold & badge; read row non-bold & no badge
        final anaText = tester.widget<Text>(find.text('Ana Reyes'));
        expect(anaText.style?.fontWeight, FontWeight.w700);
        final benText = tester.widget<Text>(find.text('Ben Cruz'));
        expect(benText.style?.fontWeight, FontWeight.w600);
        expect(find.byType(UnreadCountBadge), findsNWidgets(2));
        expect(find.text('1'), findsOneWidget);
        expect(find.text('Unread'), findsOneWidget);
        expect(find.text('Read'), findsOneWidget);
        expect(find.text('CITE'), findsOneWidget);
        expect(find.text('CBA'), findsOneWidget);
        // Manila activity time (10:05 UTC -> 6:05 PM)
        expect(find.text('6:05 PM'), findsOneWidget);

        // Select Ana Reyes -> highlights tile and marks read via Task 4
        await tester.tap(find.text('Ana Reyes'));
        await tester.pumpAndSettle();

        expect(find.text('Conversation with Ana Reyes'), findsOneWidget);
        expect(find.text('1'), findsNothing);
        expect(find.text('1 unread'), findsNothing);

        // Verify selected card uses accentFaint & accentStrong border
        final anaTileMaterial = tester.widget<Material>(
          find
              .ancestor(
                of: find.text('Ana Reyes'),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(anaTileMaterial.color, AdminColors.accentFaint);
        final shape = anaTileMaterial.shape as RoundedRectangleBorder;
        expect(shape.side.color, AdminColors.accentStrong);

        // Incoming student message on unselected s2 flips s2 back to Unread
        final tIncoming = Timestamp.fromDate(
          DateTime.utc(2026, 11, 22, 10, 15),
        );
        db.putAndEmit('counselor_threads/s2', {
          'userId': 's2',
          'collegeId': 'CBA',
          'studentName': 'Ben Cruz',
          'updatedAt': tIncoming,
          'lastStudentMessageAt': tIncoming,
          'lastStudentMessageId': 'm3',
        });
        await tester.pumpAndSettle();
        expect(find.text('1'), findsOneWidget);
        expect(find.text('1 unread'), findsOneWidget);
      },
    );

    testWidgets(
      'renders distinct Counselor and Student bubbles, stored timestamps, date pills, and strictly excludes read receipts and MindAid history',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        // Seed unrelated MindAid history to verify strict isolation
        db.seedDoc('mind_aid_messages/s1_ai', {
          'userId': 's1',
          'text': 'MindAid secret AI prompt',
          'senderRole': 'assistant',
        });

        final nov18 = Timestamp.fromDate(
          DateTime.utc(2026, 11, 18, 2, 15),
        ); // 10:15 AM Manila
        final yesterday = Timestamp.fromDate(
          DateTime.utc(2026, 11, 21, 9, 30),
        ); // 5:30 PM Manila
        final todayStudent = Timestamp.fromDate(
          DateTime.utc(2026, 11, 22, 10, 0),
        ); // 6:00 PM Manila
        final todayCounselor = Timestamp.fromDate(
          DateTime.utc(2026, 11, 22, 10, 5),
        ); // 6:05 PM Manila

        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana Reyes',
          'updatedAt': todayCounselor,
          'lastStudentMessageAt': todayStudent,
          'lastStudentMessageId': 'm3',
          'lastCounselorMessageAt': todayCounselor,
        });
        db.seedDoc('counselor_threads/s1/messages/m1', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Older student note',
          'createdAt': nov18,
        });
        db.seedDoc('counselor_threads/s1/messages/m2', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Yesterday question',
          'createdAt': yesterday,
        });
        db.seedDoc('counselor_threads/s1/messages/m3', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Student message today',
          'createdAt': todayStudent,
        });
        db.seedDoc('counselor_threads/s1/messages/m4', {
          'senderId': 'counselor-a',
          'senderRole': 'counselor',
          'text': 'Counselor reply today',
          'createdAt': todayCounselor,
        });
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s1', {
          'readAt': todayStudent,
        });

        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Ana Reyes'));
        await tester.pumpAndSettle();

        // Date separators
        expect(find.text('Nov 18, 2026'), findsOneWidget);
        expect(find.text('Yesterday'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);

        // Stored timestamps & sender labels
        expect(find.text('Ana Reyes · 10:15 AM'), findsOneWidget);
        expect(find.text('Ana Reyes · 5:30 PM'), findsOneWidget);
        expect(find.text('Ana Reyes · 6:00 PM'), findsOneWidget);
        expect(find.text('Counselor · 6:05 PM'), findsOneWidget);

        // Distinct alignment & surface colors
        final counselorAlign = tester.widget<Align>(
          find
              .ancestor(
                of: find.text('Counselor reply today'),
                matching: find.byType(Align),
              )
              .first,
        );
        expect(counselorAlign.alignment, Alignment.centerRight);

        final studentAlign = tester.widget<Align>(
          find
              .ancestor(
                of: find.text('Student message today'),
                matching: find.byType(Align),
              )
              .first,
        );
        expect(studentAlign.alignment, Alignment.centerLeft);

        final counselorBubble = tester.widget<Container>(
          find
              .ancestor(
                of: find.text('Counselor reply today'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(
          (counselorBubble.decoration as BoxDecoration).color,
          AdminColors.ink,
        );
        final counselorText = tester.widget<Text>(
          find.text('Counselor reply today'),
        );
        expect(counselorText.style?.color, Colors.white);

        final studentBubble = tester.widget<Container>(
          find
              .ancestor(
                of: find.text('Student message today'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(
          (studentBubble.decoration as BoxDecoration).color,
          AdminColors.surface,
        );

        // Sender-only 'Sent' indicator
        expect(find.text('Sent'), findsOneWidget);
        expect(find.byIcon(Icons.check), findsOneWidget);

        // Strict exclusions: no per-message read receipts & no MindAid history
        expect(find.text('Seen'), findsNothing);
        expect(find.text('Delivered'), findsNothing);
        expect(find.byIcon(Icons.done_all), findsNothing);
        expect(find.textContaining('MindAid secret AI prompt'), findsNothing);
        expect(
          db.subscribedCollectionPaths.any((p) => p.contains('mind_aid')),
          isFalse,
        );
      },
    );

    testWidgets(
      'supports loading, empty, sending, sent, failed + retry/dismiss, and pending timestamp past descending page limit',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        db = FakeCounselorFirestore(
          initialServerTime: DateTime.utc(2026, 11, 22, 10, 30),
          deferWriteCompletion: true,
          simulatePendingServerTimestamp: true,
        );
        db.seedDoc('colleges/CITE', {
          'code': 'CITE',
          'name': 'Engineering',
          'active': true,
        });
        db.holdThreadsInitialEmission = true;

        await tester.pumpWidget(buildHarness(messagePageSize: 5));
        await tester.pump();

        // Loading inbox
        expect(find.text('Loading conversations…'), findsOneWidget);

        db.emitThreads();
        await tester.pumpAndSettle();

        // Empty inbox
        expect(find.text('No messages'), findsOneWidget);
        expect(find.text('Select a conversation'), findsOneWidget);

        // Seed empty thread + populated thread (> pageSize = 5 messages)
        db.putAndEmit('counselor_threads/s_empty', {
          'userId': 's_empty',
          'collegeId': 'CITE',
          'studentName': 'Empty Student',
          'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 22, 9, 0)),
        });
        await tester.pumpAndSettle();

        await tester.tap(find.text('Empty Student'));
        await tester.pumpAndSettle();
        expect(
          find.text('No messages in this conversation yet.'),
          findsOneWidget,
        );

        // Switch to populated thread with 8 messages (> pageSize 5)
        final baseTime = DateTime.utc(2026, 11, 22, 9, 0);
        for (var i = 1; i <= 8; i++) {
          db.seedDoc('counselor_threads/s1/messages/m$i', {
            'senderId': 's1',
            'senderRole': 'user',
            'text': 'Student msg $i',
            'createdAt': Timestamp.fromDate(baseTime.add(Duration(minutes: i))),
          });
        }
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana Reyes',
          'updatedAt': Timestamp.fromDate(
            baseTime.add(const Duration(minutes: 8)),
          ),
          'lastStudentMessageAt': Timestamp.fromDate(
            baseTime.add(const Duration(minutes: 8)),
          ),
          'lastStudentMessageId': 'm8',
        });
        await tester.pumpAndSettle();

        await tester.tap(find.text('Ana Reyes'));
        await tester.pumpAndSettle();
        // Complete mark-read write
        db.completeAllPendingWrites();
        await tester.pumpAndSettle();

        // 1. Sending state: even with 8 messages (> limit 5) where pending
        // serverTimestamp (null) sorts out of descending limit(5), optimistic
        // bubble stays visible with 'Sending…'!
        await tester.enterText(find.byType(TextField), 'Optimistic reply');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('counselor_thread_message_list')),
            matching: find.text('Optimistic reply'),
          ),
          findsOneWidget,
        );
        expect(find.text('Sending…'), findsAtLeastNWidgets(1));
        expect(find.text('Sending reply…'), findsOneWidget);
        final sendBtn = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.send),
        );
        expect(sendBtn.onPressed, isNull);

        // 2. Fail write -> sanitized SnackBar, draft preserved, failed bubble + Retry/Dismiss
        db.failNextPendingWrite(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Unable to send message. Check permissions or connection.'),
          findsOneWidget,
        );
        expect(find.text('Failed to send'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Dismiss'), findsOneWidget);
        // Draft still in TextField
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller?.text, 'Optimistic reply');

        // 3. Retry succeeds -> clears matching draft, single bubble, transitions to Sent
        await tester.tap(find.text('Retry'));
        await tester.pump();
        db.completeAllPendingWrites();
        await tester.pumpAndSettle();

        expect(find.text('Failed to send'), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('counselor_thread_message_list')),
            matching: find.text('Optimistic reply'),
          ),
          findsOneWidget,
        );
        expect(find.text('Sent'), findsOneWidget);
        expect(field.controller?.text, isEmpty);

        // 4. Fail another send and Dismiss it cleanly
        await tester.enterText(find.byType(TextField), 'Discardable reply');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        db.failNextPendingWrite(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const Key('counselor_thread_message_list')),
            matching: find.text('Discardable reply'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Dismiss'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const Key('counselor_thread_message_list')),
            matching: find.text('Discardable reply'),
          ),
          findsNothing,
        );

        // 5. Thread stream error renders sanitized error
        db.emitCollectionError(
          'counselor_threads/s1/messages',
          Exception('internal stack /secret'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Unable to load messages.'), findsOneWidget);
        expect(find.textContaining('/secret'), findsNothing);
      },
    );

    testWidgets(
      'smart auto-scroll: starts at bottom, scrolls on near-bottom/own send, does not yank when scrolled up, and preserves scroll when loading older history',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final base = DateTime.utc(2026, 11, 22, 8, 0);
        for (var i = 1; i <= 25; i++) {
          db.seedDoc('counselor_threads/s1/messages/m$i', {
            'senderId': 's1',
            'senderRole': 'user',
            'text': 'History message $i with enough detail to wrap nicely',
            'createdAt': Timestamp.fromDate(base.add(Duration(minutes: i))),
          });
        }
        final tLast = Timestamp.fromDate(base.add(const Duration(minutes: 25)));
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana Reyes',
          'updatedAt': tLast,
          'lastStudentMessageAt': tLast,
          'lastStudentMessageId': 'm25',
        });
        db.seedDoc('counselor_inbox_reads/counselor-a/threads/s1', {
          'readAt': tLast,
        });

        await tester.pumpWidget(buildHarness(messagePageSize: 12));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Ana Reyes'));
        await tester.pumpAndSettle();

        final listFinder = find.byKey(
          const Key('counselor_thread_message_list'),
        );
        final listView = tester.widget<ListView>(listFinder);
        final scrollController = listView.controller!;

        // 1. Thread opens at bottom (pixels == 0) showing latest message m25
        expect(scrollController.position.pixels, 0);
        expect(find.textContaining('History message 25'), findsOneWidget);

        // 2. Incoming student message while near bottom -> stays at bottom & visible
        final t26 = Timestamp.fromDate(base.add(const Duration(minutes: 26)));
        db.putAndEmit('counselor_threads/s1/messages/m26', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Near-bottom incoming m26',
          'createdAt': t26,
        });
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana Reyes',
          'updatedAt': t26,
          'lastStudentMessageAt': t26,
          'lastStudentMessageId': 'm26',
        });
        await tester.pumpAndSettle();
        expect(find.text('Near-bottom incoming m26'), findsOneWidget);
        expect(scrollController.position.pixels, 0);

        // 3. Scroll up to read older messages (well above 96px threshold)
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final scrolledUpOffset = scrollController.position.pixels;
        expect(scrolledUpOffset, greaterThan(96));
        expect(find.text('Load older messages'), findsOneWidget);

        // 4. New incoming student message while scrolled up -> MUST NOT yank scroll!
        final t27 = Timestamp.fromDate(base.add(const Duration(minutes: 27)));
        db.putAndEmit('counselor_threads/s1/messages/m27', {
          'senderId': 's1',
          'senderRole': 'user',
          'text': 'Scrolled-up incoming m27',
          'createdAt': t27,
        });
        db.putAndEmit('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName': 'Ana Reyes',
          'updatedAt': t27,
          'lastStudentMessageAt': t27,
          'lastStudentMessageId': 'm27',
        });
        await tester.pumpAndSettle();

        expect(scrollController.position.pixels, greaterThan(96));
        expect(
          find.byKey(const Key('counselor_new_messages_button')),
          findsOneWidget,
        );
        expect(find.text('Scrolled-up incoming m27'), findsNothing);

        // 5. Load older messages while scrolled up -> preserves anchor message Y!
        final anchorFinder = find.textContaining('History message 16');
        expect(anchorFinder, findsOneWidget);
        final anchorYBefore = tester.getTopLeft(anchorFinder).dy;

        await tester.tap(find.text('Load older messages'));
        await tester.pumpAndSettle();

        // History message 16 stays at virtually the exact same viewport Y coordinate
        expect(anchorFinder, findsOneWidget);
        final anchorYAfter = tester.getTopLeft(anchorFinder).dy;
        expect((anchorYAfter - anchorYBefore).abs(), lessThan(2.0));
        expect(scrollController.position.pixels, greaterThan(96));

        // 6. Tapping 'New messages' jumps to bottom and shows deferred m27
        await tester.tap(
          find.byKey(const Key('counselor_new_messages_button')),
        );
        await tester.pumpAndSettle();
        expect(scrollController.position.pixels, 0);
        expect(find.text('Scrolled-up incoming m27'), findsOneWidget);

        // 7. Scroll up again and send own counselor reply -> auto-scrolls to bottom
        scrollController.jumpTo(300);
        await tester.pumpAndSettle();
        expect(scrollController.position.pixels, greaterThan(96));

        await tester.enterText(find.byType(TextField), 'Counselor own send');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();

        expect(scrollController.position.pixels, 0);
        expect(find.text('Counselor own send'), findsOneWidget);
      },
    );

    testWidgets(
      'responsive layouts at 390px, 768px, 1280px (including TextScaler 1.4 and CounselorInquiryWorkspace) render with zero overflow',
      (tester) async {
        addTearDown(tester.view.reset);

        final t1 = Timestamp.fromDate(DateTime.utc(2026, 11, 22, 10, 0));
        db.seedDoc('counselor_threads/s1', {
          'userId': 's1',
          'collegeId': 'CITE',
          'studentName':
              'Very Long Student Name That Might Wrap On Narrow Screens',
          'updatedAt': t1,
          'lastStudentMessageAt': t1,
          'lastStudentMessageId': 'm1',
        });
        db.seedDoc('counselor_threads/s1/messages/m1', {
          'senderId': 's1',
          'senderRole': 'user',
          'text':
              'Long incoming message to verify clean wrapping across mobile, tablet, and desktop breakpoints.',
          'createdAt': t1,
        });

        // 1. Mobile 390px with TextScaler 1.4: single-pane list -> tap -> thread with Back button
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(buildHarness(textScale: 1.4));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Select a conversation'), findsNothing);
        expect(
          find.text('Very Long Student Name That Might Wrap On Narrow Screens'),
          findsOneWidget,
        );

        await tester.tap(
          find.text('Very Long Student Name That Might Wrap On Narrow Screens'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(
          find.textContaining('Long incoming message to verify clean wrapping'),
          findsOneWidget,
        );

        // Back returns to conversation list
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.arrow_back), findsNothing);

        // 2. Tablet 768px & Desktop 1280px with TextScaler 1.4: two-pane without overflow
        for (final size in [const Size(768, 1024), const Size(1280, 900)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            buildHarness(pageKey: ValueKey('page_$size'), textScale: 1.4),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Select a conversation'), findsOneWidget);

          await tester.tap(
            find.text(
              'Very Long Student Name That Might Wrap On Narrow Screens',
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byIcon(Icons.arrow_back), findsNothing);
        }

        // 3. Embedded inside CounselorInquiryWorkspace at 390, 768, 1280
        for (final size in [
          const Size(390, 844),
          const Size(768, 1024),
          const Size(1280, 900),
        ]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            MaterialApp(
              theme: AdminTheme.data,
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: EdgeInsets.all(size.width < 600 ? 16 : 28),
                  child: CounselorInquiryWorkspace(
                    messages: CounselorMessagesPage(
                      embedded: true,
                      firestore: db,
                      auth: auth,
                      now: () => fixedNow,
                    ),
                    otherServices: const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  });
}
