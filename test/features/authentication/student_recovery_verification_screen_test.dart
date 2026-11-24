import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/authentication/screens/email_verification_screen.dart';
import 'package:mind_mates/features/authentication/screens/student_recovery_verification_screen.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/repositories/student_roster_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

const _alias = '202012345@students.mindmate.local';
const _masked = 'a***@example.com';

void main() {
  testWidgets('requests one code on open and shows only the masked recovery address', (
    tester,
  ) async {
    final auth = _FakeAuthProvider();
    await _pump(tester, auth);

    expect(auth.requests, 1);
    expect(find.textContaining(_masked), findsOneWidget);
    expect(find.byKey(const Key('recovery-code-field')), findsOneWidget);
    expect(find.textContaining('mindmate.local'), findsNothing);
    expect(find.textContaining(_alias), findsNothing);
  });

  testWidgets('an account that is already verified moves straight on', (tester) async {
    final auth = _FakeAuthProvider()..alreadyVerified = true;
    await _pump(tester, auth, gated: true);
    expect(find.text('student info target'), findsOneWidget);
    expect(auth.confirmed, isEmpty);
  });

  testWidgets('a missing or malformed code is rejected before any request', (tester) async {
    final auth = _FakeAuthProvider();
    await _pump(tester, auth);

    await tester.tap(find.byKey(const Key('recovery-verify-button')));
    await tester.pump();
    expect(find.text('Enter the 10-character code from your email.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('recovery-code-field')), 'ABC');
    await tester.tap(find.byKey(const Key('recovery-verify-button')));
    await tester.pump();
    expect(find.text('Enter the 10-character code from your email.'), findsOneWidget);
    expect(auth.confirmed, isEmpty);
  });

  testWidgets('a correct code verifies and continues to the Student Information gate', (
    tester,
  ) async {
    final auth = _FakeAuthProvider();
    await _pump(tester, auth, gated: true);

    await tester.enterText(find.byKey(const Key('recovery-code-field')), 'abcde-fghjk');
    await tester.tap(find.byKey(const Key('recovery-verify-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(auth.confirmed, ['ABCDE-FGHJK']);
    expect(find.text('student info target'), findsOneWidget);
    expect(find.text('home target'), findsNothing);
  });

  testWidgets('a verified email finishes the setup before loading the profile', (
    tester,
  ) async {
    final auth = _FakeAuthProvider();
    await _pump(tester, auth, gated: true);

    await tester.enterText(find.byKey(const Key('recovery-code-field')), 'abcde-fghjk');
    await tester.tap(find.byKey(const Key('recovery-verify-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(auth.completions, 1);
    expect(find.text('student info target'), findsOneWidget);
  });

  testWidgets('a profile that cannot be loaded offers Try again and never opens profile setup', (
    tester,
  ) async {
    final auth = _FakeAuthProvider();
    final users = _FakeUserRepository(gated: true, failLoads: 3);
    await _pump(tester, auth, users: users);

    await tester.enterText(find.byKey(const Key('recovery-code-field')), 'abcde-fghjk');
    await tester.tap(find.byKey(const Key('recovery-verify-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(users.loads, 3, reason: 'bounded retries');
    expect(find.text('profile setup target'), findsNothing);
    expect(find.byKey(const Key('recovery-finish-retry')), findsOneWidget);
    expect(find.textContaining('could not finish setting up'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recovery-finish-retry')));
    await tester.pumpAndSettle();
    expect(find.text('student info target'), findsOneWidget);
    expect(auth.completions, greaterThan(1), reason: 'the finish step is repeated safely');
  });

  testWidgets('a verified email that is not yet approved waits instead of opening the account', (
    tester,
  ) async {
    final auth = _FakeAuthProvider()..completeStatus = 'awaiting-approval';
    await _pump(tester, auth, gated: true);

    await tester.enterText(find.byKey(const Key('recovery-code-field')), 'abcde-fghjk');
    await tester.tap(find.byKey(const Key('recovery-verify-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('awaiting-approval-title')), findsOneWidget);
    expect(find.text('student info target'), findsNothing);
    expect(find.text('profile setup target'), findsNothing);
    expect(find.text('home target'), findsNothing);

    // Still waiting: the student stays on the waiting screen.
    await tester.tap(find.byKey(const Key('awaiting-approval-check')));
    await tester.pumpAndSettle();
    expect(find.text('Still waiting for approval.'), findsOneWidget);

    // Once approved, checking again opens the account.
    auth.completeStatus = 'approved';
    await tester.tap(find.byKey(const Key('awaiting-approval-check')));
    await tester.pumpAndSettle();
    expect(find.text('student info target'), findsOneWidget);
  });

  testWidgets('a waiting student can sign out', (tester) async {
    final auth = _FakeAuthProvider()
      ..completeStatus = 'awaiting-approval'
      ..alreadyVerified = true;
    await _pump(tester, auth);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('awaiting-approval-title')), findsOneWidget);
    await tester.tap(find.byKey(const Key('awaiting-approval-sign-out')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(auth.signOuts, 1);
    expect(find.text('login target'), findsOneWidget);
  });

  testWidgets('a wrong code shows the server message and stays on the screen', (tester) async {
    final auth = _FakeAuthProvider()
      ..confirmError = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'That code is not correct. Check it or request a new one.',
        details: {'reason': 'invalid-code', 'attemptsRemaining': 3},
      );
    await _pump(tester, auth, gated: true);

    await tester.enterText(find.byKey(const Key('recovery-code-field')), 'ZZZZZ-ZZZZZ');
    await tester.tap(find.byKey(const Key('recovery-verify-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('That code is not correct'), findsOneWidget);
    expect(find.text('student info target'), findsNothing);
    expect(find.byKey(const Key('recovery-code-field')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('recovery-verify-button'))).onPressed, isNotNull);
  });

  testWidgets('resending is throttled by a cooldown and then allowed again', (tester) async {
    final auth = _FakeAuthProvider();
    await _pump(tester, auth);

    expect(find.textContaining('Resend in'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recovery-resend-button')));
    await tester.pump();
    expect(auth.requests, 1, reason: 'still cooling down');

    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Resend code'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recovery-resend-button')));
    await tester.pump();
    expect(auth.requests, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a delivery failure is reported and can be retried', (tester) async {
    final auth = _FakeAuthProvider()
      ..requestError = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'The verification email could not be delivered. Please try again shortly.',
      );
    await _pump(tester, auth);

    expect(find.textContaining('could not be delivered'), findsOneWidget);
    expect(find.text('Resend code'), findsOneWidget, reason: 'no cooldown after a failure');
  });

  testWidgets('using another email explains the effect without the alias and cancels the registration', (
    tester,
  ) async {
    final auth = _FakeAuthProvider();
    await _pump(tester, auth);

    await tester.ensureVisible(find.byKey(const Key('recovery-use-another-email')));
    await tester.tap(find.byKey(const Key('recovery-use-another-email')));
    await tester.pumpAndSettle();
    expect(find.text('Use another email?'), findsOneWidget);
    expect(find.textContaining('mindmate.local'), findsNothing);

    await tester.tap(find.text('Keep this email'));
    await tester.pumpAndSettle();
    expect(auth.cancelled, 0);

    await tester.tap(find.byKey(const Key('recovery-use-another-email')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Use another email'));
    await tester.pumpAndSettle();
    expect(auth.cancelled, 1);
    expect(find.text('login request target'), findsOneWidget);
  });

  group('EmailVerificationGate', () {
    testWidgets('a Student ID account gets the code screen', (tester) async {
      await _pump(tester, _FakeAuthProvider(), useGate: true);
      expect(find.byType(StudentRecoveryVerificationScreen), findsOneWidget);
      expect(find.byType(EmailVerificationScreen), findsNothing);
    });

    testWidgets('every other account keeps the existing link screen', (tester) async {
      await _pump(tester, _FakeAuthProvider()..email = 'teacher@example.com', useGate: true);
      expect(find.byType(EmailVerificationScreen), findsOneWidget);
      expect(find.byType(StudentRecoveryVerificationScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAuthProvider auth, {
  bool gated = false,
  bool useGate = false,
  _FakeUserRepository? users,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<UserProvider>(
          create: (_) => UserProvider(users ?? _FakeUserRepository(gated: gated)),
        ),
      ],
      child: MaterialApp(
        routes: {
          RouteNames.profileSetup: (_) => const Scaffold(body: Text('profile setup target')),
          RouteNames.studentInformation: (_) => const Scaffold(body: Text('student info target')),
          RouteNames.studentLoginRequest: (_) => const Scaffold(body: Text('login request target')),
          RouteNames.home: (_) => const Scaffold(body: Text('home target')),
          RouteNames.login: (_) => const Scaffold(body: Text('login target')),
        },
        home: useGate ? const EmailVerificationGate() : const StudentRecoveryVerificationScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(AuthService());

  @override
  String? get currentUserId => 'u1';
}

class _FakeUserRepository extends UserRepository {
  _FakeUserRepository({required this.gated, this.failLoads = 0});
  final bool gated;
  int failLoads;
  int loads = 0;

  @override
  Future<UserModel?> fetchUserProfile(String uid) async {
    loads++;
    if (failLoads > 0) {
      failLoads--;
      throw FirebaseFunctionsException(code: 'unavailable', message: 'offline');
    }
    return _profile(uid);
  }

  UserModel _profile(String uid) => UserModel(
    id: uid,
    email: 'ana@example.com',
    populationRole: PopulationRole.student,
    personalInfoRequired: gated,
  );
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(_FakeAuthRepository());

  String? email = _alias;
  bool alreadyVerified = false;
  Object? requestError;
  Object? confirmError;
  int requests = 0;
  int cancelled = 0;
  final confirmed = <String>[];

  @override
  String? get currentUserEmail => email;

  @override
  bool get currentUserEmailVerified => false;

  @override
  String? get userId => 'u1';

  @override
  Future<void> reloadCurrentUser() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<RecoveryCodeRequest> requestRecoveryEmailCode() async {
    requests++;
    final error = requestError;
    if (error != null) throw error;
    return RecoveryCodeRequest(
      alreadyVerified: alreadyVerified,
      maskedEmail: _masked,
      expiresInSeconds: 900,
    );
  }

  @override
  Future<void> confirmRecoveryEmailCode(String code) async {
    final error = confirmError;
    if (error != null) throw error;
    confirmed.add(code);
  }

  @override
  Future<void> cancelPendingRegistration() async => cancelled++;

  int completions = 0;
  final order = <String>[];

  String completeStatus = 'approved';

  @override
  Future<String> completeStudentAccountSetup() async {
    completions++;
    order.add('complete');
    return completeStatus;
  }

  int signOuts = 0;

  @override
  Future<void> signOut() async => signOuts++;
}
