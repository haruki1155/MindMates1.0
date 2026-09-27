import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/screens/mind_aid_screen.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_integration_models.dart';

void main() {
  testWidgets('sending from older history follows the new reply', (
    tester,
  ) async {
    final messages = List.generate(
      20,
      (index) => MindAidMessage(
        id: 'history-$index',
        sender: MindAidSender.assistant,
        text: 'Earlier support message $index. One small step at a time.',
        createdAt: DateTime(2026),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => MindAidScreen(
            messages: List.of(messages),
            onSendMessage: (_) => setState(
              () => messages.add(
                MindAidMessage(
                  id: 'latest',
                  sender: MindAidSender.assistant,
                  text: 'Your latest reply',
                  createdAt: DateTime(2026),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    await tester.drag(scrollable, const Offset(0, 900));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'I need support');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(messages.last.id, 'latest');
    expect(find.text('Your latest reply').hitTestable(), findsOneWidget);
  });

  test('cloud response ignores actions outside the client allowlist', () {
    final response = MindAidCloudResponse.fromMap({
      'messageId': 'message-1',
      'text': 'Try one small next step.',
      'intent': 'academic_stress',
      'actions': [
        {'type': 'startBreathing', 'label': 'Breathe'},
        {'type': 'openArbitraryRoute', 'label': 'Unsafe'},
      ],
    });

    expect(response.actions, hasLength(1));
    expect(response.actions.single.type, MindAidActionType.startBreathing);
  });

  testWidgets('assistant action invokes the typed callback', (tester) async {
    MindAidAction? selected;
    const action = MindAidAction(
      type: MindAidActionType.bookAppointment,
      label: 'Book an appointment',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MindAidScreen(
          messages: [
            MindAidMessage(
              id: 'assistant-1',
              sender: MindAidSender.assistant,
              text: 'Would you like to contact PACC?',
              createdAt: DateTime(2026),
              actions: const [action],
            ),
          ],
          onActionSelected: (messageId, value) => selected = value,
        ),
      ),
    );

    await tester.tap(find.text('Book an appointment'));
    expect(selected?.type, MindAidActionType.bookAppointment);
  });
}
