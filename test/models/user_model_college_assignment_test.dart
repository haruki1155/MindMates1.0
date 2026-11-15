import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

void main() {
  test(
    'parses served colleges and revision, separate from the home college',
    () {
      final user = UserModel.fromJson({
        'id': 'counselor-1',
        'email': 'c@example.com',
        'accessRole': 'counselor',
        'collegeId': 'home-college',
        'assignedCollegeIds': ['cite', 'cas', 'cite', '', 7],
        'collegeAssignmentRevision': 3,
      });
      expect(user.collegeId, 'home-college');
      expect(user.assignedCollegeIds, ['cas', 'cite']);
      expect(user.collegeAssignmentRevision, 3);
    },
  );

  test(
    'legacy staff without assignment fields read as unassigned at revision 0',
    () {
      final user = UserModel.fromJson({
        'id': 'legacy',
        'email': 'l@example.com',
        'accessRole': 'portalStaff',
      });
      expect(user.assignedCollegeIds, isEmpty);
      expect(user.collegeAssignmentRevision, 0);
    },
  );

  test(
    'profile serialization never writes the server-owned assignment fields',
    () {
      final json = UserModel.fromJson({
        'id': 'x',
        'email': 'x@example.com',
        'assignedCollegeIds': ['cite'],
        'collegeAssignmentRevision': 2,
      }).toJson();
      expect(json.containsKey('assignedCollegeIds'), isFalse);
      expect(json.containsKey('collegeAssignmentRevision'), isFalse);
    },
  );

  test(
    'repository calls the assignment callable with the expected arguments',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final repository = AdminPortalRepository(
        callableInvoker: (name, data) async {
          calls.add((name, data));
          return {
            'ok': true,
            'revision': 4,
            'collegeIds': ['cas', 'cite'],
          };
        },
      );
      final result = await repository.setStaffCollegeAssignments(
        userId: 'counselor-1',
        collegeIds: const ['cite', 'cas'],
        expectedRevision: 3,
        reason: 'Semester coverage',
      );
      expect(result, 4);
      expect(calls.single.$1, 'setStaffCollegeAssignments');
      expect(calls.single.$2, {
        'userId': 'counselor-1',
        'collegeIds': ['cite', 'cas'],
        'expectedRevision': 3,
        'reason': 'Semester coverage',
      });
    },
  );
}
