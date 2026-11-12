import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/features/mood/domain/mood_week_recap.dart';

void main() {
  var counter = 0;
  NormalizedMoodEvent event(String? label, {int level = 3, int day = 9}) {
    counter++;
    return NormalizedMoodEvent(
      id: 'e$counter',
      userId: 'u1',
      level: level,
      dateKey: '2026-11-${'$day'.padLeft(2, '0')}',
      occurredAt: DateTime.utc(2026, 11, day, 2),
      source: MoodEventSource.v2,
      label: label,
    );
  }

  test('an empty week has no best day and a keep-going tip', () {
    final recap = MoodWeekRecap.from(const []);
    expect(recap.bestDay, isNull);
    expect(recap.tip, MoodTipKind.keepGoing);
  });

  test('best day is the highest level, ties go to the latest', () {
    final saturday = event('Great', level: 5, day: 14);
    final recap = MoodWeekRecap.from([
      event('Okay', level: 4, day: 9),
      event('Great', level: 5, day: 13),
      saturday,
    ]);
    expect(recap.bestDay, same(saturday));
  });

  test('stress or anger twice suggests breathing', () {
    expect(
      MoodWeekRecap.from([
        event('Stressed'),
        event('Stressed'),
        event('Angry'),
      ]).tip,
      MoodTipKind.breathing,
    );
    expect(
      MoodWeekRecap.from([event('stressed '), event('ANGRY')]).tip,
      MoodTipKind.breathing,
    );
  });

  test('sadness twice suggests talking to someone', () {
    expect(
      MoodWeekRecap.from([event('Sad'), event('Sad')]).tip,
      MoodTipKind.talk,
    );
  });

  test('tiredness twice suggests rest', () {
    expect(
      MoodWeekRecap.from([event('Tired'), event('Tired')]).tip,
      MoodTipKind.rest,
    );
  });

  test('the first matching rule wins', () {
    expect(
      MoodWeekRecap.from([
        event('Sad'),
        event('Sad'),
        event('Stressed'),
        event('Stressed'),
      ]).tip,
      MoodTipKind.breathing,
    );
  });

  test('missing or unknown labels fall back to keep going', () {
    final recap = MoodWeekRecap.from([
      event(null),
      event(''),
      event('Excited', level: 5),
      event('Excited', level: 5),
    ]);
    expect(recap.tip, MoodTipKind.keepGoing);
    expect(recap.bestDay?.label, 'Excited');
  });
}
