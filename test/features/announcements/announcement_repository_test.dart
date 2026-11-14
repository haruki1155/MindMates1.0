import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mind_mates/features/announcements/models/announcement.dart';
import 'package:mind_mates/features/announcements/data/announcement_repository.dart';

void main() {
  test(
    'published queries constrain status and preserve timestamp/id cursors',
    () async {
      final queries = <AnnouncementQuery>[];
      final repository = AnnouncementRepository(
        fetch: (query) async {
          queries.add(query);
          return List.generate(
            20,
            (i) => Announcement.fromJson('post-$i', {
              'status': 'published',
              'kind': 'original',
              'category': 'placements',
              'title': 'Job $i',
              'body': 'Details',
              'publishedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
              'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
            }),
          );
        },
      );
      final page = await repository.loadPublished(
        category: AnnouncementCategory.placements,
      );
      await repository.loadPublished(
        category: AnnouncementCategory.placements,
        after: page.nextCursor,
      );
      expect(queries.first.status, AnnouncementStatus.published);
      expect(queries.first.category, AnnouncementCategory.placements);
      expect(queries.last.after!.id, 'post-19');
      expect(queries.last.after!.at.millisecondsSinceEpoch, 1000);
      expect(queries.first.orderField, 'publishedAt');
    },
  );
  test(
    'callables receive only mutation contract and preview remains editable data',
    () async {
      final calls = <String, Map<String, dynamic>>{};
      final repository = AnnouncementRepository(
        call: (name, data) async {
          calls[name] = data;
          return name == 'previewAnnouncementLink'
              ? {'available': false, 'sourceUrl': data['url']}
              : {'id': 'new', 'revision': 1};
        },
      );
      await repository.save(
        expectedRevision: 0,
        action: AnnouncementAction.publish,
        post: const AnnouncementInput(
          kind: AnnouncementKind.original,
          category: AnnouncementCategory.careerGuidance,
          title: 'Talk',
          body: 'Join',
        ),
      );
      expect(calls['saveAnnouncement']!['expectedRevision'], 0);
      expect(calls['saveAnnouncement']!['action'], 'publish');
      expect(
        (calls['saveAnnouncement']!['post'] as Map)['category'],
        'careerGuidance',
      );
      final preview = await repository.previewLink('https://example.com/post');
      expect(preview.available, false);
      expect(preview.sourceUrl, 'https://example.com/post');
    },
  );
  test('malformed optional links cannot become executable destinations', () {
    final post = Announcement.fromJson('bad', {
      'sourceUrl': 'javascript:alert(1)',
      'imageUrl': 'file:///x',
      'revision': 'bad',
    });
    expect(post.sourceUri, isNull);
    expect(post.imageUrl, isEmpty);
    expect(post.revision, 0);
  });
  test(
    'empty pages end pagination and managed ordering uses updated time',
    () async {
      AnnouncementQuery? seen;
      final repository = AnnouncementRepository(
        fetch: (query) async {
          seen = query;
          return [];
        },
      );
      expect(
        (await repository.loadManaged(
          status: AnnouncementStatus.draft,
        )).nextCursor,
        isNull,
      );
      expect(seen!.orderField, 'updatedAt');
    },
  );
}
