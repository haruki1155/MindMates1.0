import 'package:cloud_firestore/cloud_firestore.dart';

enum AnnouncementKind { original, link }

enum AnnouncementCategory {
  careerGuidance,
  placements;

  String get label => this == careerGuidance ? 'Career Guidance' : 'Placements';
}

enum AnnouncementStatus { draft, published, archived }

enum AnnouncementAction { saveDraft, publish, archive }

Uri? announcementHttpUri(Object? value) {
  final uri = Uri.tryParse(value?.toString() ?? '');
  return uri != null &&
          ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

DateTime? _date(Object? value) => value is Timestamp
    ? value.toDate()
    : value is DateTime
    ? value
    : null;

class AnnouncementInput {
  const AnnouncementInput({
    required this.kind,
    required this.category,
    required this.title,
    required this.body,
    this.sourceUrl = '',
    this.imageUrl = '',
  });
  final AnnouncementKind kind;
  final AnnouncementCategory category;
  final String title, body, sourceUrl, imageUrl;
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'category': category.name,
    'title': title.trim(),
    'body': body.trim(),
    'sourceUrl': kind == AnnouncementKind.link ? sourceUrl.trim() : '',
    'imageUrl': imageUrl.trim(),
  };
}

class Announcement {
  const Announcement({
    required this.id,
    required this.content,
    required this.status,
    required this.revision,
    this.publishedAt,
    this.updatedAt,
  });
  final String id;
  final AnnouncementInput content;
  final AnnouncementStatus status;
  final int revision;
  final DateTime? publishedAt, updatedAt;
  String get title => content.title;
  String get body => content.body;
  String get imageUrl => content.imageUrl;
  Uri? get sourceUri => content.kind == AnnouncementKind.link
      ? announcementHttpUri(content.sourceUrl)
      : null;
  factory Announcement.fromJson(String id, Map<String, dynamic> data) =>
      Announcement(
        id: id,
        content: AnnouncementInput(
          kind: data['kind'] == 'link'
              ? AnnouncementKind.link
              : AnnouncementKind.original,
          category: data['category'] == 'placements'
              ? AnnouncementCategory.placements
              : AnnouncementCategory.careerGuidance,
          title: data['title']?.toString() ?? '',
          body: data['body']?.toString() ?? '',
          sourceUrl: announcementHttpUri(data['sourceUrl'])?.toString() ?? '',
          imageUrl: announcementHttpUri(data['imageUrl'])?.toString() ?? '',
        ),
        status:
            AnnouncementStatus.values
                .where((v) => v.name == data['status'])
                .firstOrNull ??
            AnnouncementStatus.draft,
        revision: (data['revision'] is num)
            ? (data['revision'] as num).toInt()
            : 0,
        publishedAt: _date(data['publishedAt']),
        updatedAt: _date(data['updatedAt']),
      );
}

class AnnouncementLinkPreview {
  const AnnouncementLinkPreview({
    required this.sourceUrl,
    required this.available,
    this.title = '',
    this.description = '',
    this.imageUrl = '',
  });
  final String sourceUrl, title, description, imageUrl;
  final bool available;
  factory AnnouncementLinkPreview.fromJson(Map<String, dynamic> data) =>
      AnnouncementLinkPreview(
        sourceUrl: data['sourceUrl']?.toString() ?? '',
        available: data['available'] == true,
        title: data['title']?.toString() ?? '',
        description: data['description']?.toString() ?? '',
        imageUrl: announcementHttpUri(data['imageUrl'])?.toString() ?? '',
      );
}
