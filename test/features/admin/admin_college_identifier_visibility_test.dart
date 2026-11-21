import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/domain/inquiry_sla.dart';
import 'package:mind_mates/features/admin/screens/admin_college_assignments_page.dart';
import 'package:mind_mates/features/admin/screens/staff_appointments_page.dart';
import 'package:mind_mates/features/admin/screens/user_management_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/college_assignment_dialog.dart';
import 'package:mind_mates/features/admin/widgets/inquiry_oversight.dart';
import 'package:mind_mates/features/admin/widgets/inquiry_routing_panel.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/appointment_queue_item.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

const _syntheticCollegeId = 'college_internal_9x7';

class _CollegeVisibilityRepo extends AdminPortalRepository {
  @override
  AccessRole get currentAccessRole => AccessRole.admin;

  @override
  bool get isSuperAdmin => true;

  @override
  String? get currentUserId => 'admin-1';

  @override
  Future<List<PublicAppUserRecord>> listPublicAppUsers() async => const [];

  @override
  Stream<List<College>> watchColleges() => Stream.value(const []);

  @override
  Stream<List<UserModel>> watchUsers() => Stream.value([
    const UserModel(
      id: 'staff-1',
      email: 'staff@example.com',
      firstName: 'Dana',
      lastName: 'Counselor',
      department: 'College of Science',
      collegeId: _syntheticCollegeId,
      assignedCollegeIds: [_syntheticCollegeId],
      accessRole: AccessRole.counselor,
      staffAccountStatus: StaffAccountStatus.approved,
    ),
  ]);

  @override
  Stream<List<AppointmentQueueItem>> watchPortalAppointmentQueue() =>
      Stream.value([
        AppointmentQueueItem(
          id: 'q1',
          studentDisplayName: 'Student One',
          collegeId: _syntheticCollegeId,
          scheduledAt: DateTime(2026, 11, 21, 10, 0),
          scheduledTime: '10:00 AM',
          status: 'confirmed',
          isArchived: false,
        ),
      ]);

  @override
  Stream<InquirySla> watchInquirySla() =>
      Stream.value(const InquirySla(hours: 24));
}

void main() {
  testWidgets(
    'never renders raw internal collegeId in UserManagementPage, StaffAppointmentsPage, or Inquiry panels',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _CollegeVisibilityRepo();
      final inquiry = AdminInquiryModel(
        id: 'inq-1',
        userId: 'u1',
        name: 'Student One',
        email: 'u1@example.com',
        category: 'General',
        subject: 'Old inquiry',
        message: 'Body',
        status: InquiryStatus.pending,
        collegeId: _syntheticCollegeId,
        createdAt: DateTime.now().subtract(const Duration(hours: 48)),
      );

      // 1. UserManagementPage
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: UserManagementPage(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Staff / Counselors (1)'));
      await tester.pumpAndSettle();
      expect(find.textContaining(_syntheticCollegeId), findsNothing);

      // 2. StaffAppointmentsPage (unresolved college lookup falls back to neutral text, never raw ID)
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(body: StaffAppointmentsPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(_syntheticCollegeId), findsNothing);
      expect(find.text('College not available'), findsOneWidget);

      // 3. InquiryOverduePanel & InquiryRoutingPanel
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  InquiryOverduePanel(
                    repository: repo,
                    inquiries: [inquiry],
                    onOpen: (_) {},
                  ),
                  InquiryRoutingPanel(
                    inquiry: inquiry,
                    repository: repo,
                    onChanged: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(_syntheticCollegeId), findsNothing);

      // 4. AdminCollegeAssignmentsPage (unknown college assignment never prints raw ID)
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(body: AdminCollegeAssignmentsPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(_syntheticCollegeId), findsNothing);
      expect(find.textContaining('Suspended'), findsNothing);

      // 5. CollegeAssignmentDialog (missing catalog college never prints raw ID)
      const staffUser = UserModel(
        id: 'staff-1',
        email: 'staff@example.com',
        firstName: 'Dana',
        lastName: 'Counselor',
        department: 'College of Science',
        collegeId: _syntheticCollegeId,
        assignedCollegeIds: [_syntheticCollegeId],
        accessRole: AccessRole.counselor,
        staffAccountStatus: StaffAccountStatus.approved,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: CollegeAssignmentDialog(
              repository: repo,
              user: staffUser,
              allUsers: const [staffUser],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(_syntheticCollegeId), findsNothing);
      expect(find.text('College not available'), findsOneWidget);
    },
  );
}
