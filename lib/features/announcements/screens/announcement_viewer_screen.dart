import 'package:flutter/material.dart';
import '../data/announcement_feed_controller.dart';
import '../models/announcement.dart';
import '../widgets/announcement_card.dart';
import '../widgets/announcement_presentation.dart';

class AnnouncementViewerScreen extends StatefulWidget {
  const AnnouncementViewerScreen({
    super.key,
    required this.feed,
    required this.initialIndex,
    required this.onOpenSource,
  });
  final AnnouncementFeedController feed;
  final int initialIndex;
  final Future<void> Function(BuildContext, Announcement) onOpenSource;
  @override
  State<AnnouncementViewerScreen> createState() =>
      _AnnouncementViewerScreenState();
}

class _AnnouncementViewerScreenState extends State<AnnouncementViewerScreen> {
  late PageController _pages;
  late int _index;
  String? _selectedId;
  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _selectedId = widget.feed.posts.elementAtOrNull(_index)?.id;
    _pages = PageController(initialPage: _index);
    widget.feed.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    final found = widget.feed.posts.indexWhere((p) => p.id == _selectedId);
    final next = found >= 0
        ? found
        : (_index.clamp(0, (widget.feed.posts.length - 1).clamp(0, 1 << 30)));
    if (next != _index) {
      _index = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_index);
      });
    }
    _selectedId = widget.feed.posts.elementAtOrNull(_index)?.id;
    setState(() {});
  }

  void _goToPage(BuildContext context, int page) {
    final duration = announcementTransitionDuration(context);
    if (duration == Duration.zero) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(page, duration: duration, curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    widget.feed.removeListener(_changed);
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: announcementMobileTheme(Theme.of(context)),
    child: Builder(builder: (context) => _buildViewer(context)),
  );
  Widget _buildViewer(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('PACC announcements'),
      actions: [
        IconButton(
          tooltip: 'Refresh announcements',
          onPressed: () => widget.feed.load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (widget.feed.loading) const LinearProgressIndicator(),
          if (widget.feed.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(widget.feed.error!),
                  TextButton(
                    onPressed: widget.feed.retry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: widget.feed.posts.isEmpty
                ? const Center(child: Text('No announcements available'))
                : PageView.builder(
                    controller: _pages,
                    scrollDirection: Axis.vertical,
                    itemCount: widget.feed.posts.length,
                    onPageChanged: (index) {
                      setState(() {
                        _index = index;
                        _selectedId = widget.feed.posts[index].id;
                      });
                      if (index >= widget.feed.posts.length - 2) {
                        widget.feed.load(more: true);
                      }
                    },
                    itemBuilder: (context, index) {
                      final post = widget.feed.posts[index];
                      return SingleChildScrollView(
                        key: ValueKey(post.id),
                        padding: const EdgeInsets.all(16),
                        child: AnnouncementCard(
                          announcement: post,
                          fullScreen: true,
                          onOpenContent: widget.feed.loading
                              ? null
                              : post.sourceUri == null
                              ? null
                              : () => widget.onOpenSource(context, post),
                        ),
                      );
                    },
                  ),
          ),
          if (widget.feed.posts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous announcement',
                    onPressed: _index > 0
                        ? () => _goToPage(context, _index - 1)
                        : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  Expanded(
                    child: Text(
                      '${_index + 1} of ${widget.feed.posts.length} · Swipe or use arrows',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next announcement',
                    onPressed: _index < widget.feed.posts.length - 1
                        ? () => _goToPage(context, _index + 1)
                        : null,
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ],
              ),
            ),
          if (!widget.feed.loading &&
              widget.feed.cursor != null &&
              _index == widget.feed.posts.length - 1)
            TextButton(
              onPressed: () => widget.feed.load(more: true),
              child: const Text('Load more announcements'),
            ),
        ],
      ),
    ),
  );
}
