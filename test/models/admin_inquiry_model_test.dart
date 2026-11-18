import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';

void main() {
  test('parses inquiry status and preserves inquiry details', () {
    final inquiry = AdminInquiryModel.fromJson({
      'id': 'inquiry-1',
      'userId': 'user-1',
      'subject': 'Course selection',
      'message': 'I need guidance choosing classes.',
      'category': 'Academic',
      'email': 'student@example.edu',
      'name': 'Jamie Lee',
      'role': 'student',
      'status': 'in_progress',
      'createdAt': '2026-07-13T10:00:00.000',
    });

    expect(inquiry.status, InquiryStatus.inProgress);
    expect(inquiry.displayName, 'Jamie Lee');
    expect(inquiry.toJson()['status'], 'in_progress');
  });

  test('defaults an unknown inquiry status to pending', () {
    expect(InquiryStatus.fromValue('new'), InquiryStatus.pending);
    expect(InquiryStatus.resolved.label, 'Resolved');
  });

  test('fromOperationalProjection strips student PII, message, subject and formData', () {
    final projection = AdminInquiryModel.fromOperationalProjection({
      'inquiryId': 'inq-99',
      'userId': 'student-secret',
      'subject': 'Sensitive student subject',
      'message': 'Confidential student narrative',
      'email': 'student@secret.edu',
      'name': 'Private Student',
      'category': 'Service Form',
      'formType': 'client_feedback',
      'operationalLabel': 'Client Feedback Form',
      'formData': {'q': 'private answer'},
      'collegeId': 'cite',
      'status': 'in_progress',
      'routingStatus': 'routed',
      'routingMode': 'manual',
      'routingRevision': 4,
      'assigneeIds': ['c1'],
      'assigneeLabels': {'c1': 'Counselor One'},
      'monitoringStaffIds': ['s1'],
      'monitoringStaffLabels': {'s1': 'Staff One'},
      'escalationStatus': 'requested',
      'escalation': {'status': 'requested', 'reason': 'Secret escalation note'},
      'createdAt': '2026-11-18T08:00:00.000',
    });

    expect(projection.isOperationalProjection, isTrue);
    expect(projection.id, 'inq-99');
    expect(projection.operationalLabel, 'Client Feedback Form');
    expect(projection.subject, 'Client Feedback Form');
    expect(projection.userId, isEmpty);
    expect(projection.message, isEmpty);
    expect(projection.email, isEmpty);
    expect(projection.name, isNull);
    expect(projection.formData, isEmpty);
    expect(projection.escalationStatus, 'requested');
    expect(projection.escalationReason, isNull);
    expect(projection.monitoringStaffIds, ['s1']);
  });
}
