import 'mood_v2_analytics.dart';

/// Which gentle, non-diagnostic tip the weekly recap shows.
enum MoodTipKind { breathing, talk, rest, keepGoing }

/// The parts of My Mood Journey's weekly recap that Journey did not already
/// show (item 38): the best day and a gentle tip from the user's own labels.
class MoodWeekRecap {
  const MoodWeekRecap({required this.bestDay, required this.tip});

  /// The highest-level check-in of the week; ties go to the latest one.
  /// Null when the week has no check-ins.
  final NormalizedMoodEvent? bestDay;
  final MoodTipKind tip;

  static MoodWeekRecap from(List<NormalizedMoodEvent> weekEvents) {
    NormalizedMoodEvent? best;
    final counts = <String, int>{};
    for (final event in weekEvents) {
      if (best == null ||
          event.level > best.level ||
          (event.level == best.level &&
              event.occurredAt.isAfter(best.occurredAt))) {
        best = event;
      }
      final label = event.label?.trim().toLowerCase() ?? '';
      if (label.isNotEmpty) counts[label] = (counts[label] ?? 0) + 1;
    }
    int count(String label) => counts[label] ?? 0;

    final MoodTipKind tip;
    if (count('stressed') + count('angry') >= 2) {
      tip = MoodTipKind.breathing;
    } else if (count('sad') >= 2) {
      tip = MoodTipKind.talk;
    } else if (count('tired') >= 2) {
      tip = MoodTipKind.rest;
    } else {
      tip = MoodTipKind.keepGoing;
    }
    return MoodWeekRecap(bestDay: best, tip: tip);
  }
}
