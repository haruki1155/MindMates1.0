import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:mind_mates/main.dart' as app;
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/mind_aid_provider.dart';
import 'package:mind_mates/features/counseling/screens/mind_aid_screen.dart';
import 'package:mind_mates/features/counseling/screens/pacc_counseling_screen.dart';
import 'package:mind_mates/features/counseling/screens/services_screen.dart';
import 'package:mind_mates/features/authentication/screens/login_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('authenticated MindAid replies and action destinations', (
    tester,
  ) async {
    final originalErrorHandler = FlutterError.onError;
    Future<void> waitFor(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(
        ready(),
        isTrue,
        reason: 'Timed out waiting for the authenticated UI',
      );
    }

    try {
      app.main();
      await waitFor(
        () =>
            find.byType(LoginScreen).evaluate().isNotEmpty ||
            find.text('Message').evaluate().isNotEmpty,
      );
      if (find.byType(LoginScreen).evaluate().isNotEmpty) {
        const schoolId = String.fromEnvironment('MINDAID_TEST_SCHOOL_ID');
        const password = String.fromEnvironment('MINDAID_TEST_PASSWORD');
        expect(schoolId, isNotEmpty, reason: 'A test account is required.');
        expect(password, isNotEmpty, reason: 'A test password is required.');
        await tester.enterText(find.byType(TextField).at(0), schoolId);
        await tester.enterText(find.byType(TextField).at(1), password);
        await tester.pump();
        await tester.tap(find.text('Sign in').last);
      }
      await waitFor(() => find.text('Message').evaluate().isNotEmpty);
      await tester.pump(const Duration(seconds: 2));
      final chatTab = find
          .ancestor(of: find.text('Message'), matching: find.byType(InkWell))
          .hitTestable();
      await waitFor(() => chatTab.evaluate().isNotEmpty);
      await tester.tap(chatTab.last);
      await waitFor(() => find.byType(MindAidScreen).evaluate().isNotEmpty);
      final context = tester.element(find.byType(MindAidScreen));
      final provider = context.read<MindAidProvider>();
      expect(
        context.read<AuthProvider>().userId,
        isNotNull,
        reason: 'Requires an already authenticated account',
      );
      await waitFor(() => !provider.isLoading);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      Future<void> send(String text) async {
        await waitFor(() => !provider.isSending && !provider.isLoading);
        final previousCount = provider.messages.length;
        final composer = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Type your message...',
        );
        expect(composer, findsOneWidget);
        await tester.tap(composer);
        await tester.pump();
        await tester.enterText(composer, text);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(composer).controller!.text, text);
        final sendButtonFinder = find.descendant(
          of: find.byTooltip('Send message'),
          matching: find.byType(IconButton),
        );
        final sendButton = tester.widget<IconButton>(sendButtonFinder);
        expect(sendButton.onPressed, isNotNull);
        await tester.tap(sendButtonFinder);
        await tester.pump();
        await waitFor(
          () =>
              provider.messages.length >= previousCount + 2 &&
              !provider.isSending &&
              !provider.isLoading,
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(provider.lastFailedText, isNull);
      }

      await send('How do I schedule an appointment?');
      expect(provider.messages.last.text, contains('appointment options'));
      await tester.ensureVisible(find.text('View appointment options').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('View appointment options').last);
      await waitFor(
        () => find.byType(PaccCounselingScreen).evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<PaccCounselingScreen>(find.byType(PaccCounselingScreen))
            .startBooking,
        isFalse,
      );
      Navigator.of(tester.element(find.byType(PaccCounselingScreen))).pop();
      await waitFor(() => find.byType(MindAidScreen).evaluate().isNotEmpty);
      await waitFor(
        () => provider.messages.last.text.contains('preparing what to discuss'),
      );
      await waitFor(() => !provider.isSending && !provider.isLoading);
      expect(
        provider.messages.any(
          (message) => message.text.contains('appointment options'),
        ),
        isTrue,
      );
      await send('What services does PAACC provide?');
      expect(provider.messages.last.text, contains('available services'));
      expect(provider.messages.last.actions, isNotEmpty);
      await tester.scrollUntilVisible(
        find.text('View PACC services').last,
        250,
        scrollable: find
            .descendant(
              of: find.byType(MindAidScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('View PACC services').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('View PACC services').last);
      await waitFor(() => find.byType(ServicesScreen).evaluate().isNotEmpty);
      Navigator.of(tester.element(find.byType(ServicesScreen))).pop();
      await waitFor(() => find.byType(MindAidScreen).evaluate().isNotEmpty);
      await waitFor(
        () => provider.messages.last.text.contains('support service'),
      );
      await send('How does self-assessment work?');
      expect(provider.messages.last.text, contains('not a diagnosis'));
      expect(find.byType(MindAidScreen), findsOneWidget);
      await send('Can you give me a recipe for spaghetti?');
      expect(provider.messages.last.text, contains('make sure I understand'));
      expect(provider.messages.last.actions, isEmpty);
    } finally {
      FlutterError.onError = originalErrorHandler;
    }
  });
}
