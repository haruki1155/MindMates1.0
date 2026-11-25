import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_companion_models.dart';
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
    expect(appointment.actions.single.type, MindAidActionType.bookAppointment);
    expect(appointment.actions.single.label, 'Book a counseling appointment');
    expect(appointment.actions.single.payload, isEmpty);
    expect(assessment.actions, hasLength(1));
  });

  test('uncertain route does not add a response override or action', () {
    final response = composer.compose(
      const PaaccRouteDecision(
        route: PaaccRouteType.uncertain,
        rawIntent: 'unknown',
        confidence: 0.2,
      ),
    );

    expect(response.actions, isEmpty);
    expect(response.text, isEmpty);
  });

  test(
    'managing an appointment and service questions get their own action',
    () {
      final manage = composer.compose(
        const PaaccRouteDecision(
          route: PaaccRouteType.appointmentHelp,
          rawIntent: 'appointment_help',
          confidence: 0.9,
          reason: 'appointment_manage',
        ),
      );
      final services = composer.compose(
        const PaaccRouteDecision(
          route: PaaccRouteType.serviceInformation,
          rawIntent: 'service_information',
          confidence: 0.9,
        ),
      );
      expect(manage.actions.single.type, MindAidActionType.viewAppointments);
      expect(manage.actions.single.label, 'View my appointments');
      expect(
        services.actions.single.type,
        MindAidActionType.openCounselingServices,
      );
      expect(services.actions.single.label, 'View PACC services');
    },
  );

  test('service and appointment buttons show in every conversation mode', () {
    for (final mode in MindAidConversationMode.values) {
      for (final route in [
        PaaccRouteType.appointmentHelp,
        PaaccRouteType.serviceInformation,
      ]) {
        expect(paaccActionAllowed(mode, route), isTrue, reason: '$mode $route');
      }
    }
    expect(
      paaccActionAllowed(
        MindAidConversationMode.supportive,
        PaaccRouteType.copingHelp,
      ),
      isFalse,
    );
    expect(
      paaccActionAllowed(
        MindAidConversationMode.coaching,
        PaaccRouteType.copingHelp,
      ),
      isTrue,
    );
  });
}
