import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/profile_roles.dart';

enum AnnouncementKind { original, link }

enum AnnouncementCategory {
  careerGuidance,
  placements;

  String get label => this == careerGuidance ? 'Career Guidance' : 'Placements';
}

enum AnnouncementPostType {
  announcement,
  information;

  String get label => this == announcement ? 'Announcement' : 'Information';
}

enum AnnouncementMediaType { standard, video }

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((v) => v.name == raw).firstOrNull ?? fallback;

/// Canonical order (student, teaching, nonTeaching), matching the backend.
List<PopulationRole> canonicalAudienceRoles(Iterable<PopulationRole> roles) =>
    PopulationRole.values.where(roles.contains).toList(growable: false);

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
    this.postType = AnnouncementPostType.announcement,
    this.audienceRoles = PopulationRole.values,
    this.mediaType = AnnouncementMediaType.standard,
    this.category,
    required this.title,
    required this.body,
    this.sourceUrl = '',
    this.imageUrl = '',
  });
  final AnnouncementKind kind;
  final AnnouncementPostType postType;
  final List<PopulationRole> audienceRoles;
  final AnnouncementMediaType mediaType;

  /// Historical only; the backend preserves it on edits.
  final AnnouncementCategory? category;
  final String title, body, sourceUrl, imageUrl;
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'postType': postType.name,
    'audienceRoles': canonicalAudienceRoles(
      audienceRoles,
    ).map((role) => role.storedValue).toList(),
    'mediaType': kind == AnnouncementKind.link
        ? mediaType.name
        : AnnouncementMediaType.standard.name,
    'category': ?category?.name,
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
  AnnouncementPostType get postType => content.postType;
  AnnouncementMediaType get mediaType => content.mediaType;
  List<PopulationRole> get audienceRoles => content.audienceRoles;
  bool get isVideo =>
      mediaType == AnnouncementMediaType.video && sourceUri != null;
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
          postType: _enumValue(
            AnnouncementPostType.values,
            data['postType'],
            AnnouncementPostType.announcement,
          ),
          audienceRoles: _audienceRoles(data['audienceRoles']),
          mediaType: _enumValue(
            AnnouncementMediaType.values,
            data['mediaType'],
            AnnouncementMediaType.standard,
          ),
          category: AnnouncementCategory.values
              .where((v) => v.name == data['category'])
              .firstOrNull,
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

// Legacy (pre-targeting) records reached every app-user role.
List<PopulationRole> _audienceRoles(Object? raw) {
  final roles = raw is List
      ? canonicalAudienceRoles(
          PopulationRole.values.where((role) => raw.contains(role.name)),
        )
      : const <PopulationRole>[];
  return roles.isEmpty ? PopulationRole.values : roles;
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
