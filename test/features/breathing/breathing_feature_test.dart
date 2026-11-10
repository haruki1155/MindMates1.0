import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/breathing/models/breathing_models.dart';
import 'package:mind_mates/features/breathing/screens/mindful_breathing_screen.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/breathing_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/breathing_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:provider/provider.dart';

void main() {
  group('BreathingPlan', () {
    test('contains all techniques in ascending duration order', () {
      final durations = BreathingPlan.techniques
          .map((technique) => technique.durationSeconds)
          .toList();

      expect(BreathingPlan.techniques, hasLength(10));
      expect(durations, [...durations]..sort());
      expect(BreathingPlan.techniques.first.title, 'Emergency Reset Breath');
      expect(BreathingPlan.techniques.last.title, 'Full Relaxation Routine');
    });

    test('generates phases for no-hold, box, 4-7-8, and routine sessions', () {
      final balanced = BreathingPlan.techniques.firstWhere(
        (technique) => technique.id == 'balanced_calm',
      );
      final box = BreathingPlan.techniques.firstWhere(
        (technique) => technique.id == 'box_breathing',
      );
      final fourSevenEight = BreathingPlan.techniques.firstWhere(
        (technique) => technique.id == 'four_seven_eight',
      );
      final routine = BreathingPlan.techniques.firstWhere(
        (technique) => technique.id == 'full_relaxation',
      );

      expect(BreathingPlan.phaseFor(balanced, 0).label, 'Inhale');
      expect(BreathingPlan.phaseFor(balanced, 4).label, 'Exhale');
      expect(BreathingPlan.phaseFor(box, 4).label, 'Hold');
      expect(BreathingPlan.phaseFor(fourSevenEight, 11).label, 'Exhale');
      expect(BreathingPlan.phaseFor(routine, 600).label, 'Box breathing');
      expect(BreathingPlan.phaseFor(box, 0).stepIndex, 0);
      expect(BreathingPlan.phaseFor(box, 3).remainingStepSeconds, 1);
      expect(BreathingPlan.phaseFor(box, 4).stepIndex, 1);
      expect(BreathingPlan.phaseFor(box, 8).stepIndex, 2);
      expect(BreathingPlan.phaseFor(box, 12).stepIndex, 3);
      expect(BreathingPlan.phaseFor(box, 16).stepIndex, 0);
    });

    test('matches researched breathing patterns to verifiable sources', () {
      final box = BreathingPlan.techniques.firstWhere(
        (technique) => technique.id == 'box_breathing',
      );
      final nhs = BreathingPlan.techniques.firstWhere(
        (technique) => technique.id == 'nhs_calm',
      );
      final balanced = BreathingPlan.techniques.firstWhere(
        (technique) => technique.id == 'balanced_calm',
      );
      expect(
        BreathingPlan.patternLabel(box),
        'Inhale 4s → Hold 4s → Exhale 4s → Hold 4s',
      );
      expect(
        BreathingPlan.evidenceFor(box).url,
        'https://doi.org/10.1016/j.xcrm.2022.100895',
      );
      expect(BreathingPlan.evidenceFor(nhs).url, contains('nhs.uk'));
      expect(
        BreathingPlan.evidenceFor(balanced).url,
        'https://doi.org/10.3389/fnhum.2018.00353',
      );
      expect(
        BreathingPlan.evidenceFor(box).limitations,
        contains('individualized'),
      );
    });
  });

  test('provider saves completed breathing sessions', () async {
    final repository = _FakeBreathingRepository();
    final provider = BreathingProvider(repository);
    final technique = BreathingPlan.techniques.first;
    final startedAt = DateTime(2026, 7, 3, 8);

    final saved = await provider.completeSession(
      userId: 'user_1',
      technique: technique,
      completedSeconds: technique.durationSeconds,
      startedAt: startedAt,
      completedAt: startedAt.add(Duration(seconds: technique.durationSeconds)),
    );

    expect(saved, isTrue);
    expect(repository.savedRecord?.userId, 'user_1');
    expect(repository.savedRecord?.technique.id, technique.id);
  });

  testWidgets('completion appears only after the timer reaches the end', (
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
          ChangeNotifierProvider(
            create: (_) => BreathingProvider(_FakeBreathingRepository()),
          ),
        ],
        child: const MaterialApp(home: MindfulBreathingScreen()),
      ),
    );

    expect(find.text('Your breathing pattern'), findsOneWidget);
    expect(find.text('Inhale 3s'), findsOneWidget);
    expect(find.text('Exhale 6s'), findsOneWidget);
    expect(find.text('Scientific basis & limitations'), findsOneWidget);

    await tester.tap(find.text('Start breathing'));
    await tester.pump();
    expect(find.text('Ready to begin?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Start breathing').last);
    await tester.pump();
    expect(find.text('Session complete'), findsNothing);

    // The updated breathing UI uses a fixed 5-minute session.
    await tester.pump(const Duration(seconds: 299));
    expect(find.text('Session complete'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Session complete'), findsOneWidget);
  });
}

class _FakeBreathingRepository extends BreathingRepository {
  BreathingSessionRecord? savedRecord;

  @override
  Future<String> completeSession(BreathingSessionRecord record) async {
    savedRecord = record;
    return 'session_1';
  }
}

class _FakeUserRepository extends UserRepository {}
