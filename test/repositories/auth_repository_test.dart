import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:mind_mates/services/firebase/callable_request_timeout.dart';

void main() {
  group('AuthRepository.authEmailForSchoolId', () {
    test('normalizes common school id formats', () {
      expect(
        AuthRepository.authEmailForSchoolId('2026-0001'),
        '2026.0001@mindmate.local',
      );
      expect(
        AuthRepository.authEmailForSchoolId(' UCU 2026/0001 '),
        'ucu.2026.0001@mindmate.local',
      );
      expect(
        AuthRepository.authEmailForSchoolId('FAC_001'),
        'fac.001@mindmate.local',
      );
    });

    test('falls back to a safe local part for blank values', () {
      expect(AuthRepository.authEmailForSchoolId(' '), 'user@mindmate.local');
    });
  });

  group('AuthRepository school ID resolver', () {
    test('returns an email when the resolver finishes within its deadline',
        () async {
      final repository = AuthRepository(
        AuthService(),
        schoolIdEmailResolver: (_) async => 'student@mindmate.local',
        resolverTimeout: const Duration(milliseconds: 10),
      );

      expect(
        await repository.resolveAuthEmailForSchoolId('2026-0001'),
        'student@mindmate.local',
      );
    });

    test('bounds Firebase Auth after successful School ID resolution',
        () async {
      final pending = Completer<firebase_auth.UserCredential>();
      final repository = AuthRepository(
        AuthService(),
        schoolIdEmailResolver: (_) async => 'student@mindmate.local',
        emailSignIn: ({required email, required password}) => pending.future,
        signInTimeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        repository.signIn(schoolId: '2026-0001', password: 'password'),
        throwsA(isA<CallableRequestTimeoutException>()),
      );
    });

    test('surfaces a recoverable timeout when the resolver never completes',
        () async {
      final pending = Completer<String>();
      final repository = AuthRepository(
        AuthService(),
        schoolIdEmailResolver: (_) => pending.future,
        resolverTimeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        repository.resolveAuthEmailForSchoolId('2026-0001'),
        throwsA(isA<CallableRequestTimeoutException>()),
      );
    });

    test('preserves resolver errors for the login flow to display', () async {
      final repository = AuthRepository(
        AuthService(),
        schoolIdEmailResolver: (_) async =>
            throw StateError('School ID could not be resolved.'),
      );

      await expectLater(
        repository.resolveAuthEmailForSchoolId('2026-0001'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AuthRepository institutional email classification', () {
    test('recognizes only the exact UCU domain as teaching personnel', () {
      expect(
        AuthRepository.registrationRoleForEmail('juandelacruz@ucu.edu.ph').name,
        'faculty',
      );
      expect(
        AuthRepository.isInstitutionalEmployeeEmail(
          ' JuanDelaCruz@UCU.EDU.PH ',
        ),
        isTrue,
      );
      expect(
        AuthRepository.isInstitutionalEmployeeEmail(
          'teacher@ucu.edu.ph.example.com',
        ),
        isFalse,
      );
      expect(
        AuthRepository.isInstitutionalEmployeeEmail('student@gmail.com'),
        isFalse,
      );
    });
  });
}
