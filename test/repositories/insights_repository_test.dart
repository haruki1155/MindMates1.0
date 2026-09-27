import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/insights/models/insights_models.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/insights_repository.dart';

void main() {
  group('InsightsRepository.fetchInsights', () {
    test(
      'empty backend data returns empty sections without crashing',
      () async {
        final repository = InsightsRepository(
          dataSource: _FakeInsightsDataSource(),
          useFallbackContent: false,
        );

        final data = await repository.fetchInsights(_context());

        expect(data.categories, isEmpty);
        expect(data.sections, isEmpty);
      },
    );

    test('static content appears in the correct sections', () async {
      final repository = InsightsRepository(
        dataSource: _FakeInsightsDataSource(
          categories: [_category()],
          content: [
            _content(id: 'pattern_1', sectionId: 'patterns'),
            _content(id: 'wellbeing_1', sectionId: 'wellbeing_101'),
          ],
        ),
        useFallbackContent: false,
      );

      final data = await repository.fetchInsights(_context());

      expect(data.categories.single.label, 'Mood tracking');
      expect(_section(data, 'patterns').items.single.id, 'pattern_1');
      expect(_section(data, 'wellbeing_101').items.single.id, 'wellbeing_1');
      expect(
        data.resources.firstWhere((item) => item.id == 'pattern_1').categoryId,
        'mood_tracking',
      );
    });

    test('category resources retain content beyond dashboard limits', () async {
      final repository = InsightsRepository(
        dataSource: _FakeInsightsDataSource(
          categories: [_category()],
          content: [
            for (var index = 0; index < 8; index++)
              _content(id: 'resource_$index', sectionId: 'latest'),
          ],
        ),
        useFallbackContent: false,
      );

      final data = await repository.fetchInsights(_context());
      final categoryResources = data.resourcesForCategory('mood_tracking');

      expect(_section(data, 'latest').items, hasLength(6));
      expect(categoryResources, hasLength(9));
      expect(categoryResources.last.isVideoPlaceholder, isTrue);
      expect(categoryResources.last.videoUrl, isNull);
    });

    test(
      'fallback library provides every category and video placeholder',
      () async {
        final data = await InsightsRepository().fetchInsights(
          _context(userId: 'preview_user'),
        );

        expect(data.categories, hasLength(6));
        for (final category in data.categories) {
          final resources = data.resourcesForCategory(category.id);
          expect(resources, isNotEmpty);
          expect(
            resources.where((item) => item.isVideoPlaceholder),
            hasLength(1),
          );
        }
      },
    );

    test('latest content is sorted by publishedAt', () async {
      final repository = InsightsRepository(
        dataSource: _FakeInsightsDataSource(
          content: [
            _content(
              id: 'older',
              sectionId: 'latest',
              publishedAt: DateTime(2026, 6),
            ),
            _content(
              id: 'newer',
              sectionId: 'latest',
              publishedAt: DateTime(2026, 7),
            ),
          ],
        ),
        useFallbackContent: false,
      );

      final data = await repository.fetchInsights(_context());

      expect(_section(data, 'latest').items.map((item) => item.id), [
        'newer',
        'older',
      ]);
    });

    test('recommended content follows rule priority', () async {
      final repository = InsightsRepository(
        dataSource: _FakeInsightsDataSource(
          content: [
            _content(id: 'low_priority', sectionId: 'recommended'),
            _content(id: 'high_priority', sectionId: 'recommended'),
          ],
          rules: [
            _rule(
              id: 'later',
              contentId: 'low_priority',
              priority: 20,
              conditions: {'mentalStatus': 'severe'},
            ),
            _rule(
              id: 'first',
              contentId: 'high_priority',
              priority: 1,
              conditions: {'mentalStatus': 'severe'},
            ),
          ],
          latestReport: _report(mentalStatus: 'severe'),
        ),
        useFallbackContent: false,
      );

      final data = await repository.fetchInsights(_context());

      expect(_section(data, 'recommended').items.map((item) => item.id), [
        'high_priority',
        'low_priority',
      ]);
    });

    test('duplicate content from multiple rules appears only once', () async {
      final repository = InsightsRepository(
        dataSource: _FakeInsightsDataSource(
          content: [_content(id: 'sleep', sectionId: 'recommended')],
          rules: [
            _rule(
              id: 'sleep_area',
              contentId: 'sleep',
              priority: 1,
              conditions: {'topConcernAreas': 'Sleep and Rest'},
            ),
            _rule(
              id: 'sleep_status',
              contentId: 'sleep',
              priority: 2,
              conditions: {'mentalStatus': 'moderate'},
            ),
          ],
          latestReport: _report(
            mentalStatus: 'moderate',
            topConcernAreas: ['Sleep and Rest'],
          ),
        ),
        useFallbackContent: false,
      );

      final data = await repository.fetchInsights(_context());

      expect(_section(data, 'recommended').items, hasLength(1));
      expect(_section(data, 'recommended').items.single.id, 'sleep');
    });

    test('missing report falls back to general content', () async {
      final repository = InsightsRepository(
        dataSource: _FakeInsightsDataSource(
          content: [
            _content(id: 'general', sectionId: 'recommended'),
            _content(id: 'latest', sectionId: 'latest'),
          ],
        ),
        useFallbackContent: false,
      );

      final data = await repository.fetchInsights(_context());

      expect(data.sections.map((section) => section.id), contains('latest'));
      expect(
        data.sections.map((section) => section.id),
        isNot(contains('recommended')),
      );
    });

    test(
      'sleep, high concern, low mood, and no activity match rules',
      () async {
        final repository = InsightsRepository(
          dataSource: _FakeInsightsDataSource(
            content: [
              _content(id: 'sleep', sectionId: 'recommended'),
              _content(id: 'support', sectionId: 'recommended'),
              _content(id: 'mood', sectionId: 'recommended'),
              _content(id: 'breathing', sectionId: 'recommended'),
              _content(id: 'mindaid', sectionId: 'recommended'),
            ],
            rules: [
              _rule(
                id: 'sleep_rule',
                contentId: 'sleep',
                priority: 1,
                conditions: {'topConcernAreas': 'Sleep and Rest'},
              ),
              _rule(
                id: 'support_rule',
                contentId: 'support',
                priority: 2,
                matchType: 'any',
                conditions: {
                  'mentalStatus': 'severe',
                  'fullAssessmentStatus': 'High Concern',
                },
              ),
              _rule(
                id: 'mood_rule',
                contentId: 'mood',
                priority: 3,
                conditions: {'averageMoodMax': 2.4},
              ),
              _rule(
                id: 'breathing_rule',
                contentId: 'breathing',
                priority: 4,
                conditions: {'breathingSessionMax': 0},
              ),
              _rule(
                id: 'mindaid_rule',
                contentId: 'mindaid',
                priority: 5,
                conditions: {'mindAidMessageMax': 0},
              ),
            ],
            latestReport: _report(
              mentalStatus: 'severe',
              fullAssessmentStatus: 'High Concern',
              topConcernAreas: ['Sleep and Rest'],
              averageMoodLevel: 2,
              breathingSessionCount: 0,
              mindAidMessageCount: 0,
            ),
          ),
          useFallbackContent: false,
        );

        final data = await repository.fetchInsights(_context());

        expect(_section(data, 'recommended').items.map((item) => item.id), [
          'sleep',
          'support',
          'mood',
          'breathing',
          'mindaid',
        ]);
      },
    );

    test('role filtering keeps audience-specific content isolated', () async {
      final repository = InsightsRepository(
        dataSource: _FakeInsightsDataSource(
          content: [
            _content(
              id: 'student',
              sectionId: 'recommended',
              targetRoles: const ['student'],
            ),
            _content(
              id: 'teaching',
              sectionId: 'recommended',
              targetRoles: const ['teaching'],
            ),
            _content(
              id: 'non_teaching',
              sectionId: 'recommended',
              targetRoles: const ['nonTeaching'],
            ),
            _content(
              id: 'shared',
              sectionId: 'recommended',
              targetRoles: const ['all'],
            ),
          ],
          latestReport: _report(),
        ),
        useFallbackContent: false,
      );

      for (final entry in {
        PopulationRole.student: {'student', 'shared'},
        PopulationRole.teaching: {'teaching', 'shared'},
        PopulationRole.nonTeaching: {'non_teaching', 'shared'},
      }.entries) {
        final data = await repository.fetchInsights(_context(role: entry.key));
        expect(
          _section(data, 'recommended').items.map((item) => item.id).toSet(),
          entry.value,
        );
      }

      final unknown = await repository.fetchInsights(_context(role: null));
      expect(_section(unknown, 'recommended').items.map((item) => item.id), [
        'shared',
      ]);
    });

    test('domain matches use canonical IDs for every population', () async {
      final content = [
        _content(
          id: 'academic',
          sectionId: 'latest',
          targetRoles: const ['student'],
          domainIds: const ['academicStress'],
        ),
        _content(
          id: 'teaching_workplace',
          sectionId: 'latest',
          targetRoles: const ['teaching'],
          domainIds: const ['workplaceStress'],
        ),
        _content(
          id: 'non_teaching_workplace',
          sectionId: 'latest',
          targetRoles: const ['nonTeaching'],
          domainIds: const ['workplaceResponsibilities'],
        ),
        _content(
          id: 'sleep',
          sectionId: 'latest',
          targetRoles: const ['all'],
          domainIds: const ['sleepRest'],
        ),
      ];
      final cases = [
        (PopulationRole.student, 'Academic Stress', 'academic'),
        (PopulationRole.student, 'Academic', 'academic'),
        (PopulationRole.teaching, 'Workplace Stress', 'teaching_workplace'),
        (
          PopulationRole.nonTeaching,
          'Workplace Responsibilities',
          'non_teaching_workplace',
        ),
        (PopulationRole.student, 'Sleep and Rest', 'sleep'),
      ];

      for (final (role, label, expectedId) in cases) {
        final repository = InsightsRepository(
          dataSource: _FakeInsightsDataSource(
            content: content,
            latestReport: _report(topConcernAreas: [label]),
          ),
          useFallbackContent: false,
        );
        final data = await repository.fetchInsights(_context(role: role));
        expect(_section(data, 'recommended').items.single.id, expectedId);
      }
    });

    test(
      'Student V4 domain statuses map to the canonical domain IDs',
      () async {
        final repository = InsightsRepository(
          dataSource: _FakeInsightsDataSource(
            content: [
              _content(
                id: 'academic',
                sectionId: 'latest',
                targetRoles: const ['student'],
                domainIds: const ['academicStress'],
              ),
            ],
            latestReport: _report(
              fullAssessmentDomainStatuses: const {
                'Academic': 'Some strain indicated',
              },
            ),
          ),
          useFallbackContent: false,
        );

        final data = await repository.fetchInsights(
          _context(role: PopulationRole.student),
        );
        expect(_section(data, 'recommended').items.single.id, 'academic');
      },
    );
  });
}

dynamic _section(dynamic data, String id) {
  return data.sections.firstWhere((section) => section.id == id);
}

InsightRecommendationContext _context({
  String userId = 'user_1',
  PopulationRole? role = PopulationRole.student,
}) => InsightRecommendationContext(userId: userId, populationRole: role);

Map<String, dynamic> _category() {
  return {
    'id': 'mood_tracking',
    'label': 'Mood tracking',
    'icon': 'mood',
    'sortOrder': 1,
    'isDefaultSelected': true,
    'isActive': true,
  };
}

Map<String, dynamic> _content({
  required String id,
  required String sectionId,
  DateTime? publishedAt,
  List<String>? targetRoles,
  List<String>? domainIds,
}) {
  final content = <String, dynamic>{
    'id': id,
    'title': 'Title $id',
    'subtitle': 'Subtitle $id',
    'categoryId': 'mood_tracking',
    'categoryLabel': 'Mood',
    'sectionId': sectionId,
    'imageAsset': '',
    'publishedAt': publishedAt,
    'sortOrder': 1,
    'isActive': true,
  };
  if (targetRoles != null) content['targetRoles'] = targetRoles;
  if (domainIds != null) content['domainIds'] = domainIds;
  return content;
}

Map<String, dynamic> _rule({
  required String id,
  required String contentId,
  required int priority,
  required Map<String, Object?> conditions,
  String matchType = 'all',
}) {
  return {
    'id': id,
    'contentId': contentId,
    'priority': priority,
    'matchType': matchType,
    'conditions': conditions,
    'isActive': true,
  };
}

Map<String, dynamic> _report({
  String mentalStatus = 'normal',
  String mentalStatusLabel = 'Normal',
  String? fullAssessmentStatus,
  String? quickAssessmentSignal,
  List<String> topConcernAreas = const [],
  double? averageMoodLevel,
  int moodCheckInCount = 1,
  int breathingSessionCount = 1,
  int mindAidMessageCount = 1,
  Map<String, String> fullAssessmentDomainStatuses = const {},
}) {
  return {
    'id': 'report_1',
    'userId': 'user_1',
    'title': 'Mental Health Summary',
    'description': 'Weekly summary',
    'generatedAt': DateTime(2026, 7, 5),
    'mentalStatus': mentalStatus,
    'mentalStatusLabel': mentalStatusLabel,
    'fullAssessmentStatus': fullAssessmentStatus,
    'quickAssessmentSignal': quickAssessmentSignal,
    'topConcernAreas': topConcernAreas,
    'averageMoodLevel': averageMoodLevel,
    'moodCheckInCount': moodCheckInCount,
    'breathingSessionCount': breathingSessionCount,
    'mindAidMessageCount': mindAidMessageCount,
    'fullAssessmentDomainStatuses': fullAssessmentDomainStatuses,
    'hasEnoughData': true,
  };
}

class _FakeInsightsDataSource implements InsightsRepositoryDataSource {
  _FakeInsightsDataSource({
    this.categories = const [],
    this.content = const [],
    this.rules = const [],
    this.latestReport,
  });

  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> content;
  final List<Map<String, dynamic>> rules;
  final Map<String, dynamic>? latestReport;

  @override
  Future<List<Map<String, dynamic>>> fetchCategories() async => categories;

  @override
  Future<List<Map<String, dynamic>>> fetchContent() async => content;

  @override
  Future<Map<String, dynamic>?> fetchLatestReport(String userId) async {
    return latestReport;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRules() async => rules;
}
