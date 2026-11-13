import 'package:flutter/material.dart';

enum BestContactTimeDays {
  weekdays('Weekdays'),
  weekends('Weekends'),
  anyDay('Any day');

  const BestContactTimeDays(this.label);
  final String label;
}

class BestContactTime {
  const BestContactTime({
    required this.days,
    required this.start,
    required this.end,
  });

  final BestContactTimeDays days;
  final TimeOfDay start;
  final TimeOfDay end;

  static const defaults = BestContactTime(
    days: BestContactTimeDays.weekdays,
    start: TimeOfDay(hour: 9, minute: 0),
    end: TimeOfDay(hour: 12, minute: 0),
  );

  bool get isValidRange =>
      end.hour * 60 + end.minute > start.hour * 60 + start.minute;
}

String formatBestContactTime(BestContactTime value) =>
    '${value.days.label}, ${_formatClock(value.start)} – ${_formatClock(value.end)}';

String _formatClock(TimeOfDay time) {
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.period == DayPeriod.am ? 'AM' : 'PM'}';
}

final _contactTimePattern = RegExp(
  r'^(Weekdays|Weekends|Any day), (1[0-2]|[1-9]):([0-5][0-9]) (AM|PM) – (1[0-2]|[1-9]):([0-5][0-9]) (AM|PM)$',
);

BestContactTime? parseBestContactTime(String raw) {
  final match = _contactTimePattern.firstMatch(raw);
  if (match == null) return null;

  TimeOfDay clock(String hour, String minute, String period) {
    final h = int.parse(hour) % 12 + (period == 'PM' ? 12 : 0);
    return TimeOfDay(hour: h, minute: int.parse(minute));
  }

  return BestContactTime(
    days: BestContactTimeDays.values.firstWhere(
      (day) => day.label == match.group(1),
    ),
    start: clock(match.group(2)!, match.group(3)!, match.group(4)!),
    end: clock(match.group(5)!, match.group(6)!, match.group(7)!),
  );
}