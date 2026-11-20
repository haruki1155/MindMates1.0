import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/admin_college_assignments_page.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/screens/counselor_assigned_colleges_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/app_notification_model.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _NavRepo extends AdminPortalRepository {
  _NavRepo({
    required this.role,
    required this.superAdmin,
    this.uid = 'user-1',
  });

  final AccessRole role;
  final bool superAdmin;
  final String? uid;
  int watchUsersCalls = 0;

  final _notifications =
      StreamController<List<AppNotificationModel>>.broadcast();

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  String? get currentUserId => uid;

  @override
  User? get currentAuthUser => null;

  @override
  Stream<List<AppNotificationModel>> watchPortalNotifications() =>
      _notifications.stream;

  @override
  Stream<List<AppointmentModel>> watchAppointments() =>
      Stream<List<AppointmentModel>>.value(const []);

  @override
  Stream<List<AppointmentModel>> watchMyAssignedAppointments() =>
      Stream<List<AppointmentModel>>.value(const []);

  @override
  Stream<List<AdminAssessmentRecord>> watchAssessments() =>
      Stream<List<AdminAssessmentRecord>>.value(const []);

  @override
  Stream<List<AdminInquiryModel>> watchInquiries() =>
      Stream<List<AdminInquiryModel>>.value(const []);

  @override
  Stream<List<UserModel>> watchUsers() {
    watchUsersCalls += 1;
    return Stream<List<UserModel>>.value([
      const UserModel(
        id: 'counselor-1',
        email: 'counselor@example.com',
        firstName: 'Elena',
        lastName: 'Reyes',
        accessRole: AccessRole.counselor,
        staffAccountStatus: StaffAccountStatus.approved,
        accountStatus: 'active',
        assignedCollegeIds: ['cite'],
      ),
    ]);
  }

  @override
  Stream<List<College>> watchColleges() => Stream<List<College>>.value(const [
    College(
      id: 'cite',
      name: 'College of Information Technology',
      code: 'CITE',
      active: true,
    ),
  ]);

  @override
  Stream<Map<String, dynamic>?> watchOwnProfile(String userId) =>
      Stream<Map<String, dynamic>?>.value({
        'accessRole': 'counselor',
        'staffAccountStatus': 'approved',
        'accountStatus': 'active',
        'assignedCollegeIds': ['cite'],
      });

  Future<void> dispose() => _notifications.close();
}

Future<void> _pumpPortal(WidgetTester tester, _NavRepo repo) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
      home: AdminPortalHome(
        repository: repo,
        registerUnload: (_) => null,
        removeUnload: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpRail(
  WidgetTester tester, {
  required AccessRole role,
  required bool isSuperAdmin,
}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
      home: Scaffold(
        body: SizedBox(
          width: 280,
          height: 2400,
          child: PortalWorkspaceNavigation(
            page: AdminPortalPage.dashboard,
            onChanged: (_) {},
            accessRole: role,
            isSuperAdmin: isSuperAdmin,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'counselor sees one College Assignments entry and navigates to My Assigned Colleges',
    (tester) async {
      final repo = _NavRepo(
        role: AccessRole.counselor,
        superAdmin: false,
        uid: 'counselor-1',
      );
      addTearDown(repo.dispose);

      await _pumpPortal(tester, repo);

      expect(find.text('College Assignments'), findsOneWidget);
      await tester.tap(find.text('College Assignments'));
      await tester.pumpAndSettle();

      expect(find.byType(CounselorAssignedCollegesPage), findsOneWidget);
      expect(find.text('My Assigned Colleges'), findsOneWidget);
      expect(find.text('College of Information Technology'), findsOneWidget);
      expect(repo.watchUsersCalls, 0);
    },
  );

  testWidgets(
    'super-administrator sees one College Assignments entry and navigates to Admin overview',
    (tester) async {
      final repo = _NavRepo(
        role: AccessRole.admin,
        superAdmin: true,
        uid: 'super-admin-1',
      );
      addTearDown(repo.dispose);

      await _pumpPortal(tester, repo);

      expect(find.text('College Assignments'), findsOneWidget);
      await tester.tap(find.text('College Assignments'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminCollegeAssignmentsPage), findsOneWidget);
      expect(
        find.textContaining(
          'Manage counselor ownership across colleges.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Elena Reyes'), findsOneWidget);
    },
  );

  for (final role in [
    AccessRole.portalStaff,
    AccessRole.appUser,
    AccessRole.admin,
  ]) {
    testWidgets(
      '${role.name} without super-admin privilege does not see College Assignments',
      (tester) async {
        await _pumpRail(tester, role: role, isSuperAdmin: false);
        expect(find.text('College Assignments'), findsNothing);
      },
    );
  }
}
