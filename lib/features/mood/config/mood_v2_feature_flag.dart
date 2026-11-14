import 'package:mind_mates/core/config/app_environment.dart';

class MoodV2FeatureFlag {
  const MoodV2FeatureFlag._();

  static String actionLabel({
    required bool hasCheckedInToday,
    bool writerEnabled = enabled,
  }) => writerEnabled
      ? 'Log a mood'
      : hasCheckedInToday
      ? 'View today’s mood'
      : 'Log your mood';

  /// Whether the Mood V2 *presentation* is shown: layout, styling, the mood
  /// cards, the notes and reflection interface, the saved-mood confirmation.
  ///
  /// Defaults to on in staging builds so the reviewed design appears without
  /// any `--dart-define` flags, and off in development and production. This
  /// flag never enables persistence — see [enabled].
  static const presentation = bool.fromEnvironment(
    'ENABLE_MOOD_V2_PRESENTATION',
    defaultValue: AppEnvironmentConfig.isStagingBuild,
  );

  /// Whether the **protected V2 writer** is used for saving.
  ///
  /// This controls persistence only and has no effect on presentation.
  ///
  /// On in staging builds, where the server now accepts `createMoodEntry` from
  /// any active account; off in development and production. Override with
  /// `--dart-define=ENABLE_MOOD_V2=false|true`. With this off, saving goes
  /// through the legacy writer.
  static const enabled = bool.fromEnvironment(
    'ENABLE_MOOD_V2',
    defaultValue: AppEnvironmentConfig.isStagingBuild,
  );

  /// Each student-facing reader is separately gated. None of these flags
  /// enable V2 persistence or alter the legacy daily check-in policy.
  ///
  /// They default to on in staging builds and off elsewhere. Reads are already
  /// permitted by `firestore.rules` for the owning account, so turning them on
  /// grants no new access; an account with no V2 entries simply reads nothing.
  static const providerRead = bool.fromEnvironment(
    'ENABLE_MOOD_V2_PROVIDER_READ',
    defaultValue: AppEnvironmentConfig.isStagingBuild,
  );
  static const homeRead = bool.fromEnvironment(
    'ENABLE_MOOD_V2_HOME_READ',
    defaultValue: AppEnvironmentConfig.isStagingBuild,
  );
  static const profileRead = bool.fromEnvironment(
    'ENABLE_MOOD_V2_PROFILE_READ',
    defaultValue: AppEnvironmentConfig.isStagingBuild,
  );
  static const historyRead = bool.fromEnvironment(
    'ENABLE_MOOD_V2_HISTORY_READ',
    defaultValue: AppEnvironmentConfig.isStagingBuild,
  );
  static const insightsRead = bool.fromEnvironment(
    'ENABLE_MOOD_V2_INSIGHTS_READ',
    defaultValue: AppEnvironmentConfig.isStagingBuild,
  );
}
