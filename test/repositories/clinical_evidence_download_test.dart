import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/session_evidence.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _CounselorRepository extends AdminPortalRepository {
  _CounselorRepository({required super.callableInvoker});

  @override
  AccessRole get currentAccessRole => AccessRole.counselor;

  @override
  String get currentUserId => 'counselor_1';
}

void main() {
  const appointmentId = 'appointment_1';
  const uploaderUid = 'counselor_1';
  const nonce = '0123456789abcdef0123456789abcdef';
  const validPath =
      'counseling_session_files/$appointmentId/$uploaderUid/$nonce.pdf';

  test(
    'clinical upload uses the private callable with the evidence bytes',
    () async {
      final bytes = Uint8List.fromList([37, 80, 68, 70]);
      Map<String, Object?>? payload;
      final repo = _CounselorRepository(
        callableInvoker: (name, data) async {
          expect(name, 'uploadClinicalSessionEvidence');
          payload = data;
          return {'path': validPath};
        },
      );
      final attachments = await repo.uploadClinicalEvidenceFiles(
        appointmentId: appointmentId,
        files: [
          PendingSessionEvidenceFile(
            name: 'Worksheet.pdf',
            contentType: 'application/pdf',
            bytes: bytes,
          ),
        ],
      );
      expect(payload?['appointmentId'], appointmentId);
      expect(payload?.containsKey('path'), isFalse);
      expect(attachments.single.path, validPath);
      expect(payload?['dataBase64'], base64Encode(bytes));
      expect(attachments.single.size, bytes.length);
    },
  );

  test(
    'getClinicalEvidenceBytes invokes downloadClinicalSessionEvidence with appointmentId and decodes bytes',
    () async {
      final expectedBytes = Uint8List.fromList([
        37,
        80,
        68,
        70,
        45,
        49,
        46,
        52,
      ]);
      String? calledName;
      Map<String, Object?>? calledData;
      final repo = AdminPortalRepository(
        callableInvoker: (name, data) async {
          calledName = name;
          calledData = data;
          return {
            'name': 'Worksheet.pdf',
            'contentType': 'application/pdf',
            'size': expectedBytes.length,
            'dataBase64': base64Encode(expectedBytes),
          };
        },
      );

      final actual = await repo.getClinicalEvidenceBytes(
        validPath,
        appointmentId: appointmentId,
      );
      expect(calledName, 'downloadClinicalSessionEvidence');
      expect(calledData, {'appointmentId': appointmentId, 'path': validPath});
      expect(actual, expectedBytes);
    },
  );

  test(
    'getClinicalEvidenceBytes derives appointmentId from path when omitted',
    () async {
      final expectedBytes = Uint8List.fromList([1, 2, 3, 4]);
      Map<String, Object?>? calledData;
      final repo = AdminPortalRepository(
        callableInvoker: (name, data) async {
          calledData = data;
          return {'dataBase64': base64Encode(expectedBytes)};
        },
      );

      final actual = await repo.getClinicalEvidenceBytes(validPath);
      expect(calledData, {'appointmentId': appointmentId, 'path': validPath});
      expect(actual, expectedBytes);
    },
  );

  test(
    'getClinicalEvidenceBytes rejects invalid paths, traversal, and mismatched appointmentId before calling backend',
    () async {
      var invokerCalled = false;
      final repo = AdminPortalRepository(
        callableInvoker: (_, _) async {
          invokerCalled = true;
          return {
            'dataBase64': base64Encode([1, 2, 3]),
          };
        },
      );

      final invalidCases = <({String path, String? appointmentId})>[
        (path: 'backups/2026/export.json', appointmentId: null),
        (path: 'profile_images/$uploaderUid/$nonce.png', appointmentId: null),
        (
          path:
              'counseling_session_files/$appointmentId/$uploaderUid/../$nonce.pdf',
          appointmentId: appointmentId,
        ),
        (
          path:
              'counseling_session_files/$appointmentId/$uploaderUid/%2e%2e/$nonce.pdf',
          appointmentId: appointmentId,
        ),
        (
          path:
              'counseling_session_files/$appointmentId/$uploaderUid\\$nonce.pdf',
          appointmentId: appointmentId,
        ),
        (
          path:
              'counseling_session_files/$appointmentId/$uploaderUid/sub/$nonce.pdf',
          appointmentId: appointmentId,
        ),
        (
          path:
              'counseling_session_files/$appointmentId/$uploaderUid/0123456789ABCDEF0123456789ABCDEF.pdf',
          appointmentId: appointmentId,
        ),
        (
          path:
              'counseling_session_files/$appointmentId/$uploaderUid/$nonce.txt',
          appointmentId: appointmentId,
        ),
        (path: validPath, appointmentId: 'other_appointment'),
        (path: validPath, appointmentId: '   '),
      ];

      for (final item in invalidCases) {
        await expectLater(
          () => repo.getClinicalEvidenceBytes(
            item.path,
            appointmentId: item.appointmentId,
          ),
          throwsFormatException,
        );
      }
      expect(invokerCalled, isFalse);
    },
  );

  test(
    'getClinicalEvidenceBytes rejects empty, missing, or oversized payloads',
    () async {
      for (final payload in <Object?>[
        null,
        <String, Object?>{},
        {'dataBase64': ''},
        {'dataBase64': base64Encode(Uint8List(0))},
        {
          'dataBase64': base64Encode(
            Uint8List(maxSessionEvidenceFileBytes + 1),
          ),
        },
      ]) {
        final repo = AdminPortalRepository(
          callableInvoker: (_, _) async => payload,
        );
        await expectLater(
          () => repo.getClinicalEvidenceBytes(
            validPath,
            appointmentId: appointmentId,
          ),
          throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
        );
      }
    },
  );

  test(
    'getClinicalEvidenceBytes propagates FirebaseFunctionsException codes cleanly',
    () async {
      for (final code in [
        'permission-denied',
        'not-found',
        'failed-precondition',
        'unavailable',
      ]) {
        final repo = AdminPortalRepository(
          callableInvoker: (_, _) async => throw FirebaseFunctionsException(
            code: code,
            message: 'Server $code',
          ),
        );
        await expectLater(
          () => repo.getClinicalEvidenceBytes(
            validPath,
            appointmentId: appointmentId,
          ),
          throwsA(
            isA<FirebaseFunctionsException>().having(
              (e) => e.code,
              'code',
              code,
            ),
          ),
        );
      }
    },
  );
}
