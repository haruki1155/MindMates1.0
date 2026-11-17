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

UserModel _counselor({
  String id = 'counselor-1',
  String first = 'Casey',
  String last = 'Counselor',
  List<String> assigned = const [],
  int revision = 0,
  StaffAccountStatus status = StaffAccountStatus.approved,
  String? accountStatus = 'active',
}) => UserModel(
  id: id,
  email: '$id@example.com',
  firstName: first,
  lastName: last,
  accessRole: AccessRole.counselor,
  staffAccountStatus: status,
  accountStatus: accountStatus,
  assignedCollegeIds: assigned,
  collegeAssignmentRevision: revision,
);

UserModel _portalStaff({
  String id = 'staff-1',
  List<String> assigned = const [],
  int revision = 0,
}) => UserModel(
  id: id,
  email: '$id@example.com',
  firstName: 'Pat',
  lastName: 'Staff',
  accessRole: AccessRole.portalStaff,
  staffAccountStatus: StaffAccountStatus.approved,
  accountStatus: 'active',
  assignedCollegeIds: assigned,
  collegeAssignmentRevision: revision,
);

class _Repo extends AdminPortalRepository {
  _Repo({this.superAdmin = true, this.error, this.users = const []});

  final bool superAdmin;
  final Object? error;
  final List<UserModel> users;
  final saves = <Map<String, Object?>>[];
  final transfers = <Map<String, Object?>>[];

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

  @override
  Future<Map<String, int>> reassignCollegeCounselor({
    required String collegeId,
    required String? toCounselorId,
    required List<String> expectedOwnerIds,
    required Map<String, int> expectedRevisions,
    required String reason,
  }) async {
    transfers.add({
      'collegeId': collegeId,
      'toCounselorId': toCounselorId,
      'expectedOwnerIds': expectedOwnerIds,
      'expectedRevisions': expectedRevisions,
      'reason': reason,
    });
    if (error != null) throw error!;
    return {
      for (final entry in expectedRevisions.entries) entry.key: entry.value + 1,
    };
  }
}

Future<void> _open(
  WidgetTester tester,
  _Repo repo,
  UserModel user, {
  List<UserModel> allUsers = const [],
}) async {
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
              allUsers: allUsers,
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
    expect(
      find.descendant(
        of: find.byType(CollegeAssignmentDialog),
        matching: find.text('Information Technology'),
      ),
      findsOneWidget,
    );
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

  testWidgets(
    'dialog prevents assigning a college already owned by another counselor',
    (tester) async {
      final c1 = _counselor(id: 'c1', first: 'Casey', assigned: const ['cite']);
      final c2 = _counselor(id: 'c2', first: 'Jordan', assigned: const []);
      await _open(tester, _Repo(), c2, allUsers: [c1, c2]);

      expect(
        find.textContaining('Assigned to Casey Counselor'),
        findsOneWidget,
      );
      await tester.tap(find.text('Information Technology'));
      await tester.pumpAndSettle();

      expect(find.text(collegeAlreadyAssignedMessage), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);
    },
  );

  testWidgets(
    'portal staff hide College assignments unless clearing legacy assignments',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final cleanRepo = _Repo(users: [_portalStaff(assigned: const [])]);
      await tester.pumpWidget(
        MaterialApp(home: UserManagementPage(repository: cleanRepo)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Staff / Counselors (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More staff actions'));
      await tester.pumpAndSettle();
      expect(find.text('College assignments'), findsNothing);
      expect(find.text('Clear legacy college assignments'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      final legacyRepo = _Repo(
        users: [
          _portalStaff(assigned: const ['cite'], revision: 2),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          key: const Key('legacy-app'),
          home: Scaffold(body: UserManagementPage(repository: legacyRepo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('user-tab-staff')));
      await tester.tap(find.byKey(const Key('user-tab-staff')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More staff actions'));
      await tester.pumpAndSettle();
      expect(find.text('College assignments'), findsNothing);
      await tester.tap(find.text('Clear legacy college assignments'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Legacy cleanup',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear assignments'));
      await tester.pumpAndSettle();
      expect(legacyRepo.saves, [
        {
          'userId': 'staff-1',
          'collegeIds': <String>[],
          'expectedRevision': 2,
          'reason': 'Legacy cleanup',
        },
      ]);
    },
  );

  testWidgets(
    'College Counselor Assignments section filters, searches, picks eligible counselors, and resolves conflicts',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final c1 = _counselor(
        id: 'c1',
        first: 'Alice',
        last: 'One',
        assigned: ['cas', 'cite'],
        revision: 3,
      );
      final c2 = _counselor(
        id: 'c2',
        first: 'Bob',
        last: 'Two',
        assigned: ['cas'],
        revision: 1,
      );
      final c3 = _counselor(
        id: 'c3',
        first: 'Clara',
        last: 'Three',
        assigned: [],
        revision: 0,
      );
      final suspended = _counselor(
        id: 'c-sus',
        first: 'Suspended',
        last: 'Counselor',
        status: StaffAccountStatus.disabled,
        accountStatus: 'suspended',
      );
      final staff = _portalStaff(id: 'staff-1');

      final repo = _Repo(users: [c1, c2, c3, suspended, staff]);
      await tester.pumpWidget(
        MaterialApp(home: UserManagementPage(repository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Staff / Counselors (5)'));
      await tester.pumpAndSettle();

      final section = find.byKey(
        const Key('college-counselor-assignments-section'),
      );
      expect(section, findsOneWidget);
      expect(find.text('College Counselor Assignments'), findsOneWidget);
      expect(find.text('Conflict'), findsOneWidget);
      expect(find.text('Resolve Conflict'), findsOneWidget);
      expect(find.text('Assigned'), findsWidgets);
      expect(find.text('Inactive'), findsWidgets);

      // Filter by Conflicts only.
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Conflicts'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Conflicts'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: section, matching: find.text('Arts and Sciences')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: section,
          matching: find.text('Information Technology'),
        ),
        findsNothing,
      );

      // Switch back to All Colleges and search by code.
      await tester.tap(find.widgetWithText(ChoiceChip, 'All Colleges'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('college-assignment-search')),
        'CITE',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: section,
          matching: find.text('Information Technology'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: section, matching: find.text('Arts and Sciences')),
        findsNothing,
      );

      // Clear search and resolve the Conflict on Arts and Sciences.
      await tester.tap(find.byTooltip('Clear college search'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Resolve Conflict'));
      await tester.tap(find.text('Resolve Conflict'));
      await tester.pumpAndSettle();

      // Open dropdown: only eligible counselors appear (not Pat Staff or Suspended Counselor).
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(DropdownMenuItem<String>),
          matching: find.text('Clara Three'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(DropdownMenuItem<String>),
          matching: find.text('Pat Staff'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(DropdownMenuItem<String>),
          matching: find.text('Suspended Counselor'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Clara Three').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Resolve conflict to Clara',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Resolve conflict'));
      await tester.pumpAndSettle();

      expect(repo.transfers, [
        {
          'collegeId': 'cas',
          'toCounselorId': 'c3',
          'expectedOwnerIds': ['c1', 'c2'],
          'expectedRevisions': {'c1': 3, 'c2': 1, 'c3': 0},
          'reason': 'Resolve conflict to Clara',
        },
      ]);
    },
  );

  testWidgets(
    'College Counselor Assignments renders cleanly on mobile width without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final c1 = _counselor(id: 'c1', first: 'Alice', assigned: ['cite']);
      final repo = _Repo(users: [c1, _portalStaff()]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: UserManagementPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('user-tab-staff')));
      await tester.tap(find.byKey(const Key('user-tab-staff')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('College Counselor Assignments'), findsOneWidget);
    },
  );
}
