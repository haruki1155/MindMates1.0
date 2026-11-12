import '../../../repositories/user_repository.dart';
import '../../mood/domain/mood_v2_analytics.dart';

/// What the Home "Day streak" card should show.
enum HomeStreakState { notStarted, activeNotToday, doneToday, milestone }

/// Streak lengths that unlock the weekly recap: 7, 14, 30, then every 30.
bool isStreakMilestone(int days) =>
    days == 7 || days == 14 || days == 30 || (days > 30 && days % 30 == 0);

class HomeStreakSnapshot {
  const HomeStreakSnapshot({
    required this.days,
    required this.checkedInToday,
    required this.activeDateKeys,
  });

  /// Consecutive days with at least one mood check-in.
  final int days;
  final bool checkedInToday;

  /// Days ('yyyy-MM-dd') with a mood check-in, for the Home week row.
  final Set<String> activeDateKeys;

  HomeStreakState get state {
    if (days <= 0) return HomeStreakState.notStarted;
    if (!checkedInToday) return HomeStreakState.activeNotToday;
    if (isStreakMilestone(days)) return HomeStreakState.milestone;
    return HomeStreakState.doneToday;
  }
}

/// One streak definition for Home, matching My Mood Journey.
///
/// Pass [v2History] only when Mood V2 reading is enabled and every event
/// belongs to the signed-in user; it then wins. Otherwise the stored
/// `users.dayStreak` counter is used through its effective (non-stale) value.
HomeStreakSnapshot resolveHomeStreak({
  MoodHistoryWindow? v2History,
  required int storedStreak,
  String? lastActivityDateKey,
  List<String> activeDateKeys = const [],
  required DateTime now,
}) {
  if (v2History != null) {
    final today = MoodManilaCalendar.dateKeyForInstant(now);
    final keys = {for (final event in v2History.uniqueEvents) event.dateKey};
    return HomeStreakSnapshot(
      days: MoodAnalytics.streak(v2History, referenceInstant: now).currentDays,
      checkedInToday: keys.contains(today),
      activeDateKeys: keys,
    );
  }
  return HomeStreakSnapshot(
    days: StreakCalculator.effectiveStreak(
      storedStreak: storedStreak,
      lastActivityDateKey: lastActivityDateKey,
      now: now,
    ),
    checkedInToday: lastActivityDateKey == StreakCalculator.dateKey(now),
    activeDateKeys: {
      for (final key in activeDateKeys)
        if (key.trim().isNotEmpty) key.trim(),
    },
  );
}
