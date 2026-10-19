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
  });

  final MoodHistoryWindow? history;
  final String? errorMessage;

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
    if (history == null || history!.uniqueEvents.isEmpty) {
      return _HistoryMessage(
        icon: Icons.mood_outlined,
        text: 'No mood entries in this history window.',
        color: colors.onSurfaceVariant,
      );
    }
    final days = MoodAnalytics.dailyAggregates(history!.uniqueEvents);
    return ListView.separated(
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
