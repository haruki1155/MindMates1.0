import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/user_management_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
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
      collegeId: 'cite',
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
  Stream<List<College>> watchColleges() => Stream.value(const [
    College(id: 'cite', name: 'CITE', code: '010', active: true),
  ]);
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

    expect(find.text('2024-001'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
    expect(find.text('CITE'), findsOneWidget);
    expect(find.text('Student ID'), findsOneWidget);
    expect(find.text('View user'), findsOneWidget);
    expect(find.text('Private Student'), findsOneWidget);
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

  testWidgets('user category navigation is connected and switches tabs', (
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
    expect(
      find.byKey(const Key('user-category-segmented-nav')),
      findsOneWidget,
    );
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.byKey(const Key('user-tab-employees')));
    await tester.pumpAndSettle();
    expect(find.text('No employees found.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('user-tab-students')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('user-category-segmented-nav')),
      findsOneWidget,
    );
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

  testWidgets(
    'uses Inactive account / Inactive / Reactivate account consistently without Suspend copy',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _LifecycleRepo();
      await tester.pumpWidget(
        MaterialApp(home: UserManagementPage(repository: repo)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Staff / Counselors (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Suspended'), findsNothing);
      expect(find.text('Suspend account'), findsNothing);
      expect(find.text('Inactive'), findsOneWidget);

      // Open overflow menu for active staff and verify 'Inactive account'.
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('Inactive account'), findsOneWidget);
      expect(find.text('Suspend account'), findsNothing);

      // Close menu and open overflow menu for disabled staff.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).last);
      await tester.pumpAndSettle();
      expect(find.text('Reactivate account'), findsOneWidget);
    },
  );

  testWidgets(
    'User Management renders cleanly at 390, 768, and 1280 px with status badges and role-based actions',
    (tester) async {
      addTearDown(tester.view.reset);

      for (final width in const [390.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: UserManagementPage(
              key: ValueKey(width),
              repository: _Repository(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'students tab overflow at $width',
        );
        expect(find.text('View user'), findsOneWidget);

        await tester.ensureVisible(find.text('Staff / Counselors (1)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Staff / Counselors (1)'));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'staff tab overflow at $width',
        );
        expect(find.text('Pending review'), findsOneWidget);
        expect(find.text('Manage'), findsOneWidget);
        expect(find.text('Suspend account'), findsNothing);

        await tester.ensureVisible(find.text('Manage'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Manage'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'staff manage drawer overflow at $width',
        );
        expect(find.text('Manage access'), findsOneWidget);
        expect(find.text('Review invitation'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Non-super-admin role sees restricted access gate and no management actions.
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: UserManagementPage(
              key: ValueKey('restricted-$width'),
              repository: _RestrictedRepo(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'restricted user management overflow at $width',
        );
        expect(
          find.text('Super-administrator access is required.'),
          findsOneWidget,
        );
        expect(find.text('Manage'), findsNothing);
        expect(find.text('View user'), findsNothing);
      }
    },
  );
}

class _RestrictedRepo extends _Repository {
  @override
  bool get isSuperAdmin => false;

  @override
  AccessRole get currentAccessRole => AccessRole.counselor;
}

class _LifecycleRepo extends _Repository {
  @override
  Stream<List<UserModel>> watchUsers() => Stream.value([
    const UserModel(
      id: 'active-staff',
      email: 'active@example.com',
      firstName: 'Active',
      lastName: 'Counselor',
      accessRole: AccessRole.counselor,
      staffAccountStatus: StaffAccountStatus.approved,
    ),
    const UserModel(
      id: 'inactive-staff',
      email: 'inactive@example.com',
      firstName: 'Disabled',
      lastName: 'Staff',
      accessRole: AccessRole.portalStaff,
      staffAccountStatus: StaffAccountStatus.disabled,
    ),
  ]);
}
