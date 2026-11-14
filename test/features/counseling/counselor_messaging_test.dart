import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/repositories/counselor_chat_repository.dart';
import 'package:mind_mates/features/counseling/controllers/counselor_send_controller.dart';
import 'package:mind_mates/features/counseling/widgets/counselor_message_timeline.dart';
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
    if (fail) throw StateError('offline');
    await completion?.future;
  }

  @override
  Future<void> markRepliesRead(String uid) async {}
}

void main() {
  test(
    'a failed retry logs type and Firebase code only, never the text',
    () async {
      const secret = 'my private counselor message';
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
      sender.draft.text = secret;
      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) {
        if (m != null) lines.add(m);
      };
      addTearDown(() => debugPrint = original);
      await sender.send();
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
      sender.draft.text = 'Hello PACC';
      final sending = sender.send();
      expect(sender.sending, isTrue);
      await sender.send();
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, ['message-0']);
      expect(sender.pending?.text, 'Hello PACC');
      expect(sender.draft.text, 'Hello PACC');
      repo.completion!.complete();
      await sending;
      expect(sender.pending, isNull);
      expect(sender.draft.text, isEmpty);
      expect(store.value, isNull);
    },
  );

  test(
    'failure and reopen preserve text and stable retry ID without overwriting a new draft',
    () async {
      final repo = FakeChat()..fail = true;
      final store = MemoryOutbox();
      final sender = CounselorSendController(
        uid: 'student',
        repository: repo,
        store: store,
      );
      await sender.restore();
      sender.draft.text = 'Original inquiry';
      await sender.send();
      expect(sender.error, isNotNull);
      expect(sender.draft.text, 'Original inquiry');
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
      expect(restored.draft.text, 'Original inquiry');
      restored.draft.text = 'New unsent draft';
      repo.fail = false;
      await restored.retry();
      expect(repo.calls, [id, id]);
      expect(restored.draft.text, 'New unsent draft');
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
      'chat uses MindMate theme, preserves failed drafts and sends only on retry ($dark)',
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
        expect(find.text('Services'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'PACC question');
        await tester.pump();
        await tester.tap(find.byTooltip('Send message'));
        await tester.pumpAndSettle();
        expect(find.text('Retry'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'PACC question',
        );
        expect(repo.calls, ['message-0']);
        repo.fail = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(repo.calls, ['message-0', 'message-0']);
        expect(find.byTooltip('Sent'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
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

  testWidgets('small screen keyboard and large text keep composer visible', (
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
    expect(tester.takeException(), isNull, reason: 'before keyboard');
    tester.view.viewInsets = FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Send message').hitTestable(), findsOneWidget);
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
      sender.draft.text = 'Keep this inquiry';
      await sender.send();
      expect(repo.calls, isEmpty);
      expect(sender.ready, isFalse);
      store.failLoad = false;
      await sender.restore();
      store.failSave = true;
      await sender.send();
      expect(repo.calls, isEmpty);
      expect(sender.draft.text, 'Keep this inquiry');
      expect(sender.error, contains('Keep this screen open'));
      final id = sender.pending!.id;
      store.failSave = false;
      await sender.retry();
      expect(repo.calls, [id]);
    },
  );
}
