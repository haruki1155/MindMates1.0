import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/profile/screens/mental_health_report_screen.dart';
import 'package:mind_mates/features/profile/screens/profile_screen.dart';
import 'package:mind_mates/models/mental_health_activity_summary.dart';
import 'package:mind_mates/models/report_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/mental_health_activity_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/mental_health_activity_repository.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/repositories/report_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/app_pages.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('profile hero shows user info and day streak', (tester) async {
    final repository = _FakeUserRepository();
    final provider = UserProvider(repository)
      ..setUser(
        UserModel.fromJson({
          'id': 'user_1',
          'email': 'leo@example.com',
          'firstName': 'Leonardo',
          'lastName': 'Molar',
          'role': 'student',
          'dayStreak': 20,
          'createdAt': '2026-06-30T00:00:00.000',
        }),
      );

    await tester.pumpWidget(
      _profileApp(provider, data: _dataFrom(provider.user!)),
    );

    expect(find.text('Leonardo Molar'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Member since Jun 30, 2026'), findsNothing);
    expect(find.text('leo@example.com'), findsNothing);
    expect(find.byType(FractionallySizedBox), findsNothing);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('--/10'), findsNWidgets(2));
  });

  testWidgets('mental health summary buttons and routes are ready', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

    await tester.pumpWidget(
      _profileApp(provider, data: _dataFrom(provider.user!)),
    );

    expect(find.text('Full Report'), findsOneWidget);
    expect(find.text('View Insights'), findsOneWidget);
    expect(AppPages.routes[RouteNames.mentalHealthReport], isNotNull);
    expect(AppPages.routes[RouteNames.mentalHealthInsights], isNotNull);
  });

  testWidgets('profile opens the Terms and Conditions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

    await tester.pumpWidget(
      _profileApp(provider, data: _dataFrom(provider.user!)),
    );

    await tester.tap(find.text('Terms and Conditions').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Terms and Conditions'), findsWidgets);
    expect(find.textContaining('Data Privacy Act of 2012'), findsOneWidget);
    expect(find.byKey(const Key('terms-close')), findsOneWidget);
  });

  testWidgets('profile Log Out confirms, signs out, and opens login', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));
    final authProvider = _FakeAuthProvider();

    await tester.pumpWidget(
      _profileApp(
        userProvider,
        data: _dataFrom(userProvider.user!),
        authProvider: authProvider,
      ),
    );

    expect(find.text('Log Out'), findsOneWidget);
    await tester.tap(find.text('Log Out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Log out of MindMate?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(authProvider.signOutCalls, 0);

    await tester.tap(find.text('Log Out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Log Out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(authProvider.signOutCalls, 1);
    expect(userProvider.user, isNull);
    expect(find.text('Login target'), findsOneWidget);
    expect(find.byType(ProfileScreen), findsNothing);
  });

  testWidgets('mental health summary uses generated report text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));
    final reportRepository = _FakeReportRepository(
      ReportModel(
        id: 'report_1',
        userId: 'user_1',
        title: 'Mental Health Summary',
        description:
            'Latest assessment shows moderate concern with a 4-day streak.',
        generatedAt: DateTime(2026, 7, 3),
        hasEnoughData: true,
      ),
    );
    final reportProvider = ReportProvider(reportRepository);
    await reportProvider.loadLatestReport('user_1');

    await tester.pumpWidget(
      _profileApp(userProvider, reportProvider: reportProvider),
    );
    await tester.pump();

    expect(
      find.text(
        'Latest assessment shows moderate concern with a 4-day streak.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('mental health report shows daily activity summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 7000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final activityRepository = _FakeActivityRepository(
      _dailySummary(
        moodCheckIns: 4,
        averageMoodLevel: 3.2,
        mindAidMessages: 5,
        breathingSessions: 2,
        breathingMinutes: 8,
        currentStreak: 4,
        secretChatPosts: 1,
        secretChatComments: 2,
        secretChatInteractions: 3,
        assessmentCount: 1,
      ),
    );
    final activityProvider = MentalHealthActivityProvider(activityRepository);
    final weeklyReport = ReportModel(
      id: 'weekly_1',
      userId: 'user_1',
      title: 'Mental Health Summary',
      description: 'A complete weekly reflection for review.',
      generatedAt: DateTime(2026, 7, 7, 12, 30),
      weekStart: DateTime(2026, 7, 1),
      weekEnd: DateTime(2026, 7, 7),
      mentalStatus: 'needs_support',
      mentalStatusLabel: 'Needs Support',
      moodCheckInCount: 4,
      averageMoodLevel: 3.2,
      assessmentCount: 1,
      fullAssessmentScore: 18,
      fullAssessmentStatus: 'At Risk',
      fullAssessmentSummary:
          'Your responses suggest some strain in Academic Stress and Sleep and Rest.',
      fullAssessmentDomainStatuses: const {
        'Academic Stress': 'At Risk',
        'Sleep and Rest': 'Stable',
      },
      quickAssessmentStatus: 'moderate',
      quickAssessmentSummary:
          'Responses suggest some areas of strain that may benefit from support.',
      quickAssessmentAreaStatuses: const {'Stress load': 'Moderate'},
      latestAssessmentStatus: 'Moderate concern',
      mentalStatusSignal: 'Academic stress needs attention.',
      breathingSessionCount: 2,
      mindfulBreathingMinutes: 8,
      activeDayCount: 4,
      currentStreak: 4,
      totalEngagementCount: 15,
      secretChatEngagementCount: 3,
      topConcernAreas: const ['Academic Stress', 'Sleep and Rest'],
      recommendedNextActions: const [
        'Continue daily mood check-ins',
        'Try a short mindful breathing session',
      ],
      hasEnoughData: true,
    );
    final reportRepository = _FakeReportRepository(weeklyReport);
    final reportProvider = ReportProvider(reportRepository);
    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MentalHealthActivityProvider>.value(
            value: activityProvider,
          ),
          ChangeNotifierProvider<ReportProvider>.value(value: reportProvider),
        ],
        child: const MaterialApp(home: MentalHealthReportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Latest Psychological Assessment'), findsOneWidget);
    expect(find.text('Quick Assessment'), findsOneWidget);
    expect(find.text('Well-being status by sector'), findsNWidgets(2));
    expect(find.text('Academic Stress'), findsOneWidget);
    expect(find.text('Sleep and Rest'), findsOneWidget);
    expect(find.text('Stress load'), findsOneWidget);
    expect(find.text('At Risk'), findsNWidgets(2));
    expect(find.text('Stable'), findsOneWidget);
    expect(
      find.textContaining('Your responses suggest some strain'),
      findsOneWidget,
    );
    expect(find.textContaining('Recorded score'), findsNothing);
    expect(find.text('Weekly mood'), findsNothing);
    expect(activityRepository.loadCount, 0);
    expect(reportRepository.refreshCount, 1);

    final refresh = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await refresh;
    await tester.pumpAndSettle();
    expect(activityRepository.loadCount, 0);
    expect(reportRepository.refreshCount, 2);
  });

  testWidgets('mental health report shows empty daily activity state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final activityRepository = _FakeActivityRepository(
      MentalHealthActivitySummary.empty(
        date: DateTime(2026, 7, 7),
        currentStreak: 2,
      ),
    );
    final activityProvider = MentalHealthActivityProvider(activityRepository);
    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MentalHealthActivityProvider>.value(
            value: activityProvider,
          ),
        ],
        child: const MaterialApp(home: MentalHealthReportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Complete a Quick or Full Assessment'),
      findsOneWidget,
    );
    expect(find.text("Today's activity"), findsNothing);
  });

  testWidgets('mental health report shows loading while refreshing on open', (
    tester,
  ) async {
    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'leo@example.com'));
    final activityRepository = _SlowActivityRepository(
      _dailySummary(moodCheckIns: 1),
    );
    final activityProvider = MentalHealthActivityProvider(activityRepository);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<MentalHealthActivityProvider>.value(
            value: activityProvider,
          ),
        ],
        child: const MaterialApp(home: MentalHealthReportScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);

    activityRepository.completeLoad();
    await tester.pumpAndSettle();

    expect(activityRepository.loadCount, 0);
  });

  testWidgets('mental health report asks for sign in when user is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<MentalHealthActivityProvider>.value(
        value: MentalHealthActivityProvider(
          _FakeActivityRepository(_dailySummary()),
        ),
        child: const MaterialApp(home: MentalHealthReportScreen()),
      ),
    );

    expect(
      find.text('Please sign in to view your assessment summary.'),
      findsOneWidget,
    );
  });
}

Widget _profileApp(
  UserProvider provider, {
  ProfileViewData? data,
  ReportProvider? reportProvider,
  AuthProvider? authProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: provider),
      if (authProvider != null)
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      if (reportProvider != null)
        ChangeNotifierProvider<ReportProvider>.value(value: reportProvider),
    ],
    child: MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: ProfileScreen(data: data),
      routes: {
        RouteNames.login: (_) =>
            const Scaffold(body: Center(child: Text('Login target'))),
      },
    ),
  );
}

ProfileViewData _dataFrom(UserModel user) {
  return ProfileViewData(
    displayName: user.displayName,
    role: user.roleLabel,
    email: user.email,
    memberSince: 'Member since Jun 30, 2026',
    metrics: [
      ProfileMetricData(
        label: 'Day Streak',
        value: '${user.dayStreak}',
        icon: Icons.local_fire_department,
      ),
      const ProfileMetricData(
        label: 'Sleep',
        value: '--/10',
        icon: Icons.sentiment_satisfied_alt,
      ),
      const ProfileMetricData(
        label: 'Stress',
        value: '--/10',
        icon: Icons.bar_chart,
      ),
    ],
    summary: const ProfileSummaryData(
      title: 'Mental Health Summary',
      description: "This week's positive moods",
    ),
  );
}

class _FakeUserRepository extends UserRepository {
  UserModel? updatedUser;

  @override
  Future<UserModel?> fetchUserProfile(String uid) async {
    return UserModel(id: uid, email: 'leo@example.com');
  }

  @override
  Future<void> updateUserProfile(String uid, UserModel user) async {
    updatedUser = user;
  }
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(_FakeAuthRepository());

  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(AuthService());
}

class _FakeReportRepository extends ReportRepository {
  _FakeReportRepository(this.report);

  final ReportModel report;
  int refreshCount = 0;

  @override
  Future<ReportModel?> fetchLatestReport(String userId) async => report;

  @override
  Future<String> generateWeeklyReport(String userId, {DateTime? now}) async {
    refreshCount += 1;
    return report.id;
  }
}

class _FakeActivityRepository extends MentalHealthActivityRepository {
  _FakeActivityRepository(this.summary);

  final MentalHealthActivitySummary summary;
  int loadCount = 0;

  @override
  Future<MentalHealthActivitySummary> fetchDailySummary(
    String userId, {
    DateTime? date,
  }) async {
    loadCount += 1;
    return summary;
  }
}

class _SlowActivityRepository extends _FakeActivityRepository {
  _SlowActivityRepository(super.summary);

  final Completer<void> _loadCompleter = Completer<void>();

  @override
  Future<MentalHealthActivitySummary> fetchDailySummary(
    String userId, {
    DateTime? date,
  }) async {
    loadCount += 1;
    await _loadCompleter.future;
    return summary;
  }

  void completeLoad() {
    if (!_loadCompleter.isCompleted) {
      _loadCompleter.complete();
    }
  }
}

MentalHealthActivitySummary _dailySummary({
  int moodCheckIns = 0,
  double? averageMoodLevel,
  int mindAidMessages = 0,
  int breathingSessions = 0,
  int breathingMinutes = 0,
  int secretChatPosts = 0,
  int secretChatComments = 0,
  int secretChatInteractions = 0,
  int assessmentCount = 0,
  int currentStreak = 0,
}) {
  return MentalHealthActivitySummary(
    date: DateTime(2026, 7, 7),
    moodCheckIns: moodCheckIns,
    averageMoodLevel: averageMoodLevel,
    mindAidMessages: mindAidMessages,
    breathingSessions: breathingSessions,
    breathingMinutes: breathingMinutes,
    secretChatPosts: secretChatPosts,
    secretChatComments: secretChatComments,
    secretChatInteractions: secretChatInteractions,
    assessmentCount: assessmentCount,
    currentStreak: currentStreak,
    recentActivities: [
      if (moodCheckIns > 0)
        MentalHealthActivityItem(
          type: 'moodCheckIn',
          label: 'Logged mood',
          occurredAt: DateTime(2026, 7, 7, 9, 15),
        ),
      if (secretChatComments > 0)
        MentalHealthActivityItem(
          type: 'secretChatComment',
          label: 'Replied in Secret Chat',
          occurredAt: DateTime(2026, 7, 7, 10, 30),
        ),
    ],
  );
}
