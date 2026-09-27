import '../models/paacc_route_decision.dart';

/// Product routing policy applied after the frozen V4 prediction.
class PaaccIntentResolver {
  const PaaccIntentResolver();

  PaaccRouteDecision resolve(String text, PaaccRouteDecision? prediction) {
    final input = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    bool has(String pattern) => RegExp(pattern).hasMatch(input);

    if (has(
      r'\b(recipe|spaghetti|weather|coding|javascript|python|novel|bookcase)\b',
    )) {
      return _decision(PaaccRouteType.uncertain, prediction, 'off_topic');
    }
    final appointment =
        has(r'\b(appointment|schedule|booking|reschedule)\b') ||
        input == 'book' ||
        has(r'\bbook\b.*\b(pacc|paacc|counseling|counselling)\b');
    final assessment = has(r'\b(assessment|screening|self assessment)\b');
    final services = has(r'\b(services|counseling|counselling|paacc|pacc)\b');
    if ((appointment && assessment) ||
        (assessment &&
            services &&
            has(r'\b(service|services|counseling|counselling)\b'))) {
      return _decision(
        PaaccRouteType.uncertain,
        prediction,
        'conflicting_product_cues',
      );
    }
    if (appointment) {
      return _decision(
        PaaccRouteType.appointmentHelp,
        prediction,
        'appointment_cue',
      );
    }
    if (assessment) {
      return _decision(
        PaaccRouteType.assessmentHelp,
        prediction,
        'assessment_cue',
      );
    }
    if (services) {
      return _decision(
        PaaccRouteType.serviceInformation,
        prediction,
        'services_cue',
      );
    }

    final route = prediction?.route ?? PaaccRouteType.uncertain;
    final supported = switch (route) {
      PaaccRouteType.greeting => has(
        r'\b(hello|hi|hey|good morning|good afternoon|good evening)\b',
      ),
      PaaccRouteType.goodbye => has(
        r'\b(bye|goodbye|done talking|see you|take care)\b',
      ),
      PaaccRouteType.copingHelp => has(
        r'\b(calm|cope|coping|breathe|breathing|ground|grounding|panic|overwhelmed)\b',
      ),
      PaaccRouteType.venting => has(
        r'\b(stress|stressed|anxious|sad|lonely|upset|worried|struggling|burnout)\b',
      ),
      _ => false,
    };
    return _decision(
      supported ? route : PaaccRouteType.uncertain,
      prediction,
      supported ? 'model_with_context' : 'unsupported_or_uncertain',
    );
  }

  PaaccRouteDecision _decision(
    PaaccRouteType route,
    PaaccRouteDecision? prediction,
    String reason,
  ) => PaaccRouteDecision(
    route: route,
    rawIntent: prediction?.rawIntent ?? 'unavailable',
    confidence: prediction?.confidence ?? 0,
    reason: reason,
  );
}
