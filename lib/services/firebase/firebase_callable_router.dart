import 'package:cloud_functions/cloud_functions.dart';

import '../../core/config/app_environment.dart';

class FirebaseCallableRouter {
  const FirebaseCallableRouter._();

  static const _stagingAliases = <String>{
    'provisionAppUserProfile',
    'repairMyStudentCollege',
    'cancelPendingRegistration',
    'resolveSchoolIdAuthEmail',
    'requestAdminPasswordReset',
    'requestStaffEmailVerification',
    'getAssessmentStatus',
    'submitQuickAssessment',
    'submitFullAssessment',
    'previewAssessmentDomain',
    'sendMindAidMessage',
    'activateStudentAccount',
    // Staging installs no App Check provider, so the protected
    // `createMoodEntry` (enforceAppCheck: true) always refuses there.
    'createMoodEntry',
  };

  static String name(String protectedName) {
    if (AppEnvironmentConfig.isStaging &&
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
