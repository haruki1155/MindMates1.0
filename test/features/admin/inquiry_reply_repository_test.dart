import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

void main() {
  test('reply documents parse author, role, message and time', () {
    final reply = InquiryReply.fromJson({
      'message': 'We will call you.',
      'authorName': 'Counselor One',
      'authorRole': 'counselor',
      'createdAt': '2026-11-15T10:00:00.000Z',
    }, id: 'r1');
    expect(reply.id, 'r1');
    expect(reply.message, 'We will call you.');
    expect(reply.authorName, 'Counselor One');
    expect(reply.isAdministrator, isFalse);
    expect(
      InquiryReply.fromJson({'authorRole': 'admin'}, id: 'r2').isAdministrator,
      isTrue,
    );
  });

  test('request ids are path-safe, unique idempotency keys', () {
    final ids = {for (var i = 0; i < 200; i++) newInquiryRequestId()};
    expect(ids.length, 200);
    for (final id in ids) {
      expect(
        RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(id),
        isTrue,
        reason: id,
      );
    }
  });

  test(
    'reply, takeover, target and revision-checked status call the audited callables',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final repository = AdminPortalRepository(
        callableInvoker: (name, data) async {
          calls.add((name, data));
          return {
            'ok': true,
            'revision': 5,
            'replyId': 'req-1',
            'duplicate': false,
            'hours': 48,
          };
        },
      );
      expect(
        await repository.replyToInquiry(
          'i1',
          message: 'Hello',
          expectedRevision: 4,
          requestId: 'req-00000001',
        ),
        5,
      );
      expect(
        await repository.takeOverInquiry(
          'i1',
          expectedRevision: 5,
          reason: 'Past the target',
        ),
        5,
      );
      await repository.setInquirySla(48);
      await repository.updateInquiryStatus(
        'i1',
        InquiryStatus.resolved,
        expectedRevision: 5,
      );
      await repository.updateInquiryStatus('i1', InquiryStatus.inProgress);
      await repository.acknowledgeInquiry('i1', expectedRevision: 6);
      await repository.escalateInquiry(
        'i1',
        escalationType: InquiryEscalationType.counselorConfirmation,
        expectedRevision: 7,
      );
      await repository.escalateInquiry(
        'i1',
        escalationType: InquiryEscalationType.staffReasoned,
        reason: 'Needs review',
        expectedRevision: 8,
      );
      expect(calls.map((c) => c.$1), [
        'replyToInquiry',
        'takeOverInquiry',
        'setInquirySla',
        'setInquiryStatus',
        'setInquiryStatus',
        'acknowledgeInquiry',
        'escalateInquiry',
        'escalateInquiry',
      ]);
      expect(calls[0].$2, {
        'inquiryId': 'i1',
        'message': 'Hello',
        'expectedRevision': 4,
        'requestId': 'req-00000001',
      });
      expect(calls[1].$2, {
        'inquiryId': 'i1',
        'expectedRevision': 5,
        'reason': 'Past the target',
      });
      expect(calls[2].$2, {'hours': 48});
      expect(calls[3].$2, {
        'inquiryId': 'i1',
        'status': 'resolved',
        'expectedRevision': 5,
      });
      expect(calls[4].$2, {'inquiryId': 'i1', 'status': 'in_progress'});
      expect(calls[5].$2, {'inquiryId': 'i1', 'expectedRevision': 6});
      expect(calls[6].$2, {
        'inquiryId': 'i1',
        'escalationType': 'counselor_confirmation',
        'expectedRevision': 7,
      });
      expect(calls[6].$2.containsKey('reason'), isFalse);
      expect(calls[7].$2, {
        'inquiryId': 'i1',
        'escalationType': 'staff_reasoned',
        'reason': 'Needs review',
        'expectedRevision': 8,
      });

      final countBefore = calls.length;
      expect(() => repository.escalateInquiry('i1'), throwsArgumentError);
      expect(
        () => repository.escalateInquiry('i1', reason: 'no'),
        throwsArgumentError,
      );
      expect(
        () => repository.escalateInquiry('i1', reason: '   '),
        throwsArgumentError,
      );
      expect(
        () => repository.escalateInquiry(
          'i1',
          escalationType: InquiryEscalationType.counselorConfirmation,
          reason: 'Conflicting',
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.escalateInquiry(
          'i1',
          escalationType: InquiryEscalationType.staffReasoned,
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.escalateInquiry(
          'i1',
          escalationType: InquiryEscalationType.staffReasoned,
          reason: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.escalateInquiry(
          'i1',
          escalationType: InquiryEscalationType.staffReasoned,
          reason: '   ',
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.escalateInquiry(
          'i1',
          escalationType: InquiryEscalationType.counselorConfirmation,
          reason: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.escalateInquiry(
          'i1',
          escalationType: InquiryEscalationType.counselorConfirmation,
          reason: '   ',
        ),
        throwsArgumentError,
      );
      expect(calls.length, countBefore);
    },
  );
}
