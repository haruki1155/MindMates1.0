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
    final request = has(
      r'\b(can i|can we|could i|please|show|open|start|book|schedule|reschedule|take|view|what.*services|how.*assessment)\b',
    );
    final appointment =
        request &&
        (has(r'\b(appointment|schedule|booking|reschedule)\b') ||
            has(
              r'\b(book|schedule)\b.*\b(counselor|counselling|counseling|pacc|paacc)\b',
            ));
    final assessment =
        request && has(r'\b(assessment|screening|self assessment)\b');
    final services =
        request && has(r'\b(services|pacc services|paacc services)\b');
    final breathing =
        request &&
        has(
          r'\b(breathing exercise|grounding exercise|start breathing|start grounding)\b',
        );
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
    if (breathing) {
      return _decision(
        PaaccRouteType.copingHelp,
        prediction,
        'explicit_breathing_request',
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
      PaaccRouteType.copingHelp => has(r'\b(calm|cope|coping)\b'),
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
