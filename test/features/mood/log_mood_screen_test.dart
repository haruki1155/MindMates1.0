import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mood/expression_check_in/expression_check_in_screen.dart';
import 'package:mind_mates/features/mood/expression_check_in/expression_scan_logic.dart';
import 'package:mind_mates/features/mood/screens/log_mood_screen.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/report_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/providers/insights_provider.dart';
import 'package:mind_mates/repositories/insights_repository.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/mood_repository.dart';
import 'package:mind_mates/repositories/mood_v2_repository.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_analytics.dart';
import 'package:mind_mates/features/mood/config/mood_v2_feature_flag.dart';
import 'package:mind_mates/repositories/report_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'landscape reflection and yellow expression action fit with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: const LogMoodScreen(
            moodV2Presentation: true,
            moodV2WriterEnabled: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Okay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Okay'));
      await tester.pumpAndSettle();
      expect(find.text('Skip').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check expression with camera'));
      await tester.pumpAndSettle();
      final action = find.widgetWithText(
        FilledButton,
        'Check expression with camera',
      );
      expect(action, findsOneWidget);
      expect(
        tester.widget<FilledButton>(action).style!.backgroundColor!.resolve({}),
        const Color(0xFFFFC414),
      );
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reflection offers Skip and Add note once per unsaved entry', (
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
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Keep my draft');
    await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
    await tester.pumpAndSettle();
    expect(find.text('Why do you feel this way?'), findsOneWidget);
    expect(writer.levels, isEmpty);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep my draft',
    );
    await tester.tap(find.byKey(const ValueKey('mood-card-Great')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();
    expect(writer.levels, [5]);
    await tester.tap(find.text('Log another mood'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    expect(writer.levels, [5]);
  });
  testWidgets('v2 compact picker has summary and full width Excited row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('How are you feeling right now?'), findsOneWidget);
    expect(find.text('Recorded mood summary'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('mood-card-Excited'))).width,
      358,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mood-card-Great'))).height,
      lessThan(120),
    );
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
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets(
      'v2 picker, keyboard and reduced motion at $width and 1.8 text',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.8),
                disableAnimations: true,
                viewInsets: const EdgeInsets.only(bottom: 240),
              ),
              child: child!,
            ),
            home: const LogMoodScreen(
              moodV2Presentation: true,
              moodV2WriterEnabled: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Save mood entry').hitTestable(), findsOneWidget);
        for (final label in [
          'Great',
          'Okay',
          'Stressed',
          'Sad',
          'Angry',
          'Tired',
          'Excited',
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await _skipReflection(tester);
          await tester.pumpAndSettle();
        }
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Save mood entry'),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('all seven V2 selections preserve exact writer value mapping', (
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
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'Great',
      'Okay',
      'Stressed',
      'Sad',
      'Angry',
      'Tired',
      'Excited',
    ]) {
      await tester.tap(find.text(label));
      await _skipReflection(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();
      expect(find.text('Your mood is recorded'), findsOneWidget);
      expect(find.textContaining('Manila time'), findsOneWidget);
      expect(find.text('Recorded mood summary'), findsNothing);
      await tester.tap(find.text('Log another mood'));
      await tester.pumpAndSettle();
    }
    expect(writer.levels, [5, 4, 2, 1, 1, 3, 5]);
    expect(writer.requestIds.toSet(), hasLength(7));
  });
  if (MoodV2FeatureFlag.historyRead) {
    for (final count in [0, 4]) {
      testWidgets(
        'v2 summary shows own $count check-ins and distinct mood streak',
        (tester) async {
          final now = DateTime.utc(2026, 7, 7, 12);
          final history = MoodHistoryWindow(
            coverage: MoodHistoryCoverage.complete,
            events: [
              for (var i = 0; i < count; i++)
                NormalizedMoodEvent(
                  id: 'entry-$i',
                  userId: 'user_1',
                  level: 5,
                  dateKey: '2026-07-07',
                  occurredAt: now,
                  source: MoodEventSource.v2,
                  label: 'Great',
                ),
            ],
          );
          await tester.pumpWidget(
            _logMoodApp(
              moodProvider: _RecordingMoodProvider(history: history),
              userProvider: UserProvider(_FakeUserRepository())
                ..setUser(_user(id: 'user_1')),
              moodV2Presentation: true,
              moodV2WriterEnabled: true,
              nowProvider: () => now,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('$count check-ins today'), findsOneWidget);
          expect(
            find.text(
              count == 0 ? 'Mood streak · 0 days' : 'Mood streak · 1 day',
            ),
            findsOneWidget,
          );
          expect(find.text('Recorded mood summary'), findsNothing);
        },
      );
    }
  }
  if (MoodV2FeatureFlag.historyRead) {
    testWidgets('legacy save refreshes combined history when readers enabled', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final mood = _RecordingMoodProvider();
      await tester.pumpWidget(
        _logMoodApp(
          moodProvider: mood,
          userProvider: UserProvider(_FakeUserRepository())
            ..setUser(_user(id: 'user_1')),
        ),
      );
      await tester.pumpAndSettle();
      mood.refreshedUsers.clear();
      await tester.tap(find.text('Great'));
      await _skipReflection(tester);
      await tester.pump();
      await tester.tap(find.text('Save mood check-in'));
      await tester.pumpAndSettle();
      expect(mood.refreshedUsers, ['user_1']);
      expect(find.text("Today's check-in is complete"), findsOneWidget);
    });
  }
  for (final width in [320.0, 360.0]) {
    testWidgets('V2 confirmation scrolls without overflow at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _logMoodApp(
          moodProvider: MoodProvider(_FakeMoodRepository()),
          userProvider: UserProvider(_FakeUserRepository())
            ..setUser(_user(id: 'user_1')),
          moodV2Presentation: true,
          moodV2WriterEnabled: true,
          moodV2Writer: _FakeMoodV2Writer(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Great'));
      await tester.tap(find.text('Great'));
      await _skipReflection(tester);
      await tester.pump();
      await tester.ensureVisible(find.text('Save mood entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Log another mood'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mood-v2-confirmation')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'dependent history failure cannot turn a confirmed write into a retry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final mood = _RecordingMoodProvider();
      final insights = _RecordingInsightsProvider();
      final writer = _FakeMoodV2Writer();
      await tester.pumpWidget(
        _logMoodApp(
          moodProvider: mood,
          userProvider: UserProvider(_FakeUserRepository())
            ..setUser(_user(id: 'user_1')),
          insightsProvider: insights,
          moodV2Presentation: true,
          moodV2WriterEnabled: true,
          moodV2Writer: writer,
        ),
      );
      await tester.pumpAndSettle();
      mood.refreshedUsers.clear();
      mood.throwOnRefresh = true;
      await tester.tap(find.text('Great'));
      await _skipReflection(tester);
      await tester.pump();
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();
      expect(find.text('Your mood is recorded'), findsOneWidget);
      expect(
        find.text('Unable to save this mood entry. Try again.'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mood-v2-confirmation')),
        findsOneWidget,
      );
      if (MoodV2FeatureFlag.historyRead) {
        mood.throwOnRefresh = false;
        await tester.ensureVisible(find.text('Retry history'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Retry history'));
        await tester.pumpAndSettle();
      }
      expect(writer.requestIds, hasLength(1));
      expect(insights.invalidatedUsers, ['user_1']);
    },
  );
  testWidgets('confirmed V2 save refreshes owner history and inSIGHT once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mood = _RecordingMoodProvider();
    final insights = _RecordingInsightsProvider();
    final writer = _FakeMoodV2Writer();
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: mood,
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        insightsProvider: insights,
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();
    mood.refreshedUsers.clear();
    await tester.tap(find.text('Great'));
    await _skipReflection(tester);
    await tester.pump();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();
    expect(mood.refreshedUsers, ['user_1']);
    expect(insights.invalidatedUsers, ['user_1']);
    expect(insights.refreshedUsers, ['user_1']);
    expect(writer.levels, [5]);
  });
  for (final failing in [false, true]) {
    testWidgets('confirmed V2 save records one mood check-in for the streak '
        '(streak sync ${failing ? 'fails' : 'succeeds'})', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final users = _FakeUserRepository(throwOnRecordActivity: failing);
      final writer = _FakeMoodV2Writer();
      await tester.pumpWidget(
        _logMoodApp(
          moodProvider: _RecordingMoodProvider(),
          userProvider: UserProvider(users)..setUser(_user(id: 'user_1')),
          insightsProvider: _RecordingInsightsProvider(),
          moodV2Presentation: true,
          moodV2WriterEnabled: true,
          moodV2Writer: writer,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Great'));
      await _skipReflection(tester);
      await tester.pump();
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();

      expect(writer.levels, [5]);
      expect(users.recordedActivities, [
        ('user_1', UserActivityType.moodCheckIn),
      ]);
      expect(
        find.text('Unable to save this mood entry. Try again.'),
        findsNothing,
      );
    });
  }

  testWidgets('renders all mood choices and note field', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: LogMoodScreen(
          moodV2Presentation: false,
          moodV2WriterEnabled: false,
        ),
      ),
    );

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

    await tester.pumpWidget(
      const MaterialApp(
        home: LogMoodScreen(
          moodV2Presentation: false,
          moodV2WriterEnabled: false,
        ),
      ),
    );

    final angryCard = find.byKey(const ValueKey('mood-card-Angry'));
    expect(_cardBorderWidth(tester, angryCard), 1.2);

    await tester.tap(find.text('Angry'));
    await _skipReflection(tester);
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
          moodV2Presentation: false,
          moodV2WriterEnabled: false,
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
    await _skipReflection(tester);
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
    await _skipReflection(tester);
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

    await tester.pumpWidget(
      const MaterialApp(
        home: LogMoodScreen(
          moodV2Presentation: false,
          moodV2WriterEnabled: false,
        ),
      ),
    );

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
    await _skipReflection(tester);
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
    expect(find.text('1-day mood streak'), findsOneWidget);
    expect(find.text('1-day activity streak'), findsNothing);
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
    await _skipReflection(tester);
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
    await _skipReflection(tester);
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
    await _skipReflection(tester);
    await tester.pump();
    await tester.tap(find.text('Save mood check-in'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mood-v2-add-entry')), findsNothing);
    expect(find.text("Today's check-in is complete"), findsOneWidget);
  });

  testWidgets('V2 form ignores a failed legacy today read', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final writer = _FakeMoodV2Writer();
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository(throwsOnToday: true)),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Great'), findsOneWidget);
    expect(find.text('Save mood entry'), findsOneWidget);
  });

  testWidgets('V2 form ignores a saved legacy daily mood', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final legacy = _FakeMoodRepository(hasToday: true);
    final writer = _FakeMoodV2Writer();
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(legacy),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Great'));
    await _skipReflection(tester);
    await tester.pump();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();
    expect(writer.levels, [5]);
    expect(legacy.createdUserId, isNull);
    expect(find.byKey(const ValueKey('mood-v2-confirmation')), findsOneWidget);
    expect(find.textContaining('check in again tomorrow'), findsNothing);
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
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Great'));
    await _skipReflection(tester);
    await tester.pump();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mood-v2-confirmation')), findsOneWidget);
    await tester.tap(find.text('Log another mood'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sad'));
    await _skipReflection(tester);
    await tester.pump();
    await tester.tap(find.text('Save mood entry'));
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

  testWidgets('enabled V2 writer supports every app-user population role', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final role in PopulationRole.values) {
      final writer = _FakeMoodV2Writer();
      await tester.pumpWidget(
        _logMoodApp(
          moodProvider: MoodProvider(_FakeMoodRepository()),
          userProvider: UserProvider(_FakeUserRepository())
            ..setUser(_user(id: 'user_${role.name}', populationRole: role)),
          moodV2Presentation: true,
          moodV2WriterEnabled: true,
          moodV2Writer: writer,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Okay'));
      await _skipReflection(tester);
      await tester.pump();
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();

      expect(writer.levels, [4], reason: '${role.label} can save a mood');
    }
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
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
        moodV2RequestIdGenerator: () => '00000000-0000-4000-8000-000000000001',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Okay'));
    await _skipReflection(tester);
    await tester.pump();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mood-v2-save-error')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Edited after failure');
    await tester.tap(find.text('Great'));
    await _skipReflection(tester);
    await tester.pump();
    await tester.tap(find.text('Save mood entry'));
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
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tired'));
    await _skipReflection(tester);
    await tester.pump();
    await tester.tap(find.text('Save mood entry'));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(writer.requestIds, hasLength(1));

    writer.completePending();
    await tester.pumpAndSettle();
  });

  testWidgets('account change clears confirmed V2 entry and draft', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final user = UserProvider(_FakeUserRepository())
      ..setUser(_user(id: 'user_1'));
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: user,
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: _FakeMoodV2Writer(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Great'));
    await _skipReflection(tester);
    await tester.pump();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mood-v2-confirmation')), findsOneWidget);
    user.setUser(_user(id: 'user_2'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mood-v2-confirmation')), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('V2 pending completion is ignored after an account change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final writer = _FakeMoodV2Writer(pending: true);
    final insights = _RecordingInsightsProvider();
    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(_user(id: 'user_1'));
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: userProvider,
        insightsProvider: insights,
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tired'));
    await _skipReflection(tester);
    await tester.pump();
    await tester.tap(find.text('Save mood entry'));
    await tester.pump();
    expect(writer.requestIds, hasLength(1));

    userProvider.setUser(_user(id: 'user_2'));
    await tester.pumpAndSettle();
    writer.completePending();
    await tester.pumpAndSettle();

    expect(find.text('Mood entry saved.'), findsNothing);
    expect(insights.invalidatedUsers, isEmpty);
    expect(insights.refreshedUsers, isEmpty);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('legacy midnight retains its daily draft reset', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var now = DateTime.utc(2026, 7, 7, 15, 59, 55);
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        nowProvider: () => now,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Okay'));
    await _skipReflection(tester);
    await tester.enterText(find.byType(TextField), 'Legacy daily draft');
    now = DateTime.utc(2026, 7, 7, 16, 0, 2);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('V2 midnight preserves an unsaved draft for its first save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var now = DateTime.utc(2026, 7, 7, 15, 59, 55);
    final writer = _FakeMoodV2Writer();
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        nowProvider: () => now,
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Okay'));
    await _skipReflection(tester);
    await tester.enterText(find.byType(TextField), 'Unsaved synthetic draft');
    now = DateTime.utc(2026, 7, 7, 16, 0, 2);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Unsaved synthetic draft',
    );
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();
    expect(writer.notes, ['Unsaved synthetic draft']);
    expect(writer.levels, [4]);
  });

  testWidgets(
    'V2 midnight preserves uncertain UUID and payload through rebuild and refresh failure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var now = DateTime.utc(2026, 7, 7, 15, 59, 55);
      var sequence = 0;
      final writer = _FakeMoodV2Writer(failuresRemaining: 1);
      final mood = _RecordingMoodProvider();
      final user = UserProvider(_FakeUserRepository())
        ..setUser(_user(id: 'user_1'));
      Widget app() => _logMoodApp(
        moodProvider: mood,
        userProvider: user,
        nowProvider: () => now,
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
        moodV2RequestIdGenerator: () =>
            '00000000-0000-4000-8000-${(++sequence).toString().padLeft(12, '0')}',
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Okay'));
      await _skipReflection(tester);
      await tester.enterText(
        find.byType(TextField),
        'Original synthetic payload',
      );
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();
      expect(writer.requestIds, hasLength(1));
      await tester.tap(find.text('Great'));
      await _skipReflection(tester);
      await tester.enterText(find.byType(TextField), 'Edited unsaved input');
      now = DateTime.utc(2026, 7, 7, 16, 0, 2);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      mood.throwOnRefresh = true;
      // A failed post-save refresh must not turn the retry into another write.
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();
      expect(writer.requestIds, hasLength(2));
      expect(writer.requestIds[1], writer.requestIds[0]);
      expect(writer.notes, [
        'Original synthetic payload',
        'Original synthetic payload',
      ]);
      expect(writer.levels, [4, 4]);
      expect(writer.payloads[1], writer.payloads[0]);
      expect(
        find.byKey(const ValueKey('mood-v2-confirmation')),
        findsOneWidget,
      );
      await tester.tap(find.text('Log another mood'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Great'));
      await _skipReflection(tester);
      await tester.enterText(find.byType(TextField), 'Intentional new entry');
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();
      expect(writer.requestIds, hasLength(3));
      expect(writer.requestIds.last, isNot(writer.requestIds.first));
      expect(writer.notes.last, 'Intentional new entry');
    },
  );

  testWidgets(
    'V2 midnight keeps a pending save locked and accepts its late success',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var now = DateTime.utc(2026, 7, 7, 15, 59, 55);
      final writer = _FakeMoodV2Writer(pending: true);
      await tester.pumpWidget(
        _logMoodApp(
          moodProvider: MoodProvider(_FakeMoodRepository()),
          userProvider: UserProvider(_FakeUserRepository())
            ..setUser(_user(id: 'user_1')),
          nowProvider: () => now,
          moodV2Presentation: true,
          moodV2WriterEnabled: true,
          moodV2Writer: writer,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Okay'));
      await _skipReflection(tester);
      await tester.pump();
      await tester.tap(find.text('Save mood entry'));
      await tester.pump();
      now = DateTime.utc(2026, 7, 7, 16, 0, 2);
      await tester.pump(const Duration(seconds: 7));
      expect(writer.requestIds, hasLength(1));
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      writer.completePending();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mood-v2-confirmation')),
        findsOneWidget,
      );
      // Another calendar change must not discard the confirmed result either.
      now = DateTime.utc(2026, 7, 8, 16, 0, 2);
      await tester.pump(const Duration(days: 1));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mood-v2-confirmation')),
        findsOneWidget,
      );
    },
  );

  testWidgets('V2 midnight retry state is discarded on account change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var now = DateTime.utc(2026, 7, 7, 15, 59, 55);
    var sequence = 0;
    final writer = _FakeMoodV2Writer(failuresRemaining: 1);
    final user = UserProvider(_FakeUserRepository())
      ..setUser(_user(id: 'user_1'));
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: user,
        nowProvider: () => now,
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
        moodV2RequestIdGenerator: () =>
            '00000000-0000-4000-8000-${(++sequence).toString().padLeft(12, '0')}',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Okay'));
    await _skipReflection(tester);
    await tester.enterText(
      find.byType(TextField),
      'Account one synthetic draft',
    );
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();
    now = DateTime.utc(2026, 7, 7, 16, 0, 2);
    await tester.pump(const Duration(seconds: 7));
    user.setUser(_user(id: 'user_2'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.byKey(const ValueKey('mood-v2-save-error')), findsNothing);
    writer.responseUserId = 'user_2';
    await tester.tap(find.text('Great'));
    await _skipReflection(tester);
    await tester.pump();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();
    expect(writer.requestIds, hasLength(2));
    expect(writer.requestIds.last, isNot(writer.requestIds.first));
    expect(writer.notes.last, isEmpty);
    expect(writer.levels.last, 5);
  });

  // --- Task 2: presentation separated from the protected writer ---------------
  //
  // Every test below runs in the staging default shape: presentation ON,
  // protected writer OFF. Saving must go through the legacy writer.

  testWidgets(
    'presentation on and writer off: the V2 form saves through the legacy writer',
    (tester) async {
      final repository = _FakeMoodRepository();
      final moodProvider = MoodProvider(repository);
      final writer = _FakeMoodV2Writer();
      await tester.pumpWidget(
        _logMoodApp(
          moodProvider: moodProvider,
          userProvider: UserProvider(_FakeUserRepository())
            ..setUser(_user(id: 'user_1')),
          moodV2Presentation: true,
          moodV2WriterEnabled: false,
          moodV2Writer: writer,
          nowProvider: () => DateTime(2026, 7, 7, 12),
        ),
      );
      await tester.pumpAndSettle();

      // The V2 presentation is what renders.
      expect(find.text('How are you feeling right now?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();

      // The legacy writer received it; the protected V2 writer was never called.
      expect(repository.createdLevel, isNotNull);
      expect(repository.createdLabel, 'Okay');
      expect(writer.levels, isEmpty);
      expect(writer.requestIds, isEmpty);
    },
  );

  testWidgets(
    'presentation on and writer off: a failed legacy save surfaces and retries',
    (tester) async {
      final repository = _FakeMoodRepository(throwsOnCreate: true);
      final moodProvider = MoodProvider(repository);
      await tester.pumpWidget(
        _logMoodApp(
          moodProvider: moodProvider,
          userProvider: UserProvider(_FakeUserRepository())
            ..setUser(_user(id: 'user_1')),
          moodV2Presentation: true,
          moodV2WriterEnabled: false,
          nowProvider: () => DateTime(2026, 7, 7, 12),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();

      expect(find.text('Unable to save mood.'), findsOneWidget);
      // The save bar is reachable again for a retry.
      expect(find.text('Save mood entry'), findsOneWidget);
    },
  );

  testWidgets(
    'presentation on and writer off: no second daily entry is offered',
    (tester) async {
      final repository = _FakeMoodRepository();
      final moodProvider = MoodProvider(repository);
      await tester.pumpWidget(
        _logMoodApp(
          moodProvider: moodProvider,
          userProvider: UserProvider(_FakeUserRepository())
            ..setUser(_user(id: 'user_1')),
          moodV2Presentation: true,
          moodV2WriterEnabled: false,
          nowProvider: () => DateTime(2026, 7, 7, 12),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save mood entry'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mood-v2-add-entry')), findsNothing);
      expect(find.text('Log another mood entry'), findsNothing);
    },
  );

  testWidgets(
    'presentation on and writer off: the day rolling over clears today',
    (tester) async {
      final repository = _FakeMoodRepository(hasToday: true);
      final moodProvider = MoodProvider(repository);
      var now = DateTime(2026, 7, 7, 23, 59, 30);
      await tester.pumpWidget(
        _logMoodApp(
          moodProvider: moodProvider,
          userProvider: UserProvider(_FakeUserRepository())
            ..setUser(_user(id: 'user_1')),
          moodV2Presentation: true,
          moodV2WriterEnabled: false,
          nowProvider: () => now,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('already logged'), findsOneWidget);

      now = DateTime(2026, 7, 8, 0, 0, 2);
      repository.hasToday = false;
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();

      // A fresh day offers the form again, not yesterday's entry.
      expect(find.textContaining('already logged'), findsNothing);
      expect(find.text('How are you feeling right now?'), findsOneWidget);
    },
  );

  testWidgets('presentation off renders the legacy layout unchanged', (
    tester,
  ) async {
    final repository = _FakeMoodRepository();
    final moodProvider = MoodProvider(repository);
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: moodProvider,
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Presentation: false,
        moodV2WriterEnabled: false,
        nowProvider: () => DateTime(2026, 7, 7, 12),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How are you feeling right now?'), findsNothing);
    expect(
      find.widgetWithText(ElevatedButton, 'Save mood check-in'),
      findsOneWidget,
    );
  });

  testWidgets('writer on still routes the save to the protected V2 writer', (
    tester,
  ) async {
    final repository = _FakeMoodRepository();
    final moodProvider = MoodProvider(repository);
    final writer = _FakeMoodV2Writer();
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: moodProvider,
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
        nowProvider: () => DateTime(2026, 7, 7, 12),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();

    expect(writer.levels, isNotEmpty);
    expect(repository.createdLevel, isNull);
  });

  // --- Task 3: source-neutral confirmation ------------------------------------

  testWidgets(
    'already logged today: the legacy entry renders in the V2 confirmation',
    (tester) async {
      final repository = _FakeMoodRepository(hasToday: true);
      final moodProvider = MoodProvider(repository);
      await tester.pumpWidget(
        _logMoodApp(
          moodProvider: moodProvider,
          userProvider: UserProvider(_FakeUserRepository())
            ..setUser(_user(id: 'user_1')),
          moodV2Presentation: true,
          moodV2WriterEnabled: false,
          nowProvider: () => DateTime(2026, 7, 7, 12),
        ),
      );
      await tester.pumpAndSettle();

      // The V2 confirmation, not a blank form and not the legacy V1 card.
      expect(
        find.byKey(const ValueKey('mood-v2-confirmation')),
        findsOneWidget,
      );
      expect(find.text('Your mood is recorded'), findsOneWidget);
      expect(find.textContaining('already logged'), findsOneWidget);
      expect(find.text('How are you feeling right now?'), findsNothing);
      // No second daily entry is offered.
      expect(find.text('Log another mood'), findsNothing);
      expect(find.byKey(const ValueKey('mood-v2-add-entry')), findsNothing);
    },
  );

  testWidgets('a legacy save lands in the V2 confirmation', (tester) async {
    final repository = _FakeMoodRepository();
    final moodProvider = MoodProvider(repository);
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: moodProvider,
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Presentation: true,
        moodV2WriterEnabled: false,
        nowProvider: () => DateTime(2026, 7, 7, 12),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mood-v2-confirmation')), findsOneWidget);
    expect(find.text('Log another mood'), findsNothing);
  });

  testWidgets('a legacy save never records a V2 event in the provider', (
    tester,
  ) async {
    final repository = _FakeMoodRepository();
    final moodProvider = _RecordingConfirmProvider(repository);
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: moodProvider,
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Presentation: true,
        moodV2WriterEnabled: false,
        nowProvider: () => DateTime(2026, 7, 7, 12),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();

    expect(repository.createdLabel, 'Okay');
    expect(
      moodProvider.recordedV2Entries,
      isEmpty,
      reason: 'a legacy save must not inject a v2-source event',
    );
  });

  testWidgets('a legacy save refreshes today and the recent history', (
    tester,
  ) async {
    final repository = _FakeMoodRepository();
    final moodProvider = MoodProvider(repository);
    final insights = _RecordingInsightsProvider();
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: moodProvider,
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        insightsProvider: insights,
        moodV2Presentation: true,
        moodV2WriterEnabled: false,
        nowProvider: () => DateTime(2026, 7, 7, 12),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();

    expect(moodProvider.todayMood, isNotNull);
    expect(repository.fetchedUserId, 'user_1');
    expect(insights.refreshedUsers, contains('user_1'));
  });

  testWidgets('switching account clears the previous confirmation', (
    tester,
  ) async {
    final repository = _FakeMoodRepository(hasToday: true);
    final moodProvider = MoodProvider(repository);
    final userProvider = UserProvider(_FakeUserRepository())
      ..setUser(_user(id: 'user_1'));
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: moodProvider,
        userProvider: userProvider,
        moodV2Presentation: true,
        moodV2WriterEnabled: false,
        nowProvider: () => DateTime(2026, 7, 7, 12),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mood-v2-confirmation')), findsOneWidget);

    repository.hasToday = false;
    userProvider.setUser(_user(id: 'user_2'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mood-v2-confirmation')), findsNothing);
    expect(find.textContaining('already logged'), findsNothing);
    expect(find.text('How are you feeling right now?'), findsOneWidget);
  });

  testWidgets('writer on renders the confirmation from the real V2 event', (
    tester,
  ) async {
    final writer = _FakeMoodV2Writer();
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(_FakeMoodRepository()),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Presentation: true,
        moodV2WriterEnabled: true,
        moodV2Writer: writer,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mood-v2-confirmation')), findsOneWidget);
    // The writer path keeps its multi-entry affordance.
    expect(find.text('Log another mood'), findsOneWidget);
  });

  // --- Review follow-ups ------------------------------------------------------

  testWidgets('a blank legacy label falls back to the level label', (
    tester,
  ) async {
    final repository = _FakeMoodRepository(hasToday: true, todayLabel: '');
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(repository),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Presentation: true,
        moodV2WriterEnabled: false,
        nowProvider: () => DateTime(2026, 7, 7, 12),
      ),
    );
    await tester.pumpAndSettle();

    // Level 4 is unambiguously 'Okay', so the pill is never blank.
    expect(find.byKey(const ValueKey('mood-v2-confirmation')), findsOneWidget);
    expect(find.text('Okay'), findsOneWidget);
  });

  testWidgets('the save bar is disabled when a reload hides the form', (
    tester,
  ) async {
    // The reviewer's scenario: pick a mood, background the app, and resume
    // into a failed reload. The retry card replaces the form, so Save must
    // not stay tappable.
    final repository = _FakeMoodRepository();
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(repository),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Presentation: true,
        moodV2WriterEnabled: false,
        nowProvider: () => DateTime(2026, 7, 7, 12),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save mood entry'),
          )
          .onPressed,
      isNotNull,
      reason: 'a selected mood is normally saveable',
    );

    repository.throwsOnToday = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Save mood entry'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save mood entry'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('the legacy save scrolls the confirmation into view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeMoodRepository();
    await tester.pumpWidget(
      _logMoodApp(
        moodProvider: MoodProvider(repository),
        userProvider: UserProvider(_FakeUserRepository())
          ..setUser(_user(id: 'user_1')),
        moodV2Presentation: true,
        moodV2WriterEnabled: false,
        nowProvider: () => DateTime(2026, 7, 7, 12),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mood-card-Okay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save mood entry'));
    await tester.pumpAndSettle();

    expect(find.text('Your mood is recorded'), findsOneWidget);
    final scrollable = tester.widget<Scrollable>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.controller?.offset ?? 0, 0);
  });
}

/// Records any attempt to push a confirmed V2 entry into combined history, so
/// a legacy save injecting a phantom v2-source event fails the test.
class _RecordingConfirmProvider extends MoodProvider {
  _RecordingConfirmProvider(super.repository);

  final List<MoodV2Event> recordedV2Entries = [];

  @override
  void recordConfirmedMoodV2Entry(MoodV2Event entry) {
    recordedV2Entries.add(entry);
    super.recordConfirmedMoodV2Entry(entry);
  }
}

Widget _logMoodApp({
  required MoodProvider moodProvider,
  UserProvider? userProvider,
  ReportProvider? reportProvider,
  InsightsProvider? insightsProvider,
  DateTime Function()? nowProvider,
  WidgetBuilder? expressionScreenBuilder,
  bool moodV2Presentation = false,
  bool moodV2WriterEnabled = false,
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
      if (insightsProvider != null)
        ChangeNotifierProvider<InsightsProvider>.value(value: insightsProvider),
    ],
    child: MaterialApp(
      home: LogMoodScreen(
        nowProvider: nowProvider,
        expressionScreenBuilder: expressionScreenBuilder,
        moodV2Presentation: moodV2Presentation,
        moodV2WriterEnabled: moodV2WriterEnabled,
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

UserModel _user({required String id, PopulationRole? populationRole}) {
  return UserModel(
    id: id,
    email: 'student@example.com',
    name: 'Student User',
    firstName: 'Student',
    lastName: 'User',
    schoolId: '2026-0001',
    department: 'CCS',
    course: 'BSIT',
    populationRole: populationRole,
  );
}

class _RecordingMoodProvider extends MoodProvider {
  _RecordingMoodProvider({this.history}) : super(_FakeMoodRepository());
  final MoodHistoryWindow? history;
  @override
  MoodHistoryWindow? get v2History => history ?? super.v2History;
  bool throwOnRefresh = false;
  @override
  String? get v2HistoryErrorMessage =>
      throwOnRefresh ? 'History offline' : null;
  final refreshedUsers = <String>[];
  @override
  bool get isMoodV2ReadEnabled => true;
  @override
  Future<void> loadMoodV2History(String userId, {DateTime? now}) async {
    refreshedUsers.add(userId);
    if (throwOnRefresh) throw StateError('offline');
  }
}

class _RecordingInsightsProvider extends InsightsProvider {
  _RecordingInsightsProvider() : super(InsightsRepository());
  final invalidatedUsers = <String>[];
  final refreshedUsers = <String>[];
  @override
  void invalidateForConfirmedMoodV2Write(String userId) {
    invalidatedUsers.add(userId);
  }

  @override
  Future<void> refreshLoadedContext(String userId) async {
    refreshedUsers.add(userId);
  }
}

class _FakeMoodRepository extends MoodRepository {
  _FakeMoodRepository({
    this.throwsOnCreate = false,
    this.throwsOnToday = false,
    this.hasToday = false,
    this.todayLabel = 'Okay',
  });

  final String? todayLabel;

  bool throwsOnToday;
  bool hasToday;

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
    if (throwsOnToday) throw StateError('today load failed');
    if (!hasToday) return null;
    return MoodModel(
      id: 'daily_${userId}_20260707',
      userId: userId,
      level: 4,
      label: todayLabel,
      note: 'already logged',
      createdAt: now ?? DateTime(2026, 7, 7, 9, 30),
    );
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
  final List<Map<String, Object?>> payloads = [];
  String responseUserId = 'user_1';
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
    payloads.add({
      'level': level,
      'label': label,
      'note': note,
      'entryMethod': entryMethod,
      'expressionAssistUsed': expressionAssistUsed,
      'expressionSuggestionAccepted': expressionSuggestionAccepted,
      'expressionModelVersion': expressionModelVersion,
    });
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
    userId: responseUserId,
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
  _FakeUserRepository({this.throwOnRecordActivity = false});

  final bool throwOnRecordActivity;
  String? loadedUid;
  final List<(String, UserActivityType)> recordedActivities = [];

  @override
  Future<UserModel?> recordActivity(
    String uid,
    UserActivityType type, {
    DateTime? occurredAt,
  }) async {
    recordedActivities.add((uid, type));
    if (throwOnRecordActivity) throw StateError('streak sync failed');
    return null;
  }

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

Future<void> _skipReflection(WidgetTester tester) async {
  await tester.pumpAndSettle();
  if (find.byType(AlertDialog).evaluate().isNotEmpty) {
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
  }
}
