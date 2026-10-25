import 'package:flutter/material.dart';

import '../domain/mood_v2_analytics.dart';

/// Read-only, gated presentation for multiple Mood V2 events per Manila day.
/// It intentionally accepts normalized events only and never exposes notes or
/// expression metadata.
class MoodV2HistoryPanel extends StatelessWidget {
  const MoodV2HistoryPanel({
    super.key,
    required this.history,
    this.errorMessage,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.paginationErrorMessage,
    this.onLoadMore,
  });

  final MoodHistoryWindow? history;
  final String? errorMessage;
  final bool hasMore;
  final bool isLoadingMore;
  final String? paginationErrorMessage;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (errorMessage != null) {
      return _HistoryMessage(
        icon: Icons.error_outline,
        text: errorMessage!,
        color: colors.error,
      );
    }
    if (history == null) {
      return _HistoryMessage(
        icon: Icons.mood_outlined,
        text: 'No mood entries in this history window.',
        color: colors.onSurfaceVariant,
      );
    }
    final events = history!.uniqueEvents;
    if (events.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HistoryMessage(
            icon: Icons.mood_outlined,
            text: 'No mood entries in this history window.',
            color: colors.onSurfaceVariant,
          ),
          if (paginationErrorMessage != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                paginationErrorMessage!,
                key: const Key('mood-v2-history-pagination-error'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ),
          ],
          if (hasMore && onLoadMore != null) ...[
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: isLoadingMore
                  ? 'Loading more mood history'
                  : 'Load more mood history',
              child: OutlinedButton.icon(
                key: const Key('mood-v2-history-load-more'),
                onPressed: isLoadingMore ? null : onLoadMore,
                icon: isLoadingMore
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(isLoadingMore ? 'Loading history…' : 'Load more'),
              ),
            ),
          ],
        ],
      );
    }
    final days = MoodAnalytics.dailyAggregates(events);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListView.separated(
          key: const Key('mood-v2-history-list'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: days.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final day = days[days.length - 1 - index];
            return _MoodDayCard(
              day: day,
              isPartial: history!.coverage == MoodHistoryCoverage.partial,
            );
          },
        ),
        if (paginationErrorMessage != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              paginationErrorMessage!,
              key: const Key('mood-v2-history-pagination-error'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
        ],
        if (hasMore && onLoadMore != null) ...[
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: isLoadingMore
                ? 'Loading more mood history'
                : 'Load more mood history',
            child: OutlinedButton.icon(
              key: const Key('mood-v2-history-load-more'),
              onPressed: isLoadingMore ? null : onLoadMore,
              icon: isLoadingMore
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: Text(isLoadingMore ? 'Loading history…' : 'Load more'),
            ),
          ),
        ],
      ],
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: ListTile(
      leading: Icon(icon, color: color),
      title: Text(text),
    ),
  );
}

class _MoodDayCard extends StatelessWidget {
  const _MoodDayCard({required this.day, required this.isPartial});
  final MoodDailyAggregate day;
  final bool isPartial;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(day.dateKey, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final event in day.events)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${_manilaTime(event.occurredAt).format(context)} · Mood ${event.level}/5',
                ),
              ),
            if (isPartial) ...[
              const SizedBox(height: 4),
              Text(
                'History window is incomplete.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  TimeOfDay _manilaTime(DateTime instant) {
    // History is grouped by Manila date keys, so use the same fixed calendar
    // zone for its wall-clock labels instead of the device or test host zone.
    return TimeOfDay.fromDateTime(
      instant.toUtc().add(const Duration(hours: 8)),
    );
  }
}
