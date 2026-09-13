import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_app_check_service.dart';
import 'firebase_runtime_diagnostics.dart';

class FirebaseErrorMessage {
  const FirebaseErrorMessage._();

  static String describe(Object error, {required String fallback}) {
    final text = [
      error.toString(),
      if (error is FirebaseFunctionsException) error.message ?? '',
      if (error is FirebaseException) error.message ?? '',
    ].join(' ').toLowerCase();
    if (text.contains('initial-throttle') ||
        text.contains('attempts allowed again')) {
      return appCheckThrottleMessage();
    }
    if (text.contains('app check') || text.contains('appcheck')) {
      return appCheckMessage();
    }
    final code = codeOf(error);
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message != null &&
          message.isNotEmpty &&
          {
            'invalid-argument',
            'failed-precondition',
            'already-exists',
            'not-found',
            'internal',
            'unavailable',
          }.contains(code)) {
        return message;
      }
    }
    if (code == 'invalid-argument' && error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
    }
    if (error is FormatException) {
      return 'The assessment was saved, but the verified result could not be read. Tap retry to refresh it.';
    }
    if (text.contains('profile') &&
        (text.contains('missing') ||
            text.contains('setup') ||
            text.contains('provision'))) {
      return 'Your account is signed in, but profile setup is incomplete. Retry profile setup.';
    }
    if (code == 'unauthenticated' && FirebaseAppCheckService.isWebUnavailable) {
      return FirebaseAppCheckService.webConfigurationMessage;
    }
    switch (code) {
      case 'permission-denied':
        return 'You do not have permission to complete this action.';
      case 'unauthenticated':
        return 'Please sign in again to continue.';
      case 'failed-precondition':
        return text.contains('profile')
            ? 'Your account profile is incomplete. Retry profile setup, then try again.'
            : 'This action cannot be completed yet. Check your profile and try again.';
      case 'app-check':
      case 'unauthorized':
        return appCheckMessage();
      case 'invalid-argument':
        return 'Some information is invalid or missing. Check your entries and try again.';
      case 'resource-exhausted':
        return 'You have reached the allowed limit for this action. Please try again later.';
      case 'already-exists':
        return 'This information has already been saved for your account.';
      case 'network-request-failed':
      case 'unavailable':
        return 'The connection to MindMates is unavailable. Check your internet connection and try again.';
      case 'email-already-in-use':
        return 'This email address is already registered. Sign in or use a different email address.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'too-many-requests':
        return 'Too many verification requests were sent. Wait a minute, then try again.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email address or password is incorrect.';
      case 'password-reset-unavailable':
        return error is FirebaseAuthException &&
                error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Password recovery is unavailable for this account. Contact MindMate support.';
      default:
        return fallback;
    }
  }

  static String appCheckMessage({
    bool? web,
    String? webHost,
    TargetPlatform? platform,
    bool? debugMode,
  }) {
    final isWeb = web ?? kIsWeb;
    if (isWeb) {
      final host = webHost ?? Uri.base.host;
      if (_isLocalWebHost(host)) {
        return 'This localhost browser is not verified by Firebase App Check. Register the debug token printed in the browser console, clear localhost site data, and restart the app.';
      }
      return 'This web app is not verified by Firebase App Check. Confirm the reCAPTCHA Enterprise site key and registered production domain.';
    }
    final target = platform ?? defaultTargetPlatform;
    final debug = debugMode ?? kDebugMode;
    if (target == TargetPlatform.android) {
      return debug
          ? 'This Android debug build is not verified. Register its App Check debug token in Firebase Console.'
          : 'This Android app is not verified. Confirm its Play Integrity registration in Firebase App Check.';
    }
    if (target == TargetPlatform.iOS || target == TargetPlatform.macOS) {
      return debug
          ? 'This Apple debug build is not verified. Register its App Check debug token in Firebase Console.'
          : 'This Apple app is not verified. Confirm its DeviceCheck registration in Firebase App Check.';
    }
    return 'This app is not verified by Firebase App Check. Confirm the registered provider for this platform.';
  }

  static String appCheckThrottleMessage({bool? web, String? webHost}) {
    final isWeb = web ?? kIsWeb;
    final host = webHost ?? Uri.base.host;
    if (isWeb && _isLocalWebHost(host)) {
      return 'Firebase App Check temporarily throttled this localhost browser. Register its debug token, clear localhost site data, and restart the app.';
    }
    if (isWeb) {
      return 'Firebase App Check temporarily throttled this browser after a rejected attestation. Verify the Enterprise key and production domain, then retry with fresh site data.';
    }
    return appCheckMessage(web: false);
  }

  static bool _isLocalWebHost(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';

  static bool isAppCheckFailure(Object error) {
    final text = error.toString().toLowerCase();
    final code = codeOf(error);
    return text.contains('app check') ||
        text.contains('appcheck') ||
        text.contains('app attestation') ||
        code == 'app-check' ||
        code == 'unauthorized';
  }

  static bool isNetworkFailure(Object error) {
    final code = codeOf(error);
    return code == 'network-request-failed' || code == 'unavailable';
  }

  static String? codeOf(Object error) =>
      FirebaseRuntimeDiagnostics.firebaseErrorCode(error);

  static void log(Object error, StackTrace stackTrace, {required String area}) {
    FirebaseRuntimeDiagnostics.log(event: area, error: error);
  }
}
