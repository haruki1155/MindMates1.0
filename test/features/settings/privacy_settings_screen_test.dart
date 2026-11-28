import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/settings/screens/privacy_settings_screen.dart';
import 'package:mind_mates/routes/route_names.dart';

void main() {
  testWidgets(
    'privacy screen links to the existing MindAid and Sleep controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const PrivacySettingsScreen(),
          routes: {
            RouteNames.mindAid: (_) =>
                const Scaffold(body: Text('MindAid target')),
            RouteNames.sleepQuality: (_) =>
                const Scaffold(body: Text('Sleep target')),
          },
        ),
      );

      expect(find.text('MindAid AI privacy settings'), findsOneWidget);
      expect(find.text('Sleep diary storage'), findsOneWidget);
      expect(
        find.textContaining(
          'do not turn off assessment or appointment records',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Privacy Officer'), findsNothing);
      expect(find.textContaining('Delete my data'), findsNothing);

      await tester.tap(find.text('MindAid AI privacy settings'));
      await tester.pumpAndSettle();
      expect(find.text('MindAid target'), findsOneWidget);

      Navigator.of(tester.element(find.text('MindAid target'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sleep diary storage'));
      await tester.pumpAndSettle();
      expect(find.text('Sleep target'), findsOneWidget);
    },
  );
}
