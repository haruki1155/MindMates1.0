import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/student_roster_models.dart';
import 'package:mind_mates/repositories/student_roster_repository.dart';

Map<Object?, Object?> _m(Map<Object?, Object?> v) => v;

void main() {
  late List<(String, Map<String, Object?>)> calls;
  late Object? Function(String name) respond;

  StudentRosterRepository build() {
    calls = [];
    return StudentRosterRepository(
      invoker: (name, data) async {
        calls.add((name, data));
        final r = respond(name);
        if (r is Exception) throw r;
        return r;
      },
    );
  }

  final codeJson = _m({
    'studentNo': '1',
    'name': 'A B',
    'college': 'c',
    'course': 'k',
    'yearLevel': '1st Year',
    'code': 'ABCD-EFGH',
    'expiresAt': '2026-12-01T00:00:00.000Z',
  });

  test('previewImport maps kinds and changes', () async {
    final repo = build();
    respond = (_) => _m({
      'rows': <Object?>[
        _m({'index': 0, 'studentNo': '1', 'kind': 'new'}),
        _m({
          'index': 1,
          'studentNo': '2',
          'kind': 'update',
          'changes': _m({
            'course': _m({'from': 'A', 'to': 'B'}),
          }),
        }),
        _m({'index': 2, 'studentNo': '3', 'kind': 'link'}),
        _m({
          'index': 3,
          'studentNo': '',
          'kind': 'error',
          'errors': <Object?>['bad'],
        }),
      ],
      'counts': _m({'new': 1, 'update': 1, 'link': 1, 'error': 1}),
    });
    final result = await repo.previewImport('f.xlsx', [
      {'studentNo': '1'},
    ]);
    expect(result.rows.map((r) => r.kind), [
      RosterPreviewKind.newRow,
      RosterPreviewKind.update,
      RosterPreviewKind.link,
      RosterPreviewKind.error,
    ]);
    expect(result.rows[1].changes['course'], (from: 'A', to: 'B'));
    expect(result.rows[3].errors, ['bad']);
    expect(result.counts['update'], 1);
    expect(calls.single.$1, 'previewStudentRosterImport');
    expect(calls.single.$2['fileName'], 'f.xlsx');
  });

  test('commitImport surfaces partial status, failed rows, message', () async {
    final repo = build();
    respond = (_) => _m({
      'status': 'partial',
      'importId': 'i1',
      'counts': _m({'new': 1, 'updated': 0, 'linked': 0}),
      'codes': <Object?>[codeJson],
      'failedRows': <Object?>[
        _m({'index': 5, 'studentNo': '9'}),
      ],
      'message': 'stopped',
    });
    final r = await repo.commitImport('f', [
      {'studentNo': '1'},
    ]);
    expect(r.status, RosterImportStatus.partial);
    expect(r.importId, 'i1');
    expect(r.codes.single.code, 'ABCD-EFGH');
    expect(r.codes.single.expiresAt, DateTime.utc(2026, 12, 1));
    expect(r.failedRows.single.studentNo, '9');
    expect(r.message, 'stopped');
    expect(r.counts['new'], 1);
  });

  test('commitImport complete has no failed rows', () async {
    final repo = build();
    respond = (_) => _m({
      'status': 'complete',
      'importId': 'i',
      'counts': _m({'new': 0}),
      'codes': <Object?>[],
    });
    final r = await repo.commitImport('f', [{}]);
    expect(r.status, RosterImportStatus.complete);
    expect(r.failedRows, isEmpty);
    expect(r.message, isNull);
  });

  test('activate sends payload and returns email', () async {
    final repo = build();
    respond = (_) => _m({'ok': true, 'email': 'a@b.c'});
    final email = await repo.activate(
      studentNo: '2021-00123',
      activationCode: 'ABCD-EFGH',
      dateOfBirthKey: '2003-04-05',
      email: 'a@b.c',
      password: 'pw',
    );
    expect(email, 'a@b.c');
    expect(calls.single.$1, 'activateStudentAccount');
    expect(calls.single.$2['dateOfBirth'], '2003-04-05');
  });

  test('activate maps details.reason to StudentActivationException', () async {
    final repo = build();
    const reasons = {
      'mismatch': StudentActivationFailure.mismatch,
      'expired': StudentActivationFailure.expired,
      'already-activated': StudentActivationFailure.alreadyActivated,
      'email-in-use': StudentActivationFailure.emailInUse,
      'invalid-input': StudentActivationFailure.invalidInput,
    };
    Future<void> call() => repo.activate(
      studentNo: 's',
      activationCode: 'c',
      dateOfBirthKey: 'd',
      email: 'e',
      password: 'p',
    );
    for (final e in reasons.entries) {
      respond = (_) => FirebaseFunctionsException(
        code: 'not-found',
        message: 'server says ${e.key}',
        details: _m({'reason': e.key}),
      );
      await expectLater(
        call(),
        throwsA(
          isA<StudentActivationException>()
              .having((x) => x.reason, 'reason', e.value)
              .having((x) => x.message, 'message', 'server says ${e.key}'),
        ),
      );
    }
    respond = (_) => FirebaseFunctionsException(code: 'internal', message: 'm');
    await expectLater(
      call(),
      throwsA(
        isA<StudentActivationException>().having(
          (x) => x.reason,
          'reason',
          StudentActivationFailure.unknown,
        ),
      ),
    );
  });

  test('listRoster maps rows and page token', () async {
    final repo = build();
    respond = (_) => _m({
      'rows': <Object?>[
        _m({
          'studentNo': '1',
          'name': 'A',
          'college': 'c',
          'course': 'k',
          'yearLevel': '1st Year',
          'activated': true,
          'status': 'active',
          'personalInfoComplete': false,
          'userId': 'u1',
        }),
      ],
      'nextPageToken': 'tok',
    });
    final r = await repo.listRoster(search: 'cruz', pageToken: 'p');
    expect(r.rows.single.activated, isTrue);
    expect(r.rows.single.userId, 'u1');
    expect(r.nextPageToken, 'tok');
    expect(calls.single.$2, {'search': 'cruz', 'pageToken': 'p'});
  });

  test('issue codes, revoke, backfill, corrections', () async {
    final repo = build();
    respond = (_) => _m({
      'codes': <Object?>[codeJson],
      'skipped': <Object?>[
        _m({'studentNo': '2', 'reason': 'Deactivated.'}),
      ],
    });
    final issued = await repo.issueActivationCodes(['1', '2']);
    expect(issued.codes.single.code, 'ABCD-EFGH');
    expect(issued.skipped.single.reason, 'Deactivated.');

    respond = (_) => _m({'code': codeJson});
    expect((await repo.revokeActivation('1', 'why')).code, 'ABCD-EFGH');
    expect(calls.last.$2, {'studentNo': '1', 'reason': 'why'});

    respond = (_) => _m({'flagged': 3, 'notInRoster': 2});
    final b = await repo.backfillInfoRequirement();
    expect((b.flagged, b.notInRoster), (3, 2));

    respond = (_) => _m({
      'requests': <Object?>[
        _m({
          'id': 'c1',
          'userId': 'u',
          'studentNo': '1',
          'studentName': 'A',
          'field': 'surname',
          'currentValue': 'x',
          'requestedValue': 'y',
          'reason': 'r',
          'status': 'pending',
          'reviewReason': '',
          'createdAt': '2026-11-01T00:00:00.000Z',
        }),
      ],
    });
    final cs = await repo.listCorrections(pendingOnly: true);
    expect(cs.single.studentName, 'A');
    expect(calls.last.$2, {'status': 'pending'});

    respond = (_) => _m({'status': 'approved'});
    await repo.reviewCorrection('c1', approve: true);
    expect(calls.last.$2, {'requestId': 'c1', 'decision': 'approve'});
  });

  test('getMyInformation and thin wrappers send expected payloads', () async {
    final repo = build();
    respond = (_) => _m({
      'official': _m({'studentNo': '1'}),
      'personal': null,
      'corrections': <Object?>[],
    });
    final info = await repo.getMyInformation();
    expect(info.official.studentNo, '1');

    respond = (_) => _m({'ok': true});
    await repo.setRosterStatus('1', active: false);
    expect(calls.last.$2, {'studentNo': '1', 'status': 'deactivated'});
    await repo.updateRosterRecord('1', {'course': 'x'});
    expect(calls.last.$2, {
      'studentNo': '1',
      'fields': {'course': 'x'},
    });
    await repo.resetActivationLock('1');
    expect(calls.last.$1, 'resetStudentActivationLock');

    respond = (_) => _m({
      'imports': <Object?>[
        _m({
          'id': 'i',
          'fileName': 'f',
          'counts': _m({'new': 1, 'updated': 2, 'linked': 3}),
          'importedByName': 'Admin',
          'importedAt': '2026-11-01T00:00:00.000Z',
        }),
      ],
    });
    final imports = await repo.listImports();
    expect(imports.single.counts['updated'], 2);

    respond = (_) => _m({
      'rows': <Object?>[
        _m({'userId': 'u', 'schoolId': 's', 'name': 'n'}),
      ],
    });
    expect((await repo.listLegacyNotInRoster()).single.schoolId, 's');
  });
}
