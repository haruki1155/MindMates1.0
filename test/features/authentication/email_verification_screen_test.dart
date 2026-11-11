import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/constants/app_colors.dart';
import 'package:mind_mates/features/authentication/screens/email_verification_screen.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

const _verifiedGreen = Color(0xFF2E7D32);
const _notVerifiedMessage =
    'Not verified yet. Open the link in your email, then return here.';

void main() {
  testWidgets('opens with a red Not yet verified badge', (tester) async {
    await _pumpScreen(tester, _FakeAuthProvider());

    expect(_badgeText('Not yet verified'), findsOneWidget);
    expect(
      tester.widget<Text>(_badgeText('Not yet verified')).style?.color,
      AppColors.error,
    );
    expect(_inBadge(find.byIcon(Icons.cancel_outlined)), findsOneWidget);
    expect(find.text('Email verified'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unverified check keeps badge red and shows red message', (
    tester,
  ) async {
    await _pumpScreen(tester, _FakeAuthProvider());

    await tester.tap(find.text('I verified my email'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(_badgeText('Not yet verified')).style?.color,
      AppColors.error,
    );
    expect(
      tester.widget<Text>(find.text(_notVerifiedMessage)).style?.color,
      AppColors.error,
    );
    final statusIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('email-verification-status')),
        matching: find.byType(Icon),
      ),
    );
    expect(statusIcon.color, AppColors.error);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'verified check turns the badge green, then opens profile setup',
    (tester) async {
      final auth = _FakeAuthProvider();
      await _pumpScreen(tester, auth);

      auth.verified = true;
      await tester.tap(find.text('I verified my email'));
      await tester.pump();

      expect(
        tester.widget<Text>(_badgeText('Email verified')).style?.color,
        _verifiedGreen,
      );
      expect(_inBadge(find.byIcon(Icons.verified_rounded)), findsOneWidget);
      expect(find.text('Not yet verified'), findsNothing);
      expect(find.text('profile setup target'), findsNothing);
      final checkButton = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('I verified my email'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(checkButton.onPressed, isNull);

      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();

      expect(find.text('profile setup target'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('check error keeps the badge red and uses error styling', (
    tester,
  ) async {
    final auth = _FakeAuthProvider()..reloadError = Exception('offline');
    await _pumpScreen(tester, auth);

    await tester.tap(find.text('I verified my email'));
    await tester.pumpAndSettle();

    expect(_badgeText('Not yet verified'), findsOneWidget);
    final statusIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('email-verification-status')),
        matching: find.byType(Icon),
      ),
    );
    expect(statusIcon.icon, Icons.error_outline_rounded);
    expect(statusIcon.color, const Color(0xFF923B35));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('verify button is red before verification', (tester) async {
    await _pumpScreen(tester, _FakeAuthProvider());

    expect(
      _checkStyle(tester).backgroundColor!.resolve(<WidgetState>{}),
      AppColors.error,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'verify button stays red after an unverified check and after an error',
    (tester) async {
      await _pumpScreen(tester, _FakeAuthProvider());
      await tester.tap(find.text('I verified my email'));
      await tester.pumpAndSettle();
      expect(
        _checkStyle(tester).backgroundColor!.resolve(<WidgetState>{}),
        AppColors.error,
      );
      await tester.pumpWidget(const SizedBox());

      await _pumpScreen(
        tester,
        _FakeAuthProvider()..reloadError = Exception('offline'),
      );
      await tester.tap(find.text('I verified my email'));
      await tester.pumpAndSettle();
      expect(
        _checkStyle(tester).backgroundColor!.resolve(<WidgetState>{}),
        AppColors.error,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('verify button turns green when verified, even while disabled', (
    tester,
  ) async {
    final auth = _FakeAuthProvider();
    await _pumpScreen(tester, auth);

    auth.verified = true;
    await tester.tap(find.text('I verified my email'));
    await tester.pump();

    final style = _checkStyle(tester);
    expect(style.backgroundColor!.resolve(<WidgetState>{}), _verifiedGreen);
    expect(
      style.backgroundColor!.resolve(<WidgetState>{WidgetState.disabled}),
      _verifiedGreen,
    );
    expect(_checkButton(tester).onPressed, isNull);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(find.text('profile setup target'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'auto-detects verification: button turns green and waits for Continue',
    (tester) async {
      final auth = _FakeAuthProvider();
      await _pumpScreen(tester, auth);

      auth.verified = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(
        tester.widget<Text>(_badgeText('Email verified')).style?.color,
        _verifiedGreen,
      );
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('I verified my email'), findsNothing);
      final button = _buttonFor(tester, 'Continue');
      expect(button.onPressed, isNotNull);
      expect(
        button.style!.backgroundColor!.resolve(<WidgetState>{}),
        _verifiedGreen,
      );

      // Nothing moves on its own.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('profile setup target'), findsNothing);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('profile setup target'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('returning to the app re-checks verification', (tester) async {
    final auth = _FakeAuthProvider();
    await _pumpScreen(tester, auth);

    auth.verified = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('Continue'), findsOneWidget);
    expect(_badgeText('Email verified'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed background check stays silent and red', (tester) async {
    final auth = _FakeAuthProvider()..reloadError = Exception('offline');
    await _pumpScreen(tester, auth);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(_badgeText('Not yet verified'), findsOneWidget);
    expect(find.text('I verified my email'), findsOneWidget);
    expect(
      find.text('Verification email sent. Check your inbox and spam folder.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('email-sent info message stays teal', (tester) async {
    await _pumpScreen(tester, _FakeAuthProvider());

    final text = tester.widget<Text>(
      find.text('Verification email sent. Check your inbox and spam folder.'),
    );
    expect(text.style?.color, AppColors.primary);

    await tester.pumpWidget(const SizedBox());
  });
}

ButtonStyleButton _buttonFor(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );

ButtonStyleButton _checkButton(WidgetTester tester) =>
    _buttonFor(tester, 'I verified my email');

ButtonStyle _checkStyle(WidgetTester tester) => _checkButton(tester).style!;

Finder _inBadge(Finder matching) => find.descendant(
  of: find.byKey(const Key('email-verification-badge')),
  matching: matching,
);

Finder _badgeText(String text) => _inBadge(find.text(text));

Future<void> _pumpScreen(WidgetTester tester, _FakeAuthProvider auth) async {
  await tester.binding.setSurfaceSize(const Size(600, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(
        routes: {
          RouteNames.profileSetup: (_) =>
              const Scaffold(body: Text('profile setup target')),
        },
        home: const EmailVerificationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(AuthService());
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(_FakeAuthRepository());

  bool verified = false;
  Object? reloadError;

  @override
  String? get currentUserEmail => 'leo@example.com';

  @override
  bool get currentUserEmailVerified => verified;

  @override
  Future<void> reloadCurrentUser() async {
    final error = reloadError;
    if (error != null) throw error;
  }

  @override
  Future<void> sendEmailVerification() async {}
}
