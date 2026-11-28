import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/announcements/data/announcement_repository.dart';
import 'package:mind_mates/features/announcements/models/announcement.dart';
import 'package:mind_mates/features/announcements/screens/announcements_screen.dart';
import 'package:mind_mates/models/profile_roles.dart';

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
    'unavailable feed shows requested calm announcement state with retry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnnouncementsScreen(
            populationRole: PopulationRole.student,
            repository: AnnouncementRepository(
              fetch: (_) async => throw StateError('unavailable'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No announcements yet'), findsOneWidget);
      expect(
        find.text('You will be notified when there is an announcement.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Unable to load announcements'), findsNothing);
    },
  );
  testWidgets('viewer arrows change pages immediately with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: AnnouncementsScreen(
          populationRole: PopulationRole.student,
          repository: AnnouncementRepository(
            fetch: (_) async => [post('one'), post('two')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View full screen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next announcement'));
    await tester.pump();
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 1);
    await tester.tap(find.byTooltip('Previous announcement'));
    await tester.pump();
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
  });
  testWidgets('long posts provide reachable next and previous navigation', (
    tester,
  ) async {
    final long = Announcement.fromJson('long', {
      'kind': 'original',
      'category': 'placements',
      'title': 'Long announcement',
      'body': List.filled(150, 'Long content to read.').join('\n'),
      'status': 'published',
      'revision': 1,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AnnouncementsScreen(
          populationRole: PopulationRole.student,
          repository: AnnouncementRepository(
            fetch: (_) async => [long, post('next')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View full screen').first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next announcement'));
    await tester.pumpAndSettle();
    expect(find.text('Post next').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Previous announcement'));
    await tester.pumpAndSettle();
    expect(find.text('Long announcement'), findsWidgets);
  });
  testWidgets(
    'retry repeats a failed refresh instead of loading the next page',
    (tester) async {
      var fail = false;
      final seen = <AnnouncementQuery>[];
      final repo = AnnouncementRepository(
        fetch: (q) async {
          seen.add(q);
          if (fail) throw StateError('offline');
          return List.generate(20, (i) => post('item-$i'));
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AnnouncementsScreen(
            populationRole: PopulationRole.student,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      fail = true;
      await tester.tap(find.byTooltip('Refresh announcements'));
      await tester.pumpAndSettle();
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(seen.last.after, isNull);
    },
  );
  testWidgets(
    'linked cards open source and separate full-screen action opens swipe viewer',
    (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AnnouncementsScreen(
            populationRole: PopulationRole.student,
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
    'errors retry, post types load independently, and empty state is clear',
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
        MaterialApp(
          home: AnnouncementsScreen(
            populationRole: PopulationRole.student,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No announcements yet'), findsOneWidget);
      await tester.tap(find.text('Information'));
      await tester.pumpAndSettle();
      expect(queries.last.postType, AnnouncementPostType.information);
      expect(queries.last.audienceRole, PopulationRole.student);
      await tester.tap(find.text('Announcement'));
      await tester.pumpAndSettle();
      expect(queries.last.postType, AnnouncementPostType.announcement);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(queries.last.postType, isNull);
    },
  );
  testWidgets(
    'post type switch ignores late results from the previous request',
    (tester) async {
      final pending = Completer<List<Announcement>>();
      final repo = AnnouncementRepository(
        fetch: (q) =>
            q.postType == null ? pending.future : Future.value([post('new')]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AnnouncementsScreen(
            populationRole: PopulationRole.student,
            repository: repo,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Information'));
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
          populationRole: PopulationRole.student,
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
            populationRole: PopulationRole.student,
            repository: AnnouncementRepository(
              fetch: (_) async => [post('one', link: true)],
            ),
            launcher: (_) async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Post one'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post one'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unable to open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing population role fails closed without querying', (
    tester,
  ) async {
    var queries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AnnouncementsScreen(
          repository: AnnouncementRepository(
            fetch: (_) async {
              queries++;
              return [post('secret')];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh announcements'));
    await tester.pumpAndSettle();
    expect(queries, 0);
    expect(find.text('Updates unavailable for this account'), findsOneWidget);
    expect(find.text('Post secret'), findsNothing);
    expect(find.text('Information'), findsNothing);
  });

  testWidgets('feed is scoped to the signed-in population role', (
    tester,
  ) async {
    final queries = <AnnouncementQuery>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AnnouncementsScreen(
          populationRole: PopulationRole.nonTeaching,
          repository: AnnouncementRepository(
            fetch: (q) async {
              queries.add(q);
              return [post('one')];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(queries.single.audienceRole, PopulationRole.nonTeaching);
    expect(queries.single.status, AnnouncementStatus.published);
    expect(find.text('Post one'), findsOneWidget);
  });

  testWidgets('video posts open their source from feed and viewer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = <Uri>[];
    final video = Announcement.fromJson('vid', {
      'kind': 'link',
      'postType': 'information',
      'mediaType': 'video',
      'title': 'Campus video',
      'body': 'Watch the tour',
      'sourceUrl': 'https://video.example/tour',
      'status': 'published',
      'publishedAt': DateTime.utc(2026, 11, 14),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AnnouncementsScreen(
          populationRole: PopulationRole.teaching,
          repository: AnnouncementRepository(fetch: (_) async => [video]),
          launcher: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final watch = find.widgetWithText(FilledButton, 'Watch Video');
    await tester.ensureVisible(watch);
    expect(tester.getSize(watch).height, greaterThanOrEqualTo(48));
    await tester.tap(watch);
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'https://video.example/tour');
    await tester.tap(find.byTooltip('View full screen'));
    await tester.pumpAndSettle();
    final viewerWatch = find.widgetWithText(FilledButton, 'Watch Video');
    await tester.ensureVisible(viewerWatch);
    await tester.tap(viewerWatch);
    await tester.pumpAndSettle();
    expect(opened, hasLength(2));
  });

  testWidgets('role arriving after first build loads the scoped feed', (
    tester,
  ) async {
    final queries = <AnnouncementQuery>[];
    final repo = AnnouncementRepository(
      fetch: (q) async {
        queries.add(q);
        return [post('one')];
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: AnnouncementsScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(queries, isEmpty);
    await tester.pumpWidget(
      MaterialApp(
        home: AnnouncementsScreen(
          populationRole: PopulationRole.teaching,
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(queries.single.audienceRole, PopulationRole.teaching);
    expect(find.text('Post one'), findsOneWidget);
  });
}
