import 'package:flutter/foundation.dart';
import 'announcement_repository.dart';
import '../models/announcement.dart';
import '../../../models/profile_roles.dart';

/// Shared state keeps list and full-screen pages in the same feed/order.
class AnnouncementFeedController extends ChangeNotifier {
  AnnouncementFeedController(this.repository, {this.audienceRole});
  final AnnouncementRepository repository;
  final List<Announcement> posts = [];
  PopulationRole? audienceRole;
  AnnouncementPostType? postType;
  AnnouncementCursor? cursor;
  bool loading = false;
  String? error;
  bool _failedMore = false;
  Future<void> retry() => load(more: _failedMore);
  int _generation = 0;
  bool _disposed = false;
  Future<void> selectPostType(AnnouncementPostType? value) async {
    postType = value;
    posts.clear();
    cursor = null;
    await load();
  }

  Future<void> setAudienceRole(PopulationRole? value) async {
    if (value == audienceRole) return;
    audienceRole = value;
    posts.clear();
    cursor = null;
    await load();
  }

  Future<void> load({bool more = false}) async {
    if (more && (loading || cursor == null)) return;
    final generation = ++_generation;
    final role = audienceRole;
    if (role == null) {
      // Fail closed: never issue an unscoped published query.
      posts.clear();
      cursor = null;
      loading = false;
      error = null;
      if (!_disposed) notifyListeners();
      return;
    }
    final target = more ? 0 : posts.length;
    loading = true;
    error = null;
    notifyListeners();
    try {
      var page = await repository.loadPublished(
        audienceRole: role,
        postType: postType,
        after: more ? cursor : null,
      );
      final fresh = <Announcement>[...page.items];
      // Refresh all currently loaded pages so a viewer beyond page one stays anchored.
      while (!more && fresh.length < target && page.nextCursor != null) {
        if (_disposed || generation != _generation) return;
        page = await repository.loadPublished(
          audienceRole: role,
          postType: postType,
          after: page.nextCursor,
        );
        fresh.addAll(page.items);
      }
      if (_disposed || generation != _generation) return;
      if (!more) posts.clear();
      final ids = posts.map((post) => post.id).toSet();
      posts.addAll(fresh.where((post) => ids.add(post.id)));
      cursor = page.nextCursor;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _failedMore = more;
        error = 'Unable to load announcements. Please retry.';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
