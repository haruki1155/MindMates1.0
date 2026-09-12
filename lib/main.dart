import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:ui';

import 'app.dart';
import 'app_bootstrap.dart';
import 'core/config/app_environment.dart';
import 'firebase_options_selector.dart';
import 'providers/assessment_provider.dart';
import 'providers/appointment_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/breathing_provider.dart';
import 'providers/insights_provider.dart';
import 'providers/mental_health_activity_provider.dart';
import 'providers/mind_aid_provider.dart';
import 'providers/journal_provider.dart';
import 'providers/mood_provider.dart';
import 'providers/report_provider.dart';
import 'providers/secret_chat_provider.dart';
import 'providers/sleep_provider.dart';
import 'providers/user_provider.dart';
import 'repositories/assessment_repository.dart';
import 'repositories/appointment_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/breathing_repository.dart';
import 'repositories/insights_repository.dart';
import 'repositories/journal_repository.dart';
import 'repositories/mental_health_activity_repository.dart';
import 'repositories/mind_aid_repository_screen.dart';
import 'repositories/mood_repository.dart';
import 'repositories/report_repository.dart';
import 'repositories/secret_chat_repository.dart';
import 'repositories/sleep_repository.dart';
import 'repositories/user_repository.dart';
import 'services/auth/auth_service.dart';
import 'services/firebase/firebase_app_check_service.dart';
import 'services/firebase/firebase_runtime_diagnostics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _registerErrorHandlers();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFFFFFFFF),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    AppBootstrap(
      initializer: _initializeFirebaseRuntime,
      child: selectMindMateRoot(isWeb: kIsWeb, mobileApp: _mobileApp()),
    ),
  );
}

Widget _mobileApp() => MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) => AuthProvider(AuthRepository(AuthService())),
    ),
    ChangeNotifierProvider(create: (_) => UserProvider(UserRepository())),
    ChangeNotifierProvider(create: (_) => MoodProvider(MoodRepository())),
    ChangeNotifierProvider(
      create: (_) => AppointmentProvider(AppointmentRepository()),
    ),
    ChangeNotifierProvider(create: (_) => JournalProvider(JournalRepository())),
    ChangeNotifierProvider(create: (_) => ReportProvider(ReportRepository())),
    ChangeNotifierProvider(
      create: (_) =>
          MentalHealthActivityProvider(MentalHealthActivityRepository()),
    ),
    ChangeNotifierProvider(
      create: (_) => InsightsProvider(InsightsRepository()),
    ),
    ChangeNotifierProvider(create: (_) => MindAidProvider(MindAidRepository())),
    ChangeNotifierProvider(
      create: (_) => SecretChatProvider(SecretChatRepository()),
    ),
    ChangeNotifierProvider(
      create: (_) => AssessmentProvider(AssessmentRepository()),
    ),
    ChangeNotifierProvider(
      create: (_) => BreathingProvider(BreathingRepository()),
    ),
    ChangeNotifierProvider(create: (_) => SleepProvider(SleepRepository())),
  ],
  child: const MindMateApp(),
);

Future<void> _initializeFirebaseRuntime() async {
  FirebaseRuntimeDiagnostics.log(event: 'startup_started');
  try {
    final options = MindMatesFirebaseOptions.currentPlatform;
    AppEnvironmentConfig.validateFirebaseIdentity(
      projectId: options.projectId,
      callableRegion: AppEnvironmentConfig.functionsRegion,
    );
    try {
      await Firebase.initializeApp(options: options);
    } on FirebaseException catch (error) {
      if (error.code != 'duplicate-app') rethrow;
      final existing = Firebase.app();
      if (existing.options.appId != options.appId ||
          existing.options.projectId != options.projectId) {
        throw StateError(
          'firebase-identity-mismatch: native Firebase app does not match '
          '${AppEnvironmentConfig.current.name}.',
        );
      }
      FirebaseRuntimeDiagnostics.log(event: 'firebase_native_app_reused');
    }
    FirebaseRuntimeDiagnostics.log(event: 'firebase_initialized');
  } catch (error) {
    FirebaseRuntimeDiagnostics.logStartupFailure(
      stage: 'firebase',
      error: error,
    );
    rethrow;
  }
  try {
    await FirebaseAppCheckService.activate();
    FirebaseRuntimeDiagnostics.log(event: 'app_check_ready');
  } catch (error) {
    FirebaseRuntimeDiagnostics.logStartupFailure(
      stage: 'app_check',
      error: error,
    );
    rethrow;
  }
}

void _registerErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    FirebaseRuntimeDiagnostics.logStartupFailure(
      stage: 'flutter',
      error: details.exception,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    FirebaseRuntimeDiagnostics.logStartupFailure(
      stage: 'platform',
      error: error,
    );
    return true;
  };
}
