import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/admin_main.dart';
import 'package:mind_mates/app.dart';
import 'package:mind_mates/app_bootstrap.dart';

void main() {
  test('web selects the admin portal root', () {
    final root = selectMindMateRoot(
      isWeb: true,
      mobileApp: const MindMateApp(),
    );

    expect(root, isA<MindMateAdminApp>());
  });

  test('native platforms preserve the mobile application root', () {
    const mobileApp = MindMateApp();

    final root = selectMindMateRoot(isWeb: false, mobileApp: mobileApp);

    expect(identical(root, mobileApp), isTrue);
  });

  testWidgets('admin root displays staff login instead of mobile startup', (
    tester,
  ) async {
    await tester.pumpWidget(
      selectMindMateRoot(
        isWeb: true,
        mobileApp: const MaterialApp(home: Text('Mobile application')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MindMate'), findsOneWidget);
    expect(find.text('Counseling Management System'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Mobile application'), findsNothing);
  });

  testWidgets('bootstrap renders its child after initialization succeeds', (
    tester,
  ) async {
    await tester.pumpWidget(
      AppBootstrap(
        initializer: () async {},
        child: const MaterialApp(home: Text('Application ready')),
      ),
    );
    expect(find.text('Starting MindMate…'), findsOneWidget);
    await tester.pump();
    expect(find.text('Application ready'), findsOneWidget);
  });

  testWidgets(
    'bootstrap shows a retryable diagnostic after initialization fails',
    (tester) async {
      var attempts = 0;
      Future<void> initialize() async {
        attempts++;
        if (attempts == 1) throw StateError('firebase-unavailable');
      }

      await tester.pumpWidget(
        AppBootstrap(
          initializer: initialize,
          child: const MaterialApp(home: Text('Application ready')),
        ),
      );
      await tester.pump();
      expect(find.text('MindMate could not start'), findsOneWidget);
      expect(find.text('Startup code: firebase-unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.text('Application ready'), findsOneWidget);
    },
  );
}
