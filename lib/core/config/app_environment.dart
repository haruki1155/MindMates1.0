import 'package:flutter/foundation.dart';

enum AppEnvironment { development, staging, production }

class AppEnvironmentConfig {
  const AppEnvironmentConfig._();

  static const _name = String.fromEnvironment(
    'APP_ENV',
    defaultValue: String.fromEnvironment(
      'FLUTTER_APP_FLAVOR',
      defaultValue: 'development',
    ),
  );

  static AppEnvironment get current => switch (_name) {
    'development' => AppEnvironment.development,
    'staging' => AppEnvironment.staging,
    'production' => AppEnvironment.production,
    _ => throw StateError(
      'APP_ENV must be development, staging, or production.',
    ),
  };

  static bool get isStaging => current == AppEnvironment.staging;
  static const functionsRegion = 'us-central1';

  static String get expectedProjectId => switch (current) {
    AppEnvironment.development => 'mindmate-dev-4e91c',
    AppEnvironment.staging => 'mindmate-staging',
    AppEnvironment.production => 'mind-mates-cd2cf',
  };

  static String get expectedAndroidPackageName => switch (current) {
    AppEnvironment.development => 'com.example.mind_mates',
    AppEnvironment.staging => 'com.example.mind_mates.staging',
    AppEnvironment.production => 'ph.edu.ucu.mindmates',
  };

  static void validateFirebaseIdentity({
    required String projectId,
    required String callableRegion,
    bool releaseBuild = kReleaseMode,
  }) {
    if (projectId != expectedProjectId) {
      throw StateError(
        'Firebase project $projectId does not match $_name (expected $expectedProjectId).',
      );
    }
    if (callableRegion != functionsRegion) {
      throw StateError(
        'Callable region $callableRegion does not match $functionsRegion.',
      );
    }
    if (releaseBuild && current == AppEnvironment.development) {
      throw StateError(
        'Release builds must use APP_ENV=staging or APP_ENV=production.',
      );
    }
  }
}
