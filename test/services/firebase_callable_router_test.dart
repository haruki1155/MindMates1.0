import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/services/firebase/firebase_callable_router.dart';

void main() {
  test('routes protected callables for the configured environment', () {
    const environment = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    final expected = environment == 'staging'
        ? 'provisionAppUserProfileDev'
        : 'provisionAppUserProfile';

    expect(FirebaseCallableRouter.name('provisionAppUserProfile'), expected);
    final assessmentExpected = environment == 'staging'
        ? 'submitQuickAssessmentDev'
        : 'submitQuickAssessment';
    expect(
      FirebaseCallableRouter.name('submitQuickAssessment'),
      assessmentExpected,
    );
    final fullExpected = environment == 'staging'
        ? 'submitFullAssessmentDev'
        : 'submitFullAssessment';
    expect(FirebaseCallableRouter.name('submitFullAssessment'), fullExpected);
  });

  test('does not rewrite an unknown callable', () {
    expect(FirebaseCallableRouter.name('unlistedCallable'), 'unlistedCallable');
  });
}
