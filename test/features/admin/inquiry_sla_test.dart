import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/inquiry_sla.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';

final _created = DateTime.utc(2026, 11, 14, 8);

AdminInquiryModel _inquiry({Map<String, dynamic> extra = const {}}) =>
    AdminInquiryModel.fromJson({
      'id': 'inq',
      'userId': 'student',
      'subject': 'S',
      'message': 'M',
      'category': 'Service Form',
      'email': 's@x',
      'status': 'pending',
      'createdAt': _created.toIso8601String(),
      ...extra,
    });

void main() {
  const target = InquirySla(hours: 48);
  final deadline = _created.add(const Duration(hours: 48));

  test('the deadline is creation plus the configured target', () {
    expect(target.deadlineFor(_inquiry()), deadline);
  });

  test('just before the deadline is not overdue; exactly at and after are', () {
    final inquiry = _inquiry();
    expect(target.isOverdue(inquiry, deadline.subtract(const Duration(seconds: 1))), isFalse);
    expect(target.isOverdue(inquiry, deadline), isTrue);
    expect(target.isOverdue(inquiry, deadline.add(const Duration(hours: 3))), isTrue);
  });

  test('a replied or resolved inquiry is never overdue; acknowledgement alone is not a reply', () {
    final late = deadline.add(const Duration(days: 2));
    expect(target.isOverdue(_inquiry(extra: {'firstResponseAt': '2026-11-14T09:00:00.000Z'}), late), isFalse);
    expect(target.isOverdue(_inquiry(extra: {'status': 'resolved'}), late), isFalse);
    expect(target.isOverdue(_inquiry(extra: {'status': 'in_progress', 'acknowledgedAt': '2026-11-14T09:00:00.000Z'}), late), isTrue);
  });

  test('without a configured target nothing is flagged', () {
    expect(const InquirySla(hours: null).isOverdue(_inquiry(), deadline.add(const Duration(days: 30))), isFalse);
    expect(const InquirySla(hours: null).isConfigured, isFalse);
    expect(InquirySla.fromJson(null).isConfigured, isFalse);
    expect(InquirySla.fromJson({'hours': 36}).isConfigured, isFalse, reason: 'only PACC options are accepted');
    expect(InquirySla.fromJson({'hours': 72}).hours, 72);
  });

  test('overdue list is oldest first and reports age', () {
    final now = deadline.add(const Duration(hours: 10));
    final older = AdminInquiryModel.fromJson({..._inquiry().toJson(), 'id': 'older', 'createdAt': _created.subtract(const Duration(hours: 5)).toIso8601String()});
    final items = [
      _inquiry(),
      older,
      _inquiry(extra: {'id': 'answered', 'firstResponseAt': '2026-11-14T10:00:00.000Z'}),
      _inquiry(extra: {'id': 'fresh', 'createdAt': now.subtract(const Duration(hours: 1)).toIso8601String()}),
    ];
    final overdue = target.overdue(items, now);
    expect(overdue.map((i) => i.id), ['older', 'inq']);
    expect(target.ageOf(_inquiry(), now), const Duration(hours: 58));
  });

  test('response fields and takeover parse from the inquiry document', () {
    final inquiry = _inquiry(extra: {
      'firstResponseAt': '2026-11-14T10:00:00.000Z',
      'lastResponseAt': '2026-11-15T10:00:00.000Z',
      'lastResponseByName': 'Counselor One',
      'lastResponseRole': 'counselor',
      'responseCount': 2,
      'takeover': {'by': 'admin', 'byName': 'Super Admin', 'reason': 'Overdue'},
    });
    expect(inquiry.firstResponseAt, DateTime.utc(2026, 11, 14, 10));
    expect(inquiry.lastResponseByName, 'Counselor One');
    expect(inquiry.responseCount, 2);
    expect(inquiry.isTakenOver, isTrue);
    expect(inquiry.takeoverByName, 'Super Admin');
    expect(_inquiry().isTakenOver, isFalse);
  });
}
