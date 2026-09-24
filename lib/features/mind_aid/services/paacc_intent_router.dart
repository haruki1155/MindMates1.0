import '../../../core/ml/paacc/intent_prediction.dart';
import '../../../services/ai/paacc_ml_service.dart';
import '../models/paacc_route_decision.dart';

class PaaccIntentRouter {
  PaaccIntentRouter({PaaccMlService? mlService})
    : _mlService = mlService ?? PaaccMlService();

  final PaaccMlService _mlService;

  Future<PaaccRouteDecision> route(String text) async {
    final prediction = await _mlService.predict(text);
    return routePrediction(prediction);
  }

  PaaccRouteDecision routePrediction(IntentPrediction prediction) {
    return PaaccRouteDecision(
      route: _routeFor(prediction.finalIntent),
      rawIntent: prediction.rawIntent,
      confidence: prediction.confidence,
    );
  }

  void dispose() => _mlService.dispose();

  PaaccRouteType _routeFor(String intent) {
    switch (intent) {
      case 'appointment_help':
        return PaaccRouteType.appointmentHelp;
      case 'assessment_help':
        return PaaccRouteType.assessmentHelp;
      case 'coping_help':
        return PaaccRouteType.copingHelp;
      case 'goodbye':
        return PaaccRouteType.goodbye;
      case 'greeting':
        return PaaccRouteType.greeting;
      case 'service_information':
        return PaaccRouteType.serviceInformation;
      case 'venting':
        return PaaccRouteType.venting;
      case 'uncertain':
      default:
        return PaaccRouteType.uncertain;
    }
  }
}
