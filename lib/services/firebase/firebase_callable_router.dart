import 'package:cloud_functions/cloud_functions.dart';

import '../../core/config/app_environment.dart';

class FirebaseCallableRouter {
  const FirebaseCallableRouter._();

  static const _stagingAliases = <String>{
    'provisionAppUserProfile',
    'cancelPendingRegistration',
    'resolveSchoolIdAuthEmail',
    'requestAdminPasswordReset',
    'requestStaffEmailVerification',
    'getAssessmentStatus',
    'submitQuickAssessment',
    'submitFullAssessment',
    'previewAssessmentDomain',
    'sendMindAidMessage',
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
  }) => httpsCallable(FirebaseCallableRouter.name(protectedName), options: options);
}
