import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/student_case_history_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

Map<Object?, Object?> _m(Map<Object?, Object?> v) => v;

void main() {
  test(
    'fetchStudentCaseHistory sends the student, cursor and page size',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final repo = AdminPortalRepository(
        callableInvoker: (name, data) async {
          calls.add((name, data));
          return _m({
            'student': _m({
              'id': 's1',
              'displayName': 'Ana Cruz',
              'collegeId': 'cite',
            }),
            'basis': 'college',
            'items': <Object?>[
              _m({
                'id': 'a2',
                'status': 'completed',
                'scheduledAt': '2026-04-02T01:00:00.000Z',
                'scheduledTime': '9:00 AM',
                'createdAt': '2026-03-20T01:00:00.000Z',
                'completedAt': null,
                'archived': true,
                'archivedAt': '2026-05-01T00:00:00.000Z',
                'counselorName': 'Coach Cite',
                'location': 'PACC',
                'concern': 'Sleep',
                'followUpStatus': 'offered',
                'hasSchedule': true,
              }),
              _m({'id': 'legacy', 'status': 'completed', 'hasSchedule': false}),
            ],
            'nextCursor': 'none|legacy',
            'truncated': false,
          });
        },
      );

      final result = await repo.fetchStudentCaseHistory(
        studentId: 's1',
        cursor: '123|a1',
        pageSize: 10,
      );

      expect(calls.single.$1, 'getStudentCaseHistory');
      expect(calls.single.$2, {
        'studentId': 's1',
        'cursor': '123|a1',
        'pageSize': 10,
      });
      expect(result.displayName, 'Ana Cruz');
      expect(result.nextCursor, 'none|legacy');
      expect(result.items.map((e) => e.id), ['a2', 'legacy']);
      final first = result.items.first;
      expect(first.archived, isTrue);
      expect(first.scheduledAt, DateTime.utc(2026, 4, 2, 1));
      expect(first.counselorName, 'Coach Cite');
      final legacy = result.items.last;
      expect(legacy.scheduledAt, isNull);
      expect(legacy.sortDate, isNull);
      expect(legacy.counselorName, '');
    },
  );

  test('the first page omits the cursor', () async {
    Map<String, Object?>? sent;
    final repo = AdminPortalRepository(
      callableInvoker: (name, data) async {
        sent = data;
        return _m({'items': <Object?>[], 'nextCursor': null});
      },
    );
    final result = await repo.fetchStudentCaseHistory(studentId: 's1');
    expect(sent, {'studentId': 's1', 'pageSize': 20});
    expect(result.items, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test(
    'entries fall back to createdAt for grouping when no schedule exists',
    () {
      final entry = StudentCaseHistoryEntry.fromJson({
        'id': 'x',
        'createdAt': '2025-01-05T00:00:00.000Z',
      });
      expect(entry.sortDate, DateTime.utc(2025, 1, 5));
      expect(entry.status, '');
    },
  );
}
