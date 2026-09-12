import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/config/app_environment.dart';

void main() {
  test('runtime environment matches the supplied build identity', () {
    const requested = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    final expected = switch (requested) {
      'development' => AppEnvironment.development,
      'staging' => AppEnvironment.staging,
      'production' => AppEnvironment.production,
      _ => throw StateError('Unexpected test environment: $requested'),
    };

    expect(AppEnvironmentConfig.current, expected);
  });
}
