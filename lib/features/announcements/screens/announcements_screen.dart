import 'package:flutter/material.dart';
import '../data/announcement_feed_controller.dart';
import '../data/announcement_repository.dart';
import '../models/announcement.dart';
import '../services/announcement_link_launcher.dart';
import '../widgets/announcement_card.dart';
import 'announcement_viewer_screen.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key, this.repository, this.launcher});
  final AnnouncementRepository? repository;
  final AnnouncementSourceLauncher? launcher;
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen>
    with WidgetsBindingObserver {
  late final _feed = AnnouncementFeedController(
    widget.repository ?? AnnouncementRepository(),
  );
  final _scroll = ScrollController();
  bool _external = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _feed.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _external) {
      _external = false;
      _feed.load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feed.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openSource(
    BuildContext sourceContext,
    Announcement post,
  ) async {
    final uri = post.sourceUri;
    if (uri == null) return;
    _external = true;
    var opened = false;
    try {
      opened = await (widget.launcher ?? openAnnouncementSource)(uri);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (!opened) {
      _external = false;
      if (sourceContext.mounted) {
        ScaffoldMessenger.of(sourceContext).showSnackBar(
          SnackBar(
            content: const Text('Unable to open the original post.'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _openSource(sourceContext, post),
            ),
          ),
        );
      }
    } else {
      await _feed.load();
    }
  }

  void _view(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnnouncementViewerScreen(
          feed: _feed,
          initialIndex: index,
          onOpenSource: _openSource,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Announcements'),
      actions: [
        IconButton(
          tooltip: 'Refresh announcements',
          onPressed: () => _feed.load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _feed,
        builder: (context, _) => RefreshIndicator(
          onRefresh: () => _feed.load(),
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Opportunities start here',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text('Career guidance and placement updates from PACC.'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _feed.category == null,
                    onSelected: (_) => _feed.selectCategory(null),
                  ),
                  for (final category in AnnouncementCategory.values)
                    ChoiceChip(
                      label: Text(category.label),
                      selected: _feed.category == category,
                      onSelected: (_) => _feed.selectCategory(category),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (_feed.error != null)
                Column(
                  children: [
                    Text(_feed.error!),
                    TextButton(
                      onPressed: () => _feed.load(
                        more: _feed.posts.isNotEmpty && _feed.cursor != null,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              if (!_feed.loading && _feed.error == null && _feed.posts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      Icon(Icons.campaign_outlined, size: 48),
                      SizedBox(height: 16),
                      Text('No announcements yet'),
                      SizedBox(height: 8),
                      Text('New opportunities will appear here.'),
                    ],
                  ),
                ),
              for (var i = 0; i < _feed.posts.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AnnouncementCard(
                    key: ValueKey(_feed.posts[i].id),
                    announcement: _feed.posts[i],
                    onOpenContent: _feed.loading
                        ? null
                        : _feed.posts[i].sourceUri != null
                        ? () => _openSource(context, _feed.posts[i])
                        : () => _view(i),
                    onOpenViewer: _feed.loading ? null : () => _view(i),
                  ),
                ),
              if (_feed.loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (!_feed.loading && _feed.cursor != null)
                OutlinedButton(
                  onPressed: () => _feed.load(more: true),
                  child: const Text('Load more announcements'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
