import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/repositories/mental_health_activity_repository.dart';

void main() {
  group('MentalHealthActivityRepository', () {
    test(
      'counts daily actions from user activities and enriches mood/breathing',
      () async {
        final repository = MentalHealthActivityRepository(
          dataSource: _FakeActivityDataSource(
            user: {'dayStreak': 6, 'lastActivityDateKey': '2026-07-07'},
            activities: [
              _activity('moodCheckIn', hour: 8),
              _activity('mindAidMessage', hour: 9),
              _activity('breathingSession', hour: 10),
              _activity('secretChatPost', hour: 11),
              _activity('secretChatComment', hour: 12),
              _activity('secretChatInteraction', hour: 13),
              _activity('quickAssessment', hour: 14),
              _activity('fullAssessment', hour: 15),
            ],
            moods: [
              {'level': 4},
              {'level': 2},
            ],
            breathingSessions: [
              {'completed': true, 'completedSeconds': 300},
              {'completed': false, 'completedSeconds': 600},
            ],
          ),
        );

        final summary = await repository.fetchDailySummary(
          'user_1',
          date: DateTime(2026, 7, 7, 16),
        );

        expect(summary.date, DateTime(2026, 7, 7));
        expect(summary.moodCheckIns, 1);
        expect(summary.averageMoodLevel, 3);
        expect(summary.mindAidMessages, 1);
        expect(summary.breathingSessions, 1);
        expect(summary.breathingMinutes, 5);
        expect(summary.secretChatPosts, 1);
        expect(summary.secretChatComments, 1);
        expect(summary.secretChatInteractions, 1);
        expect(summary.secretChatEngagementCount, 3);
        expect(summary.assessmentCount, 2);
        expect(summary.currentStreak, 6);
      expect(summary.totalActions, 8);
        expect(
          summary.recentActivities.first.label,
          'Completed full assessment',
        );
      },
    );

    test('current streak drops to 0 after a missed day', () async {
      final repository = MentalHealthActivityRepository(
        dataSource: _FakeActivityDataSource(
          user: {'dayStreak': 6, 'lastActivityDateKey': '2026-07-01'},
          activities: const [],
          moods: const [],
          breathingSessions: const [],
        ),
      );

      final summary = await repository.fetchDailySummary(
        'user_1',
        date: DateTime(2026, 7, 7, 16),
      );

      expect(summary.currentStreak, 0);
    });

    test(
      'uses user activities for Secret Chat comments without comments query',
      () async {
        final source = _FakeActivityDataSource(
          activities: [
            _activity('secretChatComment', hour: 9),
            _activity('secretChatComment', hour: 10),
          ],
        );
        final repository = MentalHealthActivityRepository(dataSource: source);

        final summary = await repository.fetchDailySummary(
          'user_1',
          date: DateTime(2026, 7, 7),
        );

        expect(summary.secretChatComments, 2);
        expect(source.fetchBreathingCount, 1);
        expect(source.fetchMoodCount, 1);
      },
    );

    test(
      'optional mood and breathing enrichment failures do not fail summary',
      () async {
        final repository = MentalHealthActivityRepository(
          dataSource: _FakeActivityDataSource(
            activities: [_activity('mindAidMessage')],
            throwMoods: true,
            throwBreathing: true,
          ),
        );

        final summary = await repository.fetchDailySummary(
          'user_1',
          date: DateTime(2026, 7, 7),
        );

        expect(summary.mindAidMessages, 1);
        expect(summary.averageMoodLevel, isNull);
        expect(summary.breathingSessions, 0);
        expect(summary.breathingMinutes, 0);
        expect(summary.totalActions, 1);
      },
    );
  });
}

Map<String, dynamic> _activity(String type, {int hour = 8}) {
  return {'type': type, 'occurredAt': DateTime(2026, 7, 7, hour)};
}

class _FakeActivityDataSource implements MentalHealthActivityDataSource {
  _FakeActivityDataSource({
    this.user,
    this.activities = const [],
    this.moods = const [],
    this.breathingSessions = const [],
    this.throwMoods = false,
    this.throwBreathing = false,
  });

  final Map<String, dynamic>? user;
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> moods;
  final List<Map<String, dynamic>> breathingSessions;
  final bool throwMoods;
  final bool throwBreathing;
  int fetchMoodCount = 0;
  int fetchBreathingCount = 0;

  @override
  Future<Map<String, dynamic>?> getUserDocument(String userId) async => user;

  @override
  Future<List<Map<String, dynamic>>> fetchUserActivities({
    required String userId,
    required DateTime since,
    required DateTime before,
  }) async {
    return activities;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMoods({
    required String userId,
    required DateTime since,
    required DateTime before,
  }) async {
    fetchMoodCount += 1;
    if (throwMoods) throw Exception('moods unavailable');
    return moods;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBreathingSessions({
    required String userId,
    required DateTime since,
    required DateTime before,
  }) async {
    fetchBreathingCount += 1;
    if (throwBreathing) throw Exception('breathing unavailable');
    return breathingSessions;
  }
}
