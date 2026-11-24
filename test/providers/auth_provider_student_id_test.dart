import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/repositories/student_roster_repository.dart';
import 'package:mind_mates/services/auth/auth_service.dart';

class _Credential implements firebase_auth.UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Repository extends AuthRepository {
  _Repository() : super(AuthService());

  final events = <String>[];
  Object? signInError;
  String? email;

  @override
  String? get currentUserId => 'user_1';

  @override
  String? get currentUserEmail => email;

  @override
  Future<firebase_auth.UserCredential> signInWithStudentId({
    required String studentId,
    required String password,
  }) async {
    events.add('studentId:$studentId');
    if (signInError != null) throw signInError!;
    return _Credential();
  }

  @override
  Future<firebase_auth.UserCredential> signIn({
    required String schoolId,
    required String password,
  }) async {
    events.add('legacy:$schoolId');
    return _Credential();
  }

  @override
  Future<firebase_auth.UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    events.add('email:$email');
    return _Credential();
  }

  @override
  Future<void> sendEmailVerification() async => events.add('firebaseVerification');

  @override
  Future<void> refreshSession() async => events.add('refreshSession');

  @override
  Future<void> signOut() async => events.add('signOut');
}

void main() {
  late _Repository repository;
  late List<String> rosterCalls;
  late Object? Function(String name) respond;
  late AuthProvider provider;

  setUp(() {
    repository = _Repository();
    rosterCalls = [];
    respond = (_) => {'ok': true};
    provider = AuthProvider(
      repository,
      rosterRepository: StudentRosterRepository(
        invoker: (name, data) async {
          rosterCalls.add(name);
          repository.events.add('callable:$name');
          return respond(name);
        },
      ),
    );
  });

  group('Student ID sign-in', () {
    test('signs in through the Student ID path only', () async {
      final id = await provider.signInWithStudentId(
        studentId: '2020-12345',
        password: 'Secret!1',
      );
      expect(id, 'user_1');
      expect(provider.isAuthenticated, isTrue);
      expect(repository.events, ['studentId:2020-12345']);
    });

    test('one generic message for a failure, the session is cleared, nothing is retried', () async {
      repository.signInError = firebase_auth.FirebaseAuthException(
        code: AuthRepository.studentIdCredentialFailure,
      );
      final id = await provider.signInWithStudentId(
        studentId: '2020-12345',
        password: 'wrong',
      );
      expect(id, isNull);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.errorMessage, 'Student ID or password is incorrect.');
      expect(repository.events, ['studentId:2020-12345', 'signOut']);
      expect(repository.events.where((e) => e.startsWith('legacy')), isEmpty);
    });

    test('the legacy School ID path is still available and separate', () async {
      await provider.signIn(schoolId: 'EMP-001', password: 'Secret!1');
      expect(repository.events, ['legacy:EMP-001']);
    });
  });

  group('account setup', () {
    Future<void> start() => provider.startStudentAccountSetup(
      studentNo: '2021-00123',
      firstName: 'Ana',
      middleName: '',
      lastName: 'Cruz',
      dateOfBirthKey: '2005-03-15',
      email: 'ana@example.com',
      password: 'Secret!1',
    );

    test('signs in with the alias and does not make Firebase mail the alias', () async {
      respond = (_) => {
        'ok': true,
        'email': 'ana@example.com',
        'authEmail': '202100123@students.mindmate.local',
      };
      await start();
      expect(repository.events, [
        'callable:startStudentAccountSetup',
        'email:202100123@students.mindmate.local',
      ]);
      expect(repository.events, isNot(contains('firebaseVerification')));
    });

    test('completing setup calls the finishing callable', () async {
      respond = (_) => {'ok': true};
      await provider.completeStudentAccountSetup();
      expect(repository.events, ['callable:completeStudentAccountSetup']);
    });
  });

  group('recovery email verification', () {
    test('requesting a code returns the masked address', () async {
      respond = (_) => {'accepted': true, 'maskedEmail': 'a***@example.com', 'expiresInSeconds': 900};
      final result = await provider.requestRecoveryEmailCode();
      expect(result.maskedEmail, 'a***@example.com');
      expect(rosterCalls, ['requestStudentRecoveryEmailCode']);
    });

    test('a correct code refreshes the session so the verified state is visible', () async {
      respond = (_) => {'verified': true};
      await provider.confirmRecoveryEmailCode('ABCDE-FGHJK');
      expect(repository.events, [
        'callable:confirmStudentRecoveryEmailCode',
        'refreshSession',
      ]);
    });

    test('a rejected code does not refresh the session and the error reaches the caller', () async {
      respond = (_) => throw StateError('invalid');
      await expectLater(
        provider.confirmRecoveryEmailCode('ABCDE-FGHJK'),
        throwsA(isA<StateError>()),
      );
      expect(repository.events, ['callable:confirmStudentRecoveryEmailCode']);
    });
  });

  group('password reset by Student ID', () {
    test('succeeds with the same outcome for any Student ID', () async {
      expect(await provider.sendPasswordResetForStudentId('2021-00123'), isTrue);
      expect(await provider.sendPasswordResetForStudentId('NOT-A-REAL-ID'), isTrue);
      expect(rosterCalls, ['requestStudentPasswordReset', 'requestStudentPasswordReset']);
    });

    test('a delivery or rate-limit error is reported without account details', () async {
      respond = (_) => throw StateError('boom');
      expect(await provider.sendPasswordResetForStudentId('2021-00123'), isFalse);
      expect(provider.errorMessage, isNotEmpty);
    });
  });

  group('the internal alias is never a contact email', () {
    test('is hidden from display and flagged as an alias', () {
      repository.email = '202100123@students.mindmate.local';
      expect(provider.currentUserIsStudentAlias, isTrue);
      expect(provider.currentUserContactEmail, isNull);
    });

    test('a normal account email is unchanged', () {
      repository.email = 'teacher@example.com';
      expect(provider.currentUserIsStudentAlias, isFalse);
      expect(provider.currentUserContactEmail, 'teacher@example.com');
    });
  });
}
