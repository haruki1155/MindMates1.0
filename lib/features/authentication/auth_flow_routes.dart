import '../../models/profile_roles.dart';
import '../../models/user_model.dart';
import '../../routes/route_names.dart';

String destinationAfterAuthentication({
  required bool hasCompletedQuickAssessment,
}) {
  return hasCompletedQuickAssessment ? RouteNames.home : RouteNames.onboarding;
}

/// The route a signed-in user must complete before using the app, or null
/// when nothing is pending. Students owing Student Information come first.
String? gateRouteForUser(UserModel user) {
  if (user.effectivePopulationRole == PopulationRole.student &&
      user.personalInfoRequired) {
    return RouteNames.studentInformation;
  }
  if (user.profileVersion >= 3 &&
      (!user.isProfileComplete || !user.profileSetupCompleted)) {
    return RouteNames.profileSetup;
  }
  return null;
}
