class MoodV2FeatureFlag {
  const MoodV2FeatureFlag._();

  /// Persistence remains disabled until the reader/UI rollout is approved.
  static const enabled = bool.fromEnvironment('ENABLE_MOOD_V2', defaultValue: false);
}
