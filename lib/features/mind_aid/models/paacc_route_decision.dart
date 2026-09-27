enum PaaccRouteType {
  appointmentHelp,
  assessmentHelp,
  copingHelp,
  goodbye,
  greeting,
  serviceInformation,
  venting,
  uncertain,
}

class PaaccRouteDecision {
  final PaaccRouteType route;
  final String rawIntent;
  final double confidence;
  final String reason;

  const PaaccRouteDecision({
    required this.route,
    required this.rawIntent,
    required this.confidence,
    this.reason = 'model',
  });

  bool get requiresConfirmation =>
      route == PaaccRouteType.appointmentHelp ||
      route == PaaccRouteType.assessmentHelp;
}
