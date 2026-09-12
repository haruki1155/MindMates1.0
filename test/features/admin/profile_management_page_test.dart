import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/profile_management_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _ProfileRepository extends AdminPortalRepository {
  @override
  Stream<List<UserModel>> watchUsers() => Stream.value([
    UserModel(
      id: 'student-1',
      email: 'ana@student.example',
      firstName: 'Ana',
      lastName: 'Santos',
      schoolId: '2024-001',
      department: 'CITE',
      course: 'BSIT',
      yearLevel: '3rd Year',
      gender: 'Female',
      dateOfBirth: DateTime(2004, 5, 12),
      populationRole: PopulationRole.student,
    ),
    const UserModel(
      id: 'student-2',
      email: 'ben@student.example',
      firstName: 'Ben',
      lastName: 'Cruz',
      schoolId: '2024-002',
      department: 'CBA',
      course: 'BSBA',
      yearLevel: '1st Year',
      populationRole: PopulationRole.student,
    ),
    const UserModel(
      id: 'teacher-1',
      email: 'prof@example.com',
      firstName: 'Mila',
      lastName: 'Reyes',
      employeeId: 'EMP-100',
      department: 'CITE',
      position: 'Instructor',
      populationRole: PopulationRole.teaching,
    ),
    const UserModel(
      id: 'staff-1',
      email: 'registrar@example.com',
      firstName: 'Nico',
      lastName: 'Diaz',
      employeeId: 'EMP-200',
      sector: 'Registrar Office',
      position: 'Records Officer',
      populationRole: PopulationRole.nonTeaching,
    ),
    const UserModel(
      id: 'portal-account',
      email: 'admin@example.com',
      firstName: 'Portal',
      lastName: 'Admin',
      accessRole: AccessRole.admin,
    ),
  ]);
}

void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: ProfileManagementPage(repository: _ProfileRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'keeps population categories separate and excludes portal users',
    (tester) async {
      await pumpPage(tester);

      expect(find.text('Ana Santos'), findsOneWidget);
      expect(find.text('Ben Cruz'), findsOneWidget);
      expect(find.text('Mila Reyes'), findsNothing);
      expect(find.text('Portal Admin'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('profile-category-teaching')));
      await tester.pumpAndSettle();

      expect(find.text('Mila Reyes'), findsOneWidget);
      expect(find.text('Ana Santos'), findsNothing);
      expect(find.text('EMP-100'), findsOneWidget);
      expect(find.text('Instructor'), findsOneWidget);
    },
  );

  testWidgets('finds a student by ID and opens registration information', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey('profile-search')),
      '2024-001',
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Santos'), findsOneWidget);
    expect(find.text('Ben Cruz'), findsNothing);
    expect(find.text('1 of 2 student users'), findsOneWidget);

    await tester.ensureVisible(find.text('Ana Santos'));
    await tester.tap(find.text('Ana Santos'));
    await tester.pumpAndSettle();

    expect(find.text('Personal information'), findsOneWidget);
    expect(find.text('Academic information'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('2024-001'), findsWidgets);
    expect(find.text('BSIT'), findsWidgets);
  });

  testWidgets('uses sector as the non-teaching organizational unit', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(
      find.byKey(const ValueKey('profile-category-nonTeaching')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nico Diaz'), findsOneWidget);
    expect(find.text('Registrar Office'), findsOneWidget);
    expect(find.text('Records Officer'), findsOneWidget);
    expect(find.text('EMP-200'), findsOneWidget);
  });

  testWidgets('aligns sorting with the wide-screen filter row', (tester) async {
    await pumpPage(tester);

    final searchTop = tester
        .getTopLeft(find.byKey(const ValueKey('profile-search')))
        .dy;
    final departmentTop = tester
        .getTopLeft(find.byKey(const ValueKey('profile-department-filter')))
        .dy;
    final sortTop = tester
        .getTopLeft(find.byKey(const ValueKey('profile-sort-control')))
        .dy;
    final directionTop = tester
        .getTopLeft(find.byKey(const ValueKey('profile-sort-direction')))
        .dy;

    expect(departmentTop, closeTo(searchTop, 1));
    expect(sortTop, closeTo(searchTop, 1));
    expect(directionTop, closeTo(searchTop, 1));
  });
}
