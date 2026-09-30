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
      case PaaccRouteType.goodbye:
      case PaaccRouteType.venting:
      case PaaccRouteType.uncertain:
        return const PaaccMindAidResponse(text: '');
      case PaaccRouteType.appointmentHelp:
        return const PaaccMindAidResponse(
          text: '',
          actions: [
            MindAidAction(
              type: MindAidActionType.viewAppointments,
              label: 'View appointment options',
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
