import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/ml/paacc/intent_prediction.dart';
import 'package:mind_mates/features/mind_aid/models/paacc_route_decision.dart';
import 'package:mind_mates/features/mind_aid/services/paacc_intent_router.dart';

void main() {
  final router = PaaccIntentRouter();
  const routes = <String, PaaccRouteType>{
    'appointment_help': PaaccRouteType.appointmentHelp,
    'assessment_help': PaaccRouteType.assessmentHelp,
    'coping_help': PaaccRouteType.copingHelp,
    'goodbye': PaaccRouteType.goodbye,
    'greeting': PaaccRouteType.greeting,
    'service_information': PaaccRouteType.serviceInformation,
    'venting': PaaccRouteType.venting,
    'uncertain': PaaccRouteType.uncertain,
  };

  for (final entry in routes.entries) {
    test('${entry.key} maps safely', () {
      expect(
        router
            .routePrediction(
              IntentPrediction(
                rawIntent: entry.key,
                finalIntent: entry.key,
                classIndex: 0,
                confidence: .8,
                probabilities: const [.8],
                accepted: entry.key != 'uncertain',
              ),
            )
            .route,
        entry.value,
      );
    });
  }

  test('unknown labels fall back to uncertain', () {
    expect(
      router
          .routePrediction(
            const IntentPrediction(
              rawIntent: 'unknown',
              finalIntent: 'unknown',
              classIndex: 0,
              confidence: .8,
              probabilities: [.8],
              accepted: true,
            ),
          )
          .route,
      PaaccRouteType.uncertain,
    );
  });
}
