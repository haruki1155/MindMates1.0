import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/announcements/data/announcement_repository.dart';
import 'package:mind_mates/features/announcements/models/announcement.dart';
import 'package:mind_mates/features/announcements/screens/announcements_screen.dart';

Announcement post(String id, {bool link = false}) => Announcement.fromJson(id, {
  'kind': link ? 'link' : 'original',
  'category': 'placements',
  'title': 'Post $id',
  'body': 'Details for $id',
  'sourceUrl': link ? 'https://example.com/$id' : '',
  'status': 'published',
  'revision': 1,
  'publishedAt': DateTime.utc(2026, 11, 14),
});
void main() {
  testWidgets(
    'linked cards open source and separate full-screen action opens swipe viewer',
    (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AnnouncementsScreen(
            repository: AnnouncementRepository(
              fetch: (_) async => [post('one', link: true), post('two')],
            ),
            launcher: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post one'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://example.com/one');
      await tester.tap(find.byTooltip('View full screen').first);
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(0, -550));
      await tester.pumpAndSettle();
      expect(find.text('Post two').hitTestable(), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsNothing);
    },
  );
  testWidgets(
    'errors retry, categories load independently, and empty state is clear',
    (tester) async {
      var fail = true;
      final queries = <AnnouncementQuery>[];
      final repo = AnnouncementRepository(
        fetch: (q) async {
          queries.add(q);
          if (fail) throw StateError('offline');
          return [];
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: AnnouncementsScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No announcements yet'), findsOneWidget);
      await tester.tap(find.text('Placements'));
      await tester.pumpAndSettle();
      expect(queries.last.category, AnnouncementCategory.placements);
    },
  );
  testWidgets(
    'category switch ignores late results from the previous request',
    (tester) async {
      final pending = Completer<List<Announcement>>();
      final repo = AnnouncementRepository(
        fetch: (q) =>
            q.category == null ? pending.future : Future.value([post('new')]),
      );
      await tester.pumpWidget(
        MaterialApp(home: AnnouncementsScreen(repository: repo)),
      );
      await tester.pump();
      await tester.tap(find.text('Placements'));
      await tester.pumpAndSettle();
      pending.complete([post('old')]);
      await tester.pumpAndSettle();
      expect(find.text('Post new'), findsOneWidget);
      expect(find.text('Post old'), findsNothing);
    },
  );
  testWidgets('refresh removes archived posts from an open viewer', (
    tester,
  ) async {
    var items = [post('one'), post('two')];
    await tester.pumpWidget(
      MaterialApp(
        home: AnnouncementsScreen(
          repository: AnnouncementRepository(fetch: (_) async => items),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post one'));
    await tester.pumpAndSettle();
    items = [post('two')];
    await tester.tap(find.byTooltip('Refresh announcements').last);
    await tester.pumpAndSettle();
    expect(find.text('Post one'), findsNothing);
    expect(find.text('Post two').hitTestable(), findsOneWidget);
  });
  testWidgets(
    'failed opening reports retry without navigating and narrow large text fits',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: AnnouncementsScreen(
            repository: AnnouncementRepository(
              fetch: (_) async => [post('one', link: true)],
            ),
            launcher: (_) async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Post one'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post one'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unable to open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
