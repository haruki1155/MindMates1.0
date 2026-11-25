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
      resolver.resolve('Can I take the self assessment?', null).route,
      PaaccRouteType.assessmentHelp,
    );
    expect(
      resolver.resolve('Book PACC counseling appointment', null).route,
      PaaccRouteType.appointmentHelp,
    );
    expect(
      resolver.resolve('What services does PACC provide?', null).route,
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
  test(
    'distress and product nouns without a request do not create actions',
    () {
      for (final text in [
        'I am overwhelmed.',
        'Maybe I should talk to someone.',
        'appointment',
        'PACC counseling',
      ]) {
        expect(resolver.resolve(text, coping).route, PaaccRouteType.uncertain);
      }
      expect(
        resolver.resolve('Can we do a breathing exercise?', coping).route,
        PaaccRouteType.copingHelp,
      );
    },
  );
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

  test('counseling and appointment questions route to appointment help', () {
    for (final text in [
      'I want to see a counselor',
      'How do I get counseling?',
      'Where can I talk to a guidance counselor?',
      'Paano magpa-schedule sa counselor?',
      'Gusto ko mag-book ng appointment',
      'Pwede ba akong makipag-usap sa counselor?',
    ]) {
      final decision = resolver.resolve(text, null);
      expect(decision.route, PaaccRouteType.appointmentHelp, reason: text);
      expect(decision.reason, 'appointment_cue', reason: text);
    }
  });

  test('managing an existing appointment is its own appointment reason', () {
    for (final text in [
      'I need to reschedule my appointment',
      'Can I cancel my appointment?',
      'Where can I see my appointments?',
    ]) {
      final decision = resolver.resolve(text, null);
      expect(decision.route, PaaccRouteType.appointmentHelp, reason: text);
      expect(decision.reason, 'appointment_manage', reason: text);
    }
  });

  test('service questions route to service information', () {
    for (final text in [
      'What services does PACC offer?',
      'Ano ang mga services ng PACC?',
      'What does PACC provide for students?',
    ]) {
      expect(
        resolver.resolve(text, null).route,
        PaaccRouteType.serviceInformation,
        reason: text,
      );
    }
  });
}
