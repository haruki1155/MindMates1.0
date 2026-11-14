import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/backup_job.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

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
}
