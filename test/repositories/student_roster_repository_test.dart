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
        _m({
          'index': 2,
          'studentNo': '3',
          'kind': 'link',
          'warnings': <Object?>['different name'],
        }),
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
    expect(result.rows[2].warnings, ['different name']);
    expect(result.rows[0].warnings, isEmpty);
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

  test(
    'startAccountSetup sends identity without any activation code',
    () async {
      final repo = build();
      respond = (_) =>
          _m({'ok': true, 'authEmail': 'a@students.mindmate.local'});
      final email = await repo.startAccountSetup(
        studentNo: '2021-00123',
        firstName: 'Ana',
        middleName: '',
        lastName: 'Cruz',
        dateOfBirthKey: '2003-04-05',
        email: 'a@b.c',
        password: 'pw',
      );
      expect(email, 'a@students.mindmate.local');
      expect(calls.single.$1, 'startStudentAccountSetup');
      expect(calls.single.$2['dateOfBirth'], '2003-04-05');
      expect(calls.single.$2.containsKey('activationCode'), isFalse);
    },
  );

  test('startAccountSetup maps the callable error code', () async {
    final repo = build();
    const codes = {
      'not-found': StudentActivationFailure.mismatch,
      'already-exists': StudentActivationFailure.emailInUse,
      'resource-exhausted': StudentActivationFailure.inProgress,
      'invalid-argument': StudentActivationFailure.invalidInput,
      'internal': StudentActivationFailure.unknown,
    };
    for (final e in codes.entries) {
      respond = (_) =>
          FirebaseFunctionsException(code: e.key, message: 'server ${e.key}');
      await expectLater(
        repo.startAccountSetup(
          studentNo: 's',
          firstName: 'f',
          middleName: '',
          lastName: 'l',
          dateOfBirthKey: 'd',
          email: 'e',
          password: 'p',
        ),
        throwsA(
          isA<StudentActivationException>()
              .having((x) => x.reason, 'reason', e.value)
              .having((x) => x.message, 'message', 'server ${e.key}'),
        ),
      );
    }
  });

  test(
    'completeAccountSetup reports waiting for approval unless approved',
    () async {
      final repo = build();
      respond = (_) => _m({'ok': true, 'status': 'awaiting-approval'});
      expect(await repo.completeAccountSetup(), 'awaiting-approval');
      expect(calls.single.$1, 'completeStudentAccountSetup');
      respond = (_) => _m({'ok': true, 'status': 'approved'});
      expect(await repo.completeAccountSetup(), 'approved');
      respond = (_) => _m({'ok': true});
      expect(
        await repo.completeAccountSetup(),
        'awaiting-approval',
        reason: 'never assume approval',
      );
    },
  );

  test('account claim review calls the administrator callables', () async {
    final repo = build();
    respond = (_) => _m({
      'claims': <Object?>[
        _m({
          'uid': 'u1',
          'studentNo': '2021-001',
          'name': 'Ana Cruz',
          'email': 'a@b.c',
          'submittedAt': '2026-11-20T00:00:00.000Z',
        }),
      ],
    });
    final claims = await repo.listAccountClaims();
    expect(claims.single.uid, 'u1');
    expect(claims.single.email, 'a@b.c');
    expect(claims.single.rosterAlreadyClaimed, isFalse);
    respond = (_) => _m({'ok': true});
    await repo.approveAccountClaim('u1');
    expect(calls.last.$1, 'approveStudentAccountClaim');
    expect(calls.last.$2, {'uid': 'u1'});
    await repo.rejectAccountClaim('u1');
    expect(calls.last.$1, 'rejectStudentAccountClaim');
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

  test('revoke, backfill, corrections', () async {
    final repo = build();
    respond = (_) => _m({'ok': true});
    await repo.revokeActivation('1', 'why');
    expect(calls.last.$1, 'revokeStudentActivation');
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

  test(
    'commitImport sets extended timeout without altering unrelated callables',
    () async {
      final recorded = <(String name, HttpsCallableOptions? options)>[];
      final repo = StudentRosterRepository(
        functions: _RecordingFirebaseFunctions((name, options) {
          recorded.add((name, options));
          if (name == 'importStudentRoster') {
            return _m({
              'status': 'complete',
              'importId': 'imp-1',
              'counts': _m({'new': 1}),
              'codes': <Object?>[],
            });
          }
          return _m({'imports': <Object?>[]});
        }),
      );

      final result = await repo.commitImport('roster.xlsx', [
        {'studentNo': '1'},
      ]);
      expect(result.status, RosterImportStatus.complete);
      expect(recorded.single.$1, 'importStudentRoster');
      expect(recorded.single.$2?.timeout, const Duration(minutes: 10));

      await repo.listImports();
      expect(recorded.last.$1, 'listStudentRosterImports');
      expect(recorded.last.$2, isNull);
    },
  );

  test(
    'RosterImportRecord.fromJson parses known statuses and tolerates legacy or malformed fields',
    () {
      final complete = RosterImportRecord.fromJson(
        _m({
          'id': 'imp-complete',
          'fileName': 'complete.xlsx',
          'status': 'complete',
          'rowCount': 10,
          'failedRowCount': 0,
          'counts': _m({'new': 10, 'updated': 0, 'linked': 0}),
          'importedByName': 'Admin A',
          'importedAt': '2026-11-01T08:00:00.000Z',
        }),
      );
      expect(complete.status, RosterImportHistoryStatus.complete);
      expect(complete.rowCount, 10);
      expect(complete.failedRowCount, 0);
      expect(complete.failureCode, isNull);

      final partial = RosterImportRecord.fromJson(
        _m({
          'id': 'imp-partial',
          'fileName': 'partial.xlsx',
          'status': 'partial',
          'rowCount': 12,
          'failedRowCount': 4,
          'failureCode': 'time-budget-exceeded',
          'counts': _m({'new': 5, 'updated': 3, 'linked': 0}),
          'importedByName': 'Admin A',
          'importedAt': '2026-11-01T09:00:00.000Z',
        }),
      );
      expect(partial.status, RosterImportHistoryStatus.partial);
      expect(partial.rowCount, 12);
      expect(partial.failedRowCount, 4);
      expect(partial.failureCode, 'time-budget-exceeded');

      final pending = RosterImportRecord.fromJson(
        _m({
          'id': 'imp-pending',
          'fileName': 'pending.xlsx',
          'status': 'pending',
          'rowCount': 50,
          'counts': _m({'new': 0, 'updated': 0, 'linked': 0}),
          'importedByName': 'Admin A',
          'importedAt': '2026-11-01T10:00:00.000Z',
        }),
      );
      expect(pending.status, RosterImportHistoryStatus.pending);
      expect(pending.rowCount, 50);
      expect(pending.failedRowCount, isNull);

      final finFail = RosterImportRecord.fromJson(
        _m({
          'id': 'imp-finfail',
          'fileName': 'finfail.xlsx',
          'status': 'partial',
          'rowCount': 20,
          'failedRowCount': 0,
          'failureCode': 'finalization-failed',
          'counts': _m({'new': 20, 'updated': 0, 'linked': 0}),
          'importedByName': 'Admin A',
          'importedAt': '2026-11-01T11:00:00.000Z',
        }),
      );
      expect(finFail.status, RosterImportHistoryStatus.partial);
      expect(finFail.failureCode, 'finalization-failed');
      expect(finFail.needsAttention, isTrue);

      final legacy = RosterImportRecord.fromJson(
        _m({
          'id': 'imp-legacy',
          'fileName': 'legacy.xlsx',
          'counts': _m({'new': 3, 'updated': 1, 'linked': 0}),
          'importedByName': 'Admin A',
          'importedAt': '2026-10-01T08:00:00.000Z',
        }),
      );
      expect(legacy.status, RosterImportHistoryStatus.unknown);
      expect(legacy.rowCount, isNull);
      expect(legacy.failedRowCount, isNull);
      expect(legacy.failureCode, isNull);

      final malformed = RosterImportRecord.fromJson(
        _m({
          'id': 'imp-bad',
          'fileName': 'bad.xlsx',
          'status': 'corrupted-status',
          'rowCount': -3,
          'failedRowCount': 'NaN',
          'failureCode': '',
          'counts': 'not-a-map',
          'importedByName': 42,
          'importedAt': 'invalid-date',
        }),
      );
      expect(malformed.status, RosterImportHistoryStatus.unknown);
      expect(malformed.rowCount, isNull);
      expect(malformed.failedRowCount, isNull);
      expect(malformed.failureCode, isNull);
    },
  );
}

class _RecordingFirebaseFunctions extends Fake implements FirebaseFunctions {
  _RecordingFirebaseFunctions(this._handler);

  final Object? Function(String name, HttpsCallableOptions? options) _handler;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _RecordingHttpsCallable(() => _handler(name, options));
}

class _RecordingHttpsCallable extends Fake implements HttpsCallable {
  _RecordingHttpsCallable(this._onCall);

  final Object? Function() _onCall;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async =>
      _FakeCallableResult<T>(_onCall() as T);
}

class _FakeCallableResult<T> extends Fake implements HttpsCallableResult<T> {
  _FakeCallableResult(this.data);

  @override
  final T data;
}
