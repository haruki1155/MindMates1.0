import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/insights/models/insights_models.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/insights_repository.dart';
import 'package:mind_mates/repositories/insights_seed_data.dart';

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

  _featuredTests();
}

void _featuredTests() {
  group('Featured recommendation', () {
    Future<InsightsDashboardData> fetch({
      required List<Map<String, dynamic>> content,
      List<Map<String, dynamic>> rules = const [],
      Map<String, dynamic>? report,
      PopulationRole? role = PopulationRole.student,
    }) {
      return InsightsRepository(
        dataSource: _FakeInsightsDataSource(
          content: content,
          rules: rules,
          latestReport: report,
        ),
        useFallbackContent: false,
      ).fetchInsights(_context(role: role));
    }

    test(
      'assessment domain match is featured with assessment reason',
      () async {
        final data = await fetch(
          content: [
            _content(
              id: 'sleep',
              sectionId: 'latest',
              domainIds: const ['sleepRest'],
              provenance: _approved(),
            ),
          ],
          report: _report(topConcernAreas: const ['Sleep and Rest']),
        );

        expect(data.featuredRecommendation?.item.id, 'sleep');
        expect(
          data.featuredRecommendation?.reason,
          InsightRecommendationReason.assessment,
        );
      },
    );

    test('mood and app-activity rules carry their reasons', () async {
      final mood = await fetch(
        content: [
          _content(id: 'mood', sectionId: 'latest', provenance: _approved()),
        ],
        rules: [
          _rule(
            id: 'r',
            contentId: 'mood',
            priority: 1,
            conditions: {'averageMoodMax': 2.4},
          ),
        ],
        report: _report(averageMoodLevel: 2),
      );
      expect(
        mood.featuredRecommendation?.reason,
        InsightRecommendationReason.mood,
      );

      final activity = await fetch(
        content: [
          _content(id: 'breathe', sectionId: 'latest', provenance: _approved()),
        ],
        rules: [
          _rule(
            id: 'r',
            contentId: 'breathe',
            priority: 1,
            conditions: {'breathingSessionMax': 0},
          ),
        ],
        report: _report(breathingSessionCount: 0),
      );
      expect(
        activity.featuredRecommendation?.reason,
        InsightRecommendationReason.appActivity,
      );
    });

    test(
      'multi-signal precedence is assessment, then mood, then activity',
      () async {
        Future<InsightRecommendationReason?> reasonFor(
          Map<String, dynamic> report,
        ) async {
          final data = await fetch(
            content: [
              _content(
                id: 'item',
                sectionId: 'latest',
                provenance: _approved(),
              ),
            ],
            rules: [
              _rule(
                id: 'r',
                contentId: 'item',
                priority: 1,
                matchType: 'any',
                conditions: {
                  'mentalStatus': 'severe',
                  'averageMoodMax': 2.4,
                  'breathingSessionMax': 0,
                },
              ),
            ],
            report: report,
          );
          return data.featuredRecommendation?.reason;
        }

        expect(
          await reasonFor(
            _report(
              mentalStatus: 'severe',
              averageMoodLevel: 2,
              breathingSessionCount: 0,
            ),
          ),
          InsightRecommendationReason.assessment,
        );
        expect(
          await reasonFor(
            _report(averageMoodLevel: 2, breathingSessionCount: 0),
          ),
          InsightRecommendationReason.mood,
        );
        expect(
          await reasonFor(_report(breathingSessionCount: 0)),
          InsightRecommendationReason.appActivity,
        );
      },
    );

    test(
      'no breathing plus low mood features low-mood guide, not breathing',
      () async {
        // Uses the shipped seed catalog and rules.
        final data = await InsightsRepository(
          dataSource: _FakeInsightsDataSource(
            latestReport: _report(
              averageMoodLevel: 2,
              breathingSessionCount: 0,
            ),
          ),
        ).fetchInsights(_context());

        expect(
          data.featuredRecommendation?.item.id,
          'healthy_coping_depression',
        );
        expect(
          data.featuredRecommendation?.reason,
          InsightRecommendationReason.mood,
        );
      },
    );

    test('quick assessment area statuses map to domains', () async {
      final data = await fetch(
        content: [
          _content(
            id: 'sleep',
            sectionId: 'latest',
            domainIds: const ['sleepRest'],
            provenance: _approved(),
          ),
        ],
        report: _report(
          quickAssessmentAreaStatuses: const {'Sleep and Rest': 'Elevated'},
        ),
      );

      expect(data.featuredRecommendation?.item.id, 'sleep');
      expect(
        data.featuredRecommendation?.reason,
        InsightRecommendationReason.assessment,
      );
    });

    test('zero-activity rules do not fire without enough data', () async {
      final data = await fetch(
        content: [
          _content(id: 'breathe', sectionId: 'latest', provenance: _approved()),
          _content(
            id: 'general',
            sectionId: 'recommended',
            provenance: _approved(),
          ),
        ],
        rules: [
          _rule(
            id: 'r',
            contentId: 'breathe',
            priority: 1,
            conditions: {'breathingSessionMax': 0},
          ),
        ],
        report: _report(
          hasEnoughData: false,
          breathingSessionCount: 0,
          moodCheckInCount: 0,
          mindAidMessageCount: 0,
        ),
      );

      expect(data.featuredRecommendation?.item.id, 'general');
      expect(
        data.featuredRecommendation?.reason,
        InsightRecommendationReason.general,
      );
    });

    for (final entry in {
      'finalized': _report(
        reportStatus: 'final',
        topConcernAreas: const ['Sleep and Rest'],
      ),
      'past-week draft': _report(
        weekStart: DateTime.now().subtract(const Duration(days: 21)),
        weekEnd: DateTime.now().subtract(const Duration(days: 14)),
        topConcernAreas: const ['Sleep and Rest'],
      ),
      'undated': _report(
        undated: true,
        topConcernAreas: const ['Sleep and Rest'],
      ),
    }.entries) {
      test('${entry.key} report falls back to general, no patterns', () async {
        final data = await fetch(
          content: [
            _content(
              id: 'sleep',
              sectionId: 'latest',
              domainIds: const ['sleepRest'],
              provenance: _approved(),
            ),
            _content(
              id: 'general',
              sectionId: 'recommended',
              provenance: _approved(),
            ),
          ],
          report: entry.value,
        );

        expect(data.featuredRecommendation?.item.id, 'general');
        expect(
          data.featuredRecommendation?.reason,
          InsightRecommendationReason.general,
        );
        expect(
          data.sections.expand((section) => section.items).map((i) => i.id),
          isNot(contains(startsWith('report_'))),
        );
      });
    }

    test('rejects every incomplete or invalid provenance', () async {
      final invalid = <Map<String, dynamic>>[
        {..._approved(), 'sourceTitle': '  '},
        {..._approved(), 'sourceUrl': null},
        {..._approved(), 'sourceUrl': 'http://www.who.int/page'},
        {..._approved(), 'sourceUrl': 'https://user:pw@www.who.int/page'},
        {..._approved(), 'sourceUrl': 'not a url'},
        {..._approved(), 'reviewStatus': 'draft'},
        {..._approved(), 'reviewStatus': 'pending_review'},
        {..._approved(), 'rightsStatus': null},
        {..._approved(), 'rightsStatus': 'unknown'},
        {..._approved(), 'evidenceType': null},
        {..._approved(), 'evidenceType': 'blog_post'},
      ];
      for (final provenance in invalid) {
        final data = await fetch(
          content: [
            _content(
              id: 'item',
              sectionId: 'recommended',
              domainIds: const ['sleepRest'],
              provenance: provenance,
            ),
          ],
          report: _report(topConcernAreas: const ['Sleep and Rest']),
        );
        expect(data.featuredRecommendation, isNull, reason: '$provenance');
        expect(_section(data, 'recommended').items.single.id, 'item');
      }
    });

    test(
      'featured item is removed from recommended but stays searchable',
      () async {
        final data = await fetch(
          content: [
            _content(
              id: 'featured',
              sectionId: 'recommended',
              provenance: _approved(),
            ),
            _content(id: 'other', sectionId: 'recommended'),
          ],
          report: _report(),
        );

        expect(data.featuredRecommendation?.item.id, 'featured');
        expect(_section(data, 'recommended').items.map((item) => item.id), [
          'other',
        ]);
        expect(data.resources.map((item) => item.id), contains('featured'));
      },
    );

    test('fallback featured respects role isolation', () async {
      final content = [
        _content(
          id: 'student',
          sectionId: 'recommended',
          targetRoles: const ['student'],
          provenance: _approved(),
        ),
        _content(
          id: 'teaching',
          sectionId: 'recommended',
          targetRoles: const ['teaching'],
          provenance: _approved(),
        ),
        _content(
          id: 'non_teaching',
          sectionId: 'recommended',
          targetRoles: const ['nonTeaching'],
          provenance: _approved(),
        ),
        _content(
          id: 'shared',
          sectionId: 'recommended',
          provenance: _approved(),
        ),
      ];
      for (final (role, expected) in [
        (PopulationRole.student, 'student'),
        (PopulationRole.teaching, 'teaching'),
        (PopulationRole.nonTeaching, 'non_teaching'),
        (null, 'shared'),
      ]) {
        final data = await fetch(content: content, role: role);
        expect(data.featuredRecommendation?.item.id, expected);
        expect(
          data.featuredRecommendation?.reason,
          InsightRecommendationReason.general,
        );
      }
    });

    test('seed catalog features an approved guide for each role', () async {
      for (final role in [...PopulationRole.values, null]) {
        final data = await InsightsRepository().fetchInsights(
          _context(userId: '', role: role),
        );
        final featured = data.featuredRecommendation;
        expect(featured, isNotNull, reason: '$role');
        expect(featured!.item.hasApprovedProvenance, isTrue);
        expect(featured.item.validActionRoute, isNotNull);
      }
    });
  });

  test('seed library links every article to an online source', () {
    // These explain MindMate's own features, so there is nothing external.
    const internal = {
      'weekly_patterns_intro',
      'mood_check_in',
      'student_financial_wellbeing',
    };
    for (final json in insightSeedContent) {
      final item = InsightCardItem.fromJson(json);
      expect(item.imageAsset, isEmpty, reason: item.id);
      if (internal.contains(item.id)) continue;
      expect(item.validSourceUri, isNotNull, reason: item.id);
      expect(item.sourcePublisher, isNotEmpty, reason: item.id);
      expect(
        item.reviewStatus,
        anyOf('approved', 'pending_review'),
        reason: item.id,
      );
    }
  });

  group('InsightCardItem provenance helpers', () {
    InsightCardItem item(Map<String, dynamic> extra) =>
        InsightCardItem.fromJson({'id': 'x', 'title': 't', ...extra});

    test('accepts approved provenance and exposes labels', () {
      final card = item({..._approved(), 'actionRoute': '/mood/log'});
      expect(card.hasApprovedProvenance, isTrue);
      expect(card.evidenceTypeLabel, 'Official guideline');
      expect(card.validActionRoute, '/mood/log');
      expect(card.actionButtonLabel, 'Log a mood check-in');
    });

    test('rejects placeholder or generated content and unknown routes', () {
      expect(
        item({
          ..._approved(),
          'contentType': 'video_placeholder',
        }).hasApprovedProvenance,
        isFalse,
      );
      expect(
        item({
          ..._approved(),
          'contentType': 'generated_pattern',
        }).hasApprovedProvenance,
        isFalse,
      );
      expect(item({'actionRoute': '/admin'}).validActionRoute, isNull);
      expect(item({'actionRoute': '/admin'}).actionButtonLabel, isNull);
    });
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

Map<String, dynamic> _approved() => {
  'sourceTitle': 'WHO — Mental Health at Work',
  'sourceUrl':
      'https://www.who.int/news-room/fact-sheets/detail/mental-health-at-work',
  'evidenceType': 'official_guideline',
  'rightsStatus': 'original',
  'reviewStatus': 'approved',
};

Map<String, dynamic> _content({
  required String id,
  required String sectionId,
  DateTime? publishedAt,
  List<String>? targetRoles,
  List<String>? domainIds,
  Map<String, dynamic> provenance = const {},
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
  content.addAll(provenance);
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
  Map<String, String> quickAssessmentAreaStatuses = const {},
  bool hasEnoughData = true,
  String reportStatus = 'draft',
  DateTime? weekStart,
  DateTime? weekEnd,
  bool undated = false,
}) {
  // Defaults to an open report for the current week.
  final now = DateTime.now();
  final currentWeekStart = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  return {
    'id': 'report_1',
    'userId': 'user_1',
    'title': 'Mental Health Summary',
    'description': 'Weekly summary',
    'generatedAt': now,
    'reportStatus': reportStatus,
    'weekStart': undated ? null : (weekStart ?? currentWeekStart),
    'weekEnd': undated
        ? null
        : (weekEnd ?? currentWeekStart.add(const Duration(days: 6))),
    'quickAssessmentAreaStatuses': quickAssessmentAreaStatuses,
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
    'hasEnoughData': hasEnoughData,
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
