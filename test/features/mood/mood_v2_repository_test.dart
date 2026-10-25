import 'package:flutter_test/flutter_test.dart';

import 'package:mind_mates/features/mood/config/mood_v2_feature_flag.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_compatibility.dart';
import 'package:mind_mates/repositories/mood_v2_repository.dart';

void main() {
  const verifyWriterOnlyPilot = bool.fromEnvironment(
    'VERIFY_MOOD_V2_WRITER_ONLY_PILOT',
    defaultValue: false,
  );

  test(
    'Mood V2 repository is inert until its rollout flag is explicitly enabled',
    () async {
      if (verifyWriterOnlyPilot) return;
      final repository = MoodV2Repository();

      expect(MoodV2FeatureFlag.enabled, isFalse);
      await expectLater(
        repository.create(
          level: 3,
          clientRequestId: '00000000-0000-4000-8000-000000000001',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await repository.fetchHistory('another-user'), isEmpty);
    },
  );

  test('all eight Mood V2 rollout flags default to disabled independently', () {
    if (verifyWriterOnlyPilot) return;
    expect([
      MoodV2FeatureFlag.enabled,
      MoodV2FeatureFlag.providerRead,
      MoodV2FeatureFlag.homeRead,
      MoodV2FeatureFlag.profileRead,
      MoodV2FeatureFlag.historyRead,
      MoodV2FeatureFlag.insightsRead,
      MoodV2ReadCompatibilityFlag.reportsEnabled,
      MoodV2ReadCompatibilityFlag.mindAidEnabled,
    ], everyElement(isFalse));
  });

  test('writer-only pilot does not enable any Mood V2 reader', () {
    if (!verifyWriterOnlyPilot) return;
    expect(MoodV2FeatureFlag.enabled, isTrue);
    expect([
      MoodV2FeatureFlag.providerRead,
      MoodV2FeatureFlag.homeRead,
      MoodV2FeatureFlag.profileRead,
      MoodV2FeatureFlag.historyRead,
      MoodV2FeatureFlag.insightsRead,
      MoodV2ReadCompatibilityFlag.reportsEnabled,
      MoodV2ReadCompatibilityFlag.mindAidEnabled,
    ], everyElement(isFalse));
  });
}
