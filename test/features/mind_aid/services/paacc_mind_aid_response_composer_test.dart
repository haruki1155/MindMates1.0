import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_integration_models.dart';
import 'package:mind_mates/features/mind_aid/models/paacc_route_decision.dart';
import 'package:mind_mates/features/mind_aid/services/paacc_mind_aid_response_composer.dart';

void main() {
  const composer = PaaccMindAidResponseComposer();

  test('appointment and assessment routes offer user-tapped actions', () {
    final appointment = composer.compose(
      const PaaccRouteDecision(
        route: PaaccRouteType.appointmentHelp,
        rawIntent: 'appointment_help',
        confidence: 0.9,
      ),
    );
    final assessment = composer.compose(
      const PaaccRouteDecision(
        route: PaaccRouteType.assessmentHelp,
        rawIntent: 'assessment_help',
        confidence: 0.9,
      ),
    );

    expect(appointment.actions, hasLength(1));
    expect(appointment.actions.single.type, MindAidActionType.viewAppointments);
    expect(assessment.actions, hasLength(1));
  });

  test('uncertain route provides clarification instead of an action', () {
    final response = composer.compose(
      const PaaccRouteDecision(
        route: PaaccRouteType.uncertain,
        rawIntent: 'unknown',
        confidence: 0.2,
      ),
    );

    expect(response.actions, isEmpty);
    expect(response.text, contains('understand'));
  });
}
