import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/config/app_environment.dart';
import 'package:mind_mates/features/mood/config/mood_v2_feature_flag.dart';

/// These are compile-time constants, so they cannot be varied at runtime.
/// This suite asserts the *relationships* between them, which hold in every
/// configuration; the two CI jobs (neutral and staging) exercise both states.
void main() {
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

  test('the protected writer follows the staging build', () {
    expect(MoodV2FeatureFlag.enabled, AppEnvironmentConfig.isStagingBuild);
  });

  test('actionLabel still takes its default from the writer flag', () {
    expect(
      MoodV2FeatureFlag.actionLabel(hasCheckedInToday: true),
      MoodV2FeatureFlag.enabled ? 'Log a mood' : 'View today’s mood',
    );
    expect(
      MoodV2FeatureFlag.actionLabel(hasCheckedInToday: false),
      MoodV2FeatureFlag.enabled ? 'Log a mood' : 'Log your mood',
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
