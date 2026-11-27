import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/counselor_assigned_colleges_page.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeCounselorCollegesRepo extends AdminPortalRepository {
  _FakeCounselorCollegesRepo({
    required this.role,
    required this.uid,
    this.superAdmin = false,
    this.ownProfileStream,
    this.collegesStream,
  });

  final AccessRole role;
  final String? uid;
  final bool superAdmin;
  final Stream<Map<String, dynamic>?>? ownProfileStream;
  final Stream<List<College>>? collegesStream;

  int watchOwnProfileCalls = 0;
  int watchCollegesCalls = 0;
  int watchUsersCalls = 0;
  final List<String> watchedProfileUids = <String>[];

  @override
  AccessRole get currentAccessRole => role;

  @override
  String? get currentUserId => uid;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  Stream<Map<String, dynamic>?> watchOwnProfile(String userId) {
    watchOwnProfileCalls += 1;
    watchedProfileUids.add(userId);
    return ownProfileStream ?? const Stream.empty();
  }

  @override
  Stream<List<College>> watchColleges() {
    watchCollegesCalls += 1;
    return collegesStream ?? const Stream.empty();
  }

  @override
  Stream<List<UserModel>> watchUsers() {
    watchUsersCalls += 1;
    return const Stream.empty();
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeCounselorCollegesRepo repo,
) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: CounselorAssignedCollegesPage(repository: repo)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shows assigned college names for counselor and updates live when profile changes',
    (tester) async {
      final profileController =
          StreamController<Map<String, dynamic>?>.broadcast();
      final repo = _FakeCounselorCollegesRepo(
        role: AccessRole.counselor,
        uid: 'counselor-1',
        ownProfileStream: profileController.stream,
        collegesStream: Stream.value(const [
          College(
            id: 'cas',
            name: 'College of Arts and Sciences',
            code: 'CAS',
            active: true,
          ),
          College(
            id: 'cite',
            name: 'College of Information Technology Education',
            code: 'CITE',
            active: true,
          ),
        ]),
      );
      addTearDown(profileController.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CounselorAssignedCollegesPage(repository: repo)),
        ),
      );
      profileController.add({
        'accessRole': 'counselor',
        'staffAccountStatus': 'approved',
        'accountStatus': 'active',
        'collegeId': 'engineering',
        'assignedCollegeIds': ['cite', 'cas'],
      });
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Read-only overview of the colleges assigned to your counselor caseload.',
        ),
        findsOneWidget,
      );
      expect(find.text('College of Arts and Sciences'), findsOneWidget);
      expect(
        find.text('College of Information Technology Education'),
        findsOneWidget,
      );
      expect(find.textContaining('engineering'), findsNothing);
      expect(repo.watchedProfileUids, ['counselor-1']);
      expect(repo.watchUsersCalls, 0);

      // Update profile live to only one college.
      profileController.add({
        'accessRole': 'counselor',
        'staffAccountStatus': 'approved',
        'accountStatus': 'active',
        'assignedCollegeIds': ['cas'],
      });
      await tester.pumpAndSettle();

      expect(find.text('College of Arts and Sciences'), findsOneWidget);
      expect(
        find.text('College of Information Technology Education'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'empty assignedCollegeIds shows No colleges assigned yet with admin contact guidance',
    (tester) async {
      final repo = _FakeCounselorCollegesRepo(
        role: AccessRole.counselor,
        uid: 'counselor-1',
        ownProfileStream: Stream.value({
          'accessRole': 'counselor',
          'staffAccountStatus': 'approved',
          'accountStatus': 'active',
          'collegeId': 'cite',
          'assignedCollegeIds': <String>[],
        }),
        collegesStream: Stream.value(const [
          College(
            id: 'cite',
            name: 'College of Information Technology Education',
            code: 'CITE',
            active: true,
          ),
        ]),
      );

      await _pumpPage(tester, repo);

      expect(find.text('No colleges assigned yet'), findsOneWidget);
      expect(find.textContaining('administrator'), findsOneWidget);
      expect(
        find.text('College of Information Technology Education'),
        findsNothing,
      );
      expect(repo.watchUsersCalls, 0);
    },
  );

  testWidgets(
    'labels unknown college IDs as unavailable/unknown and inactive catalog entries as inactive/archived',
    (tester) async {
      final repo = _FakeCounselorCollegesRepo(
        role: AccessRole.counselor,
        uid: 'counselor-1',
        ownProfileStream: Stream.value({
          'accessRole': 'counselor',
          'staffAccountStatus': 'approved',
          'accountStatus': 'active',
          'assignedCollegeIds': ['retired-col', 'missing-col'],
        }),
        collegesStream: Stream.value(const [
          College(
            id: 'retired-col',
            name: 'Retired College',
            code: 'RET',
            active: false,
          ),
        ]),
      );

      await _pumpPage(tester, repo);

      expect(find.text('Retired College'), findsOneWidget);
      expect(find.textContaining('Inactive / Archived'), findsOneWidget);
      expect(
        find.textContaining('Unknown or unavailable college'),
        findsOneWidget,
      );
      expect(find.textContaining('Catalog entry not found'), findsOneWidget);
      expect(find.textContaining('missing-col'), findsNothing);
      expect(find.textContaining('retired-col'), findsNothing);
      expect(repo.watchUsersCalls, 0);
    },
  );

  testWidgets(
    'non-counselor roles or absent UID do not query protected streams and show safe unavailable message',
    (tester) async {
      for (final scenario in [
        (AccessRole.portalStaff, 'staff-1', false),
        (AccessRole.admin, 'admin-1', false),
        (AccessRole.admin, 'super-admin-1', true),
        (AccessRole.appUser, 'student-1', false),
        (AccessRole.counselor, null, false),
        (AccessRole.counselor, '  ', false),
      ]) {
        final repo = _FakeCounselorCollegesRepo(
          role: scenario.$1,
          uid: scenario.$2,
          superAdmin: scenario.$3,
        );

        await _pumpPage(tester, repo);

        expect(repo.watchOwnProfileCalls, 0);
        expect(repo.watchCollegesCalls, 0);
        expect(repo.watchUsersCalls, 0);
        expect(
          find.text(
            'Assigned colleges are available only to signed-in counselors.',
          ),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'shows visible error state with retry button when profile or college stream fails',
    (tester) async {
      var attempt = 0;
      final repo = _RetryingCounselorCollegesRepo(() {
        attempt += 1;
        if (attempt == 1) {
          return Stream<Map<String, dynamic>?>.error(StateError('offline'));
        }
        return Stream.value({
          'accessRole': 'counselor',
          'staffAccountStatus': 'approved',
          'accountStatus': 'active',
          'assignedCollegeIds': ['cite'],
        });
      });

      await _pumpPage(tester, repo);

      expect(
        find.text('We could not load your assigned colleges.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(repo.watchUsersCalls, 0);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(
        find.text('College of Information Technology Education'),
        findsOneWidget,
      );
      expect(repo.watchUsersCalls, 0);
    },
  );
}

class _RetryingCounselorCollegesRepo extends _FakeCounselorCollegesRepo {
  _RetryingCounselorCollegesRepo(this._profileFactory)
    : super(
        role: AccessRole.counselor,
        uid: 'counselor-1',
        collegesStream: Stream.value(const [
          College(
            id: 'cite',
            name: 'College of Information Technology Education',
            code: 'CITE',
            active: true,
          ),
        ]),
      );

  final Stream<Map<String, dynamic>?> Function() _profileFactory;

  @override
  Stream<Map<String, dynamic>?> watchOwnProfile(String userId) {
    watchOwnProfileCalls += 1;
    watchedProfileUids.add(userId);
    return _profileFactory();
  }
}
