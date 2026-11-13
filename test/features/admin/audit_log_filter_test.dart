import 'package:cloud_functions/cloud_functions.dart';
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

  final actions = <String>[];
  bool failStudentViews = false;
  @override
  Future<({List<AdminAuditEvent> events, bool hasMore})> fetchAuditLogPage({
    required String targetUserId,
    String category = '',
    String action = '',
    DateTime? before,
    DateTime? after,
    int pageSize = 25,
  }) async {
    actions.add(action);
    if (failStudentViews && action == 'STUDENT_PERSONAL_INFO_VIEWED') {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'The query requires an index.',
      );
    }
    return (events: <AdminAuditEvent>[], hasMore: false);
  }

  @override
  Stream<List<College>> watchColleges() => Stream.value(const []);
  @override
  Stream<List<Department>> watchDepartments() => Stream.value(const []);
  @override
  Stream<List<Course>> watchCourses() => Stream.value(const []);
}

void main() {
  testWidgets('activity log offers Student information viewed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _Repository();
    await tester.pumpWidget(
      MaterialApp(home: UserManagementPage(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff / Counselors (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Student information viewed').last);
    await tester.pumpAndSettle();
    expect(repo.actions.last, 'STUDENT_PERSONAL_INFO_VIEWED');
  });

  Future<_Repository> openActivityLog(
    WidgetTester tester, {
    bool fail = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _Repository()..failStudentViews = fail;
    await tester.pumpWidget(
      MaterialApp(home: UserManagementPage(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff / Counselors (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('a failed student-views query is an error, not an empty log', (
    tester,
  ) async {
    await openActivityLog(tester, fail: true);
    await tester.tap(find.text('All actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Student information viewed').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Activity log unavailable: a required database index is not deployed.',
      ),
      findsOneWidget,
    );
    expect(find.text('No activity matches these filters.'), findsNothing);
  });

  testWidgets('the filter explains where student information views live', (
    tester,
  ) async {
    await openActivityLog(tester);
    expect(
      find.text('Student information views appear under their own filter.'),
      findsOneWidget,
    );
  });
}
