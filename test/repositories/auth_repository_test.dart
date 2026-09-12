import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/repositories/auth_repository.dart';

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
