import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/authentication/auth_flow_routes.dart';
import 'package:mind_mates/features/splash/screens/splash_screen.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('splash clips the square logo asset to a circle', (tester) async {
    await tester.pumpWidget(
      _SplashHarness(
        authProvider: AuthProvider(_FakeAuthRepository()),
        userProvider: UserProvider(_FakeUserRepository()),
      ),
    );

    expect(find.byType(ClipOval), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1901));
    await tester.pumpAndSettle();
  });

  testWidgets('splash routes signed out users to login', (tester) async {
    await tester.pumpWidget(
      _SplashHarness(
        authProvider: AuthProvider(_FakeAuthRepository()),
        userProvider: UserProvider(_FakeUserRepository()),
      ),
    );

    await tester.pump(const Duration(milliseconds: 1901));
    await tester.pumpAndSettle();

    expect(find.text('login target'), findsOneWidget);
  });

  testWidgets('splash routes signed in users to home and loads profile', (
    tester,
  ) async {
    final userRepository = _FakeUserRepository(
      user: const UserModel(id: 'user_1', email: 'leo@example.com'),
    );

    await tester.pumpWidget(
      _SplashHarness(
        authProvider: AuthProvider(
          _FakeAuthRepository(currentUserId: 'user_1'),
        ),
        userProvider: UserProvider(userRepository),
      ),
    );

    await tester.pump(const Duration(milliseconds: 1901));
    await tester.pumpAndSettle();

    expect(find.text('home target'), findsOneWidget);
    expect(userRepository.loadedUid, 'user_1');
  });

  test('post-auth destination opens onboarding before quick assessment', () {
    expect(
      destinationAfterAuthentication(hasCompletedQuickAssessment: false),
      RouteNames.onboarding,
    );
  });

  test('post-auth destination opens home after quick assessment', () {
    expect(
      destinationAfterAuthentication(hasCompletedQuickAssessment: true),
      RouteNames.home,
    );
  });
}

class _SplashHarness extends StatelessWidget {
  const _SplashHarness({
    required this.authProvider,
    required this.userProvider,
  });

  final AuthProvider authProvider;
  final UserProvider userProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ChangeNotifierProvider<AssessmentProvider>(
          create: (_) => AssessmentProvider(_FakeAssessmentRepository()),
        ),
      ],
      child: MaterialApp(
        initialRoute: RouteNames.splash,
        routes: {
          RouteNames.splash: (_) => const SplashScreen(),
          RouteNames.login: (_) => const _RouteMarker('login target'),
          RouteNames.home: (_) => const _RouteMarker('home target'),
        },
      ),
    );
  }
}

class _RouteMarker extends StatelessWidget {
  const _RouteMarker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.currentUserId}) : super(AuthService());

  @override
  final String? currentUserId;
}

class _FakeUserRepository extends UserRepository {
  _FakeUserRepository({this.user});

  final UserModel? user;
  String? loadedUid;

  @override
  Future<UserModel?> fetchUserProfile(String uid) async {
    loadedUid = uid;
    return user;
  }
}

class _FakeAssessmentRepository extends AssessmentRepository {
  @override
  Future<bool> ensureQuickAssessmentCompletion(String userId) async => true;
}
