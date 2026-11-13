import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/domain/best_contact_time.dart';

void main() {
  test('formats the canonical sentence', () {
    expect(
      formatBestContactTime(BestContactTime.defaults),
      'Weekdays, 9:00 AM – 12:00 PM',
    );
    expect(
      formatBestContactTime(
        const BestContactTime(
          days: BestContactTimeDays.anyDay,
          start: TimeOfDay(hour: 0, minute: 5),
          end: TimeOfDay(hour: 13, minute: 30),
        ),
      ),
      'Any day, 12:05 AM – 1:30 PM',
    );
  });

  test('parses what it formats for every day choice', () {
    for (final days in BestContactTimeDays.values) {
      final value = BestContactTime(
        days: days,
        start: const TimeOfDay(hour: 7, minute: 45),
        end: const TimeOfDay(hour: 19, minute: 0),
      );
      final parsed = parseBestContactTime(formatBestContactTime(value));
      expect(parsed?.days, days);
      expect(parsed?.start, const TimeOfDay(hour: 7, minute: 45));
      expect(parsed?.end, const TimeOfDay(hour: 19, minute: 0));
    }
  });

  test('returns null for old free text and malformed values', () {
    for (final raw in [
      '',
      '   ',
      'Weekend mornings 9 AM - 12 PM',
      'Weekdays, 9:00 AM to 12:00 PM',
      'Someday, 9:00 AM – 12:00 PM',
      'Weekdays, 13:00 AM – 2:00 PM',
    ]) {
      expect(parseBestContactTime(raw), isNull, reason: raw);
    }
  });

  test('range validity', () {
    expect(BestContactTime.defaults.isValidRange, isTrue);
    expect(
      const BestContactTime(
        days: BestContactTimeDays.weekdays,
        start: TimeOfDay(hour: 9, minute: 0),
        end: TimeOfDay(hour: 9, minute: 0),
      ).isValidRange,
      isFalse,
    );
    expect(
      const BestContactTime(
        days: BestContactTimeDays.weekdays,
        start: TimeOfDay(hour: 23, minute: 0),
        end: TimeOfDay(hour: 1, minute: 0),
      ).isValidRange,
      isFalse,
    );
  });
<<<<<<< HEAD
}
=======
}
>>>>>>> origin/main
