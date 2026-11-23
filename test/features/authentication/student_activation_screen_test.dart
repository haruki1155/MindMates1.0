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
        return {'ok': true, 'authEmail': '202100123@students.mindmate.local'};
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
      find.widgetWithText(TextFormField, 'First name'),
      'Leo',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Last name'),
      'Santos',
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
      find.widgetWithText(TextFormField, 'Password'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm Password'),
      'password123',
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
  }

  FirebaseFunctionsException failure(String code, String msg) =>
      FirebaseFunctionsException(code: code, message: msg);

  testWidgets(
    'step 1 has no activation code and gates Continue on the identity',
    (tester) async {
      await pump(tester);

      expect(find.text('Activation code'), findsNothing);
      expect(find.text('Middle name (optional)'), findsOneWidget);
      FilledButton continueButton() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(continueButton().onPressed, isNull);

      await fillStep1(tester);
      expect(continueButton().onPressed, isNotNull);
    },
  );

  testWidgets('step 2 asks for no email and requires matching passwords', (
    tester,
  ) async {
    final calls = <Map<String, Object?>>[];
    await pump(tester, calls: calls);
    await toStep2(tester);

    // The code goes to the email PACC has on file, so none is typed here.
    expect(
      find.widgetWithText(TextFormField, 'Personal email address'),
      findsNothing,
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

    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets(
    'success starts setup, signs in with the alias and opens email verification',
    (tester) async {
      final calls = <Map<String, Object?>>[];
      final auth = _FakeAuthRepository();
      await pump(tester, calls: calls, auth: auth);
      await toStep2(tester);
      await fillStep2(tester);
      await submit(tester);

      expect(calls.single['name'], 'startStudentAccountSetup');
      expect(calls.single['studentNo'], '2021-00123');
      expect(calls.single['firstName'], 'Leo');
      expect(calls.single['lastName'], 'Santos');
      expect(calls.single['middleName'], '');
      expect(calls.single.containsKey('activationCode'), isFalse);
      expect(calls.single.containsKey('email'), isFalse);
      expect(calls.single['dateOfBirth'], matches(RegExp(r'^\d{4}-\d{2}-15$')));
      expect(auth.signedInEmail, '202100123@students.mindmate.local');
      expect(auth.verificationSent, isFalse);
      expect(find.text('verify target'), findsOneWidget);
    },
  );

  testWidgets('a record with no email on file asks for one, then sends it', (
    tester,
  ) async {
    final calls = <Map<String, Object?>>[];
    final auth = _FakeAuthRepository();
    var attempts = 0;
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = StudentRosterRepository(
      invoker: (name, data) async {
        calls.add({'name': name, ...data});
        if (attempts++ == 0) {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Enter your personal email address.',
            details: {'reason': 'email-required'},
          );
        }
        return {'ok': true, 'authEmail': '202100123@students.mindmate.local'};
      },
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: AuthProvider(auth, rosterRepository: repo),
        child: MaterialApp(
          home: const StudentActivationScreen(),
          routes: {
            RouteNames.emailVerification: (_) =>
                const Scaffold(body: Center(child: Text('verify target'))),
          },
        ),
      ),
    );
    await toStep2(tester);
    await fillStep2(tester);
    await submit(tester);

    // The server asked for an email: the field appears and nothing is claimed yet.
    expect(
      find.widgetWithText(TextFormField, 'Personal email address'),
      findsOneWidget,
    );
    expect(find.text('verify target'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Personal email address'),
      'leo@example.com',
    );
    await submit(tester);

    expect(calls.first.containsKey('email'), isFalse);
    expect(calls.last['email'], 'leo@example.com');
    expect(find.text('verify target'), findsOneWidget);
  });

  testWidgets('not-found shows exactly the generic mismatch copy', (
    tester,
  ) async {
    await pump(tester, error: failure('not-found', 'server text'));
    await toStep2(tester);
    await fillStep2(tester);
    await submit(tester);

    expect(find.text("Those details don't match our records."), findsOneWidget);
    expect(find.text('verify target'), findsNothing);
  });

  testWidgets('email already registered shows its own copy', (tester) async {
    await pump(tester, error: failure('already-exists', 'server text'));
    await toStep2(tester);
    await fillStep2(tester);
    await submit(tester);

    expect(
      find.text("That email address can't be used. Try a different one."),
      findsOneWidget,
    );
  });

  testWidgets('setup already in progress shows its own copy', (tester) async {
    await pump(tester, error: failure('resource-exhausted', 'server text'));
    await toStep2(tester);
    await fillStep2(tester);
    await submit(tester);

    expect(
      find.text(
        'Setup for this record is already in progress. Wait a few minutes and try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('invalid input shows the server message', (tester) async {
    await pump(tester, error: failure('invalid-argument', 'Check the date.'));
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
        "We couldn't complete setup right now. Check your connection and try again.",
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
