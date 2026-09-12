import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/services/auth/auth_service.dart';

void main() {
  test(
    'profile setup failure keeps a recoverable authenticated session',
    () async {
      final repository = _PendingProfileRepository();
      final provider = AuthProvider(repository);

      final userId = await provider.signUp(
        password: 'password',
        firstName: 'Test',
        lastName: 'User',
        schoolId: '2026-0001',
        department: 'Department',
        course: 'Course',
      );

      expect(userId, isNull);
      expect(repository.signOutCalls, 0);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.signupState, SignupState.profileSetupPending);
      expect(provider.errorMessage, contains('App Check'));
      expect(provider.errorMessage, contains('Retry profile setup'));

      final retriedUserId = await provider.signUp(
        password: 'password',
        firstName: 'Test',
        lastName: 'User',
        schoolId: '2026-0001',
        department: 'Department',
        course: 'Course',
      );

      expect(retriedUserId, 'user_1');
      expect(repository.signupCalls, 1);
      expect(repository.profileRetryCalls, 1);
      expect(provider.signupState, SignupState.complete);
    },
  );

  test('authentication failure still clears the session', () async {
    final repository = _AuthenticationFailureRepository();
    final provider = AuthProvider(repository);

    final userId = await provider.signUp(
      password: 'password',
      firstName: 'Test',
      lastName: 'User',
      schoolId: '2026-0001',
      department: 'Department',
      course: 'Course',
    );

    expect(userId, isNull);
    expect(repository.signOutCalls, 1);
    expect(provider.isAuthenticated, isFalse);
    expect(provider.signupState, SignupState.authenticationFailed);
  });

  test('App Check rejection has a distinct signup state', () async {
    final provider = AuthProvider(
      _SignupFailureRepository(
        SignupAppCheckException(
          StateError('Firebase App Check could not verify this app.'),
        ),
      ),
    );

    final userId = await _attemptSignup(provider);

    expect(userId, isNull);
    expect(provider.signupState, SignupState.appCheckRejected);
    expect(provider.errorMessage, contains('debug build is not verified'));
  });

  test('duplicate email has a distinct signup state', () async {
    final provider = AuthProvider(
      _SignupFailureRepository(
        firebase_auth.FirebaseAuthException(code: 'email-already-in-use'),
      ),
    );

    final userId = await _attemptSignup(provider);

    expect(userId, isNull);
    expect(provider.signupState, SignupState.duplicateEmail);
    expect(provider.errorMessage, contains('email address'));
  });

  test('network failure has a distinct signup state', () async {
    final provider = AuthProvider(
      _SignupFailureRepository(
        firebase_auth.FirebaseAuthException(code: 'network-request-failed'),
      ),
    );

    final userId = await _attemptSignup(provider);

    expect(userId, isNull);
    expect(provider.signupState, SignupState.networkFailed);
    expect(provider.errorMessage, contains('internet connection'));
  });

  test('profile lookup failure preserves the authenticated session', () async {
    final repository = _ProfileLookupFailureRepository();
    final provider = AuthProvider(repository);

    final userId = await provider.signUp(
      password: 'password',
      firstName: 'Test',
      lastName: 'User',
      schoolId: '2026-0001',
      department: 'Department',
      course: 'Course',
    );

    expect(userId, isNull);
    expect(repository.signOutCalls, 0);
    expect(provider.isAuthenticated, isTrue);
    expect(provider.signupState, SignupState.profileLookupPending);
    expect(provider.errorMessage, contains('Retry account check'));
  });

  test('live authenticated ID excludes stale cached provider state', () {
    final repository = _MutableAuthRepository(currentUserId: 'user_1');
    final provider = AuthProvider(repository);

    expect(provider.hydrateCurrentUser(), 'user_1');
    repository.currentUserId = null;

    expect(provider.userId, 'user_1');
    expect(provider.authenticatedUserId, isNull);
  });

  test(
    'assessment session resolution restores an authenticated user',
    () async {
      final repository = _MutableAuthRepository(restoredUserId: 'user_2');
      final provider = AuthProvider(repository)..setAuthenticated(true);

      expect(await provider.resolveAuthenticatedUserId(), 'user_2');
      expect(provider.authenticatedUserId, 'user_2');
    },
  );

  test('failed session restoration clears coordinated profile state', () async {
    var clearCalls = 0;
    final provider = AuthProvider(
      _MutableAuthRepository(),
      onSessionCleared: () => clearCalls++,
    );

    expect(await provider.resolveAuthenticatedUserId(), isNull);
    expect(clearCalls, 1);
    expect(provider.isAuthenticated, isFalse);
  });

  test(
    'auth-state monitoring clears profile state after external sign-out',
    () async {
      final repository = _StreamingAuthRepository();
      var clearCalls = 0;
      final provider = AuthProvider(
        repository,
        onSessionCleared: () => clearCalls++,
      )..monitorAuthState();
      addTearDown(() async {
        provider.dispose();
        await repository.controller.close();
      });

      repository.controller.add('user_1');
      await Future<void>.delayed(Duration.zero);
      expect(provider.isAuthenticated, isTrue);

      repository.controller.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(provider.isAuthenticated, isFalse);
      expect(clearCalls, 1);
    },
  );
}

Future<String?> _attemptSignup(AuthProvider provider) => provider.signUp(
  password: 'password',
  firstName: 'Test',
  lastName: 'User',
  schoolId: '2026-0001',
  department: 'Department',
  course: 'Course',
);

class _SignupFailureRepository extends AuthRepository {
  _SignupFailureRepository(this.error) : super(AuthService());

  final Object error;

  @override
  Future<firebase_auth.UserCredential> signUp({
    required String password,
    required String firstName,
    required String lastName,
    required String schoolId,
    required String department,
    required String course,
    String? sector,
    String? employeeId,
    String? yearLevel,
    String? position,
    String? middleName,
    AssessmentRole? role,
    DateTime? dateOfBirth,
    String? gender,
  }) async => throw error;

  @override
  Future<void> signOut() async {}
}

class _PendingProfileRepository extends AuthRepository {
  _PendingProfileRepository() : super(AuthService());

  int signOutCalls = 0;
  int signupCalls = 0;
  int profileRetryCalls = 0;

  @override
  String? get currentUserId => 'user_1';

  @override
  String? get currentUserEmail => '2026.0001@mindmate.local';

  @override
  Future<firebase_auth.UserCredential> signUp({
    required String password,
    required String firstName,
    required String lastName,
    required String schoolId,
    required String department,
    required String course,
    String? sector,
    String? employeeId,
    String? yearLevel,
    String? position,
    String? middleName,
    AssessmentRole? role,
    DateTime? dateOfBirth,
    String? gender,
  }) async {
    signupCalls++;
    throw SignupProfileProvisioningException(
      'user_1',
      StateError('Firebase App Check token was rejected.'),
    );
  }

  @override
  Future<String> completeProfileSetup({
    required String firstName,
    required String lastName,
    required String schoolId,
    required String department,
    required String course,
    String? sector,
    String? employeeId,
    String? yearLevel,
    String? position,
    String? middleName,
    AssessmentRole? role,
    DateTime? dateOfBirth,
    String? gender,
  }) async {
    profileRetryCalls++;
    return 'user_1';
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

class _AuthenticationFailureRepository extends AuthRepository {
  _AuthenticationFailureRepository() : super(AuthService());

  int signOutCalls = 0;

  @override
  Future<firebase_auth.UserCredential> signUp({
    required String password,
    required String firstName,
    required String lastName,
    required String schoolId,
    required String department,
    required String course,
    String? sector,
    String? employeeId,
    String? yearLevel,
    String? position,
    String? middleName,
    AssessmentRole? role,
    DateTime? dateOfBirth,
    String? gender,
  }) async => throw StateError('Authentication failed.');

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

class _ProfileLookupFailureRepository extends AuthRepository {
  _ProfileLookupFailureRepository() : super(AuthService());

  int signOutCalls = 0;

  @override
  String? get currentUserId => 'user_1';

  @override
  Future<firebase_auth.UserCredential> signUp({
    required String password,
    required String firstName,
    required String lastName,
    required String schoolId,
    required String department,
    required String course,
    String? sector,
    String? employeeId,
    String? yearLevel,
    String? position,
    String? middleName,
    AssessmentRole? role,
    DateTime? dateOfBirth,
    String? gender,
  }) async {
    throw SignupProfileLookupException(
      'user_1',
      StateError('Firebase App Check token was rejected.'),
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

class _MutableAuthRepository extends AuthRepository {
  _MutableAuthRepository({this.currentUserId, this.restoredUserId})
    : super(AuthService());

  @override
  String? currentUserId;
  final String? restoredUserId;

  @override
  Future<String?> restoreCurrentUser() async {
    currentUserId = restoredUserId;
    return currentUserId;
  }
}

class _StreamingAuthRepository extends AuthRepository {
  _StreamingAuthRepository() : super(AuthService());

  final controller = StreamController<String?>();

  @override
  Stream<String?> watchAuthenticatedUserIds() => controller.stream;
}
