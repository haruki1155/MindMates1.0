import 'app_environment.dart';

class AndroidFirebaseIdentity {
  const AndroidFirebaseIdentity._();

  static String get packageName =>
      AppEnvironmentConfig.expectedAndroidPackageName;
  static String get firebaseAppId => switch (AppEnvironmentConfig.current) {
    AppEnvironment.development =>
      '1:1004916101316:android:e4c840c1c3070222c73991',
    AppEnvironment.staging => '1:978195258114:android:36354078e3d99999f5801b',
    AppEnvironment.production =>
      '1:842251480963:android:4c05d169dbacf125eb50b6',
  };
  static String get firebaseProjectId => AppEnvironmentConfig.expectedProjectId;
}
