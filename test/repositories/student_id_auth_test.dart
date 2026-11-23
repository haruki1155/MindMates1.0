import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:mind_mates/services/firebase/callable_request_timeout.dart';

class _Credential implements firebase_auth.UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('Student ID Firebase Auth alias', () {
    // Mirrors functions/src/student_auth_alias.test.ts; the client and the
    // server must always derive the same Auth email for a Student ID.
    const vectors = <String, String>{
      'QA-2026-0001': 'qa20260001@students.mindmate.local',
      ' qa 2026 0001 ': 'qa20260001@students.mindmate.local',
      '2020-12345': '202012345@students.mindmate.local',
      'abc': 'abc@students.mindmate.local',
      'ßß': 'ssss@students.mindmate.local',
      'Ñandú-001': 'and001@students.mindmate.local',
      'ﬁ-2020': 'fi2020@students.mindmate.local',
      'Straße1': 'strasse1@students.mindmate.local',
    };

    test('is derived from the canonical Student ID', () {
      vectors.forEach((input, expected) {
        expect(AuthRepository.studentAuthAliasEmail(input), expected, reason: input);
      });
    });

    test('ignores formatting differences', () {
      final forms = [
        'QA-2026-0001',
        'qa 2026 0001',
        'QA20260001',
        'q.a/2026_0001',
        '  Qa-2026-0001\n',
      ];
      expect(forms.map(AuthRepository.studentAuthAliasEmail).toSet(), hasLength(1));
    });

    test('rejects unusable Student IDs with the generic credential failure', () {
      for (final bad in ['', '  ', 'ab', '-- --', 'A' * 41]) {
        expect(
          () => AuthRepository.studentAuthAliasEmail(bad),
          throwsA(
            isA<firebase_auth.FirebaseAuthException>().having(
              (e) => e.code,
              'code',
              AuthRepository.studentIdCredentialFailure,
            ),
          ),
          reason: bad,
        );
      }
      expect(() => AuthRepository.studentAuthAliasEmail('A' * 40), returnsNormally);
    });

    test('never collides with the legacy School ID alias, which is unchanged', () {
      expect(
        AuthRepository.authEmailForSchoolId('QA-2026-0001'),
        'qa.2026.0001@mindmate.local',
      );
      expect(
        AuthRepository.studentAuthAliasEmail('QA-2026-0001').endsWith('@mindmate.local'),
        isFalse,
      );
    });

    test('is recognised only on its own domain', () {
      expect(AuthRepository.isStudentAuthAlias('qa20260001@students.mindmate.local'), isTrue);
      expect(AuthRepository.isStudentAuthAlias(' QA@Students.MindMate.Local '), isTrue);
      expect(AuthRepository.isStudentAuthAlias('qa.2026@mindmate.local'), isFalse);
      expect(AuthRepository.isStudentAuthAlias('someone@example.com'), isFalse);
      expect(AuthRepository.isStudentAuthAlias(null), isFalse);
    });
  });

  group('AuthRepository.signInWithStudentId', () {
    AuthRepository repo({
      required EmailPasswordSignIn signIn,
      List<String>? resolverCalls,
      Duration timeout = const Duration(seconds: 5),
    }) => AuthRepository(
      AuthService(),
      emailSignIn: signIn,
      signInTimeout: timeout,
      schoolIdEmailResolver: (id) async {
        resolverCalls?.add(id);
        throw StateError('the resolver must not be used for Student ID sign-in');
      },
    );

    test('signs in with the derived alias and never contacts the resolver', () async {
      final calls = <String>[];
      final resolverCalls = <String>[];
      final repository = repo(
        resolverCalls: resolverCalls,
        signIn: ({required email, required password}) async {
          calls.add('$email|$password');
          return _Credential();
        },
      );
      await repository.signInWithStudentId(studentId: ' 2020-12345 ', password: 'Secret!1');
      expect(calls, ['202012345@students.mindmate.local|Secret!1']);
      expect(resolverCalls, isEmpty);
    });

    test('every credential failure becomes one generic Student ID failure', () async {
      for (final code in [
        'invalid-credential',
        'invalid-login-credentials',
        'wrong-password',
        'user-not-found',
        'user-disabled',
        'invalid-email',
      ]) {
        final repository = repo(
          signIn: ({required email, required password}) async =>
              throw firebase_auth.FirebaseAuthException(code: code),
        );
        await expectLater(
          repository.signInWithStudentId(studentId: '2020-12345', password: 'x'),
          throwsA(
            isA<firebase_auth.FirebaseAuthException>().having(
              (e) => e.code,
              'code',
              AuthRepository.studentIdCredentialFailure,
            ),
          ),
          reason: code,
        );
      }
    });

    test('an unusable Student ID fails the same way without any network call', () async {
      var attempted = false;
      final repository = repo(
        signIn: ({required email, required password}) async {
          attempted = true;
          return _Credential();
        },
      );
      await expectLater(
        repository.signInWithStudentId(studentId: 'x', password: 'y'),
        throwsA(
          isA<firebase_auth.FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            AuthRepository.studentIdCredentialFailure,
          ),
        ),
      );
      expect(attempted, isFalse);
    });

    test('operational failures are not disguised as bad credentials', () async {
      final repository = repo(
        signIn: ({required email, required password}) async =>
            throw firebase_auth.FirebaseAuthException(code: 'network-request-failed'),
      );
      await expectLater(
        repository.signInWithStudentId(studentId: '2020-12345', password: 'x'),
        throwsA(
          isA<firebase_auth.FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'network-request-failed',
          ),
        ),
      );
    });

    test('is bounded by the sign-in deadline', () async {
      final pending = Completer<firebase_auth.UserCredential>();
      final repository = repo(
        signIn: ({required email, required password}) => pending.future,
        timeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        repository.signInWithStudentId(studentId: '2020-12345', password: 'x'),
        throwsA(isA<CallableRequestTimeoutException>()),
      );
    });

    test('does not retry anything after a failed alias attempt', () async {
      var attempts = 0;
      final resolverCalls = <String>[];
      final repository = repo(
        resolverCalls: resolverCalls,
        signIn: ({required email, required password}) async {
          attempts++;
          throw firebase_auth.FirebaseAuthException(code: 'invalid-credential');
        },
      );
      await expectLater(
        repository.signInWithStudentId(studentId: '2020-12345', password: 'x'),
        throwsA(isA<firebase_auth.FirebaseAuthException>()),
      );
      expect(attempts, 1);
      expect(resolverCalls, isEmpty);
    });

    test('the legacy School ID sign-in still resolves through the resolver', () async {
      final resolverCalls = <String>[];
      final signIns = <String>[];
      final repository = AuthRepository(
        AuthService(),
        schoolIdEmailResolver: (id) async {
          resolverCalls.add(id);
          return 'employee@example.com';
        },
        emailSignIn: ({required email, required password}) async {
          signIns.add(email);
          return _Credential();
        },
      );
      await repository.signIn(schoolId: 'EMP-001', password: 'x');
      expect(resolverCalls, ['EMP-001']);
      expect(signIns, ['employee@example.com']);
    });
  });
}
