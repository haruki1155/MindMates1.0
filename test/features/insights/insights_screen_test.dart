import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/theme/app_theme.dart';
import 'package:mind_mates/features/counseling/screens/services_screen.dart';
import 'package:mind_mates/features/insights/models/insights_models.dart';
import 'package:mind_mates/features/mood/screens/log_mood_screen.dart';
import 'package:mind_mates/features/profile/screens/mental_health_insights_screen.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/models/report_model.dart';
import 'package:mind_mates/providers/insights_provider.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/repositories/insights_repository.dart';
import 'package:mind_mates/repositories/mood_repository.dart';
import 'package:mind_mates/repositories/report_repository.dart';
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
      _FakeReportRepository(
        ReportModel(
          id: 'report_1',
          userId: 'user_1',
          generatedAt: now,
          assessmentCount: 1,
        ),
      ),
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
      find.byKey(const Key('insights_resource_fallback_unknown_resource')),
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
    expect(
      find.textContaining('Mental Health Insights Categories.docx'),
      findsOneWidget,
    );
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

    await tester.enterText(find.byType(TextField), 'academic stress');
    await tester.pumpAndSettle();

    expect(find.text('Academic stress: how to manage it'), findsOneWidget);
    expect(find.text('What is stress?'), findsNothing);

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
}

Widget _insightsApp({
  required InsightsProvider insightsProvider,
  MoodProvider? moodProvider,
  ReportProvider? reportProvider,
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
  Future<InsightsDashboardData> fetchInsights(String userId) async {
    return const InsightsDashboardData(categories: [], sections: []);
  }
}

class _FailingInsightsRepository extends InsightsRepository {
  @override
  Future<InsightsDashboardData> fetchInsights(String userId) {
    throw StateError('offline');
  }
}

class _StaticInsightsRepository extends InsightsRepository {
  _StaticInsightsRepository(this.data);

  final InsightsDashboardData data;

  @override
  Future<InsightsDashboardData> fetchInsights(String userId) async => data;
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
