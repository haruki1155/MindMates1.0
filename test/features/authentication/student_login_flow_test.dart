import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' show UserCredential;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/authentication/auth_flow_routes.dart';
import 'package:mind_mates/features/authentication/screens/student_change_password_screen.dart';
import 'package:mind_mates/features/authentication/screens/student_login_request_screen.dart';
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

UserModel _student({bool mustChange = false, bool info = false}) => UserModel(
  id: 'u1',
  email: 'student@example.com',
  schoolId: 'QA-2026-0001',
  populationRole: PopulationRole.student,
  mustChangePassword: mustChange,
  personalInfoRequired: info,
);

void main() {
  test('first-login gate comes before Student Information', () {
    expect(
      gateRouteForUser(_student(mustChange: true, info: true)),
      RouteNames.studentChangePassword,
    );
    expect(
      gateRouteForUser(_student(info: true)),
      RouteNames.studentInformation,
    );
    expect(gateRouteForUser(_student()), isNull);
    // Staff and employees have their own first-login handling.
    expect(
      gateRouteForUser(
        const UserModel(
          id: 'e1',
          email: 'e@example.com',
          populationRole: PopulationRole.teaching,
          mustChangePassword: true,
        ),
      ),
      isNull,
    );
  });

  group('request screen', () {
    Future<List<Map<String, Object?>>> pumpRequest(
      WidgetTester tester, {
      Object? error,
    }) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calls = <Map<String, Object?>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StudentLoginRequestScreen(
            repository: StudentRosterRepository(
              invoker: (name, data) async {
                calls.add({'name': name, ...data});
                if (error != null) throw error;
                return {'accepted': true};
              },
            ),
          ),
        ),
      );
      return calls;
    }

    testWidgets('asks for a Student ID and shows one neutral confirmation', (
      tester,
    ) async {
      final calls = await pumpRequest(tester);
      await tester.tap(find.text('Email me my login'));
      await tester.pump();
      expect(find.text('Enter your Student ID.'), findsOneWidget);
      expect(calls, isEmpty);

      await tester.enterText(find.byType(TextFormField), '2021-00123');
      await tester.tap(find.text('Email me my login'));
      await tester.pumpAndSettle();
      expect(calls, [
        {'name': 'requestStudentLogin', 'studentId': '2021-00123'},
      ]);
      expect(
        find.byKey(const Key('login-request-confirmation')),
        findsOneWidget,
      );
      expect(find.text('Login details sent'), findsOneWidget);
      expect(
        find.textContaining('If your Student ID is on the school roster'),
        findsOneWidget,
      );
      expect(find.textContaining('@'), findsNothing);
    });

    testWidgets('renders highlighted confirmation cleanly on 360px mobile', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: StudentLoginRequestScreen(
            repository: StudentRosterRepository(
              invoker: (_, _) async => {'accepted': true},
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), '2021-00123');
      await tester.tap(find.text('Email me my login'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('login-request-confirmation')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'already activated Student ID shows red dialogue directing student to PACC office on 360px mobile',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: StudentLoginRequestScreen(
              repository: StudentRosterRepository(
                invoker: (_, _) async => {
                  'accepted': false,
                  'alreadyActivated': true,
                },
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextFormField), '2021-00123');
        await tester.tap(find.text('Email me my login'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('login-request-already-activated')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('login-request-confirmation')),
          findsNothing,
        );
        expect(find.text('Account already activated'), findsOneWidget);
        expect(
          find.textContaining('already has an active MindMate account'),
          findsOneWidget,
        );
        expect(find.textContaining('visit the PACC office'), findsOneWidget);
        expect(find.textContaining('@'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a failure is reported without hinting at the account', (
      tester,
    ) async {
      await pumpRequest(
        tester,
        error: FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'Too many requests.',
        ),
      );
      await tester.enterText(find.byType(TextFormField), '2021-00123');
      await tester.tap(find.text('Email me my login'));
      await tester.pumpAndSettle();
      expect(find.textContaining('try again later'), findsOneWidget);
      expect(find.textContaining('If your Student ID'), findsNothing);
    });
  });

  group('change password screen', () {
    late List<Map<String, Object?>> calls;
    late _FakeAuthRepository auth;

    Future<void> pumpChange(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      calls = [];
      auth = _FakeAuthRepository();
      final userProvider = UserProvider(_FakeUserRepository())
        ..setUser(_student(mustChange: true, info: true));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: AuthProvider(auth)),
            ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ],
          child: MaterialApp(
            home: StudentChangePasswordScreen(
              repository: StudentRosterRepository(
                invoker: (name, data) async {
                  calls.add({'name': name, ...data});
                  return {'ok': true};
                },
              ),
            ),
            routes: {
              RouteNames.studentInformation: (_) => const Scaffold(
                body: Center(child: Text('student information target')),
              ),
            },
          ),
        ),
      );
    }

    testWidgets('enforces the password policy before calling the server', (
      tester,
    ) async {
      await pumpChange(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'short');
      await tester.enterText(fields.at(1), 'short');
      await tester.tap(find.text('Save password'));
      await tester.pump();
      expect(find.text('Use at least 10 characters.'), findsOneWidget);
      await tester.enterText(fields.at(0), 'Str0ngPerm!9');
      await tester.enterText(fields.at(1), 'Str0ngPerm!8');
      await tester.tap(find.text('Save password'));
      await tester.pump();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('on success signs in again and opens Student Information', (
      tester,
    ) async {
      await pumpChange(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Str0ngPerm!9');
      await tester.enterText(fields.at(1), 'Str0ngPerm!9');
      await tester.tap(find.text('Save password'));
      await tester.pumpAndSettle();
      expect(calls, [
        {'name': 'completeStudentPasswordChange', 'newPassword': 'Str0ngPerm!9'},
      ]);
      expect(auth.studentIdSignIns, ['QA-2026-0001']);
      expect(find.text('student information target'), findsOneWidget);
    });
  });
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(AuthService());
  final studentIdSignIns = <String>[];

  @override
  String? get currentUserId => 'u1';

  @override
  Future<UserCredential> signInWithStudentId({
    required String studentId,
    required String password,
  }) async {
    studentIdSignIns.add(studentId);
    return _FakeCredential();
  }
}

class _FakeCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUserRepository extends UserRepository {
  @override
  Future<UserModel?> fetchUserProfile(String uid) async => _student(info: true);
}
