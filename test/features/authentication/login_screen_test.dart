import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/authentication/screens/login_screen.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('login uses the Student ID label and validation copy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_LoginHarness(authProvider: authProvider));

    expect(find.textContaining('Unofficial'), findsNothing);
    expect(find.text('Student ID'), findsOneWidget);
    expect(find.text('School ID'), findsNothing);
    expect(find.text('Email'), findsNothing);

    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.text('Enter your Student ID and password.'), findsOneWidget);
    expect(authProvider.studentIdCalls, 0);
    expect(authProvider.signInCalls, 0);
  });

  testWidgets('login submits the Student ID as the primary credential', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_LoginHarness(authProvider: authProvider));

    await tester.enterText(
      find.widgetWithText(TextField, 'Student ID'),
      'UCU 2026-0001',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );

    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(authProvider.studentIdCalls, 1);
    expect(authProvider.studentId, 'UCU 2026-0001');
    expect(authProvider.signInCalls, 0, reason: 'the legacy path is never used implicitly');
    expect(find.text('home target'), findsOneWidget);
  });

  testWidgets(
    'login offers activation and employee sign up, not Create account',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_LoginHarness(authProvider: _FakeAuthProvider()));

      expect(find.text('Activate student account'), findsOneWidget);
      expect(find.text('Employee sign up'), findsOneWidget);
      expect(find.text('Create account'), findsNothing);

      await tester.ensureVisible(find.text('Activate student account'));
      await tester.tap(find.text('Activate student account'));
      await tester.pumpAndSettle();
      expect(find.text('activation target'), findsOneWidget);
    },
  );

  testWidgets('password sign-in sends a student owing information to the gate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(
      _LoginHarness(
        authProvider: authProvider,
        userRepository: _FakeUserRepository(gated: true),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Student ID'),
      'UCU 2026-0001',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('student information target'), findsOneWidget);
    expect(find.text('home target'), findsNothing);
  });

  testWidgets('Google sign-in sends a student owing information to the gate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(
      _LoginHarness(
        authProvider: authProvider,
        userRepository: _FakeUserRepository(gated: true),
      ),
    );

    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(authProvider.googleCalls, 1);
    expect(find.text('student information target'), findsOneWidget);
    expect(find.text('home target'), findsNothing);
  });

  testWidgets('Google sign-in with nothing pending still reaches home', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_LoginHarness(authProvider: authProvider));

    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(authProvider.googleCalls, 1);
    expect(find.text('home target'), findsOneWidget);
  });

  testWidgets('employees and older accounts choose the School ID path explicitly', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_LoginHarness(authProvider: authProvider));

    await tester.ensureVisible(find.byKey(const Key('login-path-toggle')));
    await tester.tap(find.byKey(const Key('login-path-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('School ID'), findsOneWidget);
    expect(find.text('Student ID'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'School ID'), 'EMP-001');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'password123');
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(authProvider.signInCalls, 1);
    expect(authProvider.schoolId, 'EMP-001');
    expect(authProvider.studentIdCalls, 0);
  });

  testWidgets('the School ID path has its own validation copy and can be left again', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_LoginHarness(authProvider: _FakeAuthProvider()));
    await tester.ensureVisible(find.byKey(const Key('login-path-toggle')));
    await tester.tap(find.byKey(const Key('login-path-toggle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter your School ID and password.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('login-path-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Student ID'), findsOneWidget);
  });

  testWidgets('a failed Student ID sign-in shows one generic message and never falls back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider()..failStudentId = true;
    await tester.pumpWidget(_LoginHarness(authProvider: authProvider));
    await tester.enterText(find.widgetWithText(TextField, 'Student ID'), '2020-12345');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrong');
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Student ID or password is incorrect.'), findsOneWidget);
    expect(authProvider.studentIdCalls, 1);
    expect(authProvider.signInCalls, 0);
    expect(find.text('home target'), findsNothing);
  });

  testWidgets('an unverified Student ID account is sent to recovery-email verification', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider()
      ..email = '202012345@students.mindmate.local'
      ..emailVerified = false;
    await tester.pumpWidget(_LoginHarness(authProvider: authProvider));
    await tester.enterText(find.widgetWithText(TextField, 'Student ID'), '2020-12345');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'password123');
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('verification target'), findsOneWidget);
    expect(find.text('home target'), findsNothing);
    expect(find.textContaining('mindmate.local'), findsNothing);
  });

  testWidgets('a verified Student ID account continues to the Student Information gate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider()
      ..email = '202012345@students.mindmate.local'
      ..emailVerified = true;
    await tester.pumpWidget(
      _LoginHarness(
        authProvider: authProvider,
        userRepository: _FakeUserRepository(gated: true),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Student ID'), '2020-12345');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'password123');
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('student information target'), findsOneWidget);
  });
}

class _LoginHarness extends StatelessWidget {
  const _LoginHarness({required this.authProvider, this.userRepository});

  final AuthProvider authProvider;
  final UserRepository? userRepository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<UserProvider>(
          create: (_) =>
              UserProvider(userRepository ?? _FakeUserRepository()),
        ),
        ChangeNotifierProvider<AssessmentProvider>(
          create: (_) => AssessmentProvider(_FakeAssessmentRepository()),
        ),
      ],
      child: MaterialApp(
        home: const LoginScreen(),
        routes: {
          RouteNames.onboarding: (_) =>
              const Scaffold(body: Center(child: Text('onboarding target'))),
          RouteNames.studentActivation: (_) =>
              const Scaffold(body: Center(child: Text('activation target'))),
          RouteNames.home: (_) =>
              const Scaffold(body: Center(child: Text('home target'))),
          RouteNames.signup: (_) =>
              const Scaffold(body: Center(child: Text('signup target'))),
          RouteNames.studentInformation: (_) => const Scaffold(
            body: Center(child: Text('student information target')),
          ),
          RouteNames.emailVerification: (_) =>
              const Scaffold(body: Center(child: Text('verification target'))),
        },
      ),
    );
  }
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(_FakeAuthRepository());

  int signInCalls = 0;
  int studentIdCalls = 0;
  int googleCalls = 0;
  String? schoolId;
  String? studentId;
  bool failStudentId = false;
  String? email;
  bool emailVerified = true;
  String? _error;

  @override
  String? get errorMessage => _error;

  @override
  Future<String?> signInWithStudentId({
    required String studentId,
    required String password,
  }) async {
    studentIdCalls += 1;
    this.studentId = studentId;
    if (failStudentId) {
      _error = 'Student ID or password is incorrect.';
      return null;
    }
    return 'user_1';
  }

  @override
  Future<String?> signIn({
    required String schoolId,
    required String password,
  }) async {
    signInCalls += 1;
    this.schoolId = schoolId;
    return 'user_1';
  }

  @override
  Future<String?> signInWithGoogle() async {
    googleCalls += 1;
    return 'user_1';
  }

  @override
  String? get currentUserEmail => email;

  @override
  bool get currentUserEmailVerified => emailVerified;
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(AuthService());
}

class _FakeUserRepository extends UserRepository {
  _FakeUserRepository({this.gated = false});

  /// A legacy student who still owes the mandatory Student Information form.
  final bool gated;

  @override
  Future<UserModel?> fetchUserProfile(String uid) async {
    return UserModel(
      id: uid,
      email: 'user@mindmate.local',
      populationRole: gated ? PopulationRole.student : null,
      personalInfoRequired: gated,
    );
  }
}

class _FakeAssessmentRepository extends AssessmentRepository {
  @override
  Future<bool> ensureQuickAssessmentCompletion(String userId) async => true;
}
