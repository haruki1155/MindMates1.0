import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';

void main() {
  group('UserModel', () {
    test('maps registration fields and defaults missing day streak', () {
      final user = UserModel.fromJson({
        'id': 'user_1',
        'email': 'leo@example.com',
        'firstName': 'Leonardo',
        'middleName': 'Santos',
        'lastName': 'Molar',
        'schoolId': '2026-0001',
        'department': 'Information Technology',
        'course': 'BS Information Technology',
        'sector': '',
        'role': 'student',
        'gender': 'Female',
        'createdAt': '2026-06-30T08:15:00.000',
      });

      expect(user.id, 'user_1');
      expect(user.displayName, 'Leonardo Santos Molar');
      expect(user.roleLabel, 'Student');
      expect(user.course, 'BS Information Technology');
      expect(user.gender, 'Female');
      expect(user.sector, isNull);
      expect(user.dayStreak, 0);
      expect(user.createdAt, DateTime(2026, 6, 30, 8, 15));
      expect(user.quickAssessmentCompleted, isFalse);
    });

    test('missing createdAt does not crash', () {
      final user = UserModel.fromJson({
        'id': 'user_2',
        'email': 'mia@example.com',
      });

      expect(user.createdAt, isNull);
      expect(user.displayName, 'mia@example.com');
    });

    test('normalizes obsolete pending status for auto-assigned v3 roles', () {
      final user = UserModel.fromJson({
        'id': 'user_auto_verified',
        'email': 'student@example.com',
        'populationRole': 'student',
        'declaredRole': 'student',
        'accessRole': 'appUser',
        'verificationStatus': 'pending',
        'profileVersion': 3,
      });

      expect(user.verificationStatus, VerificationStatus.verified);
    });

    test('preserves pending verification for legacy profiles', () {
      final user = UserModel.fromJson({
        'id': 'legacy_pending',
        'email': 'student@example.com',
        'populationRole': 'student',
        'accessRole': 'appUser',
        'verificationStatus': 'pending',
        'profileVersion': 2,
      });

      expect(user.verificationStatus, VerificationStatus.pending);
    });

    test('profile update json includes editable fields', () {
      final user = const UserModel(
        id: 'user_3',
        email: 'ana@example.com',
        firstName: 'Ana',
        lastName: 'Rivera',
        schoolId: 'UCU-1',
        department: 'Guidance',
        course: 'Master of Arts in Education - all major fields',
        sector: 'Guidance/PACC',
        role: 'faculty',
        dayStreak: 7,
      ).toProfileUpdateJson();

      expect(user['name'], 'Ana Rivera');
      expect(user.containsKey('schoolId'), isFalse);
      expect(user.containsKey('department'), isFalse);
      expect(user.containsKey('course'), isFalse);
      expect(user.containsKey('sector'), isFalse);
      expect(user.containsKey('role'), isFalse);
      expect(user['updatedAt'], isNotNull);
    });

    test('roleLabel maps known categories and falls back to User', () {
      expect(
        const UserModel(
          id: '1',
          email: 'a@example.com',
          role: 'student',
        ).roleLabel,
        'Student',
      );
      expect(
        const UserModel(
          id: '2',
          email: 'b@example.com',
          role: 'faculty',
        ).roleLabel,
        'Teaching',
      );
      expect(
        const UserModel(
          id: '3',
          email: 'c@example.com',
          role: 'staff',
        ).roleLabel,
        'Non-Teaching',
      );
      expect(
        const UserModel(
          id: '4',
          email: 'd@example.com',
          role: 'non-teaching',
        ).roleLabel,
        'Non-Teaching',
      );
      expect(
        const UserModel(
          id: '5',
          email: 'e@example.com',
          role: 'guest',
        ).roleLabel,
        'User',
      );
      expect(
        const UserModel(id: '6', email: 'f@example.com').roleLabel,
        'User',
      );
    });

    test('serializes non-teaching sector details', () {
      final user = const UserModel(
        id: 'user_7',
        email: '2026.0001@mindmate.local',
        schoolId: '2026-0001',
        sector: 'Guidance/PACC',
        role: 'staff',
      ).toJson();

      expect(user['schoolId'], '2026-0001');
      expect(user['sector'], 'Guidance/PACC');
      expect(user['department'], '');
      expect(user['course'], '');
      expect(user['role'], 'staff');
    });

    test('serializes registration gender', () {
      final user = const UserModel(
        id: 'user_gender',
        email: 'user@example.com',
        gender: 'Non-binary',
      ).toJson();

      expect(user['gender'], 'Non-binary');
    });

    test('maps durable quick assessment completion fields', () {
      final user = UserModel.fromJson({
        'id': 'user_8',
        'email': 'user@mindmate.local',
        'quickAssessmentCompleted': true,
        'quickAssessmentCompletedAt': '2026-07-07T09:30:00.000',
      });

      expect(user.quickAssessmentCompleted, isTrue);
      expect(user.quickAssessmentCompletedAt, DateTime(2026, 7, 7, 9, 30));
    });
  });
}
