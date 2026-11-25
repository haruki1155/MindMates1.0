import 'package:cloud_functions/cloud_functions.dart';

import '../../core/config/app_environment.dart';

class FirebaseCallableRouter {
  const FirebaseCallableRouter._();

  static const _stagingAliases = <String>{
    'provisionAppUserProfile',
    'repairMyStudentCollege',
    'cancelPendingRegistration',
    'resolveSchoolIdAuthEmail',
    // `requestAdminPasswordReset` is intentionally absent: its Dev alias can
    // mail any account without attestation and is closed on Staging (D3a).
    'requestStaffEmailVerification',
    'getAssessmentStatus',
    'submitQuickAssessment',
    'submitFullAssessment',
    'previewAssessmentDomain',
    'sendMindAidMessage',
    'activateStudentAccount',
    'startStudentAccountSetup',
    'completeStudentAccountSetup',
    'requestStudentRecoveryEmailCode',
    'confirmStudentRecoveryEmailCode',
    'requestStudentPasswordReset',
    'requestStudentLogin',
    // Staging installs no App Check provider, so the protected
    // `createMoodEntry` (enforceAppCheck: true) always refuses there.
    'createMoodEntry',
    'getStudentAcademicCalendar',
  };

  /// The Dev aliases skip App Check, so only a Staging build without an App
  /// Check provider uses them. An App Check build (live Staging Admin Web, an
  /// approved pilot APK) has a token and must call the protected callable.
  static String name(String protectedName) {
    if (AppEnvironmentConfig.isStaging &&
        !AppEnvironmentConfig.stagingAppCheckEnabled &&
        _stagingAliases.contains(protectedName)) {
      return '${protectedName}Dev';
    }
    return protectedName;
  }
}

extension FirebaseFunctionsRouting on FirebaseFunctions {
  HttpsCallable routedCallable(
    String protectedName, {
    HttpsCallableOptions? options,
  }) => httpsCallable(
    FirebaseCallableRouter.name(protectedName),
    options: options,
  );
}
