import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/android_firebase_identity.dart';
import '../../core/config/app_environment.dart';

class FirebaseRuntimeDiagnostics {
  const FirebaseRuntimeDiagnostics._();

  static void log({
    required String event,
    Object? error,
    String? errorCode,
    String? correlationId,
  }) {
    if (!kDebugMode) return;

    final metadata = <String, String>{
      'event': event,
      'environment': AppEnvironmentConfig.current.name,
      'packageName': AndroidFirebaseIdentity.packageName,
      'firebaseAppId': _firebaseAppId(),
      'buildMode': _buildMode,
      'appCheckProvider': _appCheckProvider,
      'firebaseErrorCode': errorCode ?? firebaseErrorCode(error) ?? '',
      'correlationId': correlationId ?? correlationIdFrom(error) ?? '',
    };
    debugPrint('FirebaseRuntime $metadata');
  }

  static void logStartupFailure({
    required String stage,
    required Object error,
  }) {
    log(event: 'startup_${stage}_failed', error: error);
  }

  static String? firebaseErrorCode(Object? error) {
    if (error is FirebaseException) return error.code;
    final match = RegExp(
      r'code[=: ]+([a-z0-9/-]+)',
      caseSensitive: false,
    ).firstMatch(error?.toString() ?? '');
    return match?.group(1)?.toLowerCase();
  }

  static String? correlationIdFrom(Object? error) {
    if (error is! FirebaseFunctionsException) return null;
    final details = error.details;
    if (details is! Map) return null;
    final value = details['correlationId']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static String get _buildMode => kDebugMode
      ? 'debug'
      : kProfileMode
      ? 'profile'
      : 'release';

  static String get _appCheckProvider {
    if (AppEnvironmentConfig.isStaging) return 'staging-disabled';
    if (kIsWeb) return 'recaptcha-enterprise';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return kDebugMode ? 'android-debug' : 'play-integrity';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return kDebugMode ? 'apple-debug' : 'device-check';
      default:
        return 'unsupported';
    }
  }

  static String _firebaseAppId() {
    try {
      return Firebase.app().options.appId;
    } on FirebaseException {
      return AndroidFirebaseIdentity.firebaseAppId;
    }
  }
}
