import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/user_management_page.dart';
import 'package:mind_mates/features/admin/widgets/college_assignment_dialog.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

const _colleges = [
  College(id: 'cas', name: 'Arts and Sciences', code: 'CAS', active: true),
  College(
    id: 'cite',
    name: 'Information Technology',
    code: 'CITE',
    active: true,
  ),
  College(id: 'old', name: 'Retired College', code: 'OLD', active: false),
  College(id: 'gone', name: 'Unused Archive', code: 'GONE', active: false),
];

UserModel _counselor({List<String> assigned = const [], int revision = 0}) =>
    UserModel(
      id: 'counselor-1',
      email: 'counselor@example.com',
      firstName: 'Casey',
      lastName: 'Counselor',
      accessRole: AccessRole.counselor,
      staffAccountStatus: StaffAccountStatus.approved,
      assignedCollegeIds: assigned,
      collegeAssignmentRevision: revision,
    );

class _Repo extends AdminPortalRepository {
  _Repo({this.superAdmin = true, this.error, this.users = const []});

  final bool superAdmin;
  final Object? error;
  final List<UserModel> users;
  final saves = <Map<String, Object?>>[];

  @override
  bool get isSuperAdmin => superAdmin;
  @override
  AccessRole get currentAccessRole => AccessRole.admin;
  @override
  Stream<List<College>> watchColleges() => Stream.value(_colleges);
  @override
  Stream<List<UserModel>> watchUsers() => Stream.value(users);
  @override
  Future<List<PublicAppUserRecord>> listPublicAppUsers() async => const [];

  @override
  Future<int> setStaffCollegeAssignments({
    required String userId,
    required List<String> collegeIds,
    required int expectedRevision,
    required String reason,
  }) async {
    saves.add({
      'userId': userId,
      'collegeIds': collegeIds,
      'expectedRevision': expectedRevision,
      'reason': reason,
    });
    if (error != null) throw error!;
    return expectedRevision + 1;
  }
}

Future<void> _open(WidgetTester tester, _Repo repo, UserModel user) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCollegeAssignmentDialog(
              context,
              repository: repo,
              user: user,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists active colleges, keeps assigned archived ones visible, '
      'and says Unassigned when empty', (tester) async {
    await _open(tester, _Repo(), _counselor(assigned: ['old']));
    expect(find.text('Arts and Sciences'), findsOneWidget);
    expect(find.text('Information Technology'), findsOneWidget);
    expect(find.text('Retired College (archived)'), findsOneWidget);
    expect(find.textContaining('Unused Archive'), findsNothing);
    expect(find.text('Unassigned'), findsNothing);

    await tester.tap(find.text('Retired College (archived)'));
    await tester.pumpAndSettle();
    expect(find.text('Unassigned'), findsOneWidget);
  });

  testWidgets(
    'saves the selected colleges with the stored revision and a reason',
    (tester) async {
      final repo = _Repo();
      await _open(tester, repo, _counselor(assigned: ['cas'], revision: 2));
      final save = find.widgetWithText(FilledButton, 'Save assignments');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.tap(find.text('Information Technology'));
      await tester.enterText(find.byType(TextField), 'Semester coverage');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(repo.saves, [
        {
          'userId': 'counselor-1',
          'collegeIds': ['cas', 'cite'],
          'expectedRevision': 2,
          'reason': 'Semester coverage',
        },
      ]);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('a server refusal is shown and the dialog stays open', (
    tester,
  ) async {
    final repo = _Repo(
      error: FirebaseFunctionsException(
        code: 'failed-precondition',
        message:
            'These college assignments were updated by someone else. Reload and try again.',
      ),
    );
    await _open(tester, repo, _counselor());
    await tester.tap(find.text('Arts and Sciences'));
    await tester.enterText(find.byType(TextField), 'Coverage');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save assignments'));
    await tester.pumpAndSettle();
    expect(find.textContaining('updated by someone else'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('User Management offers College assignments to the '
      'super-administrator and shows assigned colleges', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo(
      users: [
        _counselor(assigned: ['cite']),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: UserManagementPage(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff / Counselors (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More staff actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('College assignments'));
    await tester.pumpAndSettle();
    expect(find.byType(CollegeAssignmentDialog), findsOneWidget);
    expect(find.text('Information Technology'), findsOneWidget);
  });

  testWidgets(
    'a non-super-administrator cannot reach staff assignment at all',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementPage(
            repository: _Repo(superAdmin: false, users: [_counselor()]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Super-administrator access is required.'),
        findsOneWidget,
      );
      expect(find.text('College assignments'), findsNothing);
    },
  );
}
