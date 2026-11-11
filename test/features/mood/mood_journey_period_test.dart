import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mood/domain/mood_journey_period.dart';

void main() {
  test('Manila Monday and month boundaries exclude future and prior dates', () {
    final monday = DateTime.utc(2026, 10, 4, 16);
    expect(includesMoodJourneyDate('2026-10-05', MoodJourneyPeriod.week, monday), isTrue);
    expect(includesMoodJourneyDate('2026-10-04', MoodJourneyPeriod.week, monday), isFalse);
    expect(includesMoodJourneyDate('2026-10-06', MoodJourneyPeriod.week, monday), isFalse);
    final november = DateTime.utc(2026, 10, 31, 16);
    expect(includesMoodJourneyDate('2026-11-01', MoodJourneyPeriod.month, november), isTrue);
    expect(includesMoodJourneyDate('2026-10-31', MoodJourneyPeriod.month, november), isFalse);
    expect(includesMoodJourneyDate('2026-11-02', MoodJourneyPeriod.month, november), isFalse);
  });
}
