import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mind_aid/models/paacc_route_decision.dart';
import 'package:mind_mates/features/mind_aid/services/paacc_intent_resolver.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_dialogue_state.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_integration_models.dart';

void main() {
  const resolver = PaaccIntentResolver();
  const coping = PaaccRouteDecision(
    route: PaaccRouteType.copingHelp,
    rawIntent: 'coping_help',
    confidence: .99,
  );
  test('critical products resolve even when model is unavailable', () {
    expect(
      resolver.resolve('How does self-assessment work?', null).route,
      PaaccRouteType.assessmentHelp,
    );
    expect(
      resolver.resolve('self assessment', null).route,
      PaaccRouteType.assessmentHelp,
    );
    expect(
      resolver.resolve('Book PACC counseling appointment', null).route,
      PaaccRouteType.appointmentHelp,
    );
    expect(
      resolver.resolve('What services does PAACC provide?', null).route,
      PaaccRouteType.serviceInformation,
    );
  });
  test('unrelated and conflicting requests ask for clarification', () {
    for (final text in [
      'Can you give me a recipe for spaghetti?',
      'What is the weather?',
      'Write some code',
      'I need help',
      'bookcase',
      'appointment and assessment',
    ]) {
      expect(
        resolver.resolve(text, coping).route,
        PaaccRouteType.uncertain,
        reason: text,
      );
    }
    expect(
      resolver.resolve('Can you help me calm down?', coping).route,
      PaaccRouteType.copingHelp,
    );
  });
  test('below-threshold prediction is not accepted', () {
    const low = PaaccRouteDecision(
      route: PaaccRouteType.uncertain,
      rawIntent: 'coping_help',
      confidence: .69,
    );
    expect(
      resolver.resolve('help me calm down', low).route,
      PaaccRouteType.uncertain,
    );
  });
  test('state reload preserves pending action, expiry and source identity', () {
    final now = DateTime.utc(2026, 9, 27);
    const action = MindAidAction(
      type: MindAidActionType.openAssessment,
      label: 'Open self-assessment',
    );
    final original = MindAidDialogueState(
      conversationId: 'conversation',
      sourceMessageId: 'message',
      action: action,
      expiresAt: now.add(const Duration(minutes: 10)),
    );
    final restored = MindAidDialogueState.fromMap('conversation', {
      'pending': original.toPendingMap(),
    });
    expect(restored.matches('message', action, now), isTrue);
    expect(restored.matches('old-message', action, now), isFalse);
    expect(
      restored.matches('message', action, now.add(const Duration(minutes: 10))),
      isFalse,
    );
    expect(
      MindAidDialogueState.fromMap('new-conversation', null).isPendingAt(now),
      isFalse,
    );
  });
}
