import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/settings/models/reminder_preferences.dart';
import 'package:mind_mates/features/settings/screens/reminders_screen.dart';
import 'package:mind_mates/providers/reminder_preferences_provider.dart';
import 'package:mind_mates/repositories/reminder_preferences_repository.dart';
import 'package:mind_mates/services/firebase/firestore_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'appointment reminders default on and self-care reminders default off',
    (tester) async {
      final repository = _MemoryRepository(const ReminderPreferences());
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      expect(_switchValue(tester, 'appointment-24-hour-switch'), isTrue);
      expect(_switchValue(tester, 'appointment-1-hour-switch'), isTrue);
      expect(_switchValue(tester, 'mood-reminder-switch'), isFalse);
      expect(_switchValue(tester, 'breathing-reminder-switch'), isFalse);
      expect(
        find.textContaining('Philippine time (Asia/Manila)'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Mood reminder and selected time are saved independently', (
    tester,
  ) async {
    final repository = _MemoryRepository(const ReminderPreferences());
    var pickerCalled = false;
    await tester.pumpWidget(
      _app(
        repository,
        pickTime: (initial) async {
          pickerCalled = true;
          expect(initial, const TimeOfDay(hour: 20, minute: 0));
          return const TimeOfDay(hour: 21, minute: 15);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mood-reminder-switch')));
    await tester.pumpAndSettle();
    expect(repository.value.moodDailyEnabled, isTrue);
    expect(repository.value.breathingDailyEnabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('mood-reminder-time')));
    await tester.pumpAndSettle();

    expect(pickerCalled, isTrue);
    expect(repository.value.moodDailyTime, '21:15');
    expect(repository.value.breathingDailyTime, '21:00');
    expect(find.text('9:15 PM'), findsOneWidget);
  });

  testWidgets(
    'denied push permission explains inbox delivery and opens device settings',
    (tester) async {
      final repository = _MemoryRepository(const ReminderPreferences());
      var settingsOpened = false;
      await tester.pumpWidget(
        _app(
          repository,
          permissionGranted: false,
          openSettings: () async {
            settingsOpened = true;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('still appear in your MindMate inbox'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open device settings'));
      await tester.pumpAndSettle();
      expect(settingsOpened, isTrue);
    },
  );

  testWidgets('Mood shortcut initially focuses the Mood reminder section', (
    tester,
  ) async {
    final repository = _MemoryRepository(const ReminderPreferences());
    await tester.pumpWidget(_app(repository, focusMoodSection: true));
    await tester.pumpAndSettle();

    final sectionTop = tester.getTopLeft(
      find.byKey(const ValueKey('mood-reminders-section')),
    );
    expect(sectionTop.dy, lessThan(300));
  });

  testWidgets(
    'load failures show retry guidance and save failures stay visible',
    (tester) async {
      final loadFailure = _MemoryRepository(const ReminderPreferences())
        ..failLoad = true;
      await tester.pumpWidget(_app(loadFailure));
      await tester.pumpAndSettle();
      expect(find.text('Unable to load reminder settings.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      final saveFailure = _MemoryRepository(const ReminderPreferences())
        ..failSave = true;
      await tester.pumpWidget(_app(saveFailure));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('appointment-24-hour-switch')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to save reminders. Please try again.'),
        findsOneWidget,
      );
    },
  );
}

bool _switchValue(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(ValueKey(key))).value;

Widget _app(
  _MemoryRepository repository, {
  bool focusMoodSection = false,
  bool permissionGranted = true,
  Future<bool> Function()? openSettings,
  Future<TimeOfDay?> Function(TimeOfDay initialTime)? pickTime,
}) => ChangeNotifierProvider(
  create: (_) => ReminderPreferencesProvider(repository),
  child: MaterialApp(
    home: RemindersScreen(
      userId: 'user_1',
      focusMoodSection: focusMoodSection,
      notificationPermissionGranted: () async => permissionGranted,
      openDeviceSettings: openSettings ?? () async => true,
      pickTime: pickTime,
    ),
  ),
);

class _MemoryRepository extends ReminderPreferencesRepository {
  _MemoryRepository(this.value)
    : super(firestoreService: _NoopFirestoreService());

  ReminderPreferences value;
  bool failLoad = false;
  bool failSave = false;

  @override
  Future<ReminderPreferences> load(String userId) async {
    if (failLoad) throw StateError('load failed');
    return value;
  }

  @override
  Future<void> save(String userId, ReminderPreferences preferences) async {
    if (failSave) throw StateError('save failed');
    value = preferences;
  }
}

class _NoopFirestoreService extends FirestoreService {}
