import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../services/firebase/firebase_callable_router.dart';
import '../models/announcement.dart';
import '../../../models/profile_roles.dart';

class AnnouncementCursor {
  const AnnouncementCursor(this.at, this.id);
  final DateTime at;
  final String id;
}

class AnnouncementQuery {
  const AnnouncementQuery({
    this.status,
    this.audienceRole,
    this.postType,
    this.after,
    required this.orderField,
  });
  final AnnouncementStatus? status;
  final PopulationRole? audienceRole;
  final AnnouncementPostType? postType;
  final AnnouncementCursor? after;
  final String orderField;
}

class AnnouncementPage {
  const AnnouncementPage(this.items, this.nextCursor);
  final List<Announcement> items;
  final AnnouncementCursor? nextCursor;
}

typedef AnnouncementFetch =
    Future<List<Announcement>> Function(AnnouncementQuery query);
typedef AnnouncementCall =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> data,
    );

class AnnouncementRepository {
  AnnouncementRepository({this.fetch, this.call});
  final AnnouncementFetch? fetch;
  final AnnouncementCall? call;

  /// [audienceRole] is required so an unscoped published query cannot be built.
  Future<AnnouncementPage> loadPublished({
    required PopulationRole audienceRole,
    AnnouncementPostType? postType,
    AnnouncementCursor? after,
  }) => _load(
    AnnouncementQuery(
      status: AnnouncementStatus.published,
      audienceRole: audienceRole,
      postType: postType,
      after: after,
      orderField: 'publishedAt',
    ),
  );
  Future<AnnouncementPage> loadManaged({
    AnnouncementStatus? status,
    AnnouncementCursor? after,
  }) => _load(
    AnnouncementQuery(status: status, after: after, orderField: 'updatedAt'),
  );
  Future<AnnouncementPage> _load(AnnouncementQuery spec) async {
    final items = await (fetch ?? _fetchFirestore)(spec);
    final last = items.lastOrNull;
    final at = spec.orderField == 'publishedAt'
        ? last?.publishedAt
        : last?.updatedAt;
    return AnnouncementPage(
      List.unmodifiable(items),
      items.length == 20 && at != null
          ? AnnouncementCursor(at, last!.id)
          : null,
    );
  }

  Future<List<Announcement>> _fetchFirestore(AnnouncementQuery spec) async {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'announcements',
    );
    if (spec.status != null) {
      query = query.where('status', isEqualTo: spec.status!.name);
    }
    if (spec.audienceRole != null) {
      query = query.where(
        'audienceRoles',
        arrayContains: spec.audienceRole!.storedValue,
      );
    }
    if (spec.postType != null) {
      query = query.where('postType', isEqualTo: spec.postType!.name);
    }
    query = query
        .orderBy(spec.orderField, descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    if (spec.after != null) {
      query = query.startAfter([
        Timestamp.fromDate(spec.after!.at),
        spec.after!.id,
      ]);
    }
    final result = await query
        .limit(20)
        .get(const GetOptions(source: Source.server));
    return result.docs
        .map((doc) => Announcement.fromJson(doc.id, doc.data()))
        .toList();
  }

  Future<Map<String, dynamic>> save({
    String? id,
    required int expectedRevision,
    required AnnouncementAction action,
    AnnouncementInput? post,
  }) => (call ?? _callFirebase)('saveAnnouncement', {
    'id': ?id,
    'expectedRevision': expectedRevision,
    'action': action.name,
    'post': ?post?.toJson(),
  });
  Future<AnnouncementLinkPreview> previewLink(String url) async =>
      AnnouncementLinkPreview.fromJson(
        await (call ?? _callFirebase)('previewAnnouncementLink', {
          'url': url.trim(),
        }),
      );
  Future<Map<String, dynamic>> _callFirebase(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await FirebaseFunctions.instance
        .routedCallable(name)
        .call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data);
  }
}
