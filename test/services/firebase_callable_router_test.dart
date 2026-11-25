import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/services/firebase/firebase_callable_router.dart';

void main() {
  const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );
  const appCheck = bool.fromEnvironment('ENABLE_STAGING_APP_CHECK');
  // Only a Staging build without App Check may use the Dev aliases, which skip it.
  const usesDevAliases = environment == 'staging' && !appCheck;
  String expected(String name) => usesDevAliases ? '${name}Dev' : name;

  test('routes protected callables for the configured environment', () {
    for (final name in [
      'provisionAppUserProfile',
      'submitQuickAssessment',
      'submitFullAssessment',
      'previewAssessmentDomain',
      'createMoodEntry',
      'getStudentAcademicCalendar',
    ]) {
      expect(FirebaseCallableRouter.name(name), expected(name), reason: name);
    }
  });

  test('routes the Student ID setup and recovery callables', () {
    for (final name in [
      'startStudentAccountSetup',
      'completeStudentAccountSetup',
      'requestStudentRecoveryEmailCode',
      'confirmStudentRecoveryEmailCode',
      'requestStudentPasswordReset',
    ]) {
      expect(FirebaseCallableRouter.name(name), expected(name), reason: name);
    }
  });

  test('an App Check build never selects a Dev alias', () {
    if (!appCheck) return;
    expect(
      FirebaseCallableRouter.name('requestStudentPasswordReset'),
      'requestStudentPasswordReset',
    );
    expect(
      FirebaseCallableRouter.name('requestAdminPasswordReset'),
      'requestAdminPasswordReset',
    );
  });

  test('does not rewrite an unknown callable', () {
    expect(FirebaseCallableRouter.name('unlistedCallable'), 'unlistedCallable');
  });

  test('admin password reset never routes to its blocked Dev alias', () {
    // Pre-login and able to mail any account; the Dev alias is closed on
    // Staging (D3a), so every environment calls the protected callable.
    expect(
      FirebaseCallableRouter.name('requestAdminPasswordReset'),
      'requestAdminPasswordReset',
    );
  });

  test(
    'routes downloadClinicalSessionEvidence consistently across environments',
    () {
      expect(
        FirebaseCallableRouter.name('downloadClinicalSessionEvidence'),
        'downloadClinicalSessionEvidence',
      );
    },
  );
}
