import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/student_roster_models.dart';
import 'package:mind_mates/repositories/student_roster_repository.dart';

void main() {
  late List<Map<String, Object?>> calls;

  StudentRosterRepository repo(Object? Function(String name) respond) =>
      StudentRosterRepository(
        invoker: (name, data) async {
          calls.add({'name': name, 'data': data});
          return respond(name);
        },
      );

  setUp(() => calls = []);

  group('account setup sign-in email', () {
    Future<String> start(StudentRosterRepository r) => r.startAccountSetup(
      studentNo: '2021-00123',
      firstName: 'Ana',
      middleName: '',
      lastName: 'Cruz',
      dateOfBirthKey: '2005-03-15',
      email: 'Ana@Example.com',
      password: 'Secret!1',
    );

    test('signs in with the Auth email the server created, not the recovery email', () async {
      final r = repo(
        (_) => {
          'ok': true,
          'email': 'ana@example.com',
          'authEmail': '202100123@students.mindmate.local',
        },
      );
      expect(await start(r), '202100123@students.mindmate.local');
      expect(calls.single['name'], 'startStudentAccountSetup');
    });

    test('a response without an Auth email is a failure, never a guessed sign-in', () async {
      await expectLater(
        start(repo((_) => {'ok': true, 'email': 'ana@example.com'})),
        throwsA(isA<StudentActivationException>()),
      );
    });
  });

  group('recovery email verification', () {
    test('requesting a code returns only the masked address', () async {
      final r = repo((_) => {'accepted': true, 'maskedEmail': 'a***@example.com', 'expiresInSeconds': 900});
      final result = await r.requestRecoveryEmailCode();
      expect(calls.single['name'], 'requestStudentRecoveryEmailCode');
      expect(result.maskedEmail, 'a***@example.com');
      expect(result.alreadyVerified, isFalse);
      expect(result.expiresInSeconds, 900);
    });

    test('reports an account that is already verified', () async {
      final r = repo((_) => {'accepted': true, 'alreadyVerified': true});
      final result = await r.requestRecoveryEmailCode();
      expect(result.alreadyVerified, isTrue);
      expect(result.maskedEmail, isEmpty);
    });

    test('confirming sends only the typed code', () async {
      final r = repo((_) => {'verified': true});
      await r.confirmRecoveryEmailCode('ABCDE-FGHJK');
      expect(calls.single['name'], 'confirmStudentRecoveryEmailCode');
      expect(calls.single['data'], {'code': 'ABCDE-FGHJK'});
    });
  });

  group('password reset by Student ID', () {
    test('sends only the Student ID', () async {
      final r = repo((_) => {'accepted': true});
      await r.requestPasswordResetForStudentId(' 2021-00123 ');
      expect(calls.single['name'], 'requestStudentPasswordReset');
      expect(calls.single['data'], {'studentId': '2021-00123'});
    });
  });
}
