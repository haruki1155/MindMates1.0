import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:excel_plus/excel_plus.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/backup_export.dart';
import 'package:mind_mates/features/admin/domain/backup_job.dart';
import 'package:mind_mates/features/admin/screens/backup_data_page.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

BackupJob _job(
  String id, {
  BackupJobStatus status = BackupJobStatus.completed,
  BackupVerificationStatus verification = BackupVerificationStatus.verified,
}) => BackupJob(
  id: id,
  status: status,
  trigger: 'manual',
  requestedBy: 'admin',
  requestedAt: DateTime(2026, 11, 15, 2, 30),
  completedAt: status == BackupJobStatus.running
      ? null
      : DateTime(2026, 11, 15, 2, 41),
  documentsCompleted: 5190,
  documentsEstimated: 5190,
  verification: verification,
  coverage: const {
    'firestore': 'included',
    'auth': 'excluded',
    'storage': 'excluded',
  },
  retentionDays: 30,
);

class _Repo extends AdminPortalRepository {
  _Repo(this.jobs, {this.requestError, this.exportHandler});

  final Stream<List<BackupJob>> jobs;
  final Object? requestError;
  final Future<BackupExportDataset> Function(
    BackupExportFormat format,
    void Function(BackupExportProgress)? onProgress,
  )?
  exportHandler;
  int requests = 0;
  final refreshed = <String>[];

  @override
  bool get isSuperAdmin => true;

  @override
  Stream<List<BackupJob>> watchBackupJobs() => jobs;

  @override
  Future<String> requestFirestoreBackup() async {
    requests++;
    if (requestError != null) throw requestError!;
    return 'new-job';
  }

  @override
  Future<void> refreshBackupJobStatus(String jobId) async =>
      refreshed.add(jobId);

  @override
  Future<BackupExportDataset> fetchCompleteFirestoreBackup({
    required BackupExportFormat format,
    int pageSize = 200,
    void Function(BackupExportProgress progress)? onProgress,
  }) async {
    final handler = exportHandler;
    if (handler != null) {
      return handler(format, onProgress);
    }
    return BackupExportDataset(
      exportId: 'exp-default',
      exportedAt: DateTime.utc(2026, 11, 20, 8, 0, 0),
      collections: const [
        BackupCollectionDataset(
          collectionKey: 'users',
          collectionPaths: ['users'],
          documents: [
            BackupDocumentRecord(
              documentId: 'u1',
              documentPath: 'users/u1',
              collectionPath: 'users',
              collectionKey: 'users',
              fields: {'name': 'Admin'},
            ),
          ],
        ),
        BackupCollectionDataset(
          collectionKey: 'empty_col',
          collectionPaths: ['empty_col'],
          documents: [],
        ),
      ],
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Repo repo, {
  void Function(String fileName, List<int> bytes, String mimeType)?
  onDownload,
}) async {
  tester.view.physicalSize = const Size(1440, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BackupDataPage(
          repository: repo,
          downloadFile: onDownload ?? (_, _, _) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a stream error reads as not authorized, not as no backups', (
    tester,
  ) async {
    await _pump(
      tester,
      _Repo(Stream<List<BackupJob>>.error(StateError('permission-denied'))),
    );
    expect(
      find.textContaining('requires the configured super-administrator'),
      findsOneWidget,
    );
    expect(find.text('Request backup now'), findsNothing);
    expect(find.textContaining('No backups have been recorded'), findsNothing);
  });

  testWidgets('an empty history shows coverage and allows a request', (
    tester,
  ) async {
    await _pump(tester, _Repo(Stream.value(const <BackupJob>[])));
    expect(
      find.textContaining('No backups have been recorded'),
      findsOneWidget,
    );
    expect(find.textContaining('Firestore database'), findsOneWidget);
    expect(
      find.textContaining('Firebase Authentication users'),
      findsOneWidget,
    );
    expect(find.textContaining('Storage files'), findsOneWidget);
    expect(find.textContaining('Excluded in Phase 1'), findsNWidgets(2));
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Request backup now'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('a running job disables new requests and offers refresh', (
    tester,
  ) async {
    final repo = _Repo(
      Stream.value([
        _job(
          'run',
          status: BackupJobStatus.running,
          verification: BackupVerificationStatus.pending,
        ),
        _job('done'),
      ]),
    );
    await _pump(tester, repo);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Completed · Verified'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Request backup now'),
    );
    expect(button.onPressed, isNull);
    await tester.ensureVisible(find.text('Refresh status'));
    await tester.tap(find.text('Refresh status'));
    await tester.pumpAndSettle();
    expect(repo.refreshed, ['run']);
  });

  testWidgets('confirming the dialog requests exactly one backup', (
    tester,
  ) async {
    final repo = _Repo(Stream.value(const <BackupJob>[]));
    await _pump(tester, repo);
    await tester.tap(find.text('Request backup now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('one managed Firestore export'), findsOneWidget);
    expect(
      find.textContaining('may incur Google Cloud charges'),
      findsOneWidget,
    );
    await tester.tap(find.text('Start backup'));
    await tester.pumpAndSettle();
    expect(repo.requests, 1);
  });

  testWidgets('an unconfigured destination is reported as such', (
    tester,
  ) async {
    final repo = _Repo(
      Stream.value(const <BackupJob>[]),
      requestError: FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Backup destination is not configured.',
      ),
    );
    await _pump(tester, repo);
    await tester.tap(find.text('Request backup now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start backup'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Backup destination is not configured'),
      findsOneWidget,
    );
    expect(find.textContaining('BACKUP_BUCKET'), findsOneWidget);
  });

  testWidgets('other callable errors show the code', (tester) async {
    final repo = _Repo(
      Stream.value(const <BackupJob>[]),
      requestError: FirebaseFunctionsException(
        code: 'internal',
        message: 'boom',
      ),
    );
    await _pump(tester, repo);
    await tester.tap(find.text('Request backup now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start backup'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Backup request failed (internal)'),
      findsOneWidget,
    );
  });

  testWidgets('no bucket locations are rendered', (tester) async {
    await _pump(tester, _Repo(Stream.value([_job('done')])));
    expect(find.textContaining('gs://'), findsNothing);
  });

  testWidgets('a stream error hides download buttons for unauthorized users', (
    tester,
  ) async {
    await _pump(
      tester,
      _Repo(Stream<List<BackupJob>>.error(StateError('permission-denied'))),
    );
    expect(find.text('Download CSV (.zip)'), findsNothing);
    expect(find.text('Download Excel (.xlsx)'), findsNothing);
  });

  testWidgets('Download CSV (.zip) builds a complete ZIP with per-collection CSVs', (
    tester,
  ) async {
    final downloads = <({String name, List<int> bytes, String mime})>[];
    final repo = _Repo(Stream.value([_job('done')]));
    await _pump(
      tester,
      repo,
      onDownload: (name, bytes, mime) =>
          downloads.add((name: name, bytes: bytes, mime: mime)),
    );

    await tester.tap(find.text('Download CSV (.zip)'));
    await tester.pumpAndSettle();

    expect(downloads.length, 1);
    expect(downloads.single.name, 'mindmate-firestore-backup-20261120-080000.zip');
    expect(downloads.single.mime, 'application/zip');
    final archive = ZipDecoder().decodeBytes(downloads.single.bytes);
    expect(archive.files.map((f) => f.name), ['users.csv', 'empty_col.csv']);
    final usersCsv = utf8.decode(
      archive.findFile('users.csv')!.content as List<int>,
    );
    expect(usersCsv, contains('u1,users/u1,users'));
    expect(
      find.textContaining('2 collections, 1 documents'),
      findsOneWidget,
    );
  });

  testWidgets('Download Excel (.xlsx) builds a multi-sheet workbook', (
    tester,
  ) async {
    final downloads = <({String name, List<int> bytes, String mime})>[];
    final repo = _Repo(Stream.value([_job('done')]));
    await _pump(
      tester,
      repo,
      onDownload: (name, bytes, mime) =>
          downloads.add((name: name, bytes: bytes, mime: mime)),
    );

    await tester.tap(find.text('Download Excel (.xlsx)'));
    await tester.pumpAndSettle();

    expect(downloads.length, 1);
    expect(downloads.single.name, 'mindmate-firestore-backup-20261120-080000.xlsx');
    final book = excel.Excel.decodeBytes(downloads.single.bytes);
    expect(
      book.tables.keys,
      containsAll(['Backup_Summary', 'users', 'empty_col']),
    );
    expect(
      find.textContaining('2 collections, 1 documents'),
      findsOneWidget,
    );
  });

  testWidgets('failed or incomplete export never triggers a file download', (
    tester,
  ) async {
    var downloadCount = 0;
    final repo = _Repo(
      Stream.value([_job('done')]),
      exportHandler: (_, _) async {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Super-administrator access is required.',
        );
      },
    );
    await _pump(
      tester,
      repo,
      onDownload: (_, _, _) => downloadCount++,
    );

    await tester.tap(find.text('Download CSV (.zip)'));
    await tester.pumpAndSettle();

    expect(downloadCount, 0);
    expect(
      find.textContaining('Backup download failed (permission-denied)'),
      findsOneWidget,
    );
    expect(find.textContaining('No backup file was created.'), findsOneWidget);
  });
}
