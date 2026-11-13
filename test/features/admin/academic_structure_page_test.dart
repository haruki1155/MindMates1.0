import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/academic_structure_page.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _SavedRecord {
  _SavedRecord(
    this.kind,
    this.id,
    this.name,
    this.code,
    this.collegeId,
    this.departmentId,
  );
  final String kind;
  final String? id;
  final String name;
  final String code;
  final String collegeId;
  final String departmentId;
}

class _Repository extends AdminPortalRepository {
  _Repository({this.departments = const []});
  final List<Department> departments;
  final saved = <_SavedRecord>[];

  static const colleges = [
    College(
      id: 'col-1',
      name: 'College of Engineering',
      code: 'COE',
      active: true,
    ),
    College(id: 'col-2', name: 'College of Arts', code: 'CAS', active: true),
  ];

  @override
  Stream<List<College>> watchColleges() => Stream.value(colleges);
  @override
  Stream<List<Department>> watchDepartments() => Stream.value(departments);
  @override
  Stream<List<Course>> watchCourses() => Stream.value(const []);

  @override
  Future<void> saveOrganizationRecord({
    required String kind,
    String? id,
    required String name,
    required String code,
    required bool active,
    String collegeId = '',
    String departmentId = '',
  }) async {
    saved.add(_SavedRecord(kind, id, name, code, collegeId, departmentId));
  }
}

const _dept = Department(
  id: 'dep-1',
  name: 'Computer Engineering',
  code: 'CPE',
  active: true,
  collegeId: 'col-1',
);

Future<void> _pump(WidgetTester tester, _Repository repo) async {
  tester.view.physicalSize = const Size(1440, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AcademicStructurePage(repository: repo)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester, Finder row, String item) async {
  await tester.tap(
    find
        .descendant(of: row, matching: find.byType(PopupMenuButton<String>))
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('college menu adds a department with college preselected', (
    tester,
  ) async {
    final repo = _Repository(departments: const [_dept]);
    await _pump(tester, repo);
    await _menu(
      tester,
      find.widgetWithText(ExpansionTile, 'College of Engineering').first,
      'Add department',
    );
    expect(find.text('Add Department'), findsOneWidget);
    expect(find.text('College of Engineering'), findsWidgets);
    await tester.enterText(
      find.widgetWithText(TextField, 'department name'),
      'Civil Engineering',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'department code'),
      'CE',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.kind, 'department');
    expect(repo.saved.single.id, isNull);
    expect(repo.saved.single.collegeId, 'col-1');
  });

  testWidgets('department menu adds a course with college and department', (
    tester,
  ) async {
    final repo = _Repository(departments: const [_dept]);
    await _pump(tester, repo);
    await tester.tap(find.text('College of Engineering'));
    await tester.pumpAndSettle();
    await _menu(
      tester,
      find.widgetWithText(ExpansionTile, 'Computer Engineering').first,
      'Add course',
    );
    expect(find.text('Add Course'), findsOneWidget);
    expect(find.text('Computer Engineering'), findsWidgets);
    await tester.enterText(
      find.widgetWithText(TextField, 'course name'),
      'BS Computer Engineering',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'course code'),
      'BSCPE',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.kind, 'course');
    expect(repo.saved.single.id, isNull);
    expect(repo.saved.single.collegeId, 'col-1');
    expect(repo.saved.single.departmentId, 'dep-1');
  });

  testWidgets('college without departments shows inline add department', (
    tester,
  ) async {
    final repo = _Repository();
    await _pump(tester, repo);
    await tester.tap(find.text('College of Arts'));
    await tester.pumpAndSettle();
    final inline = find.widgetWithText(TextButton, 'Add department');
    expect(inline, findsOneWidget);
    await tester.tap(inline);
    await tester.pumpAndSettle();
    expect(find.text('Add Department'), findsOneWidget);
  });

  testWidgets('editing an existing department is unchanged', (tester) async {
    final repo = _Repository(departments: const [_dept]);
    await _pump(tester, repo);
    await tester.tap(find.text('College of Engineering'));
    await tester.pumpAndSettle();
    await _menu(
      tester,
      find.widgetWithText(ExpansionTile, 'Computer Engineering').first,
      'Edit',
    );
    expect(find.text('Edit Department'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(repo.saved.single.id, 'dep-1');
    expect(repo.saved.single.collegeId, 'col-1');
  });
}
