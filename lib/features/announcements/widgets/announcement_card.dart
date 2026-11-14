import 'package:flutter/material.dart';
import '../models/announcement.dart';

class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({
    super.key,
    required this.announcement,
    required this.onOpenContent,
    this.onOpenViewer,
    this.fullScreen = false,
  });
  final Announcement announcement;
  final VoidCallback? onOpenContent, onOpenViewer;
  final bool fullScreen;
  @override
  Widget build(BuildContext context) {
    final post = announcement;
    final date = post.publishedAt?.toLocal();
    final dateLabel = date == null
        ? ''
        : '${date.month}/${date.day}/${date.year}';
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: const Icon(Icons.campaign_outlined),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PACC ? Official update',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${post.content.category.label}${dateLabel.isEmpty ? '' : ' · $dateLabel'}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(height: 1.6),
                      ),
                    ],
                  ),
                ),
                if (!fullScreen)
                  IconButton(
                    tooltip: 'View full screen',
                    onPressed: onOpenViewer,
                    icon: const Icon(Icons.open_in_full),
                  ),
              ],
            ),
          ),
          InkWell(
            onTap: onOpenContent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (post.imageUrl.isNotEmpty)
                  Image.network(
                    post.imageUrl,
                    height: fullScreen ? 240 : 200,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(Icons.image_not_supported_outlined),
                          SizedBox(width: 8),
                          Text('Image unavailable'),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        post.body,
                        maxLines: fullScreen ? null : 5,
                        overflow: fullScreen ? null : TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      if (post.sourceUri != null)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Icon(Icons.open_in_new, size: 16),
                            Text(
                              'Open original post',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              post.sourceUri!.host,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        )
                      else if (!fullScreen)
                        const Text('Read announcement →'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
