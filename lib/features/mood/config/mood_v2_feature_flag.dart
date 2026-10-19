class MoodV2FeatureFlag {
  const MoodV2FeatureFlag._();

  /// Persistence remains disabled until the reader/UI rollout is approved.
  static const enabled = bool.fromEnvironment(
    'ENABLE_MOOD_V2',
    defaultValue: false,
  );

  /// Each student-facing reader is separately gated. None of these flags
  /// enable V2 persistence or alter the legacy daily check-in policy.
  static const providerRead = bool.fromEnvironment(
    'ENABLE_MOOD_V2_PROVIDER_READ',
    defaultValue: false,
  );
  static const homeRead = bool.fromEnvironment(
    'ENABLE_MOOD_V2_HOME_READ',
    defaultValue: false,
  );
  static const profileRead = bool.fromEnvironment(
    'ENABLE_MOOD_V2_PROFILE_READ',
    defaultValue: false,
  );
  static const historyRead = bool.fromEnvironment(
    'ENABLE_MOOD_V2_HISTORY_READ',
    defaultValue: false,
  );
  static const insightsRead = bool.fromEnvironment(
    'ENABLE_MOOD_V2_INSIGHTS_READ',
    defaultValue: false,
  );
}
