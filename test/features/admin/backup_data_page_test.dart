import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:excel_plus/excel_plus.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_status_presentation.dart';
import 'package:mind_mates/features/admin/domain/backup_export.dart';
import 'package:mind_mates/features/admin/domain/backup_job.dart';
import 'package:mind_mates/features/admin/screens/backup_data_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

final _fixedNow = DateTime(2026, 11, 20, 12, 0);

BackupJob _job(
  String id, {
  BackupJobStatus status = BackupJobStatus.completed,
  BackupVerificationStatus verification = BackupVerificationStatus.verified,
  String trigger = 'manual',
  DateTime? requestedAt,
  DateTime? startedAt,
  DateTime? completedAt,
  DateTime? expiresAt,
  int retentionDays = 30,
  int? documentsCompleted = 5190,
  int? documentsEstimated = 5190,
  String? errorCode,
  String? errorMessage,
}) => BackupJob(
  id: id,
  status: status,
  trigger: trigger,
  requestedBy: 'admin',
  requestedAt: requestedAt ?? DateTime(2026, 11, 15, 2, 30),
  startedAt: startedAt ?? DateTime(2026, 11, 15, 2, 31),
  completedAt:
      completedAt ??
      (status == BackupJobStatus.running
          ? null
          : DateTime(2026, 11, 15, 2, 41)),
  documentsCompleted: documentsCompleted,
  documentsEstimated: documentsEstimated,
  verification: verification,
  errorCode: errorCode,
  errorMessage: errorMessage,
  coverage: const {
    'firestore': 'included',
    'auth': 'excluded',
    'storage': 'excluded',
  },
  retentionDays: retentionDays,
  expiresAt: expiresAt,
);

class _Repo extends AdminPortalRepository {
  _Repo(
    this.jobs, {
    this.superAdmin = true,
    this.requestError,
    this.refreshError,
    this.requestHandler,
    this.refreshHandler,
    this.exportHandler,
  });

  final Stream<List<BackupJob>> jobs;
  final bool superAdmin;
  final Object? requestError;
  final Object? refreshError;
  final Future<String> Function()? requestHandler;
  final Future<void> Function(String jobId)? refreshHandler;
  final Future<BackupExportDataset> Function(
    BackupExportFormat format,
    void Function(BackupExportProgress)? onProgress,
  )?
  exportHandler;
  int requests = 0;
  final refreshed = <String>[];

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  Stream<List<BackupJob>> watchBackupJobs() => jobs;

  @override
  Future<String> requestFirestoreBackup() async {
    requests++;
    if (requestHandler != null) return requestHandler!();
    if (requestError != null) throw requestError!;
    return 'new-job';
  }

  @override
  Future<void> refreshBackupJobStatus(String jobId) async {
    refreshed.add(jobId);
    if (refreshHandler != null) {
      await refreshHandler!(jobId);
      return;
    }
    if (refreshError != null) throw refreshError!;
  }

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
  Size size = const Size(1280, 1200),
  DateTime Function()? clock,
  void Function(String fileName, List<int> bytes, String mimeType)? onDownload,
  bool settle = true,
  TextScaler? textScaler,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final scaffold = Scaffold(
    body: BackupDataPage(
      repository: repo,
      downloadFile: onDownload ?? (_, _, _) {},
      clock: clock ?? () => _fixedNow,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
      home: textScaler == null
          ? scaffold
          : Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: scaffold,
              ),
            ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void _expectNoTechnicalJargon(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .join('\n');
  // Preserve exported filename format from backup_export_formatter.dart,
  // while asserting no UI copy contains infrastructure jargon.
  final lower = texts.toLowerCase().replaceAll(
    RegExp(r'mindmate-firestore-backup-\d{8}-\d{6}\.(zip|xlsx)'),
    '',
  );
  const forbidden = [
    'firestore',
    'firebase authentication',
    'firebase storage',
    'google cloud',
    'bucket',
    'backup_bucket',
    'gs://',
    'backup_jobs',
    'admin_audit_logs',
    'counseling_population',
    'student_roster',
    'phase 1',
    'academic year backup',
    'cloud storage',
    'service account',
    'backup_service_account',
    'backup_retention_days',
    'backup_manual_daily_limit',
    'iam.gserviceaccount.com',
    'projects/',
    '(default)',
    'overall_export_metadata',
    'exportdocuments',
    'cloud function',
    'httpscallable',
    'collections',
    'documents',
  ];
  for (final term in forbidden) {
    expect(
      lower,
      isNot(contains(term)),
      reason: 'Found forbidden term "$term"',
    );
  }
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
    expect(find.byIcon(Icons.lock_person_outlined), findsOneWidget);
    expect(find.text('Request backup now'), findsNothing);
    expect(find.text('Download CSV (.zip)'), findsNothing);
    expect(find.text('Download Excel (.xlsx)'), findsNothing);
    expect(find.textContaining('No backups have been recorded'), findsNothing);
    _expectNoTechnicalJargon(tester);
  });

  testWidgets('loading state shows progress indicator before stream emits', (
    tester,
  ) async {
    final controller = StreamController<List<BackupJob>>();
    addTearDown(controller.close);

    await _pump(tester, _Repo(controller.stream), settle: false);

    expect(find.text('Loading backup history…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'empty history shows plain-language multi-year coverage and allows request',
    (tester) async {
      await _pump(tester, _Repo(Stream.value(const <BackupJob>[])));
      expect(
        find.textContaining('No backups have been recorded'),
        findsOneWidget,
      );
      expect(find.text('None recorded yet'), findsOneWidget);
      expect(find.text('Server-managed retention'), findsOneWidget);
      expect(find.text('What is included'), findsOneWidget);
      expect(
        find.textContaining(
          'Application database records (all academic years)',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('User sign-in accounts and login credentials'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Uploaded files and session attachments'),
        findsOneWidget,
      );
      expect(find.text('Included'), findsOneWidget);
      expect(find.text('Not included'), findsNWidgets(2));
      expect(find.textContaining('all academic years'), findsWidgets);
      _expectNoTechnicalJargon(tester);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Request backup now'),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets(
    'renders all 5 semantic backup states via AdminStatusBadge and respects clock',
    (tester) async {
      final jobs = [
        _job(
          'run',
          status: BackupJobStatus.running,
          verification: BackupVerificationStatus.pending,
          requestedAt: DateTime(2026, 11, 20, 11, 30),
          documentsCompleted: 1200,
          documentsEstimated: 5190,
          expiresAt: DateTime(2026, 12, 20, 11, 30),
        ),
        _job(
          'verified',
          status: BackupJobStatus.completed,
          verification: BackupVerificationStatus.verified,
          requestedAt: DateTime(2026, 11, 19, 2, 30),
          completedAt: DateTime(2026, 11, 19, 2, 40),
          expiresAt: DateTime(2026, 12, 19, 2, 30),
        ),
        _job(
          'pending',
          status: BackupJobStatus.completed,
          verification: BackupVerificationStatus.pending,
          requestedAt: DateTime(2026, 11, 18, 2, 30),
          completedAt: DateTime(2026, 11, 18, 2, 40),
          expiresAt: DateTime(2026, 12, 18, 2, 30),
        ),
        _job(
          'failed',
          status: BackupJobStatus.failed,
          verification: BackupVerificationStatus.missing,
          requestedAt: DateTime(2026, 11, 17, 2, 30),
          completedAt: DateTime(2026, 11, 17, 2, 35),
          errorCode: 'output-missing',
          errorMessage: 'gs://internal-bucket/path failed',
        ),
        _job(
          'expired',
          status: BackupJobStatus.completed,
          verification: BackupVerificationStatus.verified,
          requestedAt: DateTime(2026, 10, 1, 2, 30),
          completedAt: DateTime(2026, 10, 1, 2, 40),
          expiresAt: DateTime(2026, 10, 31, 2, 30),
        ),
      ];

      await _pump(tester, _Repo(Stream.value(jobs)), clock: () => _fixedNow);

      final badges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .toList();

      AdminStatusPresentation badgeFor(String label) =>
          badges.firstWhere((b) => b.presentation.label == label).presentation;

      expect(badgeFor('Running').tone, AdminSemanticTone.blue);
      expect(badgeFor('Running').icon, Icons.sync_outlined);

      expect(badgeFor('Successful · Verified').tone, AdminSemanticTone.green);
      expect(
        badgeFor('Successful · Verified').icon,
        Icons.check_circle_outline,
      );

      expect(badgeFor('Pending verification').tone, AdminSemanticTone.amber);
      expect(
        badgeFor('Pending verification').icon,
        Icons.hourglass_top_outlined,
      );

      expect(badgeFor('Failed · Output missing').tone, AdminSemanticTone.red);
      expect(badgeFor('Failed · Output missing').icon, Icons.error_outline);

      expect(badgeFor('Expired').tone, AdminSemanticTone.neutral);
      expect(badgeFor('Expired').icon, Icons.timer_off_outlined);

      // Summary displays the verified backup and active retention.
      expect(find.text('2026-11-19 02:40'), findsWidgets);
      expect(find.textContaining('Retention active until'), findsOneWidget);
      // Latest job retention days (30 days) shown without fabrication.
      expect(find.text('30 days'), findsWidgets);
      // gs:// path in errorMessage is sanitized.
      expect(find.textContaining('gs://'), findsNothing);
      expect(
        find.textContaining('Backup finished without a verified output file.'),
        findsOneWidget,
      );
      _expectNoTechnicalJargon(tester);
    },
  );

  testWidgets('last verified backup shows retention ended when expired', (
    tester,
  ) async {
    final jobs = [
      _job(
        'old-verified',
        status: BackupJobStatus.completed,
        verification: BackupVerificationStatus.verified,
        requestedAt: DateTime(2026, 10, 1, 2, 30),
        completedAt: DateTime(2026, 10, 1, 2, 42),
        expiresAt: DateTime(2026, 10, 31, 2, 30),
      ),
    ];

    await _pump(tester, _Repo(Stream.value(jobs)), clock: () => _fixedNow);

    expect(find.text('2026-10-01 02:42'), findsWidgets);
    expect(find.text('Retention ended'), findsOneWidget);
    expect(
      find.textContaining('Retention ended on 2026-10-31 02:30'),
      findsOneWidget,
    );
    _expectNoTechnicalJargon(tester);
  });

  testWidgets('a running job disables new requests and offers refresh', (
    tester,
  ) async {
    final refreshCompleter = Completer<void>();
    final repo = _Repo(
      Stream.value([
        _job(
          'run',
          status: BackupJobStatus.running,
          verification: BackupVerificationStatus.pending,
        ),
        _job('done', expiresAt: DateTime(2026, 12, 15, 2, 30)),
      ]),
      refreshHandler: (_) => refreshCompleter.future,
    );
    await _pump(tester, repo);
    expect(find.text('Running'), findsWidgets);
    expect(find.text('Successful · Verified'), findsOneWidget);
    expect(find.textContaining('A backup is already running.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Request backup now'),
    );
    expect(button.onPressed, isNull);
    await tester.ensureVisible(find.text('Refresh status'));
    await tester.tap(find.text('Refresh status'));
    await tester.pump();
    expect(find.text('Refreshing…'), findsOneWidget);

    refreshCompleter.complete();
    await tester.pumpAndSettle();
    expect(repo.refreshed, ['run']);
    expect(find.text('Backup status refreshed.'), findsOneWidget);
  });

  testWidgets('refresh error shows plain-language notice and dismiss works', (
    tester,
  ) async {
    final repo = _Repo(
      Stream.value([
        _job(
          'run',
          status: BackupJobStatus.running,
          verification: BackupVerificationStatus.pending,
        ),
      ]),
      refreshError: FirebaseFunctionsException(
        code: 'unavailable',
        message: 'backend down',
      ),
    );
    await _pump(tester, repo);

    await tester.ensureVisible(find.text('Refresh status'));
    await tester.tap(find.text('Refresh status'));
    await tester.pumpAndSettle();

    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    _expectNoTechnicalJargon(tester);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.textContaining('temporarily unavailable'), findsNothing);
  });

  testWidgets(
    'confirmation dialog supports confirm, cancel, and in-flight spinner',
    (tester) async {
      final completer = Completer<String>();
      final repo = _Repo(
        Stream.value(const <BackupJob>[]),
        requestHandler: () => completer.future,
      );
      await _pump(tester, repo);

      // Test Cancel first.
      await tester.tap(find.text('Request backup now'));
      await tester.pumpAndSettle();
      expect(find.text('Start a full system backup?'), findsOneWidget);
      expect(
        find.textContaining(
          'all application database records across all academic years',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Cloud usage and storage charges may apply'),
        findsOneWidget,
      );
      _expectNoTechnicalJargon(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.requests, 0);
      expect(find.text('Start a full system backup?'), findsNothing);

      // Test Confirm and in-flight spinner.
      await tester.tap(find.text('Request backup now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start backup'));
      await tester.pump();

      expect(repo.requests, 1);
      final busyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Request backup now'),
      );
      expect(busyButton.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete('new-job');
      await tester.pumpAndSettle();

      expect(find.textContaining('Backup requested.'), findsOneWidget);
    },
  );

  testWidgets('unconfigured destination reports plain-language guidance', (
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
      find.textContaining('Backup storage is not configured yet'),
      findsOneWidget,
    );
    _expectNoTechnicalJargon(tester);
  });

  testWidgets('other callable errors render plain-language error notice', (
    tester,
  ) async {
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
      find.textContaining('Unable to start the backup right now'),
      findsOneWidget,
    );
    expect(find.textContaining('(internal)'), findsNothing);
    _expectNoTechnicalJargon(tester);
  });

  testWidgets('Download CSV (.zip) shows live progress and builds ZIP', (
    tester,
  ) async {
    final completer = Completer<BackupExportDataset>();
    final downloads = <({String name, List<int> bytes, String mime})>[];
    final repo = _Repo(
      Stream.value([_job('done', expiresAt: DateTime(2026, 12, 15, 2, 30))]),
      exportHandler: (format, onProgress) {
        onProgress?.call(
          const BackupExportProgress(
            pagesLoaded: 2,
            collectionsDiscovered: 2,
            documentsLoaded: 15,
          ),
        );
        return completer.future;
      },
    );
    await _pump(
      tester,
      repo,
      onDownload: (name, bytes, mime) =>
          downloads.add((name: name, bytes: bytes, mime: mime)),
    );

    expect(find.text('Administrative Data Export'), findsOneWidget);
    await tester.tap(find.text('Download CSV (.zip)'));
    await tester.pump();

    expect(find.text('Preparing CSV…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.text('Downloaded 15 records across 2 data tables (batch 2)…'),
      findsOneWidget,
    );

    final excelButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Download Excel (.xlsx)'),
    );
    expect(excelButton.onPressed, isNull);

    completer.complete(
      BackupExportDataset(
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
      ),
    );
    await tester.pumpAndSettle();

    expect(downloads.length, 1);
    expect(
      downloads.single.name,
      'mindmate-firestore-backup-20261120-080000.zip',
    );
    expect(downloads.single.mime, 'application/zip');
    final archive = ZipDecoder().decodeBytes(downloads.single.bytes);
    expect(archive.files.map((f) => f.name), ['users.csv', 'empty_col.csv']);
    final usersCsv = utf8.decode(
      archive.findFile('users.csv')!.content as List<int>,
    );
    expect(usersCsv, contains('u1,users/u1,users'));
    expect(find.textContaining('2 data tables, 1 record'), findsOneWidget);
    _expectNoTechnicalJargon(tester);
  });

  testWidgets('Download Excel (.xlsx) builds a multi-sheet workbook', (
    tester,
  ) async {
    final downloads = <({String name, List<int> bytes, String mime})>[];
    final repo = _Repo(
      Stream.value([_job('done', expiresAt: DateTime(2026, 12, 15, 2, 30))]),
    );
    await _pump(
      tester,
      repo,
      onDownload: (name, bytes, mime) =>
          downloads.add((name: name, bytes: bytes, mime: mime)),
    );

    await tester.tap(find.text('Download Excel (.xlsx)'));
    await tester.pumpAndSettle();

    expect(downloads.length, 1);
    expect(
      downloads.single.name,
      'mindmate-firestore-backup-20261120-080000.xlsx',
    );
    final book = excel.Excel.decodeBytes(downloads.single.bytes);
    expect(
      book.tables.keys,
      containsAll(['Backup_Summary', 'users', 'empty_col']),
    );
    expect(find.textContaining('2 data tables, 1 record'), findsOneWidget);
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
    await _pump(tester, repo, onDownload: (_, _, _) => downloadCount++);

    await tester.tap(find.text('Download CSV (.zip)'));
    await tester.pumpAndSettle();

    expect(downloadCount, 0);
    expect(find.textContaining('Backup download was denied'), findsOneWidget);
    expect(find.textContaining('No backup file was created.'), findsOneWidget);
    expect(find.textContaining('(permission-denied)'), findsNothing);
    _expectNoTechnicalJargon(tester);
  });

  testWidgets(
    'non-super-admin cannot trigger backup requests or export downloads',
    (tester) async {
      var downloadCount = 0;
      final repo = _Repo(Stream.value([_job('done')]), superAdmin: false);
      await _pump(tester, repo, onDownload: (_, _, _) => downloadCount++);

      final requestBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Request backup now'),
      );
      final csvBtn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Download CSV (.zip)'),
      );
      final xlsxBtn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Download Excel (.xlsx)'),
      );
      expect(requestBtn.onPressed, isNull);
      expect(csvBtn.onPressed, isNull);
      expect(xlsxBtn.onPressed, isNull);
      expect(repo.requests, 0);
      expect(downloadCount, 0);
    },
  );

  testWidgets(
    'failed or output-missing latest job shows Not retained even when expiresAt is set',
    (tester) async {
      for (final scenario in [
        (
          'failed-past-expiry',
          _job(
            'failed-past',
            status: BackupJobStatus.failed,
            verification: BackupVerificationStatus.pending,
            requestedAt: DateTime(2026, 10, 1, 2, 30),
            completedAt: DateTime(2026, 10, 1, 2, 35),
            expiresAt: DateTime(2026, 10, 31, 2, 30),
            retentionDays: 30,
          ),
        ),
        (
          'failed-future-expiry',
          _job(
            'failed-future',
            status: BackupJobStatus.failed,
            verification: BackupVerificationStatus.missing,
            requestedAt: DateTime(2026, 11, 19, 2, 30),
            completedAt: DateTime(2026, 11, 19, 2, 35),
            expiresAt: DateTime(2026, 12, 19, 2, 30),
            retentionDays: 30,
          ),
        ),
        (
          'completed-missing-past-expiry',
          _job(
            'missing-past',
            status: BackupJobStatus.completed,
            verification: BackupVerificationStatus.missing,
            requestedAt: DateTime(2026, 10, 1, 2, 30),
            completedAt: DateTime(2026, 10, 1, 2, 40),
            expiresAt: DateTime(2026, 10, 31, 2, 30),
            retentionDays: 30,
          ),
        ),
      ]) {
        await _pump(
          tester,
          _Repo(Stream.value([scenario.$2])),
          clock: () => _fixedNow,
        );
        expect(
          find.textContaining('Latest backup kept until'),
          findsNothing,
          reason: '${scenario.$1} should not claim kept until',
        );
        expect(
          find.text('Active'),
          findsNothing,
          reason: '${scenario.$1} should not show Active badge',
        );
        expect(
          find.text('Not retained'),
          findsWidgets,
          reason: '${scenario.$1} should show Not retained',
        );
        expect(
          find.text('No verified backup was stored for the latest run.'),
          findsOneWidget,
          reason: '${scenario.$1} should explain no verified backup stored',
        );
      }
    },
  );

  testWidgets(
    'running latest job shows Pending retention until backup finishes',
    (tester) async {
      await _pump(
        tester,
        _Repo(
          Stream.value([
            _job(
              'run',
              status: BackupJobStatus.running,
              verification: BackupVerificationStatus.pending,
              requestedAt: DateTime(2026, 11, 20, 11, 30),
              expiresAt: DateTime(2026, 12, 20, 11, 30),
              retentionDays: 30,
            ),
          ]),
        ),
        clock: () => _fixedNow,
      );
      expect(find.text('Pending'), findsOneWidget);
      expect(
        find.text('Retention window starts once the backup finishes.'),
        findsOneWidget,
      );
      expect(find.textContaining('Latest backup kept until'), findsNothing);
      expect(find.text('Active'), findsNothing);
    },
  );

  testWidgets(
    'sanitizes infrastructure jargon in job errors and failed-precondition env config errors',
    (tester) async {
      final jobs = [
        _job(
          'j1',
          status: BackupJobStatus.failed,
          verification: BackupVerificationStatus.pending,
          requestedAt: DateTime(2026, 11, 19, 2, 30),
          errorMessage:
              'Cloud Storage permission denied on projects/mindmate-prod/databases/(default) for BACKUP_SERVICE_ACCOUNT',
        ),
        _job(
          'j2',
          status: BackupJobStatus.failed,
          verification: BackupVerificationStatus.pending,
          requestedAt: DateTime(2026, 11, 18, 2, 30),
          errorMessage: 'Academic Year Backup metadata missing',
        ),
      ];

      for (final envError in [
        'BACKUP_RETENTION_DAYS must be a positive integer.',
        'BACKUP_MANUAL_DAILY_LIMIT must be a positive integer.',
      ]) {
        final repo = _Repo(
          Stream.value(jobs),
          requestError: FirebaseFunctionsException(
            code: 'failed-precondition',
            message: envError,
          ),
        );
        await _pump(tester, repo, clock: () => _fixedNow);

        await tester.tap(find.text('Request backup now'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start backup'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Cloud Storage'), findsNothing);
        expect(find.textContaining('projects/mindmate-prod'), findsNothing);
        expect(find.textContaining('BACKUP_SERVICE_ACCOUNT'), findsNothing);
        expect(find.textContaining('Academic Year Backup'), findsNothing);
        expect(find.textContaining('BACKUP_RETENTION_DAYS'), findsNothing);
        expect(find.textContaining('BACKUP_MANUAL_DAILY_LIMIT'), findsNothing);
        expect(
          find.textContaining('Backup settings on the server'),
          findsOneWidget,
        );
        _expectNoTechnicalJargon(tester);
      }
    },
  );

  testWidgets(
    'renders cleanly at 390px width under 1.4x and 1.5x text scaling without overflow',
    (tester) async {
      final jobs = [
        _job(
          'pending',
          status: BackupJobStatus.completed,
          verification: BackupVerificationStatus.pending,
          requestedAt: DateTime(2026, 11, 20, 11, 30),
          completedAt: DateTime(2026, 11, 20, 11, 45),
          expiresAt: DateTime(2026, 12, 20, 11, 30),
        ),
        _job(
          'failed',
          status: BackupJobStatus.failed,
          verification: BackupVerificationStatus.missing,
          requestedAt: DateTime(2026, 11, 17, 2, 30),
          errorCode: 'output-missing',
        ),
      ];

      for (final scale in const [1.4, 1.5]) {
        await _pump(
          tester,
          _Repo(Stream.value(jobs)),
          size: const Size(390, 1600),
          clock: () => _fixedNow,
          textScaler: TextScaler.linear(scale),
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'Unexpected layout/overflow exception at 390px with ${scale}x text scale',
        );
      }
    },
  );

  testWidgets(
    'renders cleanly without overflow across 390, 544, 768, and 1280 widths',
    (tester) async {
      final jobs = [
        _job(
          'run',
          status: BackupJobStatus.running,
          verification: BackupVerificationStatus.pending,
          requestedAt: DateTime(2026, 11, 20, 11, 30),
        ),
        _job(
          'verified',
          status: BackupJobStatus.completed,
          verification: BackupVerificationStatus.verified,
          requestedAt: DateTime(2026, 11, 19, 2, 30),
          completedAt: DateTime(2026, 11, 19, 2, 40),
          expiresAt: DateTime(2026, 12, 19, 2, 30),
        ),
        _job(
          'pending',
          status: BackupJobStatus.completed,
          verification: BackupVerificationStatus.pending,
          requestedAt: DateTime(2026, 11, 18, 2, 30),
          completedAt: DateTime(2026, 11, 18, 2, 40),
        ),
        _job(
          'failed',
          status: BackupJobStatus.failed,
          verification: BackupVerificationStatus.missing,
          requestedAt: DateTime(2026, 11, 17, 2, 30),
          errorCode: 'output-missing',
        ),
        _job(
          'expired',
          status: BackupJobStatus.completed,
          verification: BackupVerificationStatus.verified,
          requestedAt: DateTime(2026, 10, 1, 2, 30),
          completedAt: DateTime(2026, 10, 1, 2, 40),
          expiresAt: DateTime(2026, 10, 31, 2, 30),
        ),
      ];

      for (final width in const [390.0, 544.0, 768.0, 1280.0]) {
        await _pump(
          tester,
          _Repo(Stream.value(jobs)),
          size: Size(width, 1400),
          clock: () => _fixedNow,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Unexpected exception at width $width',
        );
        expect(
          find.textContaining(
            'Create a full system backup covering all academic years',
          ),
          findsOneWidget,
        );
        expect(find.text('Backup history'), findsOneWidget);
        if (width < 680) {
          expect(find.byType(DataTable), findsNothing);
        } else {
          expect(find.byType(DataTable), findsOneWidget);
        }
        _expectNoTechnicalJargon(tester);
      }
    },
  );
}
