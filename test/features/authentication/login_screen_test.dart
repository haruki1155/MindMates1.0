import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/authentication/screens/login_screen.dart';
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
  testWidgets('login uses School ID label and validation copy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_LoginHarness(authProvider: authProvider));

    expect(find.textContaining('Unofficial'), findsNothing);
    expect(find.text('School ID'), findsOneWidget);
    expect(find.text('Email'), findsNothing);

    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.text('Enter your School ID and password.'), findsOneWidget);
    expect(authProvider.signInCalls, 0);
  });

  testWidgets('login submits the School ID as the primary credential', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_LoginHarness(authProvider: authProvider));

    await tester.enterText(
      find.widgetWithText(TextField, 'School ID'),
      'UCU 2026-0001',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );

    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(authProvider.signInCalls, 1);
    expect(authProvider.schoolId, 'UCU 2026-0001');
    expect(find.text('home target'), findsOneWidget);
  });
}

class _LoginHarness extends StatelessWidget {
  const _LoginHarness({required this.authProvider});

  final AuthProvider authProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<UserProvider>(
          create: (_) => UserProvider(_FakeUserRepository()),
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
          RouteNames.home: (_) =>
              const Scaffold(body: Center(child: Text('home target'))),
        },
      ),
    );
  }
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(_FakeAuthRepository());

  int signInCalls = 0;
  String? schoolId;

  @override
  Future<String?> signIn({
    required String schoolId,
    required String password,
  }) async {
    signInCalls += 1;
    this.schoolId = schoolId;
    return 'user_1';
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(AuthService());
}

class _FakeUserRepository extends UserRepository {
  @override
  Future<UserModel?> fetchUserProfile(String uid) async {
    return UserModel(id: uid, email: 'user@mindmate.local');
  }
}

class _FakeAssessmentRepository extends AssessmentRepository {
  @override
  Future<bool> ensureQuickAssessmentCompletion(String userId) async => true;
}
