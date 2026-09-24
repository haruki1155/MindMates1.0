import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/home/data/daily_affirmation_quotes.dart';
import 'package:mind_mates/features/home/screens/home_screen.dart';
import 'package:mind_mates/features/home/widgets/home_dashboard_widgets.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/models/report_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/breathing_provider.dart';
import 'package:mind_mates/providers/insights_provider.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/breathing_repository.dart';
import 'package:mind_mates/repositories/insights_repository.dart';
import 'package:mind_mates/repositories/mood_repository.dart';
import 'package:mind_mates/repositories/report_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/app_pages.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('announcement actions are interactive', (tester) async {
    var viewMoreCalls = 0;
    var detailCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeAnnouncementCard(
            onViewMore: () => viewMoreCalls++,
            onViewDetail: () => detailCalls++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('View More'));
    await tester.tap(find.text('View Detail'));

    expect(viewMoreCalls, 1);
    expect(detailCalls, 1);
  });

  testWidgets('daily affirmation rotates to the next supplied quote on tap', (
    tester,
  ) async {
    final date = DateTime(2026, 7, 14);
    final index =
        (DateTime(date.year, date.month, date.day).millisecondsSinceEpoch ~/
            Duration.millisecondsPerDay) %
        dailyAffirmationQuotes.length;
    final initialQuote = dailyAffirmationQuotes[index];
    final nextQuote =
        dailyAffirmationQuotes[(index + 1) % dailyAffirmationQuotes.length];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeDailyInsightsSection(
            insights: const [],
            affirmation: null,
            nowProvider: () => date,
            onOpen: (_) {},
          ),
        ),
      ),
    );

    expect(dailyAffirmationQuotes, hasLength(100));
    expect(find.text(initialQuote.text), findsOneWidget);
    expect(find.text(initialQuote.category), findsOneWidget);
    expect(find.text('Tap for another thought'), findsOneWidget);

    await tester.tap(find.text('Tap for another thought'));
    await tester.pumpAndSettle();

    expect(find.text(initialQuote.text), findsNothing);
    expect(find.text(nextQuote.text), findsOneWidget);
    expect(find.text(nextQuote.category), findsOneWidget);
  });

  testWidgets('home dashboard overlays profile, streak, moods, and report', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(
        const UserModel(
          id: 'user_1',
          email: 'leo@example.com',
          firstName: 'Leonardo',
          lastName: 'Molar',
          role: 'student',
          dayStreak: 5,
        ),
      );
    final moodProvider = MoodProvider(_FakeMoodRepository());
    await moodProvider.logMood(userId: 'user_1', level: 4, label: 'Good');
    final reportProvider = ReportProvider(
      _FakeReportRepository(
        latest: ReportModel(
          id: 'report_1',
          userId: 'user_1',
          title: 'Mental Health Summary',
          description: 'This week is ready for review',
          generatedAt: DateTime(2026, 6, 30),
          hasEnoughData: true,
        ),
      ),
    );
    await reportProvider.loadLatestReport('user_1');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MoodProvider>.value(value: moodProvider),
          ChangeNotifierProvider<ReportProvider>.value(value: reportProvider),
          ChangeNotifierProvider(
            create: (_) => InsightsProvider(InsightsRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => AssessmentProvider(AssessmentRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => BreathingProvider(_FakeBreathingRepository()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          routes: _testRoutes(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome back, Leonardo Molar!'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Day streak'), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('View Summary'),
      500,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View Summary'));
    await tester.pumpAndSettle();
    expect(
      find.text('Your weekly mental health summary is ready to review.'),
      findsOneWidget,
    );
    expect(find.text('This week is ready for review'), findsNothing);

    await tester.tap(find.text('View Summary'));
    await tester.pumpAndSettle();

    expect(find.text('Mental Health Summary'), findsOneWidget);
  });

  testWidgets('home Services destination opens the services screen', (
    tester,
  ) async {
    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MoodProvider>(
            create: (_) => MoodProvider(_FakeMoodRepository()),
          ),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FakeReportRepository()),
          ),
          ChangeNotifierProvider<InsightsProvider>(
            create: (_) => InsightsProvider(InsightsRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => AssessmentProvider(AssessmentRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => BreathingProvider(_FakeBreathingRepository()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          routes: _testRoutes(),
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();

    expect(find.text('PACC Services'), findsOneWidget);
  });

  testWidgets('home Log your mood opens mood check-in screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MoodProvider>(
            create: (_) => MoodProvider(_FakeMoodRepository()),
          ),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FakeReportRepository()),
          ),
          ChangeNotifierProvider<InsightsProvider>(
            create: (_) => InsightsProvider(InsightsRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => AssessmentProvider(AssessmentRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => BreathingProvider(_FakeBreathingRepository()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          routes: _testRoutes(),
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Log your mood').first);
    await tester.pumpAndSettle();

    expect(find.text('How are you feeling?'), findsOneWidget);
    expect(find.text("What's on your mind today?"), findsOneWidget);
    expect(find.text('0/300 characters'), findsOneWidget);
  });

  testWidgets('home assessment banner can be dismissed for the session', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(
        const UserModel(
          id: 'user_1',
          email: 'leo@example.com',
          populationRole: PopulationRole.student,
        ),
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MoodProvider>(
            create: (_) => MoodProvider(_FakeMoodRepository()),
          ),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FakeReportRepository()),
          ),
          ChangeNotifierProvider<InsightsProvider>(
            create: (_) => InsightsProvider(InsightsRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => AssessmentProvider(AssessmentRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => BreathingProvider(_FakeBreathingRepository()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          routes: _testRoutes(),
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Check in on academic well-being'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.text('Check in on academic well-being'), findsNothing);
  });

  testWidgets('home Mental Wellbeing 101 opens mental health insights', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MoodProvider>(
            create: (_) => MoodProvider(_FakeMoodRepository()),
          ),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FakeReportRepository()),
          ),
          ChangeNotifierProvider<InsightsProvider>(
            create: (_) => InsightsProvider(InsightsRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => AssessmentProvider(AssessmentRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => BreathingProvider(_FakeBreathingRepository()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          routes: _testRoutes(),
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Mental Wellbeing 101'),
      500,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('Mental Wellbeing 101'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mental Wellbeing 101'));
    await tester.pumpAndSettle();

    expect(find.text('Search insights...'), findsOneWidget);
    expect(find.text('Coming soon'), findsNothing);
  });

  testWidgets('home uses the supplied Dashboard icon assets', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MoodProvider>(
            create: (_) => MoodProvider(_FakeMoodRepository()),
          ),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FakeReportRepository()),
          ),
          ChangeNotifierProvider<InsightsProvider>(
            create: (_) => InsightsProvider(InsightsRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => AssessmentProvider(AssessmentRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => BreathingProvider(_FakeBreathingRepository()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          routes: _testRoutes(),
          home: const HomeScreen(),
        ),
      ),
    );

    for (final assetName in [
      'Customer.png',
      'Calendar.png',
      'High Importance.png',
      'Forward.png',
      'x.png',
      'Notification.png',
      '+.png',
      '🔥.png',
      'Thumbs up.png',
      'Good Quality.png',
    ]) {
      expect(_dashboardAsset(assetName), findsWidgets);
    }

    await tester.scrollUntilVisible(
      find.text('Mental Wellbeing 101'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    for (final assetName in [
      '🐶.png',
      'Creativity.png',
      'Rolled Up Newspaper.png',
      'Warranty.png',
    ]) {
      expect(_dashboardAsset(assetName), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home remains overflow-free on a narrow phone with larger text and reduced motion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final userProvider = UserProvider(_FakeUserRepository())
        ..setUser(
          const UserModel(
            id: 'user_1',
            email: 'leo@example.com',
            firstName: 'Leonardo',
            lastName: 'Molar',
            role: 'student',
          ),
        );
      Duration? resolvedMotionDuration;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>.value(value: userProvider),
            ChangeNotifierProvider<MoodProvider>(
              create: (_) => MoodProvider(_FakeMoodRepository()),
            ),
            ChangeNotifierProvider<ReportProvider>(
              create: (_) => ReportProvider(_FakeReportRepository()),
            ),
            ChangeNotifierProvider<InsightsProvider>(
              create: (_) => InsightsProvider(InsightsRepository()),
            ),
            ChangeNotifierProvider(
              create: (_) => AssessmentProvider(AssessmentRepository()),
            ),
            ChangeNotifierProvider(
              create: (_) => BreathingProvider(_FakeBreathingRepository()),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
            routes: _testRoutes(),
            builder: (context, child) {
              final media = MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.3),
              );
              return MediaQuery(
                data: media,
                child: Builder(
                  builder: (context) {
                    resolvedMotionDuration = HomeMotion.duration(context, 300);
                    return child!;
                  },
                ),
              );
            },
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(resolvedMotionDuration, Duration.zero);
      expect(tester.takeException(), isNull);

      final scrollable = find.byType(CustomScrollView);
      for (var index = 0; index < 7; index++) {
        await tester.drag(scrollable, const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Home'), findsOneWidget);
    },
  );

  testWidgets('home Mindful breathing insight opens breathing screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MoodProvider>(
            create: (_) => MoodProvider(_FakeMoodRepository()),
          ),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FakeReportRepository()),
          ),
          ChangeNotifierProvider<InsightsProvider>(
            create: (_) => InsightsProvider(InsightsRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => AssessmentProvider(AssessmentRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => BreathingProvider(_FakeBreathingRepository()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          routes: _testRoutes(),
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Mindful breathing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Breathing'), findsOneWidget);
    expect(find.text('Breath to reduce'), findsOneWidget);
    expect(find.text('Anger'), findsOneWidget);
  });

  testWidgets('home Breathing exercise toolkit opens breathing screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MoodProvider>(
            create: (_) => MoodProvider(_FakeMoodRepository()),
          ),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FakeReportRepository()),
          ),
          ChangeNotifierProvider<InsightsProvider>(
            create: (_) => InsightsProvider(InsightsRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => AssessmentProvider(AssessmentRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => BreathingProvider(_FakeBreathingRepository()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          routes: _testRoutes(),
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Breathing exercise'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Breathing exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Breathing exercise'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Breathing'), findsOneWidget);
    expect(find.text('Breath to reduce'), findsOneWidget);
  });

  testWidgets('home blocks main assessment when rolling limit is reached', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(
        const UserModel(
          id: 'user_1',
          email: 'leo@example.com',
          role: 'student',
        ),
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MoodProvider>(
            create: (_) => MoodProvider(_FakeMoodRepository()),
          ),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FakeReportRepository()),
          ),
          ChangeNotifierProvider<InsightsProvider>(
            create: (_) => InsightsProvider(InsightsRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) => AssessmentProvider(
              _FakeAssessmentRepository(
                eligibility: FullAssessmentEligibility(
                  canStart: false,
                  nextEligibleAt: DateTime(2026, 7, 5, 9),
                  reason: FullAssessmentBlockReason.minimumInterval,
                ),
              ),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) => BreathingProvider(_FakeBreathingRepository()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          routes: _testRoutes(),
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Start Assessment'));
    await tester.pumpAndSettle();

    expect(find.text('Assessment limit reached'), findsOneWidget);
    expect(find.textContaining('up to 2 times in 7 days'), findsOneWidget);
    expect(find.text('Start Assessment?'), findsNothing);
  });

  testWidgets('home shows fallback warning when eligibility check throws', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(
        const UserModel(
          id: 'user_1',
          email: 'leo@example.com',
          role: 'student',
        ),
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MoodProvider>(
            create: (_) => MoodProvider(_FakeMoodRepository()),
          ),
          ChangeNotifierProvider<ReportProvider>(
            create: (_) => ReportProvider(_FakeReportRepository()),
          ),
          ChangeNotifierProvider<InsightsProvider>(
            create: (_) => InsightsProvider(InsightsRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                AssessmentProvider(_FakeAssessmentRepository(throws: true)),
          ),
          ChangeNotifierProvider(
            create: (_) => BreathingProvider(_FakeBreathingRepository()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          routes: _testRoutes(),
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Start Assessment'));
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to verify assessment limit. You can continue for now.'),
      findsOneWidget,
    );
    expect(find.text('Start Assessment?'), findsOneWidget);
    expect(find.text('Assessment limit reached'), findsNothing);
  });
}

Map<String, WidgetBuilder> _testRoutes() {
  return Map<String, WidgetBuilder>.of(AppPages.routes)
    ..remove(Navigator.defaultRouteName);
}

Finder _dashboardAsset(String assetName) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is HomeDashboardAssetImage && widget.assetName == assetName,
    skipOffstage: false,
  );
}

class _FakeUserRepository extends UserRepository {}

class _FakeMoodRepository extends MoodRepository {
  @override
  Future<String> createMood({
    required String userId,
    required int level,
    String? label,
    String? note,
    DateTime? now,
  }) async {
    return 'mood_1';
  }

  @override
  Future<MoodModel?> fetchTodayMood(String userId, {DateTime? now}) async {
    return null;
  }

  @override
  Future<List<MoodModel>> fetchRecentMoods(String userId, {int limit = 14}) {
    return Future.value(const []);
  }
}

class _FakeReportRepository extends ReportRepository {
  _FakeReportRepository({this.latest});

  final ReportModel? latest;

  @override
  Future<ReportModel?> fetchLatestReport(String userId) async => latest;

  @override
  Future<String> createPlaceholderWeeklyReport(String userId) async =>
      'test_placeholder';
}

class _FakeBreathingRepository extends BreathingRepository {}

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository({
    this.eligibility = const FullAssessmentEligibility(canStart: true),
    this.throws = false,
  });

  final FullAssessmentEligibility eligibility;
  final bool throws;

  @override
  Future<FullAssessmentEligibility> fullAssessmentEligibility(
    String userId, {
    DateTime? now,
  }) async {
    if (throws) {
      throw StateError('test eligibility failure');
    }
    return eligibility;
  }
}
