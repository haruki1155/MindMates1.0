import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mind_mates/features/announcements/data/announcement_repository.dart';
import 'package:mind_mates/features/announcements/models/announcement.dart';
import 'package:mind_mates/features/announcements/screens/manage_announcements_page.dart';
import 'package:mind_mates/features/announcements/widgets/announcement_editor.dart';

void main() {
  Finder source() => find.widgetWithText(TextFormField, 'Source link');

  Finder audiencePanel(String label) => find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        (widget.properties.label?.startsWith('$label,') ?? false),
  );

  Finder audienceTapTarget(String label) => find.widgetWithText(InkWell, label);

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump();
    await tester.tap(finder);
  }

  Future<void> enterVisibleText(
    WidgetTester tester,
    Finder finder,
    String value,
  ) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump();
    await tester.enterText(finder, value);
  }

  testWidgets(
    'destination updates immediately and pending publishing blocks duplicate actions',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      final repository = AnnouncementRepository(
        call: (_, data) {
          calls++;
          return pending.future;
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: AnnouncementEditor(repository: repository)),
      );
      await tester.ensureVisible(find.text('Linked post'));
      await tester.tap(find.text('Linked post'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(TextFormField, 'Source link'),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Source link'),
        'https://first.example/post',
      );
      await tester.pump();
      expect(find.text('Destination: first.example'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Source link'),
        'https://second.example/post',
      );
      await tester.pump();
      expect(find.text('Destination: second.example'), findsOneWidget);
      expect(find.text('Destination: first.example'), findsNothing);
      await tester.ensureVisible(find.widgetWithText(TextFormField, 'Title'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Test title',
      );
      await tester.ensureVisible(
        find.widgetWithText(TextFormField, 'Description'),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Test details',
      );
      await tester.ensureVisible(find.text('Publish announcement'));
      await tester.tap(find.text('Publish announcement'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(calls, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Test title'), findsOneWidget);
    },
  );
  testWidgets('publisher creates original post only through explicit publish', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    final repo = AnnouncementRepository(
      fetch: (_) async => [],
      call: (_, data) async {
        calls.add(data);
        return {'id': 'one', 'revision': 1};
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ManageAnnouncementsPage(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New announcement'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Title'));
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, 'Description'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Career talk',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Join the PACC team',
    );
    expect(calls, isEmpty);
    await tester.ensureVisible(find.text('Publish announcement'));
    await tester.tap(find.text('Publish announcement'));
    await tester.pumpAndSettle();
    expect(calls.single['action'], 'publish');
    expect((calls.single['post'] as Map)['title'], 'Career talk');
  });
  testWidgets('link preview populates editable fields and can be published', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    final repo = AnnouncementRepository(
      call: (name, data) async {
        if (name == 'previewAnnouncementLink') {
          return {
            'available': true,
            'title': 'Imported title',
            'description': 'Imported details',
            'sourceUrl': data['url'],
          };
        }
        calls.add(data);
        return {'id': 'x', 'revision': 1};
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: AnnouncementEditor(repository: repo)),
    );
    await tester.ensureVisible(find.text('Linked post'));
    await tester.tap(find.text('Linked post'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(source());
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Source link'),
      'https://example.com/post',
    );
    await tester.ensureVisible(find.text('Load preview'));
    await tester.tap(find.text('Load preview'));
    await tester.pumpAndSettle();
    expect(find.text('Imported title'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Edited title',
    );
    await tester.ensureVisible(find.text('Publish announcement'));
    await tester.tap(find.text('Publish announcement'));
    await tester.pumpAndSettle();
    expect((calls.single['post'] as Map)['title'], 'Edited title');
    expect(
      (calls.single['post'] as Map)['sourceUrl'],
      'https://example.com/post',
    );
  });
  testWidgets('stale preview cannot replace fields after URL changes', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    var previews = 0;
    // Only the first (now stale) request answers with the old page's metadata.
    final repo = AnnouncementRepository(
      call: (_, _) async =>
          previews++ == 0 ? pending.future : {'available': false},
    );
    await tester.pumpWidget(
      MaterialApp(home: AnnouncementEditor(repository: repo)),
    );
    await tester.ensureVisible(find.text('Linked post'));
    await tester.tap(find.text('Linked post'));
    await tester.pump();
    await tester.ensureVisible(source());
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Source link'),
      'https://example.com/old',
    );
    await tester.ensureVisible(find.text('Load preview'));
    await tester.tap(find.text('Load preview'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Source link'),
      'https://example.com/new',
    );
    pending.complete({
      'available': true,
      'title': 'Old title',
      'description': 'Old body',
    });
    await tester.pumpAndSettle();
    expect(find.text('Old title'), findsNothing);
  });
  testWidgets('published edit stays local and conflict preserves form', (
    tester,
  ) async {
    final post = Announcement.fromJson('one', {
      'kind': 'original',
      'category': 'placements',
      'title': 'Existing',
      'body': 'Details',
      'status': 'published',
      'revision': 3,
    });
    var saves = 0;
    final repo = AnnouncementRepository(
      call: (_, _) async {
        saves++;
        throw StateError('conflict');
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AnnouncementEditor(repository: repo, announcement: post),
      ),
    );
    expect(find.text('Save draft'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Updated',
    );
    expect(saves, 0);
    await tester.ensureVisible(find.text('Publish changes'));
    await tester.tap(find.text('Publish changes'));
    await tester.pumpAndSettle();
    expect(find.text('Updated'), findsOneWidget);
    expect(saves, 1);
    expect(find.textContaining('Unable to save'), findsOneWidget);
  });
  testWidgets(
    'editor fits narrow screen with large text and unavailable preview fallback',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: AnnouncementEditor(
            repository: AnnouncementRepository(
              call: (_, data) async => {
                'available': false,
                'sourceUrl': data['url'],
              },
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Linked post'));
      await tester.tap(find.text('Linked post'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Source link'),
        'https://example.com',
      );
      await tester.ensureVisible(find.text('Load preview'));
      await tester.tap(find.text('Load preview'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter the details manually'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> publish(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Publish announcement'));
    await tester.tap(find.text('Publish announcement'));
    await tester.pumpAndSettle();
  }

  Future<void> fillText(WidgetTester tester) async {
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Title'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Campus update',
    );
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, 'Description'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Details',
    );
  }

  testWidgets('new posts default to all audiences and require at least one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final calls = <Map<String, dynamic>>[];
    final repo = AnnouncementRepository(
      call: (_, data) async {
        calls.add(data);
        return {'id': 'x', 'revision': 1};
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: AnnouncementEditor(repository: repo)),
    );
    for (final label in ['Student', 'Teaching', 'Non-Teaching']) {
      expect(
        tester.widget<Semantics>(audiencePanel(label)).properties.selected,
        isTrue,
      );
    }
    await fillText(tester);
    for (final label in ['Student', 'Teaching', 'Non-Teaching']) {
      await tapVisible(tester, audienceTapTarget(label));
      await tester.pump();
    }
    await publish(tester);
    expect(find.text('Select at least one audience.'), findsOneWidget);
    expect(calls, isEmpty);
    await tapVisible(tester, audienceTapTarget('Teaching'));
    await tester.ensureVisible(find.text('Information'));
    await tester.tap(find.text('Information'));
    await tester.pump();
    await publish(tester);
    final post = calls.single['post'] as Map;
    expect(post['postType'], 'information');
    expect(post['audienceRoles'], ['teaching']);
    expect(post['mediaType'], 'standard');
    expect(post.containsKey('category'), isFalse);
  });

  testWidgets('video media requires a linked source and resets for originals', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    final repo = AnnouncementRepository(
      call: (name, data) async {
        if (name == 'previewAnnouncementLink') return {'available': false};
        calls.add(data);
        return {'id': 'x', 'revision': 1};
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: AnnouncementEditor(repository: repo)),
    );
    await tester.ensureVisible(find.text('Video'));
    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    expect(source(), findsOneWidget, reason: 'video switches to a linked post');
    await fillText(tester);
    await publish(tester);
    expect(find.text('Enter a valid http or https link.'), findsOneWidget);
    expect(calls, isEmpty);
    await tester.enterText(source(), 'https://video.example/watch');
    await publish(tester);
    expect((calls.single['post'] as Map)['mediaType'], 'video');
    expect((calls.single['post'] as Map)['kind'], 'link');
  });

  testWidgets(
    'auto-preview debounces, deduplicates and never overwrites publisher edits',
    (tester) async {
      final previews = <String>[];
      final repo = AnnouncementRepository(
        call: (name, data) async {
          previews.add(data['url'] as String);
          return {
            'available': true,
            'title': 'Fetched title',
            'description': 'Fetched body',
            'imageUrl': 'https://img.example/a.png',
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: AnnouncementEditor(repository: repo)),
      );
      await tapVisible(tester, find.text('Linked post'));
      await tester.pumpAndSettle();
      await enterVisibleText(
        tester,
        find.widgetWithText(TextFormField, 'Title'),
        'My own title',
      );
      await enterVisibleText(tester, source(), 'https://news.example/a');
      await tester.pump(const Duration(milliseconds: 400));
      await enterVisibleText(tester, source(), 'https://news.example/b');
      await tester.pump(const Duration(milliseconds: 600));
      expect(previews, isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(previews, ['https://news.example/b']);
      expect(find.text('My own title'), findsOneWidget);
      expect(find.text('Fetched body'), findsOneWidget);
      await enterVisibleText(tester, source(), 'https://news.example/b ');
      await tester.pump(const Duration(seconds: 1));
      await enterVisibleText(tester, source(), 'not a url');
      await tester.pump(const Duration(seconds: 1));
      expect(previews, hasLength(1));
    },
  );

  testWidgets('stale auto-preview responses are ignored', (tester) async {
    final pending = <Completer<Map<String, dynamic>>>[];
    final repo = AnnouncementRepository(
      call: (_, _) {
        final completer = Completer<Map<String, dynamic>>();
        pending.add(completer);
        return completer.future;
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: AnnouncementEditor(repository: repo)),
    );
    await tapVisible(tester, find.text('Linked post'));
    await tester.pumpAndSettle();
    await enterVisibleText(tester, source(), 'https://news.example/old');
    await tester.pump(const Duration(milliseconds: 700));
    await enterVisibleText(tester, source(), 'https://news.example/new');
    await tester.pump(const Duration(milliseconds: 700));
    expect(pending, hasLength(2));
    pending[0].complete({'available': true, 'title': 'Old title'});
    await tester.pump();
    expect(find.text('Old title'), findsNothing);
    pending[1].complete({'available': true, 'title': 'New title'});
    await tester.pump();
    expect(find.text('New title'), findsOneWidget);
  });

  testWidgets('opening an existing linked post does not auto-fetch', (
    tester,
  ) async {
    var previews = 0;
    final post = Announcement.fromJson('one', {
      'kind': 'link',
      'postType': 'information',
      'audienceRoles': ['student'],
      'title': 'Existing',
      'body': 'Details',
      'sourceUrl': 'https://news.example/a',
      'status': 'draft',
      'revision': 2,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AnnouncementEditor(
          repository: AnnouncementRepository(
            call: (_, _) async {
              previews++;
              return {'available': false};
            },
          ),
          announcement: post,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(previews, 0);
    expect(
      tester.widget<Semantics>(audiencePanel('Teaching')).properties.selected,
      isFalse,
    );
  });

  testWidgets(
    'rate-limited preview keeps manual entry and publishing working',
    (tester) async {
      final saves = <Map<String, dynamic>>[];
      final repo = AnnouncementRepository(
        call: (name, data) async {
          if (name == 'previewAnnouncementLink') {
            throw FirebaseFunctionsException(
              code: 'resource-exhausted',
              message: 'slow down',
            );
          }
          saves.add(data);
          return {'id': 'x', 'revision': 1};
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: AnnouncementEditor(repository: repo)),
      );
      await tapVisible(tester, find.text('Linked post'));
      await tester.pumpAndSettle();
      await enterVisibleText(tester, source(), 'https://news.example/a');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.textContaining('Too many preview requests'), findsOneWidget);
      expect(find.text('Load preview'), findsOneWidget);
      await fillText(tester);
      await publish(tester);
      expect(
        (saves.single['post'] as Map)['sourceUrl'],
        'https://news.example/a',
      );
    },
  );

  testWidgets('managed list shows type, video and audience labels once', (
    tester,
  ) async {
    final repo = AnnouncementRepository(
      fetch: (_) async => [
        Announcement.fromJson('v', {
          'status': 'published',
          'kind': 'link',
          'postType': 'information',
          'mediaType': 'video',
          'audienceRoles': ['teaching', 'nonTeaching'],
          'category': 'placements',
          'title': 'Campus video',
          'body': 'Watch',
          'sourceUrl': 'https://video.example/v',
        }),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ManageAnnouncementsPage(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Information'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Teaching'), findsOneWidget);
    expect(find.text('Non-Teaching'), findsOneWidget);
    expect(find.text('Student'), findsNothing);
    expect(find.text('Placements'), findsNothing);
    expect(find.textContaining('Career guidance'), findsNothing);
  });
}
