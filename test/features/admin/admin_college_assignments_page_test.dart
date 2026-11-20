import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/admin_college_assignments_page.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeAdminAssignmentsRepo extends AdminPortalRepository {
  _FakeAdminAssignmentsRepo({
    this.superAdmin = true,
    this.role = AccessRole.admin,
    this.collegesStream,
    this.usersStream,
  });

  final bool superAdmin;
  final AccessRole role;
  final Stream<List<College>>? collegesStream;
  final Stream<List<UserModel>>? usersStream;

  int watchUsersCalls = 0;
  int watchCollegesCalls = 0;
  final List<Map<String, Object?>> transfers = <Map<String, Object?>>[];

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  AccessRole get currentAccessRole => role;

  @override
  Stream<List<College>> watchColleges() {
    watchCollegesCalls += 1;
    return collegesStream ?? const Stream.empty();
  }

  @override
  Stream<List<UserModel>> watchUsers() {
    watchUsersCalls += 1;
    return usersStream ?? const Stream.empty();
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
    return {
      for (final entry in expectedRevisions.entries) entry.key: entry.value + 1,
    };
  }
}

UserModel _counselor({
  required String id,
  required String first,
  required String last,
  List<String> assigned = const [],
  int revision = 1,
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

const _syntheticColleges = [
  College(
    id: 'cite',
    name: 'College of Information Technology',
    code: 'CITE',
    active: true,
  ),
  College(
    id: 'cas',
    name: 'College of Arts and Sciences',
    code: 'CAS',
    active: true,
  ),
  College(
    id: 'cba',
    name: 'College of Business Administration',
    code: 'CBA',
    active: true,
  ),
  College(
    id: 'old',
    name: 'Retired College',
    code: 'OLD',
    active: false,
  ),
];

Future<void> _pumpAdminPage(
  WidgetTester tester,
  _FakeAdminAssignmentsRepo repo,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AdminCollegeAssignmentsPage(repository: repo)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'displays assigned counselor, unassigned, conflict warning, archived college, and inactive owner labels',
    (tester) async {
      final users = [
        _counselor(
          id: 'c-1',
          first: 'Elena',
          last: 'Reyes',
          assigned: const ['cite', 'cba'],
        ),
        _counselor(
          id: 'c-2',
          first: 'Marco',
          last: 'Diaz',
          assigned: const ['cba'],
        ),
        _counselor(
          id: 'c-suspended',
          first: 'Sonia',
          last: 'Vega',
          assigned: const ['old'],
          status: StaffAccountStatus.disabled,
          accountStatus: 'suspended',
        ),
      ];
      final repo = _FakeAdminAssignmentsRepo(
        superAdmin: true,
        collegesStream: Stream.value(_syntheticColleges),
        usersStream: Stream.value(users),
      );

      await _pumpAdminPage(tester, repo);

      expect(find.text('College Assignments'), findsOneWidget);
      expect(find.text('College of Information Technology'), findsOneWidget);
      expect(find.textContaining('Elena Reyes'), findsWidgets);

      expect(find.text('College of Arts and Sciences'), findsOneWidget);
      expect(find.text('Unassigned'), findsWidgets);

      expect(find.text('College of Business Administration'), findsOneWidget);
      expect(find.textContaining('Assignment conflict'), findsOneWidget);
      expect(find.textContaining('Marco Diaz'), findsOneWidget);

      expect(find.text('Retired College'), findsOneWidget);
      expect(find.textContaining('Archived'), findsWidgets);
      expect(find.textContaining('Sonia Vega'), findsOneWidget);
      expect(find.textContaining('Inactive / Suspended'), findsOneWidget);
    },
  );

  testWidgets(
    'non-super-admin roles see no roster data and never invoke watchUsers or watchColleges',
    (tester) async {
      for (final role in [
        AccessRole.admin,
        AccessRole.counselor,
        AccessRole.portalStaff,
        AccessRole.appUser,
      ]) {
        final repo = _FakeAdminAssignmentsRepo(
          superAdmin: false,
          role: role,
          collegesStream: Stream.value(_syntheticColleges),
          usersStream: Stream.value([
            _counselor(
              id: 'c-1',
              first: 'Elena',
              last: 'Reyes',
              assigned: const ['cite'],
            ),
          ]),
        );

        await _pumpAdminPage(tester, repo);

        expect(repo.watchUsersCalls, 0);
        expect(repo.watchCollegesCalls, 0);
        expect(find.text('Elena Reyes'), findsNothing);
        expect(
          find.text('Super-administrator access is required.'),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'Super Admin Assign and Manage actions open existing transfer dialog with eligible counselors only',
    (tester) async {
      final users = [
        _counselor(
          id: 'c-1',
          first: 'Elena',
          last: 'Reyes',
          assigned: const ['cite'],
          revision: 3,
        ),
        _counselor(
          id: 'c-2',
          first: 'Marco',
          last: 'Diaz',
          assigned: const [],
          revision: 2,
        ),
        _counselor(
          id: 'c-suspended',
          first: 'Sonia',
          last: 'Vega',
          assigned: const [],
          status: StaffAccountStatus.disabled,
          accountStatus: 'suspended',
        ),
      ];
      final repo = _FakeAdminAssignmentsRepo(
        superAdmin: true,
        collegesStream: Stream.value(const [
          College(
            id: 'cas',
            name: 'College of Arts and Sciences',
            code: 'CAS',
            active: true,
          ),
          College(
            id: 'cite',
            name: 'College of Information Technology',
            code: 'CITE',
            active: true,
          ),
        ]),
        usersStream: Stream.value(users),
      );

      await _pumpAdminPage(tester, repo);

      // Tap Assign on unassigned CAS.
      await tester.tap(find.text('Assign'));
      await tester.pumpAndSettle();

      expect(
        find.text('Assign counselor · College of Arts and Sciences'),
        findsOneWidget,
      );

      // Select Marco Diaz in dropdown; Sonia Vega (suspended) must not be selectable.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Sonia Vega'), findsNothing);
      await tester.tap(find.text('Marco Diaz').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Reason for change'),
        'Assign CAS coverage',
      );
      await tester.pump();
      await tester.tap(find.text('Assign counselor'));
      await tester.pumpAndSettle();

      expect(repo.transfers, hasLength(1));
      expect(repo.transfers.single['collegeId'], 'cas');
      expect(repo.transfers.single['toCounselorId'], 'c-2');

      // Tap Manage on assigned CITE.
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      expect(
        find.text('Change counselor · College of Information Technology'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'shows error state when watchUsers or watchColleges fails',
    (tester) async {
      final usersErrorRepo = _FakeAdminAssignmentsRepo(
        superAdmin: true,
        collegesStream: Stream.value(_syntheticColleges),
        usersStream: Stream<List<UserModel>>.error(StateError('users-failed')),
      );
      await _pumpAdminPage(tester, usersErrorRepo);
      expect(
        find.text('We could not load college assignments.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      final collegesErrorRepo = _FakeAdminAssignmentsRepo(
        superAdmin: true,
        collegesStream: Stream<List<College>>.error(StateError('colleges-failed')),
        usersStream: Stream.value(const []),
      );
      await _pumpAdminPage(tester, collegesErrorRepo);
      expect(
        find.text('We could not load college assignments.'),
        findsOneWidget,
      );
    },
  );
}
