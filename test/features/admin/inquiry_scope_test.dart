import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/inquiry_scope.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

AdminInquiryModel _inquiry(
  String id, {
  List<String>? assignees,
  Map<String, dynamic> extra = const {},
}) => AdminInquiryModel.fromJson({
  'id': id,
  'userId': 'student-$id',
  'subject': 'Subject $id',
  'message': 'Message $id',
  'category': 'General',
  'email': 'student-$id@example.edu',
  'status': 'pending',
  'createdAt': '2026-11-14T08:00:00.000',
  'assigneeIds': ?assignees,
  ...extra,
});

void main() {
  test('parses routing, assignment and escalation fields', () {
    final inquiry = _inquiry(
      'a',
      assignees: ['c1', 's1'],
      extra: {
        'collegeId': 'cite',
        'routingStatus': 'routed',
        'routingMode': 'manual',
        'routingRevision': 3,
        'ownerId': 'c1',
        'assigneeLabels': {'c1': 'Counselor One', 's1': 'Staff One'},
        'escalation': {
          'status': 'requested',
          'type': 'counselor_confirmation',
          'reason': 'Needs review',
        },
      },
    );
    expect(inquiry.collegeId, 'cite');
    expect(inquiry.routingStatus, InquiryRoutingStatus.routed);
    expect(inquiry.routingRevision, 3);
    expect(inquiry.assigneeIds, ['c1', 's1']);
    expect(inquiry.assigneeLabels['s1'], 'Staff One');
    expect(inquiry.ownerId, 'c1');
    expect(inquiry.isManuallyRouted, isTrue);
    expect(inquiry.isEscalated, isTrue);
    expect(inquiry.escalationType, InquiryEscalationType.counselorConfirmation);
    expect(inquiry.escalationReason, 'Needs review');
  });

  test('legacy inquiries without routing fields read as unrouted', () {
    final legacy = _inquiry('legacy');
    expect(legacy.routingStatus, InquiryRoutingStatus.unrouted);
    expect(legacy.assigneeIds, isEmpty);
    expect(legacy.routingRevision, 0);
    expect(legacy.isEscalated, isFalse);
    final triage = _inquiry(
      't',
      extra: {
        'routingStatus': 'needs_triage',
        'routingReason': 'missing_college',
      },
    );
    expect(triage.routingStatus, InquiryRoutingStatus.needsTriage);
    expect(triage.routingReason, 'missing_college');
  });

  test(
    'counselors see only assigned raw inquiries; portalStaff see only assigned operational projections',
    () {
      final rawMine = _inquiry('mine', assignees: ['c1', 's1']);
      final rawTheirs = _inquiry('theirs', assignees: ['c2']);
      final rawTriage = _inquiry('triage', assignees: const []);
      final rawLegacy = _inquiry('legacy');
      final opMine = AdminInquiryModel.fromOperationalProjection({
        'inquiryId': 'mine',
        'category': 'Service Form',
        'operationalLabel': 'Service Form',
        'status': 'pending',
        'routingStatus': 'routed',
        'assigneeIds': ['c1'],
        'monitoringStaffIds': ['s1'],
        'createdAt': '2026-11-14T08:00:00.000',
      });
      final opOther = AdminInquiryModel.fromOperationalProjection({
        'inquiryId': 'other',
        'category': 'Service Form',
        'operationalLabel': 'Service Form',
        'status': 'pending',
        'routingStatus': 'routed',
        'assigneeIds': ['c2'],
        'monitoringStaffIds': ['s2'],
        'createdAt': '2026-11-14T08:00:00.000',
      });

      expect(
        scopeInquiriesForRole(
          [rawMine, rawTheirs, rawTriage, rawLegacy, opMine],
          role: AccessRole.counselor,
          uid: 'c1',
          isSuperAdmin: false,
        ).map((i) => i.id),
        ['mine'],
      );
      expect(
        scopeInquiriesForRole(
          [rawMine, opMine, opOther],
          role: AccessRole.portalStaff,
          uid: 's1',
          isSuperAdmin: false,
        ).map((i) => i.id),
        ['mine'],
      );
      expect(
        scopeInquiriesForRole(
          [rawMine, rawTheirs],
          role: AccessRole.portalStaff,
          uid: 's1',
          isSuperAdmin: false,
        ),
        isEmpty,
      );
      expect(
        scopeInquiriesForRole(
          [rawMine, opMine],
          role: AccessRole.counselor,
          uid: null,
          isSuperAdmin: false,
        ),
        isEmpty,
      );
    },
  );

  test('super-administrator sees only counselor-processed or forwarded inquiries', () {
    final unprocessed = _inquiry('a', assignees: ['c2']);
    final legacyUnprocessed = _inquiry('legacy');
    final resolved = _inquiry('resolved', extra: {'status': 'resolved'});
    final forwarded = _inquiry(
      'forwarded',
      extra: {
        'escalation': {'status': 'requested', 'type': 'counselor_confirmation'},
      },
    );
    final takenOver = _inquiry(
      'taken',
      extra: {
        'takeover': {'by': 'admin', 'byName': 'Admin', 'reason': 'Urgent'},
      },
    );
    final items = [unprocessed, legacyUnprocessed, resolved, forwarded, takenOver];
    expect(
      scopeInquiriesForRole(
        items,
        role: AccessRole.admin,
        uid: 'admin',
        isSuperAdmin: true,
      ).map((i) => i.id),
      ['resolved', 'forwarded', 'taken'],
    );
    expect(
      scopeInquiriesForRole(
        items,
        role: AccessRole.admin,
        uid: 'other-admin',
        isSuperAdmin: false,
      ),
      isEmpty,
    );
  });

  test('repository inquiry actions call the audited callables', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final repository = AdminPortalRepository(
      callableInvoker: (name, data) async {
        calls.add((name, data));
        return {
          'ok': true,
          'revision': 4,
          'routed': 2,
          'needsTriage': 1,
          'done': false,
          'nextCursor': 'inq-500',
        };
      },
    );
    await repository.updateInquiryStatus('i1', InquiryStatus.resolved);
    await repository.acknowledgeInquiry('i1');
    await repository.escalateInquiry(
      'i1',
      escalationType: InquiryEscalationType.counselorConfirmation,
    );
    expect(
      await repository.reassignInquiry(
        'i1',
        assigneeIds: const ['c2'],
        expectedRevision: 3,
        reason: 'Coverage',
      ),
      4,
    );
    final backfill = await repository.routeExistingInquiries();
    expect(backfill.routed, 2);
    expect(backfill.needsTriage, 1);
    expect(backfill.done, isFalse);
    expect(backfill.nextCursor, 'inq-500');
    await repository.routeExistingInquiries(cursor: 'inq-500');
    expect(calls.map((c) => c.$1), [
      'setInquiryStatus',
      'acknowledgeInquiry',
      'escalateInquiry',
      'reassignInquiry',
      'routeExistingInquiries',
      'routeExistingInquiries',
    ]);
    expect(calls[0].$2, {'inquiryId': 'i1', 'status': 'resolved'});
    expect(calls[2].$2, {
      'inquiryId': 'i1',
      'escalationType': 'counselor_confirmation',
    });
    expect(calls[3].$2, {
      'inquiryId': 'i1',
      'assigneeIds': ['c2'],
      'expectedRevision': 3,
      'reason': 'Coverage',
    });
    expect(calls[4].$2, {'limit': 100});
    expect(calls[5].$2, {'limit': 100, 'cursor': 'inq-500'});
  });
}
