import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/config/app_environment.dart';
import 'package:mind_mates/features/mood/config/mood_v2_feature_flag.dart';

/// These are compile-time constants, so they cannot be varied at runtime.
/// This suite asserts the *relationships* between them, which hold in every
/// configuration; the two CI jobs (neutral and staging) exercise both states.
void main() {
  // The writer-only pilot verification build deliberately turns the protected
  // writer on. Assertions that the writer is off, and the label that follows
  // from it, do not apply in that shape.
  const verifyWriterOnlyPilot = bool.fromEnvironment(
    'VERIFY_MOOD_V2_WRITER_ONLY_PILOT',
    defaultValue: false,
  );

  test('isStagingBuild agrees with the resolved environment', () {
    expect(
      AppEnvironmentConfig.isStagingBuild,
      AppEnvironmentConfig.current == AppEnvironment.staging,
    );
  });

  test('presentation follows the staging build', () {
    expect(MoodV2FeatureFlag.presentation, AppEnvironmentConfig.isStagingBuild);
  });

  test('every reader follows the staging build', () {
    final readers = <String, bool>{
      'providerRead': MoodV2FeatureFlag.providerRead,
      'homeRead': MoodV2FeatureFlag.homeRead,
      'profileRead': MoodV2FeatureFlag.profileRead,
      'historyRead': MoodV2FeatureFlag.historyRead,
      'insightsRead': MoodV2FeatureFlag.insightsRead,
    };
    for (final entry in readers.entries) {
      expect(
        entry.value,
        AppEnvironmentConfig.isStagingBuild,
        reason: '${entry.key} must default to the staging build',
      );
    }
  });

  test('the protected writer is disabled in every environment', () {
    if (verifyWriterOnlyPilot) return;
    expect(MoodV2FeatureFlag.enabled, isFalse);
  });

  test('actionLabel still takes its default from the writer flag', () {
    if (verifyWriterOnlyPilot) return;
    expect(
      MoodV2FeatureFlag.actionLabel(hasCheckedInToday: true),
      'View today’s mood',
    );
    expect(
      MoodV2FeatureFlag.actionLabel(hasCheckedInToday: false),
      'Log your mood',
    );
    expect(
      MoodV2FeatureFlag.actionLabel(
        hasCheckedInToday: true,
        writerEnabled: true,
      ),
      'Log a mood',
    );
  });
}
