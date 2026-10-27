import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/android_firebase_identity.dart';
import '../../core/config/app_environment.dart';
import 'firebase_runtime_diagnostics.dart';

enum FirebaseAppCheckStatus {
  notStarted,
  disabledForStaging,
  active,
  missingWebConfiguration,
  activationFailed,
}

abstract interface class FirebaseAppCheckGateway {
  Future<void> activateWeb(String siteKey);
  Future<void> activateNative({required bool debugMode, String? debugToken});
  Future<String?> getToken({required bool forceRefresh});
}

class FirebaseAppCheckPluginGateway implements FirebaseAppCheckGateway {
  const FirebaseAppCheckPluginGateway();

  @override
  Future<void> activateWeb(String siteKey) => FirebaseAppCheck.instance
      .activate(providerWeb: ReCaptchaEnterpriseProvider(siteKey));

  @override
  Future<void> activateNative({required bool debugMode, String? debugToken}) =>
      FirebaseAppCheck.instance.activate(
        providerAndroid: debugMode
            ? AndroidDebugProvider(debugToken: debugToken)
            : const AndroidPlayIntegrityProvider(),
        providerApple: debugMode
            ? const AppleDebugProvider()
            : const AppleDeviceCheckProvider(),
      );

  @override
  Future<String?> getToken({required bool forceRefresh}) =>
      FirebaseAppCheck.instance.getToken(forceRefresh);
}

class NativeAppCheckConfiguration {
  const NativeAppCheckConfiguration({
    required this.debugMode,
    required this.debugToken,
  });

  final bool debugMode;
  final String? debugToken;
}

class FirebaseAppCheckService {
  const FirebaseAppCheckService._();

  static const _webSiteKey = String.fromEnvironment(
    'RECAPTCHA_ENTERPRISE_SITE_KEY',
    defaultValue: '6LeYF1YtAAAAABwSnD8TeEOaZpWcB3sym5aAWuW0',
  );
  static const stagingPilotEnabled =
      AppEnvironmentConfig.stagingAppCheckEnabled;
  static const _stagingAndroidDebugToken = String.fromEnvironment(
    'APP_CHECK_DEBUG_TOKEN',
  );
  static final _debugTokenPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static FirebaseAppCheckStatus _status = FirebaseAppCheckStatus.notStarted;

  static FirebaseAppCheckStatus get status => _status;
  static bool get isWebConfigurationMissing =>
      kIsWeb && _status == FirebaseAppCheckStatus.missingWebConfiguration;
  static bool get isWebUnavailable =>
      kIsWeb &&
      (_status == FirebaseAppCheckStatus.missingWebConfiguration ||
          _status == FirebaseAppCheckStatus.activationFailed);
  static String get webConfigurationMessage =>
      'Web Firebase App Check is not configured. Run with '
      '--dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=<registered-site-key>.';

  static FirebaseAppCheckStatus statusForWebSiteKey(String siteKey) =>
      siteKey.trim().isEmpty
      ? FirebaseAppCheckStatus.missingWebConfiguration
      : FirebaseAppCheckStatus.active;

  static NativeAppCheckConfiguration nativeConfigurationFor({
    required bool isStaging,
    required bool isProduction,
    required bool stagingAppCheckEnabled,
    required bool isDebugBuild,
    required bool isAndroid,
    required String configuredDebugToken,
  }) {
    if (isProduction) {
      return const NativeAppCheckConfiguration(
        debugMode: false,
        debugToken: null,
      );
    }

    final requiresStagingAndroidDebugToken =
        isStaging && stagingAppCheckEnabled && isDebugBuild && isAndroid;
    if (!requiresStagingAndroidDebugToken) {
      return NativeAppCheckConfiguration(
        debugMode: isDebugBuild,
        debugToken: null,
      );
    }

    final debugToken = configuredDebugToken.trim();
    if (!_debugTokenPattern.hasMatch(debugToken)) {
      throw StateError(
        'Staging Android debug App Check requires a valid APP_CHECK_DEBUG_TOKEN.',
      );
    }
    return NativeAppCheckConfiguration(debugMode: true, debugToken: debugToken);
  }

  static Future<void> activate({FirebaseAppCheckGateway? gateway}) async {
    final client = gateway ?? const FirebaseAppCheckPluginGateway();
    if (AppEnvironmentConfig.isStaging && !stagingPilotEnabled) {
      _status = FirebaseAppCheckStatus.disabledForStaging;
      FirebaseRuntimeDiagnostics.log(event: 'app_check_disabled_for_staging');
      return;
    }
    if (kIsWeb) {
      if (statusForWebSiteKey(_webSiteKey) ==
          FirebaseAppCheckStatus.missingWebConfiguration) {
        _status = statusForWebSiteKey(_webSiteKey);
        debugPrint(webConfigurationMessage);
        return;
      }
      try {
        await client.activateWeb(_webSiteKey);
        if (AppEnvironmentConfig.isStaging) {
          await _requirePluginToken(client, forceRefresh: true);
        }
        _status = FirebaseAppCheckStatus.active;
      } catch (_) {
        _status = FirebaseAppCheckStatus.activationFailed;
        rethrow;
      }
      return;
    }

    final nativeConfiguration = nativeConfigurationFor(
      isStaging: AppEnvironmentConfig.isStaging,
      isProduction: AppEnvironmentConfig.current == AppEnvironment.production,
      stagingAppCheckEnabled: stagingPilotEnabled,
      isDebugBuild: kDebugMode,
      isAndroid: defaultTargetPlatform == TargetPlatform.android,
      configuredDebugToken: _stagingAndroidDebugToken,
    );

    if (nativeConfiguration.debugMode &&
        defaultTargetPlatform == TargetPlatform.android) {
      debugPrint(
        'Firebase App Check debug mode is active. Copy the Android debug token '
        'from Logcat and register it in Firebase Console for '
        '${AndroidFirebaseIdentity.packageName}.',
      );
    }

    try {
      await client.activateNative(
        debugMode: nativeConfiguration.debugMode,
        debugToken: nativeConfiguration.debugToken,
      );
      if (AppEnvironmentConfig.isStaging) {
        await _requirePluginToken(client, forceRefresh: true);
      }
      _status = FirebaseAppCheckStatus.active;
      FirebaseRuntimeDiagnostics.log(event: 'app_check_activated');
    } catch (error) {
      _status = FirebaseAppCheckStatus.activationFailed;
      FirebaseRuntimeDiagnostics.log(
        event: 'app_check_activation_failed',
        error: error,
      );
      rethrow;
    }
  }

  static Future<String?> refreshToken({
    FirebaseAppCheckGateway? gateway,
  }) async {
    if (AppEnvironmentConfig.isStaging && !stagingPilotEnabled) {
      return null;
    }
    try {
      return await _requirePluginToken(
        gateway ?? const FirebaseAppCheckPluginGateway(),
        forceRefresh: true,
      );
    } catch (error) {
      _markTokenFailure(error);
      rethrow;
    }
  }

  static Future<void> requireToken({FirebaseAppCheckGateway? gateway}) async {
    if (AppEnvironmentConfig.isStaging && !stagingPilotEnabled) return;
    if (isWebUnavailable) throw StateError(webConfigurationMessage);
    if (_status != FirebaseAppCheckStatus.active) {
      throw StateError('Firebase App Check is not active on this device.');
    }
    try {
      await _requirePluginToken(
        gateway ?? const FirebaseAppCheckPluginGateway(),
        forceRefresh: false,
      );
    } catch (error) {
      _markTokenFailure(error);
      rethrow;
    }
  }

  static Future<String> _requirePluginToken(
    FirebaseAppCheckGateway gateway, {
    required bool forceRefresh,
  }) async {
    final token = await gateway.getToken(forceRefresh: forceRefresh);
    if (token == null || token.trim().isEmpty) {
      throw StateError('Firebase App Check could not verify this app.');
    }
    return token;
  }

  static void _markTokenFailure(Object error) {
    _status = FirebaseAppCheckStatus.activationFailed;
    FirebaseRuntimeDiagnostics.log(
      event: 'app_check_token_failed',
      error: error,
    );
  }

  @visibleForTesting
  static void resetForTesting() {
    _status = FirebaseAppCheckStatus.notStarted;
  }
}
