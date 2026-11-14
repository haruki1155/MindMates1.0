import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/inquiry_scope.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/profile_roles.dart';

AdminInquiryModel _inquiry(String id, {String? assignedStaffId}) =>
    AdminInquiryModel.fromJson({
      'id': id,
      'userId': 'student-$id',
      'subject': 'Subject $id',
      'message': 'Message $id',
      'category': 'General',
      'email': 'student-$id@example.edu',
      'status': 'pending',
      'createdAt': '2026-11-14T08:00:00.000',
      'assignedStaffId': ?assignedStaffId,
    });

void main() {
  test('inquiry model keeps the assigned staff identifier', () {
    expect(
      _inquiry('a', assignedStaffId: 'counselor-1').assignedStaffId,
      'counselor-1',
    );
    expect(_inquiry('b').assignedStaffId, isNull);
    expect(_inquiry('c', assignedStaffId: '   ').assignedStaffId, isNull);
  });

  test(
    'counselor sees unassigned inquiries and inquiries assigned to them',
    () {
      final items = [
        _inquiry('unassigned'),
        _inquiry('mine', assignedStaffId: 'counselor-1'),
        _inquiry('theirs', assignedStaffId: 'counselor-2'),
      ];

      final visible = scopeInquiriesForRole(
        items,
        role: AccessRole.counselor,
        uid: 'counselor-1',
      );

      expect(visible.map((i) => i.id), ['unassigned', 'mine']);
    },
  );

  test('administrator sees every inquiry regardless of assignment', () {
    final items = [
      _inquiry('unassigned'),
      _inquiry('theirs', assignedStaffId: 'counselor-2'),
    ];

    final visible = scopeInquiriesForRole(
      items,
      role: AccessRole.admin,
      uid: 'admin-1',
    );

    expect(visible.length, 2);
  });

  test(
    'counselor without a session identity sees only unassigned inquiries',
    () {
      final items = [
        _inquiry('unassigned'),
        _inquiry('theirs', assignedStaffId: 'counselor-2'),
      ];

      final visible = scopeInquiriesForRole(
        items,
        role: AccessRole.counselor,
        uid: null,
      );

      expect(visible.map((i) => i.id), ['unassigned']);
    },
  );
}
