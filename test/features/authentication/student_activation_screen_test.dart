import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' show UserCredential;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/authentication/screens/student_activation_screen.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/repositories/student_roster_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Object? error,
    List<Map<String, Object?>>? calls,
    _FakeAuthRepository? auth,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = StudentRosterRepository(
      invoker: (name, data) async {
        calls?.add({'name': name, ...data});
        if (error != null) throw error;
        return {'email': 'Leo@Example.com'};
      },
    );
    final provider = AuthProvider(
      auth ?? _FakeAuthRepository(),
      rosterRepository: repo,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: provider,
        child: MaterialApp(
          home: const StudentActivationScreen(),
          routes: {
            RouteNames.emailVerification: (_) =>
                const Scaffold(body: Center(child: Text('verify target'))),
            RouteNames.login: (_) =>
                const Scaffold(body: Center(child: Text('login target'))),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillStep1(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Student No.'),
      '2021-00123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Activation code'),
      'abcde-23456',
    );
    await tester.tap(find.text('Select date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> toStep2(WidgetTester tester) async {
    await fillStep1(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  Future<void> fillStep2(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'leo@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm Password'),
      'password123',
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text('Activate account'));
    await tester.pumpAndSettle();
  }

  FirebaseFunctionsException failure(String code, String reason, String msg) =>
      FirebaseFunctionsException(
        code: code,
        message: msg,
        details: {'reason': reason},
      );

  testWidgets('step 1 shows hint, helper and gates Continue', (tester) async {
    await pump(tester);

    expect(find.text('XXXXX-XXXXX'), findsOneWidget);
    expect(
      find.text('Your activation code is on the slip from the PACC office.'),
      findsOneWidget,
    );
    FilledButton continueButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(continueButton().onPressed, isNull);

    await fillStep1(tester);
    expect(continueButton().onPressed, isNotNull);
    // Auto-uppercase.
    expect(find.text('ABCDE-23456'), findsOneWidget);
  });

  testWidgets('step 2 requires valid email and matching passwords', (
    tester,
  ) async {
    final calls = <Map<String, Object?>>[];
    await pump(tester, calls: calls);
    await toStep2(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'not-an-email',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'short',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm Password'),
      'different',
    );
    await submit(tester);

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('success activates, signs in and opens email verification', (
    tester,
  ) async {
    final calls = <Map<String, Object?>>[];
    final auth = _FakeAuthRepository();
    await pump(tester, calls: calls, auth: auth);
    await toStep2(tester);
    await fillStep2(tester);
    await submit(tester);

    expect(calls.single['name'], 'activateStudentAccount');
    expect(calls.single['studentNo'], '2021-00123');
    expect(calls.single['activationCode'], 'ABCDE-23456');
    expect(calls.single['dateOfBirth'], matches(RegExp(r'^\d{4}-\d{2}-15$')));
    expect(auth.signedInEmail, 'Leo@Example.com');
    expect(auth.verificationSent, isTrue);
    expect(find.text('verify target'), findsOneWidget);
  });

  testWidgets('not-found shows exactly the generic mismatch copy', (
    tester,
  ) async {
    await pump(tester, error: failure('not-found', 'mismatch', 'server text'));
    await toStep2(tester);
    await fillStep2(tester);
    await submit(tester);

    expect(find.text("Those details don't match our records."), findsOneWidget);
    expect(find.text('verify target'), findsNothing);
  });

  testWidgets('deadline-exceeded shows the expired copy', (tester) async {
    await pump(
      tester,
      error: failure('deadline-exceeded', 'expired', 'server text'),
    );
    await toStep2(tester);
    await fillStep2(tester);
    await submit(tester);

    expect(
      find.text(
        'This activation code has expired. Ask the PACC office for a new one.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('already activated shows copy plus a Sign in button', (
    tester,
  ) async {
    await pump(
      tester,
      error: failure('already-exists', 'already-activated', 'server text'),
    );
    await toStep2(tester);
    await fillStep2(tester);
    await submit(tester);

    expect(
      find.text(
        'This account is already activated. Sign in or use Forgot password.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('login target'), findsOneWidget);
  });

  testWidgets('email in use shows its own copy', (tester) async {
    await pump(
      tester,
      error: failure('already-exists', 'email-in-use', 'server text'),
    );
    await toStep2(tester);
    await fillStep2(tester);
    await submit(tester);

    expect(
      find.text('This email address is already registered.'),
      findsOneWidget,
    );
  });

  testWidgets('invalid input shows the server message', (tester) async {
    await pump(
      tester,
      error: failure('invalid-argument', 'invalid-input', 'Check the date.'),
    );
    await toStep2(tester);
    await fillStep2(tester);
    await submit(tester);

    expect(find.text('Check the date.'), findsOneWidget);
  });

  testWidgets('network/unknown failures never show the mismatch copy', (
    tester,
  ) async {
    await pump(
      tester,
      error: FirebaseFunctionsException(
        code: 'unavailable',
        message: 'offline',
      ),
    );
    await toStep2(tester);
    await fillStep2(tester);
    await submit(tester);

    expect(
      find.text(
        "We couldn't complete activation right now. Check your connection and try again.",
      ),
      findsOneWidget,
    );
    expect(find.text("Those details don't match our records."), findsNothing);
  });
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(AuthService());

  String? signedInEmail;
  bool verificationSent = false;

  @override
  String? get currentUserId => 'user_1';

  @override
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    signedInEmail = email;
    return _FakeCredential();
  }

  @override
  Future<void> sendEmailVerification() async => verificationSent = true;
}

class _FakeCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
