import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/announcements/data/announcement_repository.dart';
import 'package:mind_mates/features/announcements/models/announcement.dart';
import 'package:mind_mates/features/announcements/screens/manage_announcements_page.dart';
import 'package:mind_mates/features/announcements/widgets/announcement_editor.dart';

void main() {
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
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Career talk',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Join the PACC team',
    );
    expect(calls, isEmpty);
    await tester.ensureVisible(find.text('Publish'));
    await tester.tap(find.text('Publish'));
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
        if (name == 'previewAnnouncementLink')
          return {
            'available': true,
            'title': 'Imported title',
            'description': 'Imported details',
            'sourceUrl': data['url'],
          };
        calls.add(data);
        return {'id': 'x', 'revision': 1};
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: AnnouncementEditor(repository: repo)),
    );
    await tester.tap(find.text('Linked post'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Source link'),
      'https://example.com/post',
    );
    await tester.tap(find.text('Load preview'));
    await tester.pumpAndSettle();
    expect(find.text('Imported title'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Edited title',
    );
    await tester.ensureVisible(find.text('Publish'));
    await tester.tap(find.text('Publish'));
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
    final repo = AnnouncementRepository(call: (_, _) => pending.future);
    await tester.pumpWidget(
      MaterialApp(home: AnnouncementEditor(repository: repo)),
    );
    await tester.tap(find.text('Linked post'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Source link'),
      'https://example.com/old',
    );
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
}
