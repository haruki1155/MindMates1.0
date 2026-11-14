import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mind_mates/core/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mind_mates/features/home/screens/home_screen.dart';
import 'package:mind_mates/features/home/widgets/home_dashboard_widgets.dart';
import 'package:mind_mates/features/mood/screens/log_mood_screen.dart';
import 'package:mind_mates/features/mood/screens/mood_journey_screen.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/features/mood/config/mood_v2_feature_flag.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/repositories/mood_repository.dart';
import 'package:mind_mates/repositories/mood_combined_history_repository.dart';
import 'package:mind_mates/repositories/mood_v2_repository.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:mind_mates/routes/route_names.dart';

void main() => moodVisualAcceptance();

/// Runs the real screens/provider against an in-memory persistence boundary.
/// The device wrapper supplies screenshots; no Firebase is initialized.
void moodVisualAcceptance({Future<void> Function(String name)? screenshot}) {
  testWidgets('three same-day saves, route navigation and owner isolation', (
    tester,
  ) async {
    final authRepo = _AuthRepository();
    final auth = AuthProvider(authRepo);
    final history = _History();
    final mood = MoodProvider(
      _Legacy(),
      combinedHistoryRepository: history,
      useMoodV2Read: true,
    )..bindAuthenticatedUser(authRepo.uid);
    final users = UserProvider(_Users())..setUser(_profile(authRepo.uid));
    final writer = _Writer(history, authRepo);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<UserProvider>.value(value: users),
          ChangeNotifierProvider<MoodProvider>.value(value: mood),
          ChangeNotifierProvider(
            create: (_) => AssessmentProvider(AssessmentRepository()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          routes: {
            RouteNames.logMood: (_) => LogMoodScreen(
              moodV2Presentation: true,
              moodV2WriterEnabled: true,
              moodV2Writer: writer,
            ),
            RouteNames.mentalHealthInsights: (_) =>
                const Scaffold(body: Text('Existing inSIGHT destination')),
          },
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mood check-ins'), findsNothing);
    // Item 40: Home logs moods from the Day streak card's "Log mood".
    final log = find.descendant(
      of: find.byType(HomeStreakCard),
      matching: find.text(
        MoodV2FeatureFlag.actionLabel(hasCheckedInToday: false),
      ),
    );
    expect(log, findsOneWidget);
    if (screenshot != null) await screenshot('01-home');
    await tester.ensureVisible(log);
    await tester.pumpAndSettle();
    await tester.tap(log);
    await tester.pumpAndSettle();
    if (MoodV2FeatureFlag.historyRead) {
      await tester.tap(find.text('0 check-ins today'));
      await tester.pumpAndSettle();
      expect(find.byType(MoodJourneyScreen), findsOneWidget);
      expect(writer.ids, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Okay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    if (screenshot != null) await screenshot('02-mood-log');
    for (var i = 0; i < 3; i++) {
      if (i > 0) {
        await tester.ensureVisible(find.text('Log another mood'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Log another mood'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Okay'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Okay'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byType(TextField),
        'Synthetic owner-only note $i',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save mood entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();
      expect(find.text('Your mood is recorded'), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        0,
        reason: 'Saved confirmation starts at the header',
      );
    }
    expect(writer.ids.toSet(), hasLength(3));
    expect(mood.v2History!.uniqueEvents, hasLength(3));
    expect(
      MoodAnalytics.streak(
        mood.v2History!,
        referenceInstant: DateTime.now(),
      ).currentDays,
      1,
    );
    if (screenshot != null) await screenshot('03-mood-saved');
    await tester.ensureVisible(find.text('View My Mood Journey'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View My Mood Journey'));
    await tester.pumpAndSettle();
    expect(find.byType(MoodJourneyScreen), findsOneWidget);
    expect(find.text('3 check-ins · 1 mood-active day'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsOneWidget);
    if (screenshot != null) await screenshot('04-mood-journey');
    await tester.ensureVisible(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ExpansionTile).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic owner-only note 2'), findsOneWidget);
    authRepo.uid = 'synthetic-b';
    mood.bindAuthenticatedUser(authRepo.uid);
    users.setUser(_profile(authRepo.uid));
    auth.hydrateCurrentUser();
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic owner-only note'), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Mental Health Support'),
      160,
      scrollable: find
          .descendant(
            of: find.byType(MoodJourneyScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mental Health Support'));
    await tester.pumpAndSettle();
    expect(find.text('Existing inSIGHT destination'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

UserModel _profile(String uid) => UserModel(
  id: uid,
  email: 'synthetic@example.invalid',
  name: 'Student',
  firstName: 'Student',
  dayStreak: 3,
);

class _AuthRepository extends AuthRepository {
  _AuthRepository() : super(AuthService());
  String uid = 'synthetic-a';
  @override
  String? get currentUserId => uid;
}

class _Users extends UserRepository {
  @override
  Future<UserModel?> fetchUserProfile(String uid) async => _profile(uid);
  @override
  Future<UserModel?> recordActivity(
    String uid,
    UserActivityType type, {
    DateTime? occurredAt,
  }) async => _profile(uid);
}

class _Legacy extends MoodRepository {
  @override
  Future<MoodModel?> fetchTodayMood(String userId, {DateTime? now}) async =>
      null;
  @override
  Future<List<MoodModel>> fetchRecentMoods(
    String userId, {
    int limit = 14,
  }) async => [];
}

class _History implements MoodCombinedHistoryRepository {
  @override
  Future<Map<String, String?>> fetchOwnerNotes({
    required String userId,
    required List<NormalizedMoodEvent> events,
  }) async => {
    for (final event in events.where((e) => e.userId == userId))
      event.stableIdentity: event.note,
  };

  final events = <NormalizedMoodEvent>[];
  @override
  Future<MoodCombinedHistoryPage> fetch(
    MoodCombinedHistoryRequest request,
  ) async => MoodCombinedHistoryPage(
    window: MoodHistoryWindow(
      events: events.where((e) => e.userId == request.userId).toList(),
      coverage: MoodHistoryCoverage.complete,
    ),
    nextCursor: null,
    failedSources: const {},
  );
}

class _Writer implements MoodV2EntryWriter {
  _Writer(this.history, this.auth);
  final _History history;
  final _AuthRepository auth;
  final ids = <String>[];
  @override
  Future<MoodV2Event> create({
    required int level,
    required String clientRequestId,
    String? label,
    String? note,
    String entryMethod = 'manual',
    bool expressionAssistUsed = false,
    bool expressionSuggestionAccepted = false,
    String? expressionModelVersion,
  }) async {
    ids.add(clientRequestId);
    final now = DateTime.now();
    final entry = MoodV2Event(
      id: clientRequestId,
      userId: auth.uid,
      level: level,
      dateKey: MoodManilaCalendar.dateKeyForInstant(now),
      occurredAt: now,
      clientRequestId: clientRequestId,
      label: label,
      note: note,
    );
    history.events.add(entry.toNormalized());
    return entry;
  }
}
