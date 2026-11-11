import 'package:flutter/material.dart';

import '../domain/mood_v2_analytics.dart';

/// Read-only, gated presentation for multiple Mood V2 events per Manila day.
/// Personal details are opt-in for an authenticated owner's journey screen.
class MoodV2HistoryPanel extends StatelessWidget {
  const MoodV2HistoryPanel({
    super.key,
    required this.history,
    this.errorMessage,
    this.isLoading = false,
    this.onRetry,
    this.analytics,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.paginationErrorMessage,
    this.onLoadMore,
    this.showPersonalDetails = false,
  });

  final MoodHistoryWindow? history;
  final String? errorMessage;
  final bool isLoading;
  final VoidCallback? onRetry;
  final MoodAnalyticsSnapshot? analytics;
  final bool hasMore;
  final bool isLoadingMore;
  final String? paginationErrorMessage;
  final VoidCallback? onLoadMore;
  final bool showPersonalDetails;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (isLoading && history == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null) {
      return Column(
        children: [
          _HistoryMessage(
            icon: Icons.error_outline,
            text: errorMessage!,
            color: colors.error,
          ),
          if (onRetry != null)
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry history'),
            ),
        ],
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
          if (analytics != null) _MoodSummary(analytics: analytics!),
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
        if (isLoading) const LinearProgressIndicator(),
        if (showPersonalDetails &&
            history!.coverage == MoodHistoryCoverage.partial)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Based on loaded entries'),
          ),
        if (analytics != null) ...[
          _MoodSummary(analytics: analytics!),
          const SizedBox(height: 12),
        ],
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
              showPersonalDetails: showPersonalDetails,
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

class _MoodSummary extends StatelessWidget {
  const _MoodSummary({required this.analytics});
  final MoodAnalyticsSnapshot analytics;

  String _quantity(int value, String singular, String plural) =>
      '$value ${value == 1 ? singular : plural}';

  @override
  Widget build(BuildContext context) {
    final weekly = analytics.weekly;
    final streak = analytics.streak;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recorded mood summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (analytics.daily.isNotEmpty)
              Text(
                'Latest recorded level: ${analytics.daily.last.latestEvent!.level}/5',
              ),
            Text(
              '${_quantity(analytics.eventCount, 'entry', 'entries')} across '
              '${_quantity(analytics.activeDayCount, 'mood-active day', 'mood-active days')} in loaded history',
            ),
            Text(
              '${_quantity(weekly.entryCount, 'entry', 'entries')} · '
              '${_quantity(weekly.activeDayCount, 'mood-active day', 'mood-active days')} this week',
            ),
            Text(
              'Mood streak: ${_quantity(streak.currentDays, 'day', 'days')}',
            ),
            Text(
              '${streak.isLongestWindowed ? 'Longest mood streak (loaded window)' : 'Longest mood streak'}: '
              '${_quantity(streak.longestDays, 'day', 'days')}',
            ),
            const SizedBox(height: 8),
            Text(
              'Recorded levels this week',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Wrap(
              spacing: 12,
              children: [
                for (var level = 1; level <= 5; level++)
                  Text('Level $level: ${weekly.distribution[level]}'),
              ],
            ),
            if (analytics.coverage == MoodHistoryCoverage.partial)
              const Text('Summary uses incomplete recorded history.'),
          ],
        ),
      ),
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
  const _MoodDayCard({
    required this.day,
    required this.isPartial,
    required this.showPersonalDetails,
  });
  final MoodDailyAggregate day;
  final bool isPartial;
  final bool showPersonalDetails;
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
            Text(
              showPersonalDetails
                  ? '${MaterialLocalizations.of(context).formatFullDate(MoodManilaCalendar.dateForKey(day.dateKey))} · ${day.entryCount} check-in${day.entryCount == 1 ? '' : 's'}'
                  : day.dateKey,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            for (final event in day.events.reversed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_manilaTime(event.occurredAt).format(context)} · ${showPersonalDetails && (event.label?.isNotEmpty ?? false) ? event.label : 'Mood ${event.level}/5'}',
                    ),
                    if (showPersonalDetails &&
                        (event.note?.trim().isNotEmpty ?? false))
                      Text(event.note!),
                  ],
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
