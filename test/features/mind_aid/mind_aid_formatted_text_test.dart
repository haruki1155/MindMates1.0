import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mind_aid/widgets/mind_aid_formatted_text.dart';
import 'package:mind_mates/features/counseling/screens/mind_aid_screen.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_integration_models.dart';

void main() {
  Widget subject(String value) =>
      MaterialApp(home: Scaffold(body: MindAidFormattedText(value)));

  testWidgets('renders bold text without visible markdown markers', (
    tester,
  ) async {
    await tester.pumpWidget(subject('**Individual Counseling**'));
    expect(find.text('Individual Counseling'), findsOneWidget);
    expect(find.text('**'), findsNothing);
  });

  testWidgets('renders star and dash bullets as clean bullets', (tester) async {
    await tester.pumpWidget(subject('* one\n- two'));
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
  });

  testWidgets('keeps emergency action full width and hides Not now', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MindAidScreen(
          messages: [
            MindAidMessage(
              id: 'crisis',
              sender: MindAidSender.assistant,
              text: '**Emergency Support**\n\nYour safety matters right now.',
              createdAt: DateTime(2026),
              status: 'urgent',
              actions: const [
                MindAidAction(
                  type: MindAidActionType.openCounselingServices,
                  label: 'View PAACC Support',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    expect(find.text('Emergency Support'), findsAtLeastNWidgets(1));
    expect(find.text('View PAACC Support'), findsOneWidget);
    expect(find.text('Not now'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
