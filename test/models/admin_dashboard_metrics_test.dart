import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

void main() {
  group('admin dashboard metric classification', () {
    test('only app accounts qualify as app users', () {
      const accounts = [
        UserModel(
          id: 'student',
          email: 'student@ucu.edu.ph',
          accessRole: AccessRole.appUser,
        ),
        UserModel(
          id: 'staff',
          email: 'staff@ucu.edu.ph',
          accessRole: AccessRole.portalStaff,
        ),
        UserModel(
          id: 'counselor',
          email: 'counselor@ucu.edu.ph',
          accessRole: AccessRole.counselor,
        ),
        UserModel(
          id: 'admin',
          email: 'admin@ucu.edu.ph',
          accessRole: AccessRole.admin,
        ),
        UserModel(
          id: 'legacy_staff',
          email: 'legacy.staff@ucu.edu.ph',
          staffAccountStatus: StaffAccountStatus.approved,
        ),
      ];

      expect(accounts.where((account) => account.isAppUser).length, 1);
    });

    test('quick assessments are excluded from the main assessment count', () {
      final createdAt = DateTime(2026, 9, 9);
      final quick = AdminAssessmentRecord(
        id: 'quick_user',
        userId: 'user',
        type: 'quick',
        createdAt: createdAt,
      );
      final main = AdminAssessmentRecord(
        id: 'full_user_1',
        userId: 'user',
        type: 'student',
        createdAt: createdAt,
      );
      final legacyQuick = AdminAssessmentRecord(
        id: 'quick_user_legacy',
        userId: 'user',
        type: 'Quick Assessment',
        createdAt: createdAt,
      );

      expect(quick.isMainAssessment, isFalse);
      expect(legacyQuick.isMainAssessment, isFalse);
      expect(main.isMainAssessment, isTrue);
    });

    test('inquiry form types get readable dashboard labels', () {
      final inquiry = AdminInquiryModel(
        id: 'inquiry',
        userId: 'user',
        subject: 'Student Satisfaction Survey',
        message: '',
        category: 'Service Form',
        email: '',
        createdAt: DateTime(2026, 9, 9),
        status: InquiryStatus.pending,
        formType: 'guidance_satisfaction_survey',
      );

      expect(inquiry.typeLabel, 'Guidance Satisfaction Survey');
    });
  });
}
