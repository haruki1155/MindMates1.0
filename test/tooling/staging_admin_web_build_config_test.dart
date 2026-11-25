import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the deployment configuration that keeps Staging admin password
/// recovery on the App Check protected callable. If the live Staging build
/// loses App Check, "Forgot password" silently breaks again (the Dev alias is
/// closed on Staging), so these settings must not drift.
void main() {
  String read(String path) => File(path).readAsStringSync();

  String buildLine(String workflow) => read(workflow)
      .split('\n')
      .firstWhere((line) => line.contains('flutter build web'));

  test('the main → Staging live build enables Staging App Check', () {
    final line = buildLine('.github/workflows/firebase-hosting-merge.yml');
    expect(line, contains('--target lib/admin_main.dart'));
    expect(line, contains('--dart-define=APP_ENV=staging'));
    expect(line, contains('--dart-define=ENABLE_STAGING_APP_CHECK=true'));
  });

  test('preview and production builds do not enable Staging App Check', () {
    // Preview channel hosts are not on the Staging reCAPTCHA key; production
    // never uses the Staging flag.
    for (final workflow in [
      '.github/workflows/firebase-hosting-pull-request.yml',
      '.github/workflows/firebase-hosting-production.yml',
    ]) {
      expect(
        buildLine(workflow),
        isNot(contains('ENABLE_STAGING_APP_CHECK=true')),
        reason: workflow,
      );
    }
    expect(
      buildLine('.github/workflows/firebase-hosting-production.yml'),
      contains('--dart-define=APP_ENV=production'),
    );
  });

  test('the Vercel build passes the opt-in Staging App Check flag through', () {
    final script = read('tool/vercel_build.sh');
    expect(
      script,
      contains(r'staging_app_check="${MINDMATES_ENABLE_STAGING_APP_CHECK:-false}"'),
    );
    expect(
      script,
      contains(r'--dart-define=ENABLE_STAGING_APP_CHECK="$staging_app_check"'),
    );
  });
}
