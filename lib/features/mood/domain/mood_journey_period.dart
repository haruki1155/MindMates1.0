import 'mood_v2_analytics.dart';

enum MoodJourneyPeriod { week, month }

DateTime moodJourneyStart(MoodJourneyPeriod period, DateTime now) {
  final today = MoodManilaCalendar.dateForKey(
    MoodManilaCalendar.dateKeyForInstant(now),
  );
  return period == MoodJourneyPeriod.month
      ? DateTime.utc(today.year, today.month)
      : today.subtract(Duration(days: today.weekday - 1));
}

bool includesMoodJourneyDate(
  String dateKey,
  MoodJourneyPeriod period,
  DateTime now,
) {
  final start = MoodManilaCalendar.dateKeyForDate(
    moodJourneyStart(period, now),
  );
  final today = MoodManilaCalendar.dateKeyForInstant(now);
  return dateKey.compareTo(start) >= 0 && dateKey.compareTo(today) <= 0;
}
