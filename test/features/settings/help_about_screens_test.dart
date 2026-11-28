import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/settings/screens/about_screen.dart';
import 'package:mind_mates/features/settings/screens/help_screen.dart';
import 'package:mind_mates/core/widgets/mindmate_terms_and_conditions.dart';

void main() {
  testWidgets('Help shows offline feature guidance and opens PACC email', (
    tester,
  ) async {
    Uri? openedUri;
    await tester.pumpWidget(
      MaterialApp(
        home: HelpScreen(
          launchEmail: (uri) async {
            openedUri = uri;
            return true;
          },
        ),
      ),
    );

    for (final topic in [
      'Account and profile',
      'Assessments',
      'Mood and Sleep',
      'Appointments and inquiries',
      'MindAid',
      'Notifications and reminders',
      'Privacy',
    ]) {
      expect(find.text(topic), findsOneWidget);
    }
    await tester.tap(find.text('MindAid'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not monitored in real time'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Email PACC Counseling Services'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Email PACC Counseling Services'));
    await tester.pump();
    expect(openedUri?.scheme, 'mailto');
    expect(openedUri?.path, 'pacc@ucu.edu.ph');
  });

  testWidgets('About explains MindMate and opens the existing Terms dialog', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));

    expect(
      find.text(
        'MindMate supports mental health awareness, reflection, and access to counseling resources.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('does not replace professional care'),
      findsOneWidget,
    );

    await tester.tap(find.text('Terms and Conditions'));
    await tester.pumpAndSettle();
    expect(find.text(mindMateTermsAndConditionsTitle), findsWidgets);
    expect(find.textContaining('Data Privacy Act of 2012'), findsOneWidget);
  });
}
