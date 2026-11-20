import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/backup_export.dart';
import 'package:mind_mates/features/admin/domain/backup_job.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _SuperAdminTestRepository extends AdminPortalRepository {
  _SuperAdminTestRepository({super.callableInvoker});

  @override
  bool get isSuperAdmin => true;
}

Map<String, dynamic> _job(String id, {Map<String, dynamic> over = const {}}) =>
    {
      'id': id,
      'status': 'running',
      'trigger': 'manual',
      'requestedBy': 'admin-1',
      'requestedAt': '2026-11-15T02:30:00.000Z',
      'startedAt': '2026-11-15T02:30:05.000Z',
      'completedAt': null,
      'coverage': {
        'firestore': 'included',
        'auth': 'excluded',
        'storage': 'excluded',
      },
      'progress': {
        'documents': {'completed': 40, 'estimated': 100},
        'bytes': {'completed': 1, 'estimated': 2},
      },
      'verification': {
        'status': 'pending',
        'metadataPath': 'firestore-exports/x/x.overall_export_metadata',
        'checkedAt': null,
      },
      'error': null,
      'retentionDays': 30,
      'expiresAt': '2026-12-15T02:30:00.000Z',
      ...over,
    };

void main() {
  test('parses a running job with progress and coverage', () {
    final job = BackupJob.fromJson(_job('j1'));
    expect(job.id, 'j1');
    expect(job.status, BackupJobStatus.running);
    expect(job.trigger, 'manual');
    expect(job.documentsCompleted, 40);
    expect(job.documentsEstimated, 100);
    expect(job.verification, BackupVerificationStatus.pending);
    expect(job.coverage['auth'], 'excluded');
    expect(job.retentionDays, 30);
    expect(job.expiresAt, isNotNull);
    expect(job.isTerminal, isFalse);
  });

  test('unknown status is treated as failed and missing progress is null', () {
    final job = BackupJob.fromJson(
      _job(
        'j2',
        over: {
          'status': 'weird',
          'progress': null,
          'verification': null,
          'error': {'code': 'export-7', 'message': 'denied'},
          'completedAt': '2026-11-15T02:40:00.000Z',
        },
      ),
    );
    expect(job.status, BackupJobStatus.failed);
    expect(job.documentsCompleted, isNull);
    expect(job.verification, BackupVerificationStatus.pending);
    expect(job.errorCode, 'export-7');
    expect(job.errorMessage, 'denied');
    expect(job.isTerminal, isTrue);
  });

  test('summary picks the newest job and the last verified completion', () {
    final jobs = [
      BackupJob.fromJson(_job('newest')),
      BackupJob.fromJson(
        _job(
          'done',
          over: {
            'status': 'completed',
            'requestedAt': '2026-11-14T02:30:00.000Z',
            'completedAt': '2026-11-14T02:41:00.000Z',
            'verification': {
              'status': 'verified',
              'metadataPath': 'p',
              'checkedAt': '2026-11-14T02:41:00.000Z',
            },
          },
        ),
      ),
      BackupJob.fromJson(
        _job(
          'failed',
          over: {
            'status': 'failed',
            'requestedAt': '2026-11-13T02:30:00.000Z',
            'completedAt': '2026-11-13T02:31:00.000Z',
          },
        ),
      ),
    ];
    final summary = BackupSummary.fromJobs(jobs);
    expect(summary.latest?.id, 'newest');
    expect(summary.hasRunning, isTrue);
    expect(summary.lastVerifiedAt, DateTime.parse('2026-11-14T02:41:00.000Z'));
    expect(BackupSummary.fromJobs(const []).latest, isNull);
  });

  test('a non-super-admin repository surfaces backup history as an error', () {
    final repository = AdminPortalRepository(
      callableInvoker: (name, data) async => null,
    );
    expect(repository.isSuperAdmin, isFalse);
    expect(repository.watchBackupJobs(), emitsError(isA<StateError>()));
  });

  test('repository callables carry the expected names and arguments', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final repository = AdminPortalRepository(
      callableInvoker: (name, data) async {
        calls.add((name, data));
        return {'jobId': 'j1', 'status': 'running'};
      },
    );
    expect(await repository.requestFirestoreBackup(), 'j1');
    await repository.refreshBackupJobStatus('j1');
    expect(calls.map((call) => call.$1), [
      'requestFirestoreBackup',
      'refreshFirestoreBackupStatus',
    ]);
    expect(calls[0].$2, isEmpty);
    expect(calls[1].$2, {'jobId': 'j1'});
  });

  test('non-super-admin repository cannot fetch complete backup export', () async {
    var called = false;
    final repository = AdminPortalRepository(
      callableInvoker: (name, data) async {
        called = true;
        return null;
      },
    );
    await expectLater(
      repository.fetchCompleteFirestoreBackup(format: BackupExportFormat.csv),
      throwsStateError,
    );
    expect(called, isFalse);
  });

  test('fetchCompleteFirestoreBackup paginates all collections and reports progress', () async {
    final pages = [
      {
        'exportId': 'exp-1',
        'exportedAt': '2026-11-20T00:00:00.000Z',
        'visitedCollections': [
          {'collectionKey': 'users', 'collectionPath': 'users'},
          {'collectionKey': 'empty_col', 'collectionPath': 'empty_col'},
        ],
        'documents': [
          {
            'documentId': 'u1',
            'documentPath': 'users/u1',
            'collectionPath': 'users',
            'collectionKey': 'users',
            'fields': {'name': 'Alice'},
          },
        ],
        'hasMore': true,
        'nextCursor': {
          'currentCollection': 'appointments/a1/history',
          'afterDocId': null,
          'queue': <String>[],
        },
      },
      {
        'exportId': 'exp-1',
        'exportedAt': '2026-11-20T00:00:01.000Z',
        'visitedCollections': [
          {
            'collectionKey': 'appointments__history',
            'collectionPath': 'appointments/a1/history',
          },
        ],
        'documents': [
          {
            'documentId': 'h1',
            'documentPath': 'appointments/a1/history/h1',
            'collectionPath': 'appointments/a1/history',
            'collectionKey': 'appointments__history',
            'parentCollection': 'appointments',
            'parentDocumentId': 'a1',
            'fields': {'action': 'created'},
          },
        ],
        'hasMore': false,
        'nextCursor': null,
      },
    ];
    var callIndex = 0;
    final progressUpdates = <BackupExportProgress>[];
    final repository = _SuperAdminTestRepository(
      callableInvoker: (name, data) async {
        expect(name, 'exportFirestoreBackupPage');
        return pages[callIndex++];
      },
    );

    final dataset = await repository.fetchCompleteFirestoreBackup(
      format: BackupExportFormat.xlsx,
      onProgress: progressUpdates.add,
    );

    expect(dataset.exportId, 'exp-1');
    expect(dataset.totalCollections, 3);
    expect(dataset.totalDocuments, 2);
    expect(
      dataset.collections.map((c) => c.collectionKey).toList(),
      ['appointments__history', 'empty_col', 'users'],
    );
    expect(progressUpdates.length, 2);
    expect(progressUpdates.last.documentsLoaded, 2);
  });

  test('fetchCompleteFirestoreBackup rejects incomplete or stalled pagination', () async {
    final missingCursorRepo = _SuperAdminTestRepository(
      callableInvoker: (_, _) async => {
        'exportId': 'exp-bad',
        'exportedAt': '2026-11-20T00:00:00.000Z',
        'visitedCollections': const [],
        'documents': const [],
        'hasMore': true,
        'nextCursor': null,
      },
    );
    await expectLater(
      missingCursorRepo.fetchCompleteFirestoreBackup(
        format: BackupExportFormat.csv,
      ),
      throwsStateError,
    );

    final stalledRepo = _SuperAdminTestRepository(
      callableInvoker: (_, _) async => {
        'exportId': 'exp-stalled',
        'exportedAt': '2026-11-20T00:00:00.000Z',
        'visitedCollections': const [],
        'documents': const [],
        'hasMore': true,
        'nextCursor': {
          'currentCollection': 'users',
          'afterDocId': 'u1',
          'queue': const <String>[],
        },
      },
    );
    await expectLater(
      stalledRepo.fetchCompleteFirestoreBackup(format: BackupExportFormat.csv),
      throwsStateError,
    );
  });
}
