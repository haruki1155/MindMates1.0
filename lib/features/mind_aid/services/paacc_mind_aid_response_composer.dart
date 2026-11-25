import '../domain/mind_aid_companion_models.dart';
import '../domain/mind_aid_integration_models.dart';
import '../models/paacc_route_decision.dart';

class PaaccMindAidResponse {
  const PaaccMindAidResponse({required this.text, this.actions = const []});

  final String text;
  final List<MindAidAction> actions;
}

/// Whether a PACC action button may show. Service and appointment questions
/// are direct requests for PACC, so their buttons show in any mode.
bool paaccActionAllowed(MindAidConversationMode mode, PaaccRouteType route) =>
    route == PaaccRouteType.appointmentHelp ||
    route == PaaccRouteType.serviceInformation ||
    mode == MindAidConversationMode.navigation ||
    mode == MindAidConversationMode.coaching;

class PaaccMindAidResponseComposer {
  const PaaccMindAidResponseComposer();

  PaaccMindAidResponse compose(PaaccRouteDecision decision) {
    switch (decision.route) {
      case PaaccRouteType.greeting:
      case PaaccRouteType.goodbye:
      case PaaccRouteType.venting:
      case PaaccRouteType.uncertain:
        return const PaaccMindAidResponse(text: '');
      case PaaccRouteType.appointmentHelp:
        return PaaccMindAidResponse(
          text: '',
          actions: [
            decision.reason == 'appointment_manage'
                ? const MindAidAction(
                    type: MindAidActionType.viewAppointments,
                    label: 'View my appointments',
                  )
                : const MindAidAction(
                    type: MindAidActionType.bookAppointment,
                    label: 'Book a counseling appointment',
                  ),
          ],
        );
      case PaaccRouteType.assessmentHelp:
        return const PaaccMindAidResponse(
          text: '',
          actions: [
            MindAidAction(
              type: MindAidActionType.openAssessment,
              label: 'Open self-assessment',
            ),
          ],
        );
      case PaaccRouteType.serviceInformation:
        return const PaaccMindAidResponse(
          text: '',
          actions: [
            MindAidAction(
              type: MindAidActionType.openCounselingServices,
              label: 'View PACC services',
            ),
          ],
        );
      case PaaccRouteType.copingHelp:
        return const PaaccMindAidResponse(
          text: '',
          actions: [
            MindAidAction(
              type: MindAidActionType.startBreathing,
              label: 'Start breathing exercise',
            ),
          ],
        );
    }
  }
}
