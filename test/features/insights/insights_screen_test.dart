import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/theme/app_theme.dart';
import 'package:mind_mates/features/counseling/screens/services_screen.dart';
import 'package:mind_mates/features/insights/models/insights_models.dart';
import 'package:mind_mates/features/mood/screens/log_mood_screen.dart';
import 'package:mind_mates/features/profile/screens/mental_health_insights_screen.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/report_model.dart';
import 'package:mind_mates/providers/insights_provider.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/insights_repository.dart';
import 'package:mind_mates/repositories/mood_repository.dart';
import 'package:mind_mates/repositories/report_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('renders insights screen with backend-ready weekly metrics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final moodProvider = MoodProvider(
      _FakeMoodRepository([
        MoodModel(id: 'mood_1', userId: 'user_1', level: 5, createdAt: now),
        MoodModel(id: 'mood_2', userId: 'user_1', level: 2, createdAt: now),
      ]),
    );
    await moodProvider.loadRecentMoods('user_1');

    final reportProvider = ReportProvider(
      _FakeReportRepository(_currentWeekReport(now, assessmentCount: 1)),
    );
    await reportProvider.loadLatestReport('user_1');

    await tester.pumpWidget(
      _insightsApp(
        insightsProvider: InsightsProvider(InsightsRepository()),
        moodProvider: moodProvider,
        reportProvider: reportProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Search insights...'), findsOneWidget);
    expect(find.text('Stress relief'), findsAtLeastNWidgets(1));
    expect(find.text('Manage anxiety'), findsOneWidget);
    expect(find.text('Mood tracking'), findsOneWidget);
    expect(find.text('Better sleep'), findsOneWidget);
    expect(find.text('This week at a glance'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Your mental health patterns'), findsOneWidget);
    expect(find.text('Mental Wellbeing 101'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('PACC support services'), findsOneWidget);
  });

  testWidgets('loads insights with the signed-in population role', (
    tester,
  ) async {
    final repository = _CapturingInsightsRepository();
    final userProvider = UserProvider(UserRepository())
      ..setUser(
        const UserModel(
          id: 'teaching_user',
          email: 'teacher@ucu.edu.ph',
          populationRole: PopulationRole.teaching,
        ),
      );

    await tester.pumpWidget(
      _insightsApp(
        insightsProvider: InsightsProvider(repository),
        userProvider: userProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.context?.userId, 'teaching_user');
    expect(repository.context?.populationRole, PopulationRole.teaching);
  });

  testWidgets(
    'category navigation uses supplied assets and designed fallbacks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _insightsApp(insightsProvider: InsightsProvider(InsightsRepository())),
      );
      await tester.pumpAndSettle();

      for (final categoryId in const [
        'stress_burnout',
        'anxiety',
        'emotional_wellbeing',
        'sleep_mental_health',
      ]) {
        expect(
          find.byKey(Key('insights_category_asset_$categoryId')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(
          const Key('insights_category_fallback_self_esteem_confidence'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('insights_category_fallback_depression_support')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('insights_header_brain_asset')),
        findsOneWidget,
      );
      final headerBrain = tester.widget<Image>(
        find.byKey(const Key('insights_header_brain_asset')),
      );
      final heroBrain = tester.widget<Image>(
        find.byKey(const Key('insights_hero_brain_asset')),
      );
      expect(
        (headerBrain.image as AssetImage).assetName,
        'assets/images/INSIGHTS/creativity_15557951 1.png',
      );
      expect(
        (heroBrain.image as AssetImage).assetName,
        'assets/images/INSIGHTS/Creativity.png',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mockup category order fits the first four and keeps all six', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _insightsApp(insightsProvider: InsightsProvider(InsightsRepository())),
    );
    await tester.pumpAndSettle();

    const firstFour = [
      'emotional_wellbeing',
      'stress_burnout',
      'sleep_mental_health',
      'anxiety',
    ];
    final stripRect = tester.getRect(
      find.byKey(const Key('insights_category_strip')),
    );
    var previousX = double.negativeInfinity;
    for (final categoryId in firstFour) {
      final rect = tester.getRect(
        find.byKey(Key('insights_category_$categoryId')),
      );
      expect(rect.left, greaterThan(previousX));
      expect(rect.right, lessThanOrEqualTo(stripRect.right + 0.1));
      previousX = rect.left;
    }

    expect(
      tester
          .getRect(
            find.byKey(const Key('insights_category_self_esteem_confidence')),
          )
          .left,
      greaterThanOrEqualTo(stripRect.right),
    );
    expect(
      find.byKey(const Key('insights_category_depression_support')),
      findsOneWidget,
    );
    final selectedSurface = tester.widget<Ink>(
      find.byKey(const Key('insights_category_surface_sleep_mental_health')),
    );
    expect(
      (selectedSurface.decoration as BoxDecoration).color,
      const Color(0xFFFFBC00),
    );
    expect(find.text('Recommended starting point'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('main Insights dashboard uses dark contrast-safe surfaces', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _insightsApp(
        insightsProvider: InsightsProvider(InsightsRepository()),
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      const Color(0xFF15120D),
    );
    final hero = tester.widget<Container>(
      find.byKey(const Key('insights_hero')),
    );
    final heroGradient = (hero.decoration as BoxDecoration).gradient;
    expect((heroGradient as LinearGradient).colors, const [
      Color(0xFF6A4E00),
      Color(0xFF3A2E11),
    ]);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('insights_hero_title')))
          .style!
          .color,
      const Color(0xFFFFF7E3),
    );
    final search = tester.widget<TextField>(find.byType(TextField));
    expect(search.decoration!.fillColor, const Color(0xFF2B251C));
    final weekly = tester.widget<Container>(
      find.byKey(const Key('insights_weekly_card')),
    );
    expect((weekly.decoration as BoxDecoration).color, const Color(0xFF241F17));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion removes Insights transition durations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _insightsApp(
        insightsProvider: InsightsProvider(InsightsRepository()),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AnimatedSwitcher>(
            find.byKey(const Key('insights_content_switcher')),
          )
          .duration,
      Duration.zero,
    );
    for (final scale in tester.widgetList<AnimatedScale>(
      find.byKey(const Key('insights_press_scale')),
    )) {
      expect(scale.duration, Duration.zero);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown categories and invalid thumbnails use calm fallbacks', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const item = InsightCardItem(
      id: 'unknown_resource',
      title: 'A new wellness topic',
      subtitle: 'Helpful information for students.',
      category: 'A thoughtfully long wellness category name',
      categoryId: 'new_topic',
      imageAsset: 'assets/images/INSIGHTS/does-not-exist.png',
    );

    await tester.pumpWidget(
      _insightsApp(
        insightsProvider: InsightsProvider(
          _StaticInsightsRepository(
            const InsightsDashboardData(
              categories: [
                InsightCategory(
                  id: 'new_topic',
                  label: 'A thoughtfully long wellness category name',
                  icon: 'unknown',
                ),
              ],
              resources: [item],
              sections: [
                InsightSection(
                  id: 'latest',
                  title: 'The latest',
                  items: [item],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('insights_category_fallback_new_topic')),
      findsOneWidget,
    );
    final visual = tester.widget<Container>(
      find.byKey(const Key('insights_category_visual_new_topic')),
    );
    expect(
      (visual.decoration! as BoxDecoration).color,
      const Color(0xFFEDE2C6),
    );
    expect(
      find.byKey(const Key('insights_resource_art_unknown_resource')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'polished insights layout supports narrow screens and large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _insightsApp(
          insightsProvider: InsightsProvider(InsightsRepository()),
          textScaler: const TextScaler.linear(1.35),
          safeAreaPadding: const EdgeInsets.only(bottom: 24),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('insights_category_strip')), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('PACC support services'),
        find.byType(CustomScrollView),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(find.text('PACC support services'), findsOneWidget);
      final sliverPadding = tester.widget<SliverPadding>(
        find.byType(SliverPadding).first,
      );
      expect((sliverPadding.padding as EdgeInsets).bottom, 68);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows polished empty state when insight sections are absent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _insightsApp(
        insightsProvider: InsightsProvider(_EmptyInsightsRepository()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No wellness resources are available yet.'),
      findsOneWidget,
    );
  });

  testWidgets('shows retry action when insight loading fails', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _insightsApp(
        insightsProvider: InsightsProvider(_FailingInsightsRepository()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('We couldn’t load wellness resources.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('tapping a seeded insight opens article detail page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _insightsApp(insightsProvider: InsightsProvider(InsightsRepository())),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('What is stress?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('What is stress?'));
    await tester.pumpAndSettle();

    expect(find.text('Insight'), findsOneWidget);
    expect(find.text('What is stress?'), findsOneWidget);
    expect(
      find.textContaining('Stress is the body natural response to challenges'),
      findsOneWidget,
    );
    // Internal authoring file names stay hidden; the source link shows.
    expect(find.textContaining('.docx'), findsNothing);
    expect(find.textContaining('MindMate summary •'), findsOneWidget);
    expect(find.text('Read the full article at WHO'), findsOneWidget);
    expect(find.text('stress'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MentalHealthInsightsScreen), findsOneWidget);
  });

  testWidgets('category tile opens complete resource library', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _insightsApp(insightsProvider: InsightsProvider(InsightsRepository())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stress relief').first);
    await tester.pumpAndSettle();

    expect(find.byType(InsightCategoryResourceScreen), findsOneWidget);
    expect(find.text('Featured resource'), findsOneWidget);
    expect(find.text('Articles and guides'), findsOneWidget);
    expect(find.text('What is stress?'), findsAtLeastNWidgets(1));
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Video coming soon'), findsOneWidget);

    await tester.tap(find.text('Video coming soon'));
    await tester.pumpAndSettle();
    expect(find.byType(InsightArticleDetailScreen), findsNothing);
  });

  testWidgets('article detail falls back when optional fields are missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const InsightArticleDetailScreen(
          item: InsightCardItem(
            id: 'minimal',
            title: 'Minimal insight',
            subtitle: 'Subtitle becomes the body.',
            category: 'General',
            imageAsset: '',
          ),
        ),
      ),
    );

    expect(find.text('Minimal insight'), findsOneWidget);
    expect(find.text('Subtitle becomes the body.'), findsNWidgets(2));
    expect(find.text('General'), findsOneWidget);
    expect(find.textContaining('PACC support is available'), findsNothing);
  });

  testWidgets('insights controls navigate to existing screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _insightsApp(insightsProvider: InsightsProvider(InsightsRepository())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('insights_log_mood_action')));
    await tester.pumpAndSettle();
    expect(find.byType(LogMoodScreen), findsOneWidget);
    expect(find.text('Log your mood'), findsOneWidget);

    Navigator.of(tester.element(find.byType(LogMoodScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('No insight notifications yet'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -950));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contact counselor'));
    await tester.pumpAndSettle();
    expect(find.byType(ServicesScreen), findsOneWidget);
    expect(find.text('All Services'), findsOneWidget);
  });

  testWidgets('search filters insights and shows empty state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _insightsApp(insightsProvider: InsightsProvider(InsightsRepository())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'what is stress');
    await tester.pumpAndSettle();

    expect(find.text('What is stress?'), findsOneWidget);
    expect(find.text('Academic stress: how to manage it'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz no results');
    await tester.pumpAndSettle();

    expect(
      find.text('No insights found for "zzzz no results".'),
      findsOneWidget,
    );
  });

  testWidgets('see all opens section detail and cards open articles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _insightsApp(insightsProvider: InsightsProvider(InsightsRepository())),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('See all').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See all').at(1));
    await tester.pumpAndSettle();

    expect(find.text('Mental Wellbeing 101'), findsOneWidget);
    expect(find.text('What is stress?'), findsOneWidget);

    await tester.tap(find.text('What is stress?'));
    await tester.pumpAndSettle();

    expect(find.text('Insight'), findsOneWidget);
    expect(
      find.textContaining('Stress is the body natural response to challenges'),
      findsOneWidget,
    );
  });

  group('Featured recommendation', () {
    InsightCardItem approvedItem({
      String id = 'featured',
      String title = 'Featured guide',
      String? actionRoute = RouteNames.mindfulBreathing,
    }) => InsightCardItem(
      id: id,
      title: title,
      subtitle: 'A calm subtitle',
      category: 'Stress relief',
      imageAsset: '',
      contentType: 'article',
      body: 'Short MindMate summary.',
      sourceTitle: 'WHO — Stress: Questions and Answers',
      sourceUrl:
          'https://www.who.int/news-room/questions-and-answers/item/stress',
      evidenceType: 'official_guideline',
      rightsStatus: 'original',
      reviewStatus: 'approved',
      reviewedAt: DateTime(2026, 11, 28),
      actionRoute: actionRoute,
    );

    InsightsDashboardData dashboard(
      InsightRecommendationReason reason, {
      InsightCardItem? item,
    }) {
      final featured = item ?? approvedItem();
      return InsightsDashboardData(
        categories: const [],
        resources: [featured],
        sections: const [],
        featuredRecommendation: FeaturedInsightRecommendation(
          item: featured,
          reason: reason,
        ),
      );
    }

    testWidgets('renders below weekly glance with fixed reason copy', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const copy = {
        InsightRecommendationReason.assessment:
            'Based on a focus area from your recent assessment',
        InsightRecommendationReason.mood:
            'Based on your mood check-ins this week',
        InsightRecommendationReason.appActivity:
            'An optional MindMate tool you can try this week',
        InsightRecommendationReason.general: 'Curated wellness guide for you',
      };
      for (final entry in copy.entries) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _insightsApp(
            insightsProvider: InsightsProvider(
              _StaticInsightsRepository(dashboard(entry.key)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(entry.value), findsOneWidget);
        expect(
          find.text('Verified source • WHO — Stress: Questions and Answers'),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(find.byKey(const Key('featured_insight_card'))).dy,
          greaterThan(tester.getTopLeft(find.text('This week at a glance')).dy),
        );
      }
    });

    testWidgets('featured item is not repeated in the recommended rail', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final featured = approvedItem(title: 'Only once guide');
      await tester.pumpWidget(
        _insightsApp(
          insightsProvider: InsightsProvider(
            InsightsRepository(
              dataSource: _FakeDataSource(
                content: [
                  {
                    ...featured.toCatalogJson(),
                    'id': 'featured',
                    'sectionId': 'recommended',
                  },
                  {
                    'id': 'other',
                    'title': 'Other guide',
                    'subtitle': 's',
                    'sectionId': 'recommended',
                  },
                ],
                report: {
                  'id': 'r',
                  'userId': 'preview_user',
                  'generatedAt': DateTime.now(),
                  'reportStatus': 'draft',
                  'weekStart': DateTime.now(),
                  'weekEnd': DateTime.now().add(const Duration(days: 1)),
                  'hasEnoughData': true,
                },
              ),
              useFallbackContent: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('featured_insight_card')), findsOneWidget);
      expect(find.text('Recommended for you'), findsOneWidget);
      expect(find.text('Other guide'), findsOneWidget);
      expect(find.text('Only once guide'), findsOneWidget);
    });

    testWidgets('search hides featured card but still finds the article', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _insightsApp(
          insightsProvider: InsightsProvider(
            _StaticInsightsRepository(
              dashboard(InsightRecommendationReason.general),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('featured_insight_card')), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'featured');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('featured_insight_card')), findsNothing);
      expect(find.text('Featured guide'), findsOneWidget);
    });

    testWidgets('unverified catalog renders without a featured card', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _insightsApp(
          insightsProvider: InsightsProvider(
            InsightsRepository(
              dataSource: _FakeDataSource(
                content: [
                  {
                    'id': 'legacy',
                    'title': 'Legacy guide',
                    'subtitle': 's',
                    'sectionId': 'wellbeing_101',
                    'source': 'Mental Health Insights Categories.docx',
                  },
                ],
              ),
              useFallbackContent: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('featured_insight_card')), findsNothing);
      expect(find.text('Legacy guide'), findsOneWidget);
    });

    testWidgets('read guide opens detail with source and in-app action', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _insightsApp(
          insightsProvider: InsightsProvider(
            _StaticInsightsRepository(
              dashboard(InsightRecommendationReason.mood),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('featured_insight_read')));
      await tester.pumpAndSettle();

      expect(find.byType(InsightArticleDetailScreen), findsOneWidget);
      expect(find.text('Verified Source & Attribution'), findsOneWidget);
      expect(
        find.text('Official guideline • Reviewed Nov 28, 2026'),
        findsOneWidget,
      );
      expect(find.text('Read the full article at WHO'), findsOneWidget);
      expect(
        find.byKey(const Key('insight_local_crisis_line')),
        findsOneWidget,
      );
      expect(find.text('Try mindful breathing'), findsOneWidget);
    });

    testWidgets(
      'featured secondary action navigates to the allowlisted route',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _insightsApp(
            insightsProvider: InsightsProvider(
              _StaticInsightsRepository(
                dashboard(
                  InsightRecommendationReason.general,
                  item: approvedItem(actionRoute: RouteNames.logMood),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('featured_insight_action')));
        await tester.pumpAndSettle();

        expect(find.byType(LogMoodScreen), findsOneWidget);
      },
    );

    testWidgets('detail opens source via launcher and navigates the CTA', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final opened = <Uri>[];
      var launchResult = true;
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            RouteNames.mindfulBreathing: (_) =>
                const Scaffold(body: Text('Breathing route')),
          },
          home: InsightArticleDetailScreen(
            item: approvedItem(),
            onOpenSource: (uri) async {
              opened.add(uri);
              return launchResult;
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('insight_open_source')));
      await tester.pumpAndSettle();
      expect(opened.single.host, 'www.who.int');
      expect(find.text('Unable to open the source right now.'), findsNothing);

      launchResult = false;
      await tester.tap(find.byKey(const Key('insight_open_source')));
      await tester.pumpAndSettle();
      expect(find.text('Unable to open the source right now.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('insight_action_button')));
      await tester.pumpAndSettle();
      expect(find.text('Breathing route'), findsOneWidget);
    });

    testWidgets('legacy article shows no source panel or action', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InsightArticleDetailScreen(
            item: InsightCardItem(
              id: 'legacy',
              title: 'Legacy',
              subtitle: 's',
              category: 'c',
              imageAsset: '',
              actionRoute: '/admin',
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('insight_source_panel')), findsNothing);
      expect(find.byKey(const Key('insight_action_button')), findsNothing);
    });

    testWidgets('article detail uses dark theme surfaces', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: InsightArticleDetailScreen(item: approvedItem()),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFF15120D));
      final title = tester.widget<Text>(find.text('Featured guide'));
      expect(title.style?.color, const Color(0xFFFFF7E3));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('finalized report does not count toward weekly logs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final reportProvider = ReportProvider(
      _FakeReportRepository(
        ReportModel(
          id: 'old',
          generatedAt: DateTime.now(),
          reportStatus: 'final',
          weekStart: DateTime.now().subtract(const Duration(days: 3)),
          weekEnd: DateTime.now().add(const Duration(days: 3)),
          assessmentCount: 7,
        ),
      ),
    );
    await reportProvider.loadLatestReport('user_1');

    await tester.pumpWidget(
      _insightsApp(
        insightsProvider: InsightsProvider(_EmptyInsightsRepository()),
        reportProvider: reportProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('7'), findsNothing);
  });
}

ReportModel _currentWeekReport(DateTime now, {int assessmentCount = 0}) {
  final weekStart = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  return ReportModel(
    id: 'report_1',
    userId: 'user_1',
    generatedAt: now,
    reportStatus: 'draft',
    weekStart: weekStart,
    weekEnd: weekStart.add(const Duration(days: 6)),
    assessmentCount: assessmentCount,
  );
}

class _FakeDataSource implements InsightsRepositoryDataSource {
  _FakeDataSource({this.content = const [], this.report});

  final List<Map<String, dynamic>> content;
  final Map<String, dynamic>? report;

  @override
  Future<List<Map<String, dynamic>>> fetchCategories() async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchContent() async => content;

  @override
  Future<Map<String, dynamic>?> fetchLatestReport(String userId) async =>
      report;

  @override
  Future<List<Map<String, dynamic>>> fetchRules() async => const [];
}

Widget _insightsApp({
  required InsightsProvider insightsProvider,
  MoodProvider? moodProvider,
  ReportProvider? reportProvider,
  UserProvider? userProvider,
  TextScaler? textScaler,
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
  EdgeInsets safeAreaPadding = EdgeInsets.zero,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<InsightsProvider>.value(value: insightsProvider),
      if (moodProvider != null)
        ChangeNotifierProvider<MoodProvider>.value(value: moodProvider),
      if (reportProvider != null)
        ChangeNotifierProvider<ReportProvider>.value(value: reportProvider),
      if (userProvider != null)
        ChangeNotifierProvider<UserProvider>.value(value: userProvider),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: textScaler ?? mediaQuery.textScaler,
            disableAnimations: disableAnimations,
            padding: safeAreaPadding,
            viewPadding: safeAreaPadding,
          ),
          child: child!,
        );
      },
      routes: {
        RouteNames.logMood: (_) => const LogMoodScreen(),
        RouteNames.services: (_) => const ServicesScreen(),
      },
      home: const MentalHealthInsightsScreen(),
    ),
  );
}

class _EmptyInsightsRepository extends InsightsRepository {
  @override
  Future<InsightsDashboardData> fetchInsights(
    InsightRecommendationContext context,
  ) async {
    return const InsightsDashboardData(categories: [], sections: []);
  }
}

class _FailingInsightsRepository extends InsightsRepository {
  @override
  Future<InsightsDashboardData> fetchInsights(
    InsightRecommendationContext context,
  ) {
    throw StateError('offline');
  }
}

class _StaticInsightsRepository extends InsightsRepository {
  _StaticInsightsRepository(this.data);

  final InsightsDashboardData data;

  @override
  Future<InsightsDashboardData> fetchInsights(
    InsightRecommendationContext context,
  ) async => data;
}

class _CapturingInsightsRepository extends InsightsRepository {
  InsightRecommendationContext? context;

  @override
  Future<InsightsDashboardData> fetchInsights(
    InsightRecommendationContext value,
  ) async {
    context = value;
    return const InsightsDashboardData(categories: [], sections: []);
  }
}

class _FakeMoodRepository extends MoodRepository {
  _FakeMoodRepository(this.moods);

  final List<MoodModel> moods;

  @override
  Future<List<MoodModel>> fetchRecentMoods(String userId, {int limit = 14}) {
    return Future.value(moods);
  }
}

class _FakeReportRepository extends ReportRepository {
  _FakeReportRepository(this.latest);

  final ReportModel? latest;

  @override
  Future<ReportModel?> fetchLatestReport(String userId) async => latest;
}
