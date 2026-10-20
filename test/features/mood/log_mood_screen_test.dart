import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mood/expression_check_in/expression_check_in_screen.dart';
import 'package:mind_mates/features/mood/expression_check_in/expression_scan_logic.dart';
import 'package:mind_mates/features/mood/screens/log_mood_screen.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/models/report_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/mood_repository.dart';
import 'package:mind_mates/repositories/mood_v2_repository.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/repositories/report_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('renders all mood choices and note field', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: LogMoodScreen()));

    expect(find.text('How are you feeling?'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    for (final label in [
      'Great',
      'Okay',
      'Stressed',
      'Sad',
      'Angry',
      'Tired',
      'Excited',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text("What's on your mind today?"), findsOneWidget);
    expect(find.text('0/300 characters'), findsOneWidget);
  });

  testWidgets('tapping a mood updates selected card styling', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: LogMoodScreen()));

    final angryCard = find.byKey(const ValueKey('mood-card-Angry'));
    expect(_cardBorderWidth(tester, angryCard), 1.2);

    await tester.tap(find.text('Angry'));
    await tester.pumpAndSettle();

    expect(_cardBorderWidth(tester, angryCard), 2);
    expect(_saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('expression suggestion requires confirmation before saving', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: LogMoodScreen(
          expressionScreenBuilder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).pop(
                const ExpressionCheckInResult(
                  completed: true,
                  cue: ExpressionCue.smiling,
                ),
              ),
              child: const Text('Return cue'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Check expression with camera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return cue'));
    await tester.pumpAndSettle();

    expect(find.text('Smiling expression detected'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    await tester.tap(find.text('Yes, somewhat'));
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNotNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('saves only minimal metadata for a confirmed expression assist', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeMoodRepository();

    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(repository),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        expressionScreenBuilder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).pop(
              const ExpressionCheckInResult(
                completed: true,
                cue: ExpressionCue.tenseLike,
                source: ExpressionCueSource.tflite,
              ),
            ),
            child: const Text('Return TFLite cue'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Check expression with camera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return TFLite cue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not really'));
    await tester.pump();
    await tester.tap(find.text('Okay'));
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNotNull);
    await tester.ensureVisible(find.text('Save mood check-in'));
    await tester.tap(find.text('Save mood check-in'));
    await tester.pumpAndSettle();

    expect(repository.createdEntryMethod, 'expression_assisted');
    expect(repository.createdExpressionAssistUsed, isTrue);
    expect(repository.createdExpressionSuggestionAccepted, isFalse);
    expect(
      repository.createdExpressionModelVersion,
      'justinshenk_fer_tflite_v1',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('typing thoughts updates character count', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: LogMoodScreen()));

    await tester.enterText(find.byType(TextField), 'Feeling steady today');
    await tester.pump();

    expect(find.text('20/300 characters'), findsOneWidget);
  });

  testWidgets('saving mood writes backend data and refreshes summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final moodRepository = _FakeMoodRepository();
    final userRepository = _FakeUserRepository();
    final reportRepository = _FakeReportRepository();
    final fixedNow = DateTime(2026, 7, 7, 12);

    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(moodRepository),
        userProvider: UserProvider(userRepository)
          ..setUser(_user(id: 'user_1')),
        reportProvider: ReportProvider(reportRepository),
        nowProvider: () => fixedNow,
      ),
    );

    await tester.tap(find.text('Stressed'));
    await tester.enterText(find.byType(TextField), 'Exams feel heavy.');
    await tester.tap(find.text('Save mood check-in'));
    await tester.pumpAndSettle();

    expect(moodRepository.createdUserId, 'user_1');
    expect(moodRepository.createdLevel, 2);
    expect(moodRepository.createdLabel, 'Stressed');
    expect(moodRepository.createdNote, 'Exams feel heavy.');
    expect(userRepository.loadedUid, 'user_1');
    expect(moodRepository.fetchedUserId, 'user_1');
    expect(reportRepository.generatedForUserId, 'user_1');
    expect(find.byType(LogMoodScreen), findsOneWidget);
    expect(find.text("Today's check-in is complete"), findsOneWidget);
    expect(find.text('Exams feel heavy.'), findsOneWidget);
  });

  testWidgets('save failure keeps screen visible and shows error', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository(throwsOnCreate: true)),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
      ),
    );

    await tester.tap(find.text('Sad'));
    await tester.ensureVisible(find.text('Save mood check-in'));
    await tester.pump();
    await tester.tap(find.text('Save mood check-in'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(LogMoodScreen), findsOneWidget);
    expect(find.text('Unable to save mood.'), findsOneWidget);
  });

  testWidgets('missing user id shows sign-in error and does not save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final moodRepository = _FakeMoodRepository();

    await tester.pumpWidget(
      _logMoodApp(moodProvider: MoodProvider(moodRepository)),
    );

    await tester.tap(find.text('Great'));
    await tester.ensureVisible(find.text('Save mood check-in'));
    await tester.pump();
    await tester.tap(find.text('Save mood check-in'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(moodRepository.createdUserId, isNull);
    expect(find.text('Please sign in to save your mood.'), findsOneWidget);
  });

  testWidgets('disabled Mood V2 keeps the existing daily logger unchanged', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Great'));
    await tester.pump();
    await tester.tap(find.text('Save mood check-in'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mood-v2-add-entry')), findsNothing);
    expect(find.text("Today's check-in is complete"), findsOneWidget);
  });

  testWidgets('enabled V2 writer accepts multiple intentional entries', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final writer = _FakeMoodV2Writer();
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Enabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Great'));
    await tester.pump();
    await tester.tap(find.text('Save mood check-in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sad'));
    await tester.pump();
    await tester.tap(find.text('Save mood check-in'));
    await tester.pumpAndSettle();

    expect(writer.levels, [5, 1]);
    expect(writer.requestIds.toSet().length, 2);
    expect(
      writer.requestIds.every(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch,
      ),
      isTrue,
    );
  });

  testWidgets('V2 retry preserves one request ID after a failed attempt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final writer = _FakeMoodV2Writer(failuresRemaining: 1);
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Enabled: true,
        moodV2Writer: writer,
        moodV2RequestIdGenerator: () => '00000000-0000-4000-8000-000000000001',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Okay'));
    await tester.pump();
    await tester.tap(find.text('Save mood check-in'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mood-v2-save-error')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Edited after failure');
    await tester.tap(find.text('Great'));
    await tester.pump();
    await tester.tap(find.text('Save mood check-in'));
    await tester.pumpAndSettle();
    expect(writer.requestIds, [
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000001',
    ]);
    expect(writer.levels, [4, 4]);
    expect(writer.notes, ['', '']);
  });

  testWidgets('V2 save prevents duplicate taps while a request is pending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final writer = _FakeMoodV2Writer(pending: true);
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Enabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tired'));
    await tester.pump();
    await tester.tap(find.text('Save mood check-in'));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(writer.requestIds, hasLength(1));

    writer.completePending();
    await tester.pumpAndSettle();
  });

  testWidgets('V2 pending completion is ignored after an account change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final writer = _FakeMoodV2Writer(pending: true);
    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(_user(id: 'user_1'));
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: userProvider,
        moodV2Enabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tired'));
    await tester.pump();
    await tester.tap(find.text('Save mood check-in'));
    await tester.pump();
    expect(writer.requestIds, hasLength(1));

    userProvider.setUser(_user(id: 'user_2'));
    await tester.pumpAndSettle();
    writer.completePending();
    await tester.pumpAndSettle();

    expect(find.text('Mood entry saved.'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });
}

Widget _logMoodApp({
  required MoodProvider moodProvider,
  UserProvider? userProvider,
  ReportProvider? reportProvider,
  DateTime Function()? nowProvider,
  WidgetBuilder? expressionScreenBuilder,
  bool moodV2Enabled = false,
  MoodV2EntryWriter? moodV2Writer,
  String Function()? moodV2RequestIdGenerator,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MoodProvider>.value(value: moodProvider),
      if (userProvider != null)
        ChangeNotifierProvider<UserProvider>.value(value: userProvider),
      if (reportProvider != null)
        ChangeNotifierProvider<ReportProvider>.value(value: reportProvider),
    ],
    child: MaterialApp(
      home: LogMoodScreen(
        nowProvider: nowProvider,
        expressionScreenBuilder: expressionScreenBuilder,
        moodV2Enabled: moodV2Enabled,
        moodV2Writer: moodV2Writer,
        moodV2RequestIdGenerator: moodV2RequestIdGenerator,
      ),
    ),
  );
}

ElevatedButton _saveButton(WidgetTester tester) {
  return tester.widget<ElevatedButton>(
    find.widgetWithText(ElevatedButton, 'Save mood check-in'),
  );
}

double? _cardBorderWidth(WidgetTester tester, Finder finder) {
  final card = tester.widget<AnimatedContainer>(finder);
  final decoration = card.decoration;
  if (decoration is! BoxDecoration) return null;
  final border = decoration.border;
  if (border is! Border) return null;
  return border.top.width;
}

UserModel _user({required String id}) {
  return UserModel(
    id: id,
    email: 'student@example.com',
    name: 'Student User',
    firstName: 'Student',
    lastName: 'User',
    schoolId: '2026-0001',
    department: 'CCS',
    course: 'BSIT',
  );
}

class _FakeMoodRepository extends MoodRepository {
  _FakeMoodRepository({this.throwsOnCreate = false});

  final bool throwsOnCreate;
  String? createdUserId;
  int? createdLevel;
  String? createdLabel;
  String? createdNote;
  String? createdEntryMethod;
  bool? createdExpressionAssistUsed;
  bool? createdExpressionSuggestionAccepted;
  String? createdExpressionModelVersion;
  String? fetchedUserId;

  @override
  Future<String> createMood({
    required String userId,
    required int level,
    String? label,
    String? note,
    DateTime? now,
  }) async {
    if (throwsOnCreate) throw StateError('save failed');
    createdUserId = userId;
    createdLevel = level;
    createdLabel = label;
    createdNote = note;
    return 'mood_1';
  }

  @override
  Future<MoodModel?> fetchTodayMood(String userId, {DateTime? now}) async {
    return null;
  }

  @override
  Future<DailyMoodSaveResult> saveDailyMood({
    required String userId,
    required int level,
    String? label,
    String? note,
    String? entryMethod,
    bool? expressionAssistUsed,
    bool? expressionSuggestionAccepted,
    String? expressionModelVersion,
    DateTime? now,
  }) async {
    if (throwsOnCreate) throw StateError('save failed');
    createdUserId = userId;
    createdLevel = level;
    createdLabel = label;
    createdNote = note;
    createdEntryMethod = entryMethod;
    createdExpressionAssistUsed = expressionAssistUsed;
    createdExpressionSuggestionAccepted = expressionSuggestionAccepted;
    createdExpressionModelVersion = expressionModelVersion;
    return DailyMoodSaveResult(
      mood: MoodModel(
        id: 'daily_user_1_20260707',
        userId: userId,
        level: level,
        label: label,
        note: note,
        createdAt: now ?? DateTime(2026, 7, 7, 12),
      ),
      created: true,
    );
  }

  @override
  Future<List<MoodModel>> fetchRecentMoods(String userId, {int limit = 14}) {
    fetchedUserId = userId;
    return Future.value([
      MoodModel(
        id: 'mood_1',
        userId: userId,
        level: 2,
        createdAt: DateTime.now(),
      ),
    ]);
  }
}

class _FakeMoodV2Writer implements MoodV2EntryWriter {
  _FakeMoodV2Writer({this.failuresRemaining = 0, this.pending = false});

  int failuresRemaining;
  final bool pending;
  final List<String> requestIds = [];
  final List<int> levels = [];
  final List<String?> notes = [];
  Completer<MoodV2Event>? _pendingResult;

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
  }) {
    requestIds.add(clientRequestId);
    levels.add(level);
    notes.add(note);
    if (failuresRemaining > 0) {
      failuresRemaining--;
      return Future<MoodV2Event>.error(StateError('offline'));
    }
    if (pending) {
      return (_pendingResult ??= Completer<MoodV2Event>()).future;
    }
    return Future.value(
      _event(level, clientRequestId, label, note, entryMethod),
    );
  }

  void completePending() {
    _pendingResult?.complete(
      _event(levels.last, requestIds.last, null, null, 'manual'),
    );
  }

  MoodV2Event _event(
    int level,
    String requestId,
    String? label,
    String? note,
    String? entryMethod,
  ) => MoodV2Event(
    id: 'mood_v2_$requestId',
    userId: 'user_1',
    level: level,
    dateKey: '2026-07-07',
    occurredAt: DateTime.utc(2026, 7, 7, 12),
    clientRequestId: requestId,
    label: label,
    note: note,
    entryMethod: entryMethod,
  );
}

class _FakeUserRepository extends UserRepository {
  String? loadedUid;

  @override
  Future<UserModel?> fetchUserProfile(String uid) async {
    loadedUid = uid;
    return _user(id: uid).copyWith(dayStreak: 1, longestStreak: 1);
  }
}

class _FakeReportRepository extends ReportRepository {
  String? generatedForUserId;

  @override
  Future<String> generateWeeklyReport(String userId, {DateTime? now}) async {
    generatedForUserId = userId;
    return 'report_1';
  }

  @override
  Future<ReportModel?> fetchLatestReport(String userId) async {
    return null;
  }
}
