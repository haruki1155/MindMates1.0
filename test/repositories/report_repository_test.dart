import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/repositories/report_repository.dart';

void main() {
  group('ReportRepository.generateWeeklyReport', () {
    test('builds quick-only report fields and severe status', () async {
      final dataSource = _FakeReportDataSource(
        userDoc: _userDoc(),
        assessments: [
          _quickAssessment(
            createdAt: DateTime(2026, 7, 2, 9),
            score: 82,
            level: 'veryHigh',
            signal: 'highSupport',
          ),
        ],
        moods: [_mood(DateTime(2026, 7, 2), 4)],
        activities: [_activity('2026-07-02')],
      );
      final repository = ReportRepository(dataSource: dataSource);

      await repository.generateWeeklyReport(
        'user_1',
        now: DateTime(2026, 7, 3, 12),
      );

      final report = dataSource.createdReport!;
      expect(report['quickAssessmentScore'], 82);
      expect(report['quickAssessmentStatus'], 'veryHigh');
      expect(report['quickAssessmentSignal'], 'highSupport');
      expect(
        report['quickAssessmentSummary'],
        'Exact quick assessment summary.',
      );
      expect(report['quickAssessmentAreaStatuses'], {
        'Stress load': 'Elevated',
      });
      expect(report['latestAssessmentSource'], 'quickAssessment');
      expect(report['mentalStatus'], 'severe');
      expect(report['mentalStatusLabel'], 'Needs support');
      expect(report['reportStatus'], 'draft');
      expect(report['weekStart'].toDate(), DateTime(2026, 6, 29));
      expect(report['weekEnd'].toDate(), DateTime(2026, 7, 5));
    });

    test(
      'prefers latest full assessment while retaining quick fields',
      () async {
        final dataSource = _FakeReportDataSource(
          userDoc: _userDoc(),
          assessments: [
            _quickAssessment(
              createdAt: DateTime(2026, 7, 2, 9),
              score: 58,
              level: 'moderate',
              signal: 'watchful',
            ),
            _fullAssessment(
              createdAt: DateTime(2026, 7, 3, 9),
              score: 72,
              status: 'High Concern',
            ),
          ],
        );
        final repository = ReportRepository(dataSource: dataSource);

        await repository.generateWeeklyReport(
          'user_1',
          now: DateTime(2026, 7, 3, 12),
        );

        final report = dataSource.createdReport!;
        expect(report['latestAssessmentSource'], 'fullAssessment');
        expect(report['latestAssessmentStatus'], 'High Concern');
        expect(report['fullAssessmentScore'], 72);
        expect(report['fullAssessmentStatus'], 'High Concern');
        expect(report['fullAssessmentTopConcernAreas'], ['Sleep and Rest']);
        expect(
          report['fullAssessmentSummary'],
          'Exact full assessment summary.',
        );
        expect(report['fullAssessmentDomainStatuses'], {
          'Sleep and Rest': 'Moderate',
        });
        expect(report['quickAssessmentScore'], 58);
        expect(report['quickAssessmentStatus'], 'moderate');
        expect(report['mentalStatus'], 'severe');
      },
    );

    test(
      'selects newest assessment even when data source order is mixed',
      () async {
        final dataSource = _FakeReportDataSource(
          userDoc: _userDoc(),
          assessments: [
            _quickAssessment(
              createdAt: DateTime(2026, 7, 1, 9),
              score: 82,
              level: 'veryHigh',
              signal: 'highSupport',
            ),
            _quickAssessment(
              createdAt: DateTime(2026, 7, 3, 9),
              score: 20,
              level: 'low',
              signal: 'stable',
            ),
          ],
        );
        final repository = ReportRepository(dataSource: dataSource);

        await repository.generateWeeklyReport(
          'user_1',
          now: DateTime(2026, 7, 3, 12),
        );

        final report = dataSource.createdReport!;
        expect(report['quickAssessmentScore'], 20);
        expect(report['quickAssessmentStatus'], 'low');
        expect(report['mentalStatus'], 'normal');
      },
    );

    test('classifies low mood average as severe without assessment', () async {
      final dataSource = _FakeReportDataSource(
        userDoc: _userDoc(),
        moods: [_mood(DateTime(2026, 7, 1), 1), _mood(DateTime(2026, 7, 2), 2)],
      );
      final repository = ReportRepository(dataSource: dataSource);

      await repository.generateWeeklyReport(
        'user_1',
        now: DateTime(2026, 7, 3, 12),
      );

      final report = dataSource.createdReport!;
      expect(report['moodCheckInCount'], 2);
      expect(report['averageMoodLevel'], 1.5);
      expect(report['latestMoodLevel'], 2);
      expect(report['mentalStatus'], 'severe');
    });

    test('does not treat Moderate Well-Being as moderate concern', () async {
      final dataSource = _FakeReportDataSource(
        userDoc: _userDoc(),
        assessments: [
          _fullAssessment(
            createdAt: DateTime(2026, 7, 2, 9),
            score: 36,
            status: 'Moderate Well-Being',
          ),
        ],
      );
      final repository = ReportRepository(dataSource: dataSource);

      await repository.generateWeeklyReport(
        'user_1',
        now: DateTime(2026, 7, 3, 12),
      );

      expect(dataSource.createdReport!['mentalStatus'], 'normal');
      expect(dataSource.adminStatus!['status'], 'normal');
    });

    test(
      'counts Secret Chat engagement without copying private text',
      () async {
        final dataSource = _FakeReportDataSource(
          userDoc: _userDoc(),
          secretChatPosts: [
            {
              'authorId': 'user_1',
              'message': 'private anonymous post',
              'moderationStatus': 'active',
              'createdAt': DateTime(2026, 7, 2),
            },
            {
              'authorId': 'user_1',
              'message': 'private inactive post',
              'moderationStatus': 'removed',
              'createdAt': DateTime(2026, 7, 2),
            },
          ],
          secretChatComments: [
            {
              'authorId': 'user_1',
              'message': 'private anonymous comment',
              'moderationStatus': 'active',
              'createdAt': DateTime(2026, 7, 2),
            },
            {
              'authorId': 'user_1',
              'message': 'private inactive comment',
              'moderationStatus': 'hidden',
              'createdAt': DateTime(2026, 7, 2),
            },
          ],
          secretChatInteractions: [
            {
              'userId': 'user_1',
              'liked': true,
              'updatedAt': DateTime(2026, 7, 2),
            },
            {
              'userId': 'user_1',
              'saved': true,
              'updatedAt': DateTime(2026, 7, 2),
            },
            {
              'userId': 'user_1',
              'liked': false,
              'saved': false,
              'updatedAt': DateTime(2026, 7, 2),
            },
          ],
        );
        final repository = ReportRepository(dataSource: dataSource);

        await repository.generateWeeklyReport(
          'user_1',
          now: DateTime(2026, 7, 3, 12),
        );

        final report = dataSource.createdReport!;
        expect(report['secretChatPostCount'], 1);
        expect(report['secretChatCommentCount'], 1);
        expect(report['secretChatInteractionCount'], 2);
        expect(report['secretChatEngagementCount'], 4);
        expect(dataSource.adminStatus!['secretChatEngagementCount'], 4);
        expect(_containsPrivateText(report), isFalse);
        expect(_containsPrivateText(dataSource.adminStatus!), isFalse);
      },
    );

    test('syncs admin payload with status and engagement counts', () async {
      final dataSource = _FakeReportDataSource(
        userDoc: _userDoc(role: 'faculty'),
        moods: [_mood(DateTime(2026, 7, 2), 3)],
        mindAidMessages: [
          {'sender': 'user', 'createdAt': DateTime(2026, 7, 2)},
        ],
        breathingSessions: [
          {
            'completed': true,
            'completedSeconds': 360,
            'completedAt': DateTime(2026, 7, 2),
          },
        ],
        activities: [_activity('2026-07-02'), _activity('2026-07-03')],
        secretChatPosts: [
          {
            'authorId': 'user_1',
            'moderationStatus': 'active',
            'createdAt': DateTime(2026, 7, 2),
          },
        ],
      );
      final repository = ReportRepository(dataSource: dataSource);

      await repository.generateWeeklyReport(
        'user_1',
        now: DateTime(2026, 7, 3, 12),
      );

      final admin = dataSource.adminStatus!;
      expect(admin['userId'], 'user_1');
      expect(admin['role'], 'faculty');
      expect(admin['status'], 'normal');
      expect(admin['moodCheckInCount'], 1);
      expect(admin['mindAidMessageCount'], 1);
      expect(admin['breathingSessionCount'], 1);
      expect(admin['secretChatEngagementCount'], 1);
      expect(admin['totalEngagementCount'], 6);
    });

    test('upserts the same weekly report for repeated refreshes', () async {
      final dataSource = _FakeReportDataSource(userDoc: _userDoc());
      final repository = ReportRepository(dataSource: dataSource);

      final firstId = await repository.generateWeeklyReport(
        'user_1',
        now: DateTime(2026, 7, 3, 12),
      );
      final secondId = await repository.generateWeeklyReport(
        'user_1',
        now: DateTime(2026, 7, 4, 12),
      );

      expect(firstId, 'user_1_20260629');
      expect(secondId, firstId);
      expect(dataSource.upsertedReportIds, [firstId, secondId]);
    });
  });
}

Map<String, dynamic> _userDoc({String role = 'student'}) {
  return {
    'name': 'Leo Molar',
    'role': role,
    'email': 'leo@example.com',
    'dayStreak': 4,
  };
}

Map<String, dynamic> _quickAssessment({
  required DateTime createdAt,
  required int score,
  required String level,
  required String signal,
}) {
  return {
    'type': 'quick',
    'createdAt': createdAt,
    'concernScore': score,
    'overallLevel': level,
    'mentalStatusSignal': signal,
    'signalSource': 'quickAssessment',
    'topConcernAreas': ['Stress load'],
    'summary': 'Exact quick assessment summary.',
    'interpretation': {
      'userSummary': 'Exact quick assessment summary.',
      'domainResults': [
        {
          'domain': 'Stress load',
          'band': level == 'low' ? 'low' : 'elevated',
          'bandLabel': level == 'low' ? 'Low' : 'Elevated',
          'isScorable': true,
        },
      ],
    },
  };
}

Map<String, dynamic> _fullAssessment({
  required DateTime createdAt,
  required int score,
  required String status,
}) {
  return {
    'type': 'student',
    'createdAt': createdAt,
    'overallScore': score,
    'status': status,
    'mainConcernAreas': ['Sleep and Rest'],
    'interpretation': {
      'userSummary': 'Exact full assessment summary.',
      'domainResults': [
        {
          'domain': 'Sleep and Rest',
          'band': 'moderate',
          'bandLabel': 'Moderate',
          'isScorable': true,
        },
      ],
    },
  };
}

Map<String, dynamic> _mood(DateTime createdAt, int level) {
  return {'createdAt': createdAt, 'level': level};
}

Map<String, dynamic> _activity(String dateKey) {
  return {
    'dateKey': dateKey,
    'occurredAt': DateTime.parse('$dateKey 09:00:00'),
  };
}

bool _containsPrivateText(Object? value) {
  if (value is Map) {
    return value.values.any(_containsPrivateText);
  }
  if (value is Iterable) {
    return value.any(_containsPrivateText);
  }
  final text = value?.toString() ?? '';
  return text.contains('private anonymous post') ||
      text.contains('private anonymous comment');
}

class _FakeReportDataSource implements ReportRepositoryDataSource {
  _FakeReportDataSource({
    this.userDoc,
    this.assessments = const [],
    this.mindAidMessages = const [],
    this.activities = const [],
    this.moods = const [],
    this.breathingSessions = const [],
    this.secretChatPosts = const [],
    this.secretChatComments = const [],
    this.secretChatInteractions = const [],
  });

  final Map<String, dynamic>? userDoc;
  final List<Map<String, dynamic>> assessments;
  final List<Map<String, dynamic>> mindAidMessages;
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> moods;
  final List<Map<String, dynamic>> breathingSessions;
  final List<Map<String, dynamic>> secretChatPosts;
  final List<Map<String, dynamic>> secretChatComments;
  final List<Map<String, dynamic>> secretChatInteractions;

  Map<String, dynamic>? createdReport;
  Map<String, dynamic>? adminStatus;
  final List<String> upsertedReportIds = [];

  @override
  Future<Map<String, dynamic>?> getUserDocument(String userId) async => userDoc;

  @override
  Future<List<Map<String, dynamic>>> fetchAssessments(String userId) async {
    return assessments;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMindAidMessages({
    required String userId,
    required DateTime since,
    required DateTime before,
  }) async {
    return mindAidMessages;
  }

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
    return moods;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBreathingSessions({
    required String userId,
    required DateTime since,
    required DateTime before,
  }) async {
    return breathingSessions;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSecretChatPosts({
    required String userId,
    required DateTime since,
    required DateTime before,
  }) async {
    return secretChatPosts;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSecretChatComments({
    required String userId,
    required DateTime since,
    required DateTime before,
  }) async {
    return secretChatComments;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSecretChatInteractions({
    required String userId,
    required DateTime since,
    required DateTime before,
  }) async {
    return secretChatInteractions;
  }

  @override
  Future<String> upsertReport(
    String reportId,
    Map<String, dynamic> payload,
  ) async {
    upsertedReportIds.add(reportId);
    createdReport = payload;
    return reportId;
  }

  @override
  Future<void> setAdminStatusSummary(
    String userId,
    Map<String, dynamic> payload,
  ) async {
    adminStatus = payload;
  }
}
