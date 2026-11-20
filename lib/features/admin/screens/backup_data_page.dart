import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../repositories/admin_portal_repository.dart';
import '../domain/backup_export.dart';
import '../domain/backup_job.dart';
import '../services/admin_file_download.dart';
import '../services/backup_export_formatter.dart';
import '../theme/admin_theme.dart';

/// Super-administrator view of Firestore managed-export backup jobs and
/// authorized full-database downloads (CSV ZIP and Excel `.xlsx`).
///
/// Managed-export job rows show status, timing, counts and sanitised error
/// codes only, never bucket paths or signed URLs.
class BackupDataPage extends StatefulWidget {
  const BackupDataPage({
    super.key,
    required this.repository,
    this.downloadFile = downloadAdminFile,
  });

  final AdminPortalRepository repository;
  final AdminFileDownloader downloadFile;

  @override
  State<BackupDataPage> createState() => _BackupDataPageState();
}

class _BackupDataPageState extends State<BackupDataPage> {
  late Stream<List<BackupJob>> _jobs;
  bool _busy = false;
  BackupExportFormat? _downloadingFormat;
  BackupExportProgress? _exportProgress;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _jobs = widget.repository.watchBackupJobs();
  }

  Future<void> _request() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request a backup?'),
        content: const Text(
          'This starts one managed Firestore export into the private backup '
          'bucket. It may incur Google Cloud charges for document reads and '
          'storage. Firebase Authentication users and Storage files are not '
          'included in Phase 1.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start backup'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await widget.repository.requestFirestoreBackup();
      if (!mounted) return;
      setState(
        () => _notice =
            'Backup requested. The job appears below; use Refresh status '
            'to check progress.',
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _notice = error.code == 'failed-precondition'
            ? (error.message?.contains('not configured') == true
                  ? 'Backup destination is not configured. Ask the operator '
                        'to set BACKUP_BUCKET before requesting a backup.'
                  : 'Backup request refused: ${error.message ?? error.code}')
            : 'Backup request failed (${error.code}).',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _notice = 'Backup request failed (unavailable).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh(String jobId) async {
    setState(() => _notice = null);
    try {
      await widget.repository.refreshBackupJobStatus(jobId);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() => _notice = 'Status refresh failed (${error.code}).');
    } catch (_) {
      if (!mounted) return;
      setState(() => _notice = 'Status refresh failed (unavailable).');
    }
  }

  Future<void> _downloadBackup(BackupExportFormat format) async {
    if (_downloadingFormat != null || !widget.repository.isSuperAdmin) return;
    setState(() {
      _downloadingFormat = format;
      _exportProgress = null;
      _notice = null;
    });
    try {
      final dataset = await widget.repository.fetchCompleteFirestoreBackup(
        format: format,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _exportProgress = progress);
        },
      );
      final bytes = switch (format) {
        BackupExportFormat.csv => buildBackupCsvZipBytes(dataset),
        BackupExportFormat.xlsx => buildBackupExcelBytes(dataset),
      };
      final fileName = buildBackupFileName(format, dataset.exportedAt);
      widget.downloadFile(fileName, bytes, format.mimeType);
      if (!mounted) return;
      setState(
        () => _notice =
            'Downloaded $fileName (${dataset.totalCollections} collections, '
            '${dataset.totalDocuments} documents).',
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _notice =
            'Backup download failed (${error.code}). '
            'No backup file was created.',
      );
    } on UnsupportedError catch (error) {
      if (!mounted) return;
      setState(
        () => _notice =
            'Backup download failed: ${error.message ?? 'unsupported platform.'}',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _notice =
            'Backup download failed: incomplete or unavailable export. '
            'No backup file was created.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingFormat = null;
          _exportProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: StreamBuilder<List<BackupJob>>(
          stream: _jobs,
          builder: (context, snapshot) {
            final jobs = snapshot.data ?? const <BackupJob>[];
            final summary = BackupSummary.fromJobs(jobs);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Back-up Data',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Managed Firestore exports into a private Google Cloud '
                  'Storage bucket, or download a complete authorized Firestore '
                  'snapshot as CSV (ZIP) or Excel (.xlsx).',
                  style: TextStyle(color: AdminColors.muted),
                ),
                const SizedBox(height: 20),
                const _CoverageCard(),
                const SizedBox(height: 16),
                if (snapshot.hasError)
                  const _Panel(
                    child: Text(
                      'Backup history requires the configured '
                      'super-administrator account.',
                    ),
                  )
                else ...[
                  _SummaryRow(
                    summary: summary,
                    busy: _busy,
                    onRequest: _request,
                  ),
                  const SizedBox(height: 16),
                  _DownloadCard(
                    downloadingFormat: _downloadingFormat,
                    progress: _exportProgress,
                    enabled: widget.repository.isSuperAdmin,
                    onDownloadCsv: () => _downloadBackup(BackupExportFormat.csv),
                    onDownloadExcel: () =>
                        _downloadBackup(BackupExportFormat.xlsx),
                  ),
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    _Panel(child: Text(_notice!)),
                  ],
                  const SizedBox(height: 16),
                  if (!snapshot.hasData)
                    const _Panel(child: Text('Loading backup history…'))
                  else if (jobs.isEmpty)
                    const _Panel(
                      child: Text('No backups have been recorded yet.'),
                    )
                  else
                    _JobTable(jobs: jobs, onRefresh: _refresh),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard();

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Coverage', style: TextStyle(fontWeight: FontWeight.w900)),
        SizedBox(height: 8),
        _CoverageRow('Firestore database', 'Included', included: true),
        _CoverageRow(
          'Firebase Authentication users',
          'Excluded in Phase 1',
          included: false,
        ),
        _CoverageRow('Storage files', 'Excluded in Phase 1', included: false),
      ],
    ),
  );
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow(this.source, this.state, {required this.included});

  final String source;
  final String state;
  final bool included;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(
          included ? Icons.check_circle_outline : Icons.remove_circle_outline,
          size: 18,
          color: included ? AdminColors.accent : AdminColors.muted,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(source)),
        Text(state, style: const TextStyle(color: AdminColors.muted)),
      ],
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.summary,
    required this.busy,
    required this.onRequest,
  });

  final BackupSummary summary;
  final bool busy;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Last verified backup',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                summary.lastVerifiedAt == null
                    ? 'None recorded'
                    : _dateTime(summary.lastVerifiedAt!),
                style: const TextStyle(color: AdminColors.muted),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: busy || summary.hasRunning ? null : onRequest,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.backup_outlined),
          label: const Text('Request backup now'),
        ),
      ],
    ),
  );
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.downloadingFormat,
    required this.progress,
    required this.enabled,
    required this.onDownloadCsv,
    required this.onDownloadExcel,
  });

  final BackupExportFormat? downloadingFormat;
  final BackupExportProgress? progress;
  final bool enabled;
  final VoidCallback onDownloadCsv;
  final VoidCallback onDownloadExcel;

  @override
  Widget build(BuildContext context) {
    final isDownloading = downloadingFormat != null;
    final canDownload = enabled && !isDownloading;
    const description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Download complete backup',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 4),
        Text(
          'Exports every Firestore collection and subcollection covered by '
          'the authorized backup, preserving document IDs, references, '
          'timestamps, and parent relationships.',
          style: TextStyle(color: AdminColors.muted),
        ),
      ],
    );
    final buttons = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        OutlinedButton.icon(
          onPressed: canDownload ? onDownloadCsv : null,
          icon: downloadingFormat == BackupExportFormat.csv
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.folder_zip_outlined),
          label: Text(
            downloadingFormat == BackupExportFormat.csv
                ? 'Preparing CSV…'
                : 'Download CSV (.zip)',
          ),
        ),
        OutlinedButton.icon(
          onPressed: canDownload ? onDownloadExcel : null,
          icon: downloadingFormat == BackupExportFormat.xlsx
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.table_chart_outlined),
          label: Text(
            downloadingFormat == BackupExportFormat.xlsx
                ? 'Preparing Excel…'
                : 'Download Excel (.xlsx)',
          ),
        ),
      ],
    );

    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (constraints.maxWidth < 760) ...[
              description,
              const SizedBox(height: 12),
              buttons,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: description),
                  const SizedBox(width: 16),
                  buttons,
                ],
              ),
            if (isDownloading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(
                progress == null
                    ? 'Fetching authorized Firestore collections…'
                    : 'Fetched page ${progress!.pagesLoaded}: '
                          '${progress!.documentsLoaded} documents across '
                          '${progress!.collectionsDiscovered} collections…',
                style: const TextStyle(color: AdminColors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JobTable extends StatelessWidget {
  const _JobTable({required this.jobs, required this.onRefresh});

  final List<BackupJob> jobs;
  final ValueChanged<String> onRefresh;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: EdgeInsets.zero,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Requested')),
          DataColumn(label: Text('Trigger')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Documents')),
          DataColumn(label: Text('Completed')),
          DataColumn(label: Text('Error')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final job in jobs)
            DataRow(
              cells: [
                DataCell(Text(_dateTime(job.requestedAt))),
                DataCell(Text(job.trigger)),
                DataCell(Text(_statusLabel(job))),
                DataCell(
                  Text(
                    job.documentsCompleted == null
                        ? '-'
                        : job.documentsEstimated == null ||
                              job.documentsEstimated == 0
                        ? '${job.documentsCompleted}'
                        : '${job.documentsCompleted} / ${job.documentsEstimated}',
                  ),
                ),
                DataCell(
                  Text(
                    job.completedAt == null ? '-' : _dateTime(job.completedAt!),
                  ),
                ),
                DataCell(Text(job.errorCode ?? '-')),
                DataCell(
                  job.isTerminal
                      ? const SizedBox.shrink()
                      : TextButton(
                          onPressed: () => onRefresh(job.id),
                          child: const Text('Refresh status'),
                        ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

String _statusLabel(BackupJob job) => switch (job.status) {
  BackupJobStatus.running => 'Running',
  BackupJobStatus.completed => 'Completed · ${job.verification.label}',
  BackupJobStatus.failed =>
    job.verification == BackupVerificationStatus.missing
        ? 'Failed · ${job.verification.label}'
        : 'Failed',
};

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AdminColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminColors.border),
    ),
    child: child,
  );
}
