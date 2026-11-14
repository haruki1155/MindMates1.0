import 'package:flutter/foundation.dart';
import 'announcement_repository.dart';
import '../models/announcement.dart';

/// Shared state keeps list and full-screen pages in the same feed/order.
class AnnouncementFeedController extends ChangeNotifier {
  AnnouncementFeedController(this.repository);
  final AnnouncementRepository repository;
  final List<Announcement> posts = [];
  AnnouncementCategory? category;
  AnnouncementCursor? cursor;
  bool loading = false;
  String? error;
  int _generation = 0;
  bool _disposed = false;
  Future<void> selectCategory(AnnouncementCategory? value) async {
    category = value;
    posts.clear();
    cursor = null;
    await load();
  }

  Future<void> load({bool more = false}) async {
    if (more && (loading || cursor == null)) return;
    final generation = ++_generation;
    final target = more ? 0 : posts.length;
    loading = true;
    error = null;
    notifyListeners();
    try {
      var page = await repository.loadPublished(
        category: category,
        after: more ? cursor : null,
      );
      final fresh = <Announcement>[...page.items];
      // Refresh all currently loaded pages so a viewer beyond page one stays anchored.
      while (!more && fresh.length < target && page.nextCursor != null) {
        if (_disposed || generation != _generation) return;
        page = await repository.loadPublished(
          category: category,
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
