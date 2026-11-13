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

const _defaultColleges = [
  College(
    id: 'col-1',
    name: 'College of Engineering',
    code: 'COE',
    active: true,
  ),
  College(id: 'col-2', name: 'College of Arts', code: 'CAS', active: true),
];

class _Repository extends AdminPortalRepository {
  _Repository({
    this.departments = const [],
    this.courses = const [],
    this.colleges = _defaultColleges,
  });
  final List<Department> departments;
  final List<Course> courses;
  final List<College> colleges;
  final saved = <_SavedRecord>[];
  final archived = <String>[];

  @override
  Stream<List<College>> watchColleges() => Stream.value(colleges);
  @override
  Stream<List<Department>> watchDepartments() => Stream.value(departments);
  @override
  Stream<List<Course>> watchCourses() => Stream.value(courses);

  @override
  Future<void> archiveOrganizationRecord({
    required String kind,
    required String id,
    required bool archived,
  }) async {
    this.archived.add('$kind:$id:$archived');
  }

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
const _artsDept = Department(
  id: 'dep-2',
  name: 'Fine Arts',
  code: 'FA',
  active: true,
  collegeId: 'col-2',
);
const _course = Course(
  id: 'crs-1',
  name: 'BS Computer Engineering',
  code: 'BSCPE',
  active: true,
  collegeId: 'col-1',
  departmentId: 'dep-1',
);
const _archivedCourse = Course(
  id: 'crs-2',
  name: 'Old Course',
  code: 'OLDC',
  active: false,
  collegeId: 'col-1',
  departmentId: 'dep-1',
);
const _artsCourse = Course(
  id: 'crs-3',
  name: 'BA Fine Arts',
  code: 'BAFA',
  active: true,
  collegeId: 'col-2',
  departmentId: 'dep-2',
);
const _artsArchivedOnly = Course(
  id: 'crs-4',
  name: 'Archived Arts',
  code: 'ARCH',
  active: false,
  collegeId: 'col-2',
  departmentId: 'dep-2',
);

Future<void> _pump(
  WidgetTester tester,
  _Repository repo, {
  Size size = const Size(1440, 2000),
}) async {
  tester.view.physicalSize = size;
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

Future<void> _setStatus(WidgetTester tester, String status) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(status).last);
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
      find.byKey(const ValueKey('college-row-col-1')),
      'Add department',
    );
    expect(find.text('Add Department'), findsOneWidget);
    expect(find.text('College of Engineering'), findsWidgets);
    await tester.enterText(
      find.widgetWithText(TextField, 'Department name'),
      'Civil Engineering',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Department code'),
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
      find.byKey(const ValueKey('department-dep-1')),
      'Add course',
    );
    expect(find.text('Add Course'), findsOneWidget);
    expect(find.text('Computer Engineering'), findsWidgets);
    await tester.enterText(
      find.widgetWithText(TextField, 'Course name'),
      'BS Computer Engineering',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Course code'),
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
    await _menu(tester, find.byKey(const ValueKey('department-dep-1')), 'Edit');
    expect(find.text('Edit Department'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(repo.saved.single.id, 'dep-1');
    expect(repo.saved.single.collegeId, 'col-1');
  });

  testWidgets('selecting a college shows only its departments and courses', (
    tester,
  ) async {
    final repo = _Repository(
      departments: const [_dept, _artsDept],
      courses: const [_course, _artsCourse],
    );
    await _pump(tester, repo);
    expect(find.text('Computer Engineering'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('college-row-col-1')));
    await tester.pumpAndSettle();
    expect(find.text('Computer Engineering'), findsOneWidget);
    expect(find.text('BS Computer Engineering'), findsOneWidget);
    expect(find.text('Fine Arts'), findsNothing);
    expect(find.text('BA Fine Arts'), findsNothing);
  });

  testWidgets('college row shows chips and an active course count', (
    tester,
  ) async {
    final repo = _Repository(
      departments: const [_dept, _artsDept],
      courses: const [_course, _archivedCourse, _artsArchivedOnly],
    );
    await _pump(tester, repo);
    final eng = find.byKey(const ValueKey('college-row-col-1'));
    expect(
      find.descendant(of: eng, matching: find.text('COE')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: eng, matching: find.text('Active')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: eng, matching: find.text('1 course')),
      findsOneWidget,
    );
    final arts = find.byKey(const ValueKey('college-row-col-2'));
    expect(
      find.descendant(of: arts, matching: find.text('no courses')),
      findsOneWidget,
    );
  });

  testWidgets('filter excluding the selected college clears the selection', (
    tester,
  ) async {
    final repo = _Repository(
      departments: const [_dept],
      colleges: const [
        ..._defaultColleges,
        College(id: 'col-9', name: 'Old College', code: 'OLD', active: false),
      ],
    );
    await _pump(tester, repo);
    await tester.tap(find.byKey(const ValueKey('college-row-col-1')));
    await tester.pumpAndSettle();
    expect(find.text('Computer Engineering'), findsOneWidget);
    await _setStatus(tester, 'Inactive');
    expect(find.text('Computer Engineering'), findsNothing);
    expect(find.text('Select a college'), findsOneWidget);
    await _setStatus(tester, 'Active');
    expect(find.text('Computer Engineering'), findsNothing);
    expect(find.text('Select a college'), findsOneWidget);
  });

  testWidgets('archived college is reachable and can be restored', (
    tester,
  ) async {
    final repo = _Repository(
      colleges: const [
        College(id: 'col-9', name: 'Old College', code: 'OLD', active: false),
      ],
    );
    await _pump(tester, repo);
    expect(find.text('Old College'), findsNothing);
    await _setStatus(tester, 'Inactive');
    await _menu(
      tester,
      find.byKey(const ValueKey('college-row-col-9')),
      'Restore',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(repo.archived, ['college:col-9:false']);
  });

  testWidgets('narrow width renders the single-column list', (tester) async {
    final repo = _Repository(departments: const [_dept]);
    await _pump(tester, repo, size: const Size(600, 1600));
    expect(find.byKey(const ValueKey('academic-two-pane')), findsNothing);
    expect(
      find.byKey(const ValueKey('academic-single-column')),
      findsOneWidget,
    );
    expect(find.byType(ExpansionTile), findsWidgets);
  });

  testWidgets('wide width renders two panes', (tester) async {
    await _pump(tester, _Repository());
    expect(find.byKey(const ValueKey('academic-two-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('academic-single-column')), findsNothing);
  });

  testWidgets('course menu archives from the right pane', (tester) async {
    final repo = _Repository(
      departments: const [_dept],
      courses: const [_course],
    );
    await _pump(tester, repo);
    await tester.tap(find.byKey(const ValueKey('college-row-col-1')));
    await tester.pumpAndSettle();
    await _menu(tester, find.byKey(const ValueKey('course-crs-1')), 'Archive');
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(repo.archived, ['course:crs-1:true']);
  });

  testWidgets('department + Course action opens an Add Course dialog', (
    tester,
  ) async {
    final repo = _Repository(departments: const [_dept]);
    await _pump(tester, repo);
    await tester.tap(find.byKey(const ValueKey('college-row-col-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-course-dep-1')));
    await tester.pumpAndSettle();
    expect(find.text('Add Course'), findsOneWidget);
    expect(find.text('Course name'), findsOneWidget);
  });
}
