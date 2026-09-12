import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

import 'core/config/app_environment.dart';
import 'firebase_options.dart';
import 'firebase_options_development.dart';
import 'firebase_options_staging.dart';

class MindMatesFirebaseOptions {
  const MindMatesFirebaseOptions._();

  static FirebaseOptions get currentPlatform =>
      switch (AppEnvironmentConfig.current) {
        AppEnvironment.development =>
          DevelopmentFirebaseOptions.currentPlatform,
        AppEnvironment.staging => StagingFirebaseOptions.currentPlatform,
        AppEnvironment.production => DefaultFirebaseOptions.currentPlatform,
      };
}
