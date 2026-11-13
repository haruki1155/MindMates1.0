import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/widgets/app_user_directory_table.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _Repository extends AdminPortalRepository {
  @override
  bool get isSuperAdmin => true;

  @override
  Stream<List<College>> watchColleges() => Stream.value(const [
    College(id: 'cite', name: 'CITE', code: '010', active: true),
    College(id: 'cba', name: 'Business College', code: '020', active: true),
  ]);
}

const student = UserModel(
  id: 's',
  email: 'student@example.com',
  firstName: 'Sample',
  lastName: 'Student',
  schoolId: '2024-101',
  collegeId: 'cite',
  populationRole: PopulationRole.student,
  verificationStatus: VerificationStatus.verified,
);
const teacher = UserModel(
  id: 't',
  email: 'teaching@example.com',
  firstName: 'Sample',
  lastName: 'Teacher',
  employeeId: 'EMP-101',
  collegeId: 'cite',
  populationRole: PopulationRole.teaching,
  verificationStatus: VerificationStatus.verified,
);
const nonTeacher = UserModel(
  id: 'n',
  email: 'nonteaching@example.com',
  firstName: 'Office',
  lastName: 'Employee',
  employeeId: 'EMP-102',
  collegeId: 'cba',
  populationRole: PopulationRole.nonTeaching,
  verificationStatus: VerificationStatus.verified,
);
const staff = UserModel(
  id: 'p',
  email: 'staff@example.com',
  firstName: 'PACC',
  lastName: 'Staff',
  employeeId: 'EMP-999',
  collegeId: 'cite',
  populationRole: PopulationRole.nonTeaching,
  accessRole: AccessRole.portalStaff,
);

void main() {
  test('population split excludes portal staff and counselors', () {
    expect(
      matchesAppDirectoryGroup(student, AppDirectoryGroup.students),
      isTrue,
    );
    expect(
      matchesAppDirectoryGroup(teacher, AppDirectoryGroup.students),
      isFalse,
    );
    expect(
      matchesAppDirectoryGroup(teacher, AppDirectoryGroup.employees),
      isTrue,
    );
    expect(
      matchesAppDirectoryGroup(nonTeacher, AppDirectoryGroup.employees),
      isTrue,
    );
    expect(
      matchesAppDirectoryGroup(staff, AppDirectoryGroup.employees),
      isFalse,
    );
  });

  test('statuses never label unverified profiles as Active', () {
    expect(appDirectoryStatus(student), 'Active');
    expect(
      appDirectoryStatus(
        const UserModel(id: 'pending', email: 'pending@example.com'),
      ),
      'Pending verification',
    );
    expect(
      appDirectoryStatus(teacher.copyWith(accountStatus: 'disabled')),
      'Suspended',
    );
  });

  testWidgets('employees table shows requested columns and real names', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUserDirectoryTable(
            repository: _Repository(),
            profiles: const [student, teacher, nonTeacher, staff],
            group: AppDirectoryGroup.employees,
            query: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Employee ID'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('College'), findsWidgets);
    expect(find.text('Teaching or non-teaching'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('EMP-101'), findsOneWidget);
    expect(find.text('Sample Teacher'), findsOneWidget);
    expect(find.text('EMP-102'), findsOneWidget);
    expect(find.text('PACC Staff'), findsNothing);
    expect(find.text('2024-101'), findsNothing);
  });

  testWidgets('college filter restricts employees by canonical collegeId', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUserDirectoryTable(
            repository: _Repository(),
            profiles: const [teacher, nonTeacher],
            group: AppDirectoryGroup.employees,
            query: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Business College').last);
    await tester.pumpAndSettle();
    expect(find.text('EMP-102'), findsOneWidget);
    expect(find.text('EMP-101'), findsNothing);
  });
}
