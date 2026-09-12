import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android package and Firebase configuration stay aligned', () {
    const packageName = 'ph.edu.ucu.mindmates';
    const firebaseAppId = '1:842251480963:android:4c05d169dbacf125eb50b6';

    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/ph/edu/ucu/mindmates/MainActivity.kt',
    );
    final googleServices =
        jsonDecode(
              File(
                'android/app/src/production/google-services.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final firebaseOptions = File(
      'lib/firebase_options.dart',
    ).readAsStringSync();

    expect(gradle, contains('val productionApplicationId = "$packageName"'));
    expect(gradle, contains('create("staging")'));
    expect(gradle, contains('create("development")'));
    expect(manifest, contains('package="$packageName"'));
    expect(manifest, contains('android:name="ph.edu.ucu.mindmates.MainActivity"'));
    expect(manifest, contains('android.permission.INTERNET'));
    expect(activity.existsSync(), isTrue);
    expect(activity.readAsStringSync(), contains('package $packageName'));
    expect(
      File(
        'android/app/src/main/kotlin/com/example/mind_mates/MainActivity.kt',
      ).existsSync(),
      isFalse,
    );

    final clients = googleServices['client'] as List<dynamic>;
    expect(clients, hasLength(1));
    final clientInfo =
        (clients.single as Map<String, dynamic>)['client_info']
            as Map<String, dynamic>;
    final androidClientInfo =
        clientInfo['android_client_info'] as Map<String, dynamic>;
    expect(clientInfo['mobilesdk_app_id'], firebaseAppId);
    expect(androidClientInfo['package_name'], packageName);

    final androidOptions = RegExp(
      r'static const FirebaseOptions android = FirebaseOptions\(([\s\S]*?)\n  \);',
    ).firstMatch(firebaseOptions);
    expect(androidOptions, isNotNull);
    expect(androidOptions!.group(1), contains("appId: '$firebaseAppId'"));
    expect(firebaseOptions, contains("appId: '$firebaseAppId'"));
  });

  test('debug App Check tokens cannot be injected through Dart defines', () {
    final appCheckService = File(
      'lib/services/firebase/firebase_app_check_service.dart',
    ).readAsStringSync();

    expect(appCheckService, contains('const AndroidDebugProvider()'));
    expect(appCheckService, contains('const AndroidPlayIntegrityProvider()'));
    expect(appCheckService, isNot(contains('APP_CHECK_DEBUG_TOKEN')));
    expect(appCheckService, isNot(contains('debugToken:')));
  });
}
