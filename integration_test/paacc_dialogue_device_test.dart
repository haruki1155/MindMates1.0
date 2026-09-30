import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mind_mates/features/mind_aid/models/paacc_route_decision.dart';
import 'package:mind_mates/features/mind_aid/services/paacc_intent_router.dart';
import 'package:mind_mates/features/mind_aid/services/paacc_intent_resolver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('frozen V4 plus resolver passes eight physical-device prompts', (
    tester,
  ) async {
    final router = PaaccIntentRouter();
    const resolver = PaaccIntentResolver();
    const cases = {
      'Hello, good morning!': PaaccRouteType.greeting,
      'How do I schedule an appointment?': PaaccRouteType.appointmentHelp,
      'How does self-assessment work?': PaaccRouteType.assessmentHelp,
      'What services does PACC provide?': PaaccRouteType.serviceInformation,
      'I have been stressed with school lately.': PaaccRouteType.venting,
      'Can you help me calm down?': PaaccRouteType.copingHelp,
      "I think I'm done talking now.": PaaccRouteType.goodbye,
      'Can you give me a recipe for spaghetti?': PaaccRouteType.uncertain,
    };
    try {
      for (final entry in cases.entries) {
        final prediction = await router.route(entry.key);
        final decision = resolver.resolve(entry.key, prediction);
        expect(decision.route, entry.value, reason: entry.key);
        // Labels and confidence only; do not log conversation text.
        debugPrint(
          'PACC raw=${decision.rawIntent} confidence=${decision.confidence} resolved=${decision.route.name} reason=${decision.reason}',
        );
      }
    } finally {
      router.dispose();
    }
  });
}
