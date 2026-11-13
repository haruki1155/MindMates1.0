import 'package:flutter/material.dart';

import '../../../routes/route_names.dart';
import '../../counseling/screens/pacc_counseling_screen.dart';
import '../../home/widgets/home_dashboard_widgets.dart';
import '../domain/mood_v2_analytics.dart';
import '../domain/mood_week_recap.dart';

/// Item 38: best day, a gentle tip and the support note for This Week.
class MoodWeekRecapCards extends StatelessWidget {
  const MoodWeekRecapCards({super.key, required this.recap});

  final MoodWeekRecap recap;

  static const _teal = Color(0xFF2F7D6D);
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _titleStyle = TextStyle(
    color: HomePalette.text,
    fontSize: 16,
    fontWeight: FontWeight.w800,
  );
  static const _bodyStyle = TextStyle(
    color: HomePalette.text,
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final best = recap.bestDay;
    final action = _tipAction(recap.tip);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (best != null) ...[
          const SizedBox(height: 12),
          Container(
            decoration: HomeDecor.card(),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Best day', style: _titleStyle),
                const SizedBox(height: 6),
                Text(
                  '${_weekdayOf(best)} · ${_label(best)}',
                  style: const TextStyle(
                    color: HomePalette.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Notice what made it a good day.',
                  style: _bodyStyle,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          decoration: HomeDecor.card(),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.self_improvement, color: _teal),
                  SizedBox(width: 8),
                  Expanded(child: Text('A gentle tip', style: _titleStyle)),
                ],
              ),
              const SizedBox(height: 6),
              Text(_tipText(recap.tip), style: _bodyStyle),
              if (action != null) ...[
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () => Navigator.of(context).pushNamed(action.$2),
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 44),
                  ),
                  child: Text(action.$1),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: HomeDecor.card(color: HomePalette.surfaceWarm),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "This reflects your own check-ins. It is not a diagnosis. If you'd "
                'like to talk to someone, PACC is here for you.',
                style: TextStyle(
                  color: HomePalette.muted,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const PaccCounselingScreen(startBooking: true),
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: _teal,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 44),
                ),
                child: const Text('Book a PACC appointment'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _weekdayOf(NormalizedMoodEvent event) =>
      _weekdays[MoodManilaCalendar.dateForKey(event.dateKey).weekday - 1];

  static String _label(NormalizedMoodEvent event) {
    final label = event.label?.trim() ?? '';
    return label.isEmpty ? 'Mood logged' : label;
  }

  static String _tipText(MoodTipKind tip) => switch (tip) {
    MoodTipKind.breathing =>
      'Stress showed up a few times this week. A 2-minute breathing '
          'session can help you reset.',
    MoodTipKind.talk =>
      'Some days felt low this week. Talking to someone can help.',
    MoodTipKind.rest =>
      'You felt tired on a few days. Try an earlier night or a short rest '
          'today.',
    MoodTipKind.keepGoing => "Keep doing what's working.",
  };

  static (String, String)? _tipAction(MoodTipKind tip) => switch (tip) {
    MoodTipKind.breathing => ('Try breathing', RouteNames.mindfulBreathing),
    MoodTipKind.talk => ('Open MindAid', RouteNames.mindAid),
    _ => null,
  };
}
