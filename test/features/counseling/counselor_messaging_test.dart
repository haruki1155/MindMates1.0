import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/data/guidance_quick_replies.dart';
import 'package:mind_mates/features/counseling/repositories/counselor_chat_repository.dart';
import 'package:mind_mates/features/counseling/controllers/counselor_send_controller.dart';
import 'package:mind_mates/features/counseling/widgets/counselor_message_timeline.dart';
import 'package:mind_mates/features/counseling/widgets/guidance_quick_reply_composer.dart';
import 'package:mind_mates/features/counseling/widgets/service_inquiry_composer.dart';
import 'package:mind_mates/features/counseling/screens/counselor_chat_screen.dart';
import 'package:mind_mates/core/theme/app_theme.dart';

class MemoryOutbox extends CounselorOutboxStore {
  OutgoingInquiry? value;
  bool failSave = false;
  bool failLoad = false;
  @override
  Future<OutgoingInquiry?> load() async {
    if (failLoad) throw StateError('storage unavailable');
    return value;
  }

  @override
  Future<void> save(OutgoingInquiry attempt) async {
    if (failSave) throw StateError('storage unavailable');
    value = attempt;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class FakeChat extends CounselorChatRepository {
  final messages = StreamController<List<CounselorMessage>>.broadcast();
  final calls = <String>[];
  final texts = <String>[];
  DateTime? readAt;
  Completer<void>? completion;
  bool fail = false;
  Object? failure;
  @override
  Stream<List<CounselorMessage>> watch(String uid) async* {
    yield [];
    yield* messages.stream;
  }

  @override
  String newMessageId(String uid) => 'message-${calls.length}';
  @override
  Future<void> send(String uid, String id, String text) async {
    calls.add(id);
    if (failure != null) throw failure!;
    texts.add(text);
    if (fail) throw StateError('offline');
    await completion?.future;
  }

  @override
  Stream<DateTime?> watchCounselorReadAt(String uid) => Stream.value(readAt);

  @override
  Future<void> markRepliesRead(String uid) async {}
}

void main() {
  test(
    'a failed retry logs type and Firebase code only, never the text',
    () async {
      final secret = guidanceQuickReplies[2].text;
      final repo = FakeChat()
        ..failure = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'denied for $secret',
        );
      final sender = CounselorSendController(
        uid: 'student-uid-123',
        repository: repo,
        store: MemoryOutbox(),
      );
      addTearDown(sender.dispose);
      await sender.restore();
      sender.select(guidanceQuickReplies[2]);
      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) {
        if (m != null) lines.add(m);
      };
      addTearDown(() => debugPrint = original);
      await sender.sendSelected();
      final log = lines
          .where((l) => l.contains('counselor_send_failed'))
          .toList();
      expect(log, hasLength(1));
      expect(log.single, contains('FirebaseException'));
      expect(log.single, contains('permission-denied'));
      expect(log.single, contains('cloud_firestore'));
      expect(log.single, isNot(contains(secret)));
      expect(log.single, isNot(contains('student-uid-123')));
    },
  );

  test(
    'Sending is immediate, duplicate taps are ignored, and Sent awaits acknowledgment',
    () async {
      final repo = FakeChat()..completion = Completer<void>();
      final store = MemoryOutbox();
      final sender = CounselorSendController(
        uid: 'student',
        repository: repo,
        store: store,
      );
      addTearDown(sender.dispose);
      await sender.restore();
      sender.select(guidanceQuickReplies[1]);
      final sending = sender.sendSelected();
      expect(sender.sending, isTrue);
      await sender.sendSelected();
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, ['message-0']);
      expect(repo.texts, ['Noted.']);
      expect(sender.pending?.text, 'Noted.');
      expect(sender.selected, guidanceQuickReplies[1]);
      repo.completion!.complete();
      await sending;
      expect(sender.pending, isNull);
      expect(sender.selected, isNull);
      expect(sender.acknowledged.single.text, 'Noted.');
      expect(store.value, isNull);
    },
  );

  test('nothing is sent without a selected reply', () async {
    final repo = FakeChat();
    final sender = CounselorSendController(
      uid: 'student',
      repository: repo,
      store: MemoryOutbox(),
    );
    addTearDown(sender.dispose);
    await sender.restore();
    await sender.sendSelected();
    expect(repo.calls, isEmpty);
    expect(sender.pending, isNull);
  });

  test(
    'a restored legacy draft the policy refuses is never resent and can be discarded',
    () async {
      final repo = FakeChat()..failure = const QuickReplyNotAllowedException();
      final store = MemoryOutbox()
        ..value = const OutgoingInquiry(id: 'legacy-1', text: 'Hello');
      final sender = CounselorSendController(
        uid: 'student',
        repository: repo,
        store: store,
      );
      addTearDown(sender.dispose);
      await sender.restore();
      await sender.retry();
      expect(repo.calls, ['legacy-1']);
      expect(sender.pendingNotAllowed, isTrue);
      expect(
        sender.error,
        "This earlier message can't be sent under the new Guidance Assistance "
        'policy. Discard it and choose a quick reply.',
      );
      await sender.retry();
      sender.select(guidanceQuickReplies.first);
      await sender.sendSelected();
      expect(repo.calls, ['legacy-1'], reason: 'never resent or replaced');
      await sender.discardPending();
      expect(store.value, isNull);
      expect(sender.pending, isNull);
      expect(sender.pendingNotAllowed, isFalse);
      expect(sender.error, isNull);
      repo.failure = null;
      await sender.sendSelected();
      expect(repo.calls, ['legacy-1', 'message-1']);
    },
  );

  test(
    'failure keeps the reply and stable retry ID across reopen without overwriting a new selection',
    () async {
      final repo = FakeChat()..fail = true;
      final store = MemoryOutbox();
      final sender = CounselorSendController(
        uid: 'student',
        repository: repo,
        store: store,
      );
      await sender.restore();
      sender.select(guidanceQuickReplies[3]);
      await sender.sendSelected();
      expect(sender.error, isNotNull);
      expect(sender.selected, guidanceQuickReplies[3]);
      final id = sender.pending!.id;
      sender.dispose();
      final restored = CounselorSendController(
        uid: 'student',
        repository: repo,
        store: store,
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.pending!.id, id);
      expect(restored.pending!.text, 'I need clarification.');
      restored.select(guidanceQuickReplies[0]);
      repo.fail = false;
      await restored.retry();
      expect(repo.calls, [id, id]);
      expect(restored.selected, guidanceQuickReplies[0]);
    },
  );

  testWidgets('server times, date separators, and only verified statuses', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 13, 17, 26);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CounselorMessageTimeline(
            uid: 'student',
            now: () => now,
            messages: [
              CounselorMessage(
                id: 'old',
                text: 'Yesterday reply',
                senderId: 'counselor',
                createdAt: now.subtract(const Duration(days: 1)),
              ),
              CounselorMessage(
                id: 'sent',
                text: 'My inquiry',
                senderId: 'student',
                createdAt: now,
              ),
              const CounselorMessage(
                id: 'pending',
                text: 'Pending inquiry',
                senderId: 'student',
                pendingWrites: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.textContaining('5:26 PM'), findsWidgets);
    expect(find.byTooltip('Sent'), findsOneWidget);
    expect(find.byTooltip('Sending'), findsOneWidget);
    expect(find.text('Time pending'), findsOneWidget);
    expect(find.textContaining('Delivered'), findsNothing);
    expect(find.textContaining('Read'), findsNothing);
  });
  testWidgets(
    'latest opens at bottom, older reading is stable, incoming indicator and own sends scroll',
    (tester) async {
      final now = DateTime(2026, 11, 13, 17, 26);
      var history = List.generate(
        35,
        (i) => CounselorMessage(
          id: 'm$i',
          text: 'Message $i ${'a long message ' * (i % 4 + 1)}',
          senderId: 'counselor',
          createdAt: now.add(Duration(minutes: i)),
        ),
      );
      OutgoingInquiry? pending;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return CounselorMessageTimeline(
                  uid: 'student',
                  messages: history,
                  pending: pending,
                  sending: pending != null,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(const Key('counselor_message_list'));
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.pixels, 0);
      await tester.drag(list, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(96));
      final offset = position.pixels;
      update(
        () => history = [
          ...history,
          CounselorMessage(
            id: 'incoming',
            text: 'New counselor reply ' * 30,
            senderId: 'counselor',
            createdAt: now.add(const Duration(hours: 1)),
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(offset, 1));
      expect(find.text('New messages'), findsOneWidget);
      await tester.tap(find.text('New messages'));
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
      expect(find.text('New messages'), findsNothing);
      update(
        () => history = [
          ...history,
          CounselorMessage(
            id: 'near-bottom',
            text: 'Another reply',
            senderId: 'counselor',
            createdAt: now.add(const Duration(hours: 2)),
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
      await tester.drag(list, const Offset(0, 400));
      await tester.pumpAndSettle();
      update(
        () => history = [
          CounselorMessage(
            id: 'older-page',
            text: 'Older page',
            senderId: 'counselor',
            createdAt: now.subtract(const Duration(days: 5)),
          ),
          ...history,
        ],
      );
      final beforePage = position.pixels;
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(beforePage, 1));
      update(
        () => pending = const OutgoingInquiry(
          id: 'own',
          text: 'My outgoing inquiry',
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(position.pixels, 0);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'chat uses MindMate theme, keeps a failed reply and sends only on retry ($dark)',
      (tester) async {
        final repo = FakeChat()..fail = true;
        final store = MemoryOutbox();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: CounselorChatScreen(
              userId: 'student',
              repository: repo,
              outbox: store,
            ),
          ),
        );
        await tester.pumpAndSettle();
        repo.messages.add([]);
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        await tester.ensureVisible(find.text('I am available.'));
        await tester.tap(find.text('I am available.'));
        await tester.pump();
        await tester.tap(find.byTooltip('Send reply'));
        await tester.pumpAndSettle();
        expect(find.text('Retry'), findsOneWidget);
        expect(repo.calls, ['message-0']);
        repo.fail = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(repo.calls, ['message-0', 'message-0']);
        expect(find.byTooltip('Sent'), findsOneWidget);
        final bubble = tester.widget<CounselorMessageBubble>(
          find.byType(CounselorMessageBubble),
        );
        final theme = Theme.of(
          tester.element(find.byType(CounselorMessageBubble)),
        );
        final containers = tester.widgetList<Container>(
          find.descendant(
            of: find.byType(CounselorMessageBubble),
            matching: find.byType(Container),
          ),
        );
        expect(
          containers.any(
            (c) =>
                c.decoration is BoxDecoration &&
                (c.decoration as BoxDecoration).color ==
                    theme.colorScheme.primary,
          ),
          isTrue,
        );
        expect(bubble.own, isTrue);
        await tester.pumpWidget(const SizedBox());
        await repo.messages.close();
      },
    );
  }

  testWidgets(
    'no text field; nine replies; Send needs a selection and clears it after sending',
    (tester) async {
      final repo = FakeChat();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CounselorChatScreen(
            userId: 'student',
            repository: repo,
            outbox: MemoryOutbox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      for (final reply in guidanceQuickReplies) {
        expect(find.text(reply.text), findsOneWidget, reason: reply.id);
      }
      final send = find.byTooltip('Send reply');
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.descendant(
                of: send,
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('I need further assistance.'));
      await tester.tap(find.text('I need further assistance.'));
      await tester.pump();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(repo.texts, ['I need further assistance.']);
      expect(
        find.text('Noted.'),
        findsOneWidget,
        reason: 'replies stay in place',
      );
      expect(find.byKey(const Key('guidance_selected_preview')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await repo.messages.close();
    },
  );

  testWidgets('info icon explains Guidance Assistance', (tester) async {
    final repo = FakeChat();
    await tester.pumpWidget(
      MaterialApp(
        home: CounselorChatScreen(
          userId: 'student',
          repository: repo,
          outbox: MemoryOutbox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('About Guidance Assistance'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Guidance Assistance allows you to receive instructions from your '
        'guidance counselor and respond using predefined Quick Replies. For '
        'concerns requiring detailed discussion, please request a counseling '
        'session.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await repo.messages.close();
  });

  testWidgets('session and urgent support open PACC counseling', (
    tester,
  ) async {
    final repo = FakeChat();
    final opened = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CounselorChatScreen(
          userId: 'student',
          repository: repo,
          outbox: MemoryOutbox(),
          openPaccCounseling: (context, {required startBooking}) =>
              opened.add(startBooking),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Book a session'));
    await tester.tap(find.text('Book a session'));
    await tester.ensureVisible(find.text('Urgent help'));
    await tester.tap(find.text('Urgent help'));
    expect(opened, [true, false]);
    await tester.pumpWidget(const SizedBox());
    await repo.messages.close();
  });

  testWidgets('legacy draft shows the policy message and Discard', (
    tester,
  ) async {
    final repo = FakeChat()..failure = const QuickReplyNotAllowedException();
    final store = MemoryOutbox()
      ..value = const OutgoingInquiry(id: 'legacy-1', text: 'Old free text');
    await tester.pumpWidget(
      MaterialApp(
        home: CounselorChatScreen(
          userId: 'student',
          repository: repo,
          outbox: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be sent under the new"), findsWidgets);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(store.value, isNull);
    expect(find.text('Old free text'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await repo.messages.close();
  });

  testWidgets(
    'own message shows Read only when counselorReadAt has passed it',
    (tester) async {
      final readAt = DateTime(2026, 11, 13, 17, 30);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CounselorMessageTimeline(
              uid: 'student',
              counterpartReadAt: readAt,
              messages: [
                CounselorMessage(
                  id: 'before',
                  text: 'Noted.',
                  senderId: 'student',
                  createdAt: readAt.subtract(const Duration(minutes: 1)),
                ),
                CounselorMessage(
                  id: 'after',
                  text: 'I am available.',
                  senderId: 'student',
                  createdAt: readAt.add(const Duration(minutes: 1)),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Seen'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
    },
  );

  testWidgets('the chat screen streams counselorReadAt into the timeline', (
    tester,
  ) async {
    final readAt = DateTime(2026, 11, 13, 17, 30);
    final repo = FakeChat()..readAt = readAt;
    await tester.pumpWidget(
      MaterialApp(
        home: CounselorChatScreen(
          userId: 'student',
          repository: repo,
          outbox: MemoryOutbox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repo.messages.add([
      CounselorMessage(
        id: 'm',
        text: 'Noted.',
        senderId: 'student',
        createdAt: readAt.subtract(const Duration(minutes: 1)),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Seen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await repo.messages.close();
  });

  test('secure outbox is isolated by Firebase project and user', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = CounselorOutboxStore(projectId: 'staging', uid: 'student');
    await store.save(
      const OutgoingInquiry(id: 'stable', text: 'Private question'),
    );
    expect((await store.load())!.text, 'Private question');
    expect(
      await CounselorOutboxStore(
        projectId: 'production',
        uid: 'student',
      ).load(),
      isNull,
    );
    expect(
      await CounselorOutboxStore(projectId: 'staging', uid: 'other').load(),
      isNull,
    );
    await store.clear();
    expect(await store.load(), isNull);
  });

  testWidgets('small screen at 2x text keeps every reply and Send reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeChat();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: CounselorChatScreen(
          userId: 'student',
          repository: repo,
          outbox: MemoryOutbox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final last = find.text(guidanceQuickReplies.last.text);
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('Send reply'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Send reply').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await repo.messages.close();
  });

  test(
    'storage failures never submit or overwrite saved outgoing messages',
    () async {
      final repo = FakeChat();
      final store = MemoryOutbox()..failLoad = true;
      final sender = CounselorSendController(
        uid: 'student',
        repository: repo,
        store: store,
      );
      addTearDown(sender.dispose);
      await sender.restore();
      sender.select(guidanceQuickReplies[4]);
      await sender.sendSelected();
      expect(repo.calls, isEmpty);
      expect(sender.ready, isFalse);
      store.failLoad = false;
      await sender.restore();
      store.failSave = true;
      await sender.sendSelected();
      expect(repo.calls, isEmpty);
      expect(sender.selected, guidanceQuickReplies[4]);
      expect(sender.error, contains('Keep this screen open'));
      final id = sender.pending!.id;
      store.failSave = false;
      await sender.retry();
      expect(repo.calls, [id]);
    },
  );

  testWidgets('the composer sits flush with the bottom of the screen', (
    tester,
  ) async {
    final repo = FakeChat();
    await tester.pumpWidget(
      MaterialApp(
        home: CounselorChatScreen(
          userId: 'student',
          repository: repo,
          outbox: MemoryOutbox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final screenBottom = tester.getBottomLeft(find.byType(Scaffold)).dy;
    expect(
      tester.getBottomLeft(find.byType(GuidanceQuickReplyComposer)).dy,
      screenBottom,
    );
    await tester.pumpWidget(const SizedBox());
    await repo.messages.close();
  });

  testWidgets(
    'the legacy notice keeps Discard reachable at 2x on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeChat()..failure = const QuickReplyNotAllowedException();
      final store = MemoryOutbox()
        ..value = const OutgoingInquiry(id: 'legacy-1', text: 'Old free text');
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: CounselorChatScreen(
            userId: 'student',
            repository: repo,
            outbox: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Discard').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await repo.messages.close();
    },
  );

  testWidgets('Services sends the chosen inquiry template exactly', (
    tester,
  ) async {
    final repo = FakeChat();
    await tester.pumpWidget(
      MaterialApp(
        home: CounselorChatScreen(
          userId: 'student',
          repository: repo,
          outbox: MemoryOutbox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Counseling Service'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appointment Inquiry'));
    await tester.pumpAndSettle();
    final template = serviceInquiryDraft(
      'Counseling Service',
      'Appointment Inquiry',
    );
    expect(find.byKey(const Key('guidance_selected_preview')), findsOneWidget);
    expect(find.text(template), findsOneWidget);
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pumpAndSettle();
    expect(repo.texts, [template]);
    await tester.pumpWidget(const SizedBox());
    await repo.messages.close();
  });

  testWidgets(
    'Make an inquiry from a service opens that service in the picker',
    (tester) async {
      final repo = FakeChat();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: const RouteSettings(arguments: 'Testing Service'),
                  builder: (_) => CounselorChatScreen(
                    userId: 'student',
                    repository: repo,
                    outbox: MemoryOutbox(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.text('What do you want to know about Testing Service?'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await repo.messages.close();
    },
  );
}
