import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/user_management_page.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _Repository extends AdminPortalRepository {
  @override
  AccessRole get currentAccessRole => AccessRole.admin;
  @override
  bool get isSuperAdmin => true;

  @override
  Future<List<PublicAppUserRecord>> listPublicAppUsers() async => [
    PublicAppUserRecord(
      userId: 'private-app-uid',
      publicUserId: 'USR-7K4P2Q',
      populationRole: PopulationRole.student,
      department: 'CITE',
      createdAt: DateTime(2026, 9, 1),
    ),
  ];

  @override
  Stream<List<UserModel>> watchUsers() => Stream.value([
    UserModel(
      id: 'private-app-uid',
      email: 'private@student.example',
      firstName: 'Private',
      lastName: 'Student',
      schoolId: '2024-001',
      department: 'CITE',
      course: 'BSIT',
      yearLevel: '3rd Year',
      populationRole: PopulationRole.student,
      createdAt: DateTime(2026, 9, 1),
    ),
    UserModel(
      id: 'staff-uid',
      email: 'staff@example.com',
      firstName: 'Portal',
      lastName: 'Staff',
      employeeId: 'EMP-1',
      position: 'Counselor',
      department: 'Guidance/PACC',
      accessRole: AccessRole.portalStaff,
      staffAccountStatus: StaffAccountStatus.pending,
    ),
    UserModel(
      id: 'admin-uid',
      email: 'admin@example.com',
      firstName: 'System',
      lastName: 'Admin',
      accessRole: AccessRole.admin,
    ),
  ]);

  @override
  Stream<List<College>> watchColleges() => Stream.value(const []);
  @override
  Stream<List<Department>> watchDepartments() => Stream.value(const []);
  @override
  Stream<List<Course>> watchCourses() => Stream.value(const []);
}

void main() {
  testWidgets('app users show department, creation date, and profile action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: UserManagementPage(repository: _Repository())),
    );
    await tester.pumpAndSettle();

    expect(find.text('USR-7K4P2Q'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('CITE'), findsOneWidget);
    expect(find.text('2026-09-01'), findsOneWidget);
    expect(find.text('View user'), findsOneWidget);
    expect(find.text('Private Student'), findsNothing);
    expect(find.text('private@student.example'), findsNothing);
    expect(find.text('Review'), findsNothing);
    expect(find.text('Verify'), findsNothing);
    expect(find.text('Reject'), findsNothing);

    await tester.tap(find.text('View user'));
    await tester.pumpAndSettle();
    expect(find.text('Personal information'), findsOneWidget);
    expect(find.text('Private Student'), findsWidgets);
    expect(find.text('Academic information'), findsOneWidget);
  });

  testWidgets('pending staff show visible contextual action buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: UserManagementPage(repository: _Repository())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff / Counselors (1)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Requested:'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Pending review'), findsOneWidget);
  });
}
