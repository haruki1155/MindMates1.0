import '../domain/mind_aid_integration_models.dart';
import '../models/paacc_route_decision.dart';

class PaaccMindAidResponse {
  const PaaccMindAidResponse({required this.text, this.actions = const []});

  final String text;
  final List<MindAidAction> actions;
}

class PaaccMindAidResponseComposer {
  const PaaccMindAidResponseComposer();

  PaaccMindAidResponse compose(PaaccRouteDecision decision) {
    switch (decision.route) {
      case PaaccRouteType.greeting:
        return const PaaccMindAidResponse(
          text:
              'Hello! It is good to hear from you. How can I support you today?',
        );
      case PaaccRouteType.goodbye:
        return const PaaccMindAidResponse(
          text:
              'Take care of yourself. You can return to MindAid whenever you need support.',
        );
      case PaaccRouteType.appointmentHelp:
        return const PaaccMindAidResponse(
          text:
              'I can help with appointment options. Would you like to view them?',
          actions: [
            MindAidAction(
              type: MindAidActionType.viewAppointments,
              label: 'View appointment options',
            ),
          ],
        );
      case PaaccRouteType.assessmentHelp:
        return const PaaccMindAidResponse(
          text: 'The self-assessment helps you reflect on your wellbeing; it is not a diagnosis. You can review its privacy information before answering. Would you like to open it?',
          actions: [
            MindAidAction(
              type: MindAidActionType.openAssessment,
              label: 'Open self-assessment',
            ),
          ],
        );
      case PaaccRouteType.serviceInformation:
        return const PaaccMindAidResponse(
          text:
              'PAACC offers counseling and student support services. Would you like to view the available services?',
          actions: [
            MindAidAction(
              type: MindAidActionType.openCounselingServices,
              label: 'View PACC services',
            ),
          ],
        );
      case PaaccRouteType.venting:
        return const PaaccMindAidResponse(
          text:
              'That sounds difficult. I am here to listen—what feels most important to share right now?',
        );
      case PaaccRouteType.copingHelp:
        return const PaaccMindAidResponse(
          text:
              'Let us take one small step. Would a brief breathing exercise or a grounding pause help right now?',
          actions: [
            MindAidAction(
              type: MindAidActionType.startBreathing,
              label: 'Start breathing exercise',
            ),
          ],
        );
      case PaaccRouteType.uncertain:
        return const PaaccMindAidResponse(
          text:
              'I want to make sure I understand. Are you looking for support, services, an appointment, or an assessment?',
        );
    }
  }
}
