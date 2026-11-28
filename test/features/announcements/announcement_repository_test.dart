import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mind_mates/features/announcements/models/announcement.dart';
import 'package:mind_mates/features/announcements/data/announcement_repository.dart';
import 'package:mind_mates/features/announcements/data/announcement_feed_controller.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'dart:async';

void main() {
  test(
    'published queries constrain status, audience and type and preserve cursors',
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
        audienceRole: PopulationRole.teaching,
        postType: AnnouncementPostType.information,
      );
      await repository.loadPublished(
        audienceRole: PopulationRole.teaching,
        postType: AnnouncementPostType.information,
        after: page.nextCursor,
      );
      expect(queries.first.status, AnnouncementStatus.published);
      expect(queries.first.audienceRole, PopulationRole.teaching);
      expect(queries.first.postType, AnnouncementPostType.information);
      expect(queries.last.audienceRole, PopulationRole.teaching);
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
          postType: AnnouncementPostType.information,
          audienceRoles: [PopulationRole.nonTeaching, PopulationRole.student],
          mediaType: AnnouncementMediaType.video,
          title: 'Talk',
          body: 'Join',
        ),
      );
      expect(calls['saveAnnouncement']!['expectedRevision'], 0);
      expect(calls['saveAnnouncement']!['action'], 'publish');
      final sent = calls['saveAnnouncement']!['post'] as Map;
      expect(sent['postType'], 'information');
      expect(sent['audienceRoles'], ['student', 'nonTeaching']);
      expect(
        sent['mediaType'],
        'standard',
        reason: 'original posts are never video',
      );
      expect(sent.containsKey('category'), isFalse);
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
  test('legacy records default type, media and audience safely', () {
    final legacy = Announcement.fromJson('old', {
      'status': 'published',
      'kind': 'link',
      'category': 'placements',
      'sourceUrl': 'https://example.com/v',
    });
    expect(legacy.postType, AnnouncementPostType.announcement);
    expect(legacy.mediaType, AnnouncementMediaType.standard);
    expect(legacy.audienceRoles, PopulationRole.values);
    expect(legacy.content.category, AnnouncementCategory.placements);
    expect(legacy.isVideo, isFalse);
    final video = Announcement.fromJson('v', {
      'kind': 'link',
      'postType': 'information',
      'mediaType': 'video',
      'audienceRoles': ['teaching'],
      'sourceUrl': 'https://example.com/v',
    });
    expect(video.postType, AnnouncementPostType.information);
    expect(video.isVideo, isTrue);
    expect(video.audienceRoles, [PopulationRole.teaching]);
    expect(video.content.category, isNull);
    expect(video.content.toJson()['mediaType'], 'video');
  });

  test(
    'feed controller fails closed without a role and ignores stale pages',
    () async {
      final queries = <AnnouncementQuery>[];
      final pending = <Completer<List<Announcement>>>[];
      final repository = AnnouncementRepository(
        fetch: (query) {
          queries.add(query);
          final completer = Completer<List<Announcement>>();
          pending.add(completer);
          return completer.future;
        },
      );
      final controller = AnnouncementFeedController(repository);
      await controller.load();
      await controller.retry();
      await controller.selectPostType(AnnouncementPostType.information);
      expect(queries, isEmpty);
      expect(controller.loading, isFalse);
      expect(controller.posts, isEmpty);

      Announcement post(String id) => Announcement.fromJson(id, {
        'status': 'published',
        'title': id,
        'publishedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      });
      final first = controller.setAudienceRole(PopulationRole.student);
      expect(queries.single.audienceRole, PopulationRole.student);
      expect(queries.single.postType, AnnouncementPostType.information);
      final second = controller.selectPostType(null);
      pending[1].complete([post('fresh')]);
      await second;
      pending[0].complete([post('stale')]);
      await first;
      expect(controller.posts.map((p) => p.id), ['fresh']);
      expect(queries.last.postType, isNull);

      await controller.setAudienceRole(null);
      expect(controller.posts, isEmpty);
      expect(queries, hasLength(2));
      controller.dispose();
    },
  );
}
