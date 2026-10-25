import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/services/firebase/firebase_app_check_service.dart';
import 'package:mind_mates/services/firebase/firebase_runtime_diagnostics.dart';

void main() {
  const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );
  const stagingPilotEnabled = bool.fromEnvironment(
    'ENABLE_STAGING_APP_CHECK',
    defaultValue: false,
  );

  setUp(FirebaseAppCheckService.resetForTesting);

  test('web App Check requires a non-empty Enterprise site key', () {
    expect(
      FirebaseAppCheckService.statusForWebSiteKey(''),
      FirebaseAppCheckStatus.missingWebConfiguration,
    );
    expect(
      FirebaseAppCheckService.statusForWebSiteKey('  '),
      FirebaseAppCheckStatus.missingWebConfiguration,
    );
    expect(
      FirebaseAppCheckService.statusForWebSiteKey('site-key'),
      FirebaseAppCheckStatus.active,
    );
  });

  test(
    'web configuration error tells developers how to configure App Check',
    () {
      expect(
        FirebaseAppCheckService.webConfigurationMessage,
        contains('RECAPTCHA_ENTERPRISE_SITE_KEY'),
      );
    },
  );

  test('safe diagnostics extract only code and correlation ID', () {
    final error = FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'private message must not be copied into metadata',
      details: const {'correlationId': 'correlation-123'},
    );

    expect(
      FirebaseRuntimeDiagnostics.firebaseErrorCode(error),
      'failed-precondition',
    );
    expect(
      FirebaseRuntimeDiagnostics.correlationIdFrom(error),
      'correlation-123',
    );
  });

  test(
    'staging App Check is explicitly disabled unless pilot-enabled',
    () async {
      if (environment != 'staging' || stagingPilotEnabled) return;
      final gateway = _FakeAppCheckGateway();

      await FirebaseAppCheckService.activate(gateway: gateway);
      expect(
        await FirebaseAppCheckService.refreshToken(gateway: gateway),
        isNull,
      );
      await FirebaseAppCheckService.requireToken(gateway: gateway);

      expect(
        FirebaseAppCheckService.status,
        FirebaseAppCheckStatus.disabledForStaging,
      );
      expect(gateway.activationCalls, 0);
      expect(gateway.tokenCalls, 0);
    },
  );

  test(
    'enabled staging pilot activates a provider and requires a real token',
    () async {
      if (environment != 'staging' || !stagingPilotEnabled) return;
      final gateway = _FakeAppCheckGateway(token: 'verified-token');

      await FirebaseAppCheckService.activate(gateway: gateway);

      expect(FirebaseAppCheckService.status, FirebaseAppCheckStatus.active);
      expect(gateway.activationCalls, 1);
      expect(gateway.forceRefreshes, [true]);

      expect(
        await FirebaseAppCheckService.refreshToken(gateway: gateway),
        'verified-token',
      );
      await FirebaseAppCheckService.requireToken(gateway: gateway);
      expect(gateway.forceRefreshes, [true, true, false]);
    },
  );

  test('enabled staging pilot fails closed when no token is issued', () async {
    if (environment != 'staging' || !stagingPilotEnabled) return;
    final gateway = _FakeAppCheckGateway(token: '  ');

    await expectLater(
      FirebaseAppCheckService.activate(gateway: gateway),
      throwsA(isA<StateError>()),
    );

    expect(
      FirebaseAppCheckService.status,
      FirebaseAppCheckStatus.activationFailed,
    );
    expect(gateway.activationCalls, 1);
  });

  test(
    'enabled staging pilot loses active status when refresh fails',
    () async {
      if (environment != 'staging' || !stagingPilotEnabled) return;
      final gateway = _FakeAppCheckGateway(token: 'verified-token');
      await FirebaseAppCheckService.activate(gateway: gateway);
      gateway.token = null;

      await expectLater(
        FirebaseAppCheckService.refreshToken(gateway: gateway),
        throwsA(isA<StateError>()),
      );

      expect(
        FirebaseAppCheckService.status,
        FirebaseAppCheckStatus.activationFailed,
      );
    },
  );

  test('provider activation errors remain fail-closed', () async {
    if (environment == 'staging' && !stagingPilotEnabled) return;
    final gateway = _FakeAppCheckGateway(activationError: StateError('failed'));

    await expectLater(
      FirebaseAppCheckService.activate(gateway: gateway),
      throwsA(isA<StateError>()),
    );
    expect(
      FirebaseAppCheckService.status,
      FirebaseAppCheckStatus.activationFailed,
    );
  });
}

class _FakeAppCheckGateway implements FirebaseAppCheckGateway {
  _FakeAppCheckGateway({this.token = 'verified-token', this.activationError});

  String? token;
  final Object? activationError;
  int activationCalls = 0;
  int tokenCalls = 0;
  final List<bool> forceRefreshes = [];

  @override
  Future<void> activateNative({required bool debugMode}) async {
    activationCalls++;
    if (activationError != null) throw activationError!;
  }

  @override
  Future<void> activateWeb(String siteKey) async {
    activationCalls++;
    if (activationError != null) throw activationError!;
  }

  @override
  Future<String?> getToken({required bool forceRefresh}) async {
    tokenCalls++;
    forceRefreshes.add(forceRefresh);
    return token;
  }
}
