import 'package:flutter/material.dart';
import '../data/announcement_repository.dart';
import '../models/announcement.dart';
import '../widgets/announcement_editor.dart';

class ManageAnnouncementsPage extends StatefulWidget {
  const ManageAnnouncementsPage({super.key, this.repository});
  final AnnouncementRepository? repository;
  @override
  State<ManageAnnouncementsPage> createState() =>
      _ManageAnnouncementsPageState();
}

class _ManageAnnouncementsPageState extends State<ManageAnnouncementsPage> {
  late final _repository = widget.repository ?? AnnouncementRepository();
  AnnouncementStatus _status = AnnouncementStatus.published;
  final List<Announcement> _posts = [];
  AnnouncementCursor? _cursor;
  bool _loading = true;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _posts.clear();
        _cursor = null;
      }
    });
    try {
      final page = await _repository.loadManaged(
        status: _status,
        after: more ? _cursor : null,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _posts.map((p) => p.id).toSet();
        _posts.addAll(page.items.where((p) => ids.add(p.id)));
        _cursor = page.nextCursor;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Unable to load announcements. Please retry.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _edit([Announcement? post]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            AnnouncementEditor(repository: _repository, announcement: post),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _archive(Announcement post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive announcement?'),
        content: const Text(
          'This removes it from the mobile feed. Its history is retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await _repository.save(
        id: post.id,
        expectedRevision: post.revision,
        action: AnnouncementAction.archive,
      );
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to archive. Reload the post and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 20,
        runSpacing: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Announcements',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Text('Career guidance and placement updates'),
            ],
          ),
          FilledButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('New announcement'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final status in AnnouncementStatus.values)
            ChoiceChip(
              label: Text(switch (status) {
                AnnouncementStatus.draft => 'Drafts',
                AnnouncementStatus.published => 'Published',
                AnnouncementStatus.archived => 'Archived',
              }),
              selected: _status == status,
              onSelected: (_) {
                setState(() => _status = status);
                _load();
              },
            ),
          IconButton(
            onPressed: _loading ? null : () => _load(),
            tooltip: 'Refresh announcements',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (_error != null)
        Column(
          children: [
            Text(_error!),
            TextButton(
              onPressed: () => _load(more: _posts.isNotEmpty),
              child: const Text('Retry'),
            ),
          ],
        ),
      if (!_loading && _posts.isEmpty && _error == null)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Text('No announcements here yet.'),
        ),
      for (final post in _posts)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.content.category.label,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  post.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(post.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                if (post.sourceUri != null) Text(post.sourceUri!.host),
                const SizedBox(height: 8),
                if (post.status != AnnouncementStatus.archived)
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _loading ? null : () => _edit(post),
                        child: const Text('Edit'),
                      ),
                      TextButton(
                        onPressed: _loading ? null : () => _archive(post),
                        child: const Text('Archive'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ),
        ),
      if (!_loading && _cursor != null)
        TextButton(
          onPressed: () => _load(more: true),
          child: const Text('Load more'),
        ),
    ],
  );
}
