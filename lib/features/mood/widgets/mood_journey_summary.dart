import 'package:flutter/material.dart';

import '../domain/mood_v2_analytics.dart';

class MoodJourneySummary extends StatefulWidget {
  const MoodJourneySummary({
    super.key,
    required this.history,
    required this.now,
  });
  final MoodHistoryWindow history;
  final DateTime now;

  @override
  State<MoodJourneySummary> createState() => _MoodJourneySummaryState();
}

class _MoodJourneySummaryState extends State<MoodJourneySummary> {
  bool _month = false;

  @override
  Widget build(BuildContext context) {
    final today = MoodManilaCalendar.dateForKey(
      MoodManilaCalendar.dateKeyForInstant(widget.now),
    );
    final events = widget.history.uniqueEvents;
    final streak = MoodAnalytics.streak(
      widget.history,
      referenceInstant: widget.now,
    );
    final days = events.map((e) => e.dateKey).toSet();
    final start = _month
        ? DateTime.utc(today.year, today.month)
        : today.subtract(Duration(days: today.weekday - 1));
    final filtered = events.where((e) {
      final date = MoodManilaCalendar.dateForKey(e.dateKey);
      return !date.isBefore(start) && !date.isAfter(today);
    }).toList();
    final active = filtered.map((e) => e.dateKey).toSet().length;
    final counts = <String, int>{};
    for (final event in filtered) {
      final label = event.label?.trim();
      if (label != null && label.isNotEmpty) {
        counts[label] = (counts[label] ?? 0) + 1;
      }
    }
    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final uniqueTop =
        top.isNotEmpty && (top.length == 1 || top[0].value > top[1].value);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last 7 days', style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Mood Streak: ${streak.currentDays} ${streak.currentDays == 1 ? 'day' : 'days'}',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 6; i >= 0; i--)
                  Builder(
                    builder: (context) {
                      final day = today.subtract(Duration(days: i));
                      final logged = days.contains(
                        MoodManilaCalendar.dateKeyForDate(day),
                      );
                      return Semantics(
                        label:
                            '${day.month}/${day.day}: ${logged
                                ? 'mood logged'
                                : widget.history.coverage == MoodHistoryCoverage.partial
                                ? 'no check-in in loaded history'
                                : 'no mood logged'}',
                        child: Chip(
                          label: Text(
                            '${day.month}/${day.day} ${logged ? '✓' : '–'}',
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('This Week'),
                  selected: !_month,
                  onSelected: (_) => setState(() => _month = false),
                ),
                ChoiceChip(
                  label: const Text('This Month'),
                  selected: _month,
                  onSelected: (_) => setState(() => _month = true),
                ),
              ],
            ),
            Text(
              '${filtered.length} check-in${filtered.length == 1 ? '' : 's'} · $active mood-active day${active == 1 ? '' : 's'}',
            ),
            if (uniqueTop) Text('Most logged mood: ${top.first.key}'),
            if (top.length > 1 && top[0].value == top[1].value)
              const Text('Most logged moods are tied.'),
            if (widget.history.coverage == MoodHistoryCoverage.partial)
              const Text('Based on loaded entries'),
          ],
        ),
      ),
    );
  }
}
