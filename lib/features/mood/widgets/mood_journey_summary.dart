import 'package:flutter/material.dart';

import '../domain/mood_v2_analytics.dart';
import '../domain/mood_journey_period.dart';
import '../../home/widgets/home_dashboard_widgets.dart';

class MoodJourneySummary extends StatefulWidget {
  const MoodJourneySummary({
    super.key,
    required this.history,
    required this.now,
    this.period,
    this.onPeriodChanged,
  });
  final MoodHistoryWindow history;
  final DateTime now;
  final MoodJourneyPeriod? period;
  final ValueChanged<MoodJourneyPeriod>? onPeriodChanged;

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
    final period =
        widget.period ??
        (_month ? MoodJourneyPeriod.month : MoodJourneyPeriod.week);
    final start = moodJourneyStart(period, widget.now);
    final filtered = events
        .where((e) => includesMoodJourneyDate(e.dateKey, period, widget.now))
        .toList();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFDCEEE5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.eco_outlined,
                color: Color(0xFF2F7D6D),
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Mood streak · ${streak.currentDays} ${streak.currentDays == 1 ? 'day' : 'days'}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: HomeDecor.card(),
          padding: const EdgeInsets.all(6),
          child: SingleChildScrollView(
            key: const Key('mood-seven-day-strip'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 6; i >= 0; i--)
                  Builder(
                    builder: (context) {
                      final day = today.subtract(Duration(days: i));
                      final logged = days.contains(
                        MoodManilaCalendar.dateKeyForDate(day),
                      );
                      const weekdays = [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ];
                      return Semantics(
                        label:
                            '${day.month}/${day.day}: ${logged
                                ? 'mood logged'
                                : widget.history.coverage == MoodHistoryCoverage.partial
                                ? 'no check-in in loaded history'
                                : 'no mood logged'}',
                        child: Container(
                          width: 48,
                          constraints: const BoxConstraints(minHeight: 76),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: i == 0
                                ? HomePalette.softGold
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                weekdays[day.weekday - 1],
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                '${day.day}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Icon(
                                logged ? Icons.circle : Icons.circle_outlined,
                                size: 12,
                                color: logged
                                    ? const Color(0xFF2F7D6D)
                                    : HomePalette.muted,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('This Week')),
            ButtonSegment(value: true, label: Text('This Month')),
          ],
          selected: {period == MoodJourneyPeriod.month},
          showSelectedIcon: true,
          onSelectionChanged: (values) {
            final value = values.single
                ? MoodJourneyPeriod.month
                : MoodJourneyPeriod.week;
            if (widget.onPeriodChanged != null) {
              widget.onPeriodChanged!(value);
            } else {
              setState(() => _month = values.single);
            }
          },
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFF2F7D6D)
                  : HomePalette.surface,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.white
                  : const Color(0xFF2F7D6D),
            ),
            side: const WidgetStatePropertyAll(
              BorderSide(color: HomePalette.outlineStrong),
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final tiles = [
              Container(
                decoration: HomeDecor.card(),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_available_outlined,
                      color: Color(0xFF2F7D6D),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${filtered.length} check-in${filtered.length == 1 ? '' : 's'} · $active mood-active day${active == 1 ? '' : 's'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: HomeDecor.card(),
                padding: const EdgeInsets.all(12),
                child: Text(
                  uniqueTop
                      ? 'Most logged mood: ${top.first.key}'
                      : top.isEmpty
                      ? 'Your feelings, at your pace'
                      : 'Most logged moods are tied.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 12),
                Expanded(child: tiles[1]),
              ],
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${MaterialLocalizations.of(context).formatShortDate(start)} – ${MaterialLocalizations.of(context).formatShortDate(today)}',
            style: const TextStyle(color: HomePalette.muted),
          ),
        ),
        if (widget.history.coverage == MoodHistoryCoverage.partial)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Based on loaded entries',
              style: TextStyle(fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
