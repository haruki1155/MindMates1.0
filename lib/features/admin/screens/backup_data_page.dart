import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_status_presentation.dart';
import '../domain/backup_export.dart';
import '../domain/backup_job.dart';
import '../services/admin_file_download.dart';
import '../services/backup_export_formatter.dart';
import '../theme/admin_theme.dart';
import '../widgets/admin_status_badge.dart';

/// Super-administrator view of full system backups (covering all academic
/// years) and downloadable non-clinical administrative exports (CSV ZIP and
/// Excel `.xlsx`).
///
/// Backup history rows display status, timing, record counts, retention
/// windows, and plain-language notes only — never internal storage paths or
/// download links.
class BackupDataPage extends StatefulWidget {
  const BackupDataPage({
    super.key,
    required this.repository,
    this.downloadFile = downloadAdminFile,
    this.clock,
  });

  final AdminPortalRepository repository;
  final AdminFileDownloader downloadFile;
  final DateTime Function()? clock;

  @override
  State<BackupDataPage> createState() => _BackupDataPageState();
}

enum _NoticeTone { success, info, error }

class _BackupNotice {
  const _BackupNotice(this.tone, this.message);

  final _NoticeTone tone;
  final String message;
}

class _BackupDataPageState extends State<BackupDataPage> {
  late Stream<List<BackupJob>> _jobs;
  bool _busy = false;
  String? _refreshingJobId;
  BackupExportFormat? _downloadingFormat;
  BackupExportProgress? _exportProgress;
  _BackupNotice? _notice;

  @override
  void initState() {
    super.initState();
    _jobs = widget.repository.watchBackupJobs();
  }

  Future<void> _request() async {
    if (_busy || !widget.repository.isSuperAdmin) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a full system backup?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This creates a full system backup of all application '
                  'database records across all academic years in secure '
                  'server storage.',
                  style: TextStyle(color: AdminColors.ink, height: 1.45),
                ),
                SizedBox(height: AdminSpacing.sm),
                Text(
                  'Cloud usage and storage charges may apply. User sign-in '
                  'accounts and uploaded files are not included in this '
                  'backup.',
                  style: TextStyle(
                    color: AdminColors.muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
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
        () => _notice = const _BackupNotice(
          _NoticeTone.success,
          'Backup requested. Track its progress in the backup history below '
          'and use Refresh status to update it.',
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _notice = _BackupNotice(
          _NoticeTone.error,
          _mapRequestException(error),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _notice = const _BackupNotice(
          _NoticeTone.error,
          'Unable to start the backup right now because the service is '
          'unavailable.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh(String jobId) async {
    if (_refreshingJobId != null) return;
    setState(() {
      _refreshingJobId = jobId;
      _notice = null;
    });
    try {
      await widget.repository.refreshBackupJobStatus(jobId);
      if (!mounted) return;
      setState(
        () => _notice = const _BackupNotice(
          _NoticeTone.info,
          'Backup status refreshed.',
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _notice = _BackupNotice(
          _NoticeTone.error,
          _mapRefreshException(error),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _notice = const _BackupNotice(
          _NoticeTone.error,
          'Unable to refresh backup status right now because the service is '
          'unavailable.',
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshingJobId = null);
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
        () => _notice = _BackupNotice(
          _NoticeTone.success,
          'Downloaded $fileName (${dataset.totalCollections} '
          '${dataset.totalCollections == 1 ? 'data table' : 'data tables'}, '
          '${dataset.totalDocuments} '
          '${dataset.totalDocuments == 1 ? 'record' : 'records'}).',
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _notice = _BackupNotice(
          _NoticeTone.error,
          _mapDownloadException(error),
        ),
      );
    } on UnsupportedError catch (error) {
      if (!mounted) return;
      final detail = _safePlainText(error.message);
      setState(
        () => _notice = _BackupNotice(
          _NoticeTone.error,
          detail == null
              ? 'Backup download is not supported on this platform. '
                    'No backup file was created.'
              : 'Backup download failed: $detail No backup file was created.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _notice = const _BackupNotice(
          _NoticeTone.error,
          'Backup download failed because the export could not be completed. '
          'No backup file was created.',
        ),
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 680;
      final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 28.0;
      final theme = Theme.of(context);
      final now = (widget.clock ?? DateTime.now)();

      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          compact ? 20 : 28,
          horizontalPadding,
          40,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: StreamBuilder<List<BackupJob>>(
              stream: _jobs,
              builder: (context, snapshot) {
                final jobs = snapshot.data ?? const <BackupJob>[];
                final summary = BackupSummary.fromJobs(jobs);
                final lastVerifiedJob = _lastVerifiedJob(jobs);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Back-up Data',
                      style:
                          theme.textTheme.headlineLarge ??
                          const TextStyle(
                            fontSize: 28,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AdminColors.ink,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create a full system backup covering all academic years '
                      'in secure server storage, or download approved '
                      'non-clinical administrative records across all academic '
                      'years as CSV (ZIP) or Excel (.xlsx).',
                      style:
                          theme.textTheme.bodyMedium ??
                          const TextStyle(
                            color: AdminColors.muted,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: AdminSpacing.lg - 4),
                    const _CoverageCard(),
                    const SizedBox(height: AdminSpacing.md),
                    if (snapshot.hasError)
                      const _UnauthorizedStatePanel()
                    else ...[
                      _SummarySection(
                        summary: summary,
                        lastVerifiedJob: lastVerifiedJob,
                        now: now,
                        busy: _busy,
                        enabled: widget.repository.isSuperAdmin,
                        onRequest: _request,
                      ),
                      const SizedBox(height: AdminSpacing.md),
                      _DownloadCard(
                        downloadingFormat: _downloadingFormat,
                        progress: _exportProgress,
                        enabled: widget.repository.isSuperAdmin,
                        onDownloadCsv: () =>
                            _downloadBackup(BackupExportFormat.csv),
                        onDownloadExcel: () =>
                            _downloadBackup(BackupExportFormat.xlsx),
                      ),
                      if (_notice != null) ...[
                        const SizedBox(height: AdminSpacing.sm),
                        _NoticeBanner(
                          notice: _notice!,
                          onDismiss: () => setState(() => _notice = null),
                        ),
                      ],
                      const SizedBox(height: AdminSpacing.md),
                      if (!snapshot.hasData)
                        const _LoadingStatePanel()
                      else if (jobs.isEmpty)
                        const _EmptyStatePanel()
                      else
                        _BackupHistorySection(
                          jobs: jobs,
                          now: now,
                          refreshingJobId: _refreshingJobId,
                          onRefresh: _refresh,
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What is included',
            style:
                theme.textTheme.titleMedium ??
                const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.ink,
                ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Full system backups cover all academic years across the main '
            'application database.',
            style: TextStyle(
              color: AdminColors.muted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AdminSpacing.sm),
          const _CoverageRow(
            'Application database records (all academic years)',
            included: true,
          ),
          const Divider(height: 16, color: AdminColors.surfaceMuted),
          const _CoverageRow(
            'User sign-in accounts and login credentials',
            included: false,
          ),
          const Divider(height: 16, color: AdminColors.surfaceMuted),
          const _CoverageRow(
            'Uploaded files and session attachments',
            included: false,
          ),
        ],
      ),
    );
  }
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow(this.source, {required this.included});

  final String source;
  final bool included;

  @override
  Widget build(BuildContext context) {
    final badge = AdminStatusBadge(
      compact: true,
      presentation: included
          ? AdminStatusPresentation.fromTone(
              tone: AdminSemanticTone.green,
              label: 'Included',
              icon: Icons.check_circle_outline,
            )
          : AdminStatusPresentation.fromTone(
              tone: AdminSemanticTone.neutral,
              label: 'Not included',
              icon: Icons.remove_circle_outline,
            ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 460) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source,
                style: const TextStyle(
                  color: AdminColors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 6),
              badge,
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Text(
                source,
                style: const TextStyle(
                  color: AdminColors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
            const SizedBox(width: AdminSpacing.sm),
            badge,
          ],
        );
      },
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.summary,
    required this.lastVerifiedJob,
    required this.now,
    required this.busy,
    required this.enabled,
    required this.onRequest,
  });

  final BackupSummary summary;
  final BackupJob? lastVerifiedJob;
  final DateTime now;
  final bool busy;
  final bool enabled;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final columns = constraints.maxWidth >= 900
              ? 3
              : constraints.maxWidth >= 560
              ? 2
              : 1;
          final tileWidth =
              (constraints.maxWidth - (columns - 1) * AdminSpacing.sm) /
              columns;

          final actionButton = FilledButton.icon(
            onPressed: !enabled || busy || summary.hasRunning
                ? null
                : onRequest,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.backup_outlined),
            label: const Text('Request backup now'),
          );

          final headerText = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Full system backups',
                style:
                    theme.textTheme.titleMedium ??
                    const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.ink,
                    ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Server-stored snapshots covering all academic years.',
                style: TextStyle(color: AdminColors.muted, fontSize: 13),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                headerText,
                const SizedBox(height: AdminSpacing.sm),
                SizedBox(width: double.infinity, child: actionButton),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: headerText),
                    const SizedBox(width: AdminSpacing.md),
                    actionButton,
                  ],
                ),
              if (summary.hasRunning) ...[
                const SizedBox(height: AdminSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AdminColors.blueBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AdminColors.blueBorder.withValues(alpha: 0.65),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 17,
                        color: AdminColors.blueFg,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'A backup is already running. Refresh its status '
                          'below before starting another.',
                          style: TextStyle(
                            color: AdminColors.blueFg,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AdminSpacing.md),
              Wrap(
                spacing: AdminSpacing.sm,
                runSpacing: AdminSpacing.sm,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _buildLastVerifiedTile(lastVerifiedJob, now),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _buildLatestStatusTile(summary.latest, now),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _buildRetentionTile(summary.latest, now),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLastVerifiedTile(BackupJob? job, DateTime now) {
    if (job == null || job.completedAt == null) {
      return _SummaryMetricTile(
        title: 'Last verified backup',
        value: 'None recorded yet',
        caption: 'No verified full system backup has completed yet.',
        badge: AdminStatusBadge(
          compact: true,
          presentation: AdminStatusPresentation.fromTone(
            tone: AdminSemanticTone.neutral,
            label: 'None yet',
            icon: Icons.history_outlined,
          ),
        ),
      );
    }

    final expiresAt = job.expiresAt;
    final retentionEnded = expiresAt != null && !expiresAt.isAfter(now);
    final caption = expiresAt == null
        ? '${_triggerLabel(job.trigger)} full system backup'
        : retentionEnded
        ? 'Retention ended on ${_dateTime(expiresAt)}'
        : 'Retention active until ${_dateTime(expiresAt)}';

    return _SummaryMetricTile(
      title: 'Last verified backup',
      value: _dateTime(job.completedAt!),
      caption: caption,
      badge: AdminStatusBadge(
        compact: true,
        presentation: retentionEnded
            ? AdminStatusPresentation.fromTone(
                tone: AdminSemanticTone.neutral,
                label: 'Retention ended',
                icon: Icons.timer_off_outlined,
              )
            : AdminStatusPresentation.fromTone(
                tone: AdminSemanticTone.green,
                label: 'Verified',
                icon: Icons.check_circle_outline,
              ),
      ),
    );
  }

  Widget _buildLatestStatusTile(BackupJob? latest, DateTime now) {
    if (latest == null) {
      return _SummaryMetricTile(
        title: 'Latest backup status',
        value: 'No runs yet',
        caption: 'Start a manual backup or wait for a scheduled run.',
        badge: AdminStatusBadge(
          compact: true,
          presentation: AdminStatusPresentation.fromTone(
            tone: AdminSemanticTone.neutral,
            label: 'Idle',
            icon: Icons.inbox_outlined,
          ),
        ),
      );
    }

    final recordsSuffix = latest.documentsCompleted != null
        ? ' · ${_formatInt(latest.documentsCompleted!)} records'
        : '';

    return _SummaryMetricTile(
      title: 'Latest backup status',
      value: _dateTime(latest.requestedAt),
      caption: '${_triggerLabel(latest.trigger)} request$recordsSuffix',
      badge: AdminStatusBadge(
        compact: true,
        presentation: resolveBackupJobStatus(latest, now: now),
      ),
    );
  }

  Widget _buildRetentionTile(BackupJob? latest, DateTime now) {
    if (latest == null) {
      return _SummaryMetricTile(
        title: 'Retention window',
        value: 'Server-managed retention',
        caption: 'Applied automatically on the server when a backup runs.',
        badge: AdminStatusBadge(
          compact: true,
          presentation: AdminStatusPresentation.fromTone(
            tone: AdminSemanticTone.neutral,
            label: 'Server policy',
            icon: Icons.policy_outlined,
          ),
        ),
      );
    }

    if (latest.status == BackupJobStatus.failed ||
        latest.verification == BackupVerificationStatus.missing) {
      return _SummaryMetricTile(
        title: 'Retention window',
        value: 'Not retained',
        caption: 'No verified backup was stored for the latest run.',
        badge: AdminStatusBadge(
          compact: true,
          presentation: AdminStatusPresentation.fromTone(
            tone: AdminSemanticTone.neutral,
            label: 'Not retained',
            icon: Icons.remove_circle_outline,
          ),
        ),
      );
    }

    if (latest.status == BackupJobStatus.running) {
      final value = latest.retentionDays > 0
          ? '${latest.retentionDays} ${latest.retentionDays == 1 ? 'day' : 'days'}'
          : 'Pending';
      return _SummaryMetricTile(
        title: 'Retention window',
        value: value,
        caption: 'Retention window starts once the backup finishes.',
        badge: AdminStatusBadge(
          compact: true,
          presentation: AdminStatusPresentation.fromTone(
            tone: AdminSemanticTone.neutral,
            label: 'Pending',
            icon: Icons.schedule_outlined,
          ),
        ),
      );
    }

    if (latest.retentionDays <= 0 && latest.expiresAt == null) {
      return _SummaryMetricTile(
        title: 'Retention window',
        value: 'Server-managed retention',
        caption: 'Applied automatically on the server when a backup runs.',
        badge: AdminStatusBadge(
          compact: true,
          presentation: AdminStatusPresentation.fromTone(
            tone: AdminSemanticTone.neutral,
            label: 'Server policy',
            icon: Icons.policy_outlined,
          ),
        ),
      );
    }

    final expiresAt = latest.expiresAt;
    final expired = expiresAt != null && !expiresAt.isAfter(now);
    final value = latest.retentionDays > 0
        ? '${latest.retentionDays} ${latest.retentionDays == 1 ? 'day' : 'days'}'
        : (expired ? 'Retention ended' : 'Active retention');
    final caption = expiresAt == null
        ? 'Server-managed per-backup retention'
        : expired
        ? 'Latest backup expired on ${_dateTime(expiresAt)}'
        : 'Latest backup kept until ${_dateTime(expiresAt)}';

    return _SummaryMetricTile(
      title: 'Retention window',
      value: value,
      caption: caption,
      badge: AdminStatusBadge(
        compact: true,
        presentation: expired
            ? AdminStatusPresentation.fromTone(
                tone: AdminSemanticTone.neutral,
                label: 'Expired',
                icon: Icons.timer_off_outlined,
              )
            : AdminStatusPresentation.fromTone(
                tone: AdminSemanticTone.blue,
                label: 'Active',
                icon: Icons.schedule_outlined,
              ),
      ),
    );
  }
}

class _SummaryMetricTile extends StatelessWidget {
  const _SummaryMetricTile({
    required this.title,
    required this.value,
    required this.caption,
    required this.badge,
  });

  final String title;
  final String value;
  final String caption;
  final Widget badge;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AdminColors.canvas,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AdminColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AdminColors.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              badge,
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: AdminColors.ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: const TextStyle(
            color: AdminColors.muted,
            fontSize: 12.5,
            height: 1.35,
          ),
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
    final theme = Theme.of(context);
    final isDownloading = downloadingFormat != null;
    final canDownload = enabled && !isDownloading;

    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Administrative Data Export',
          style:
              theme.textTheme.titleMedium ??
              const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AdminColors.ink,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Downloads approved non-clinical administrative, directory, and '
          'audit records across all academic years. Passwords and access '
          'tokens are redacted; clinical notes, assessments, private chats, '
          'and anonymity records are excluded.',
          style: TextStyle(color: AdminColors.muted, fontSize: 13, height: 1.4),
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
              const SizedBox(height: AdminSpacing.sm),
              buttons,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: description),
                  const SizedBox(width: AdminSpacing.md),
                  buttons,
                ],
              ),
            if (isDownloading) ...[
              const SizedBox(height: AdminSpacing.sm),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(
                progress == null
                    ? 'Preparing administrative records for export…'
                    : 'Downloaded ${progress!.documentsLoaded} '
                          '${progress!.documentsLoaded == 1 ? 'record' : 'records'} '
                          'across ${progress!.collectionsDiscovered} '
                          '${progress!.collectionsDiscovered == 1 ? 'data table' : 'data tables'} '
                          '(batch ${progress!.pagesLoaded})…',
                style: const TextStyle(color: AdminColors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.notice, required this.onDismiss});

  final _BackupNotice notice;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border, icon) = switch (notice.tone) {
      _NoticeTone.success => (
        AdminColors.greenBg,
        AdminColors.greenFg,
        AdminColors.greenBorder,
        Icons.check_circle_outline,
      ),
      _NoticeTone.info => (
        AdminColors.blueBg,
        AdminColors.blueFg,
        AdminColors.blueBorder,
        Icons.info_outline,
      ),
      _NoticeTone.error => (
        AdminColors.redBg,
        AdminColors.redFg,
        AdminColors.redBorder,
        Icons.error_outline,
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice.message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: Icon(Icons.close, size: 16, color: fg),
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _UnauthorizedStatePanel extends StatelessWidget {
  const _UnauthorizedStatePanel();

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.all(28),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_person_outlined, size: 36, color: AdminColors.muted),
        SizedBox(height: AdminSpacing.sm),
        Text(
          'Super-administrator access required',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AdminColors.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Backup history requires the configured super-administrator account.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AdminColors.muted, fontSize: 13),
        ),
      ],
    ),
  );
}

class _LoadingStatePanel extends StatelessWidget {
  const _LoadingStatePanel();

  @override
  Widget build(BuildContext context) => const _Panel(
    padding: EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: AdminSpacing.sm),
        Text(
          'Loading backup history…',
          style: TextStyle(
            color: AdminColors.muted,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _EmptyStatePanel extends StatelessWidget {
  const _EmptyStatePanel();

  @override
  Widget build(BuildContext context) => const _Panel(
    padding: EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.history_toggle_off_outlined,
          size: 34,
          color: AdminColors.muted,
        ),
        SizedBox(height: AdminSpacing.sm),
        Text(
          'No backups have been recorded yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AdminColors.ink,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Use Request backup now above to create a full system backup, '
          'or wait for the next scheduled run.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AdminColors.muted, fontSize: 13),
        ),
      ],
    ),
  );
}

class _BackupHistorySection extends StatelessWidget {
  const _BackupHistorySection({
    required this.jobs,
    required this.now,
    required this.refreshingJobId,
    required this.onRefresh,
  });

  final List<BackupJob> jobs;
  final DateTime now;
  final String? refreshingJobId;
  final ValueChanged<String> onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Backup history',
                    style:
                        theme.textTheme.titleMedium ??
                        const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.ink,
                        ),
                  ),
                ),
                Text(
                  '${jobs.length} ${jobs.length == 1 ? 'record' : 'records'}',
                  style: const TextStyle(
                    color: AdminColors.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AdminSpacing.xs),
            if (compact)
              Column(
                children: [
                  for (var i = 0; i < jobs.length; i++) ...[
                    _BackupHistoryCard(
                      job: jobs[i],
                      now: now,
                      refreshing: refreshingJobId == jobs[i].id,
                      onRefresh: () => onRefresh(jobs[i].id),
                    ),
                    if (i < jobs.length - 1)
                      const SizedBox(height: AdminSpacing.sm),
                  ],
                ],
              )
            else
              _Panel(
                padding: EdgeInsets.zero,
                child: LayoutBuilder(
                  builder: (context, tableConstraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: tableConstraints.maxWidth,
                      ),
                      child: DataTable(
                        columnSpacing: 20,
                        horizontalMargin: 16,
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 68,
                        columns: const [
                          DataColumn(label: Text('Requested')),
                          DataColumn(label: Text('Source')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Records')),
                          DataColumn(label: Text('Completed')),
                          DataColumn(label: Text('Retention')),
                          DataColumn(label: Text('Notes')),
                          DataColumn(label: Text('')),
                        ],
                        rows: [
                          for (final job in jobs)
                            DataRow(
                              cells: [
                                DataCell(Text(_dateTime(job.requestedAt))),
                                DataCell(Text(_triggerLabel(job.trigger))),
                                DataCell(
                                  AdminStatusBadge(
                                    compact: true,
                                    presentation: resolveBackupJobStatus(
                                      job,
                                      now: now,
                                    ),
                                  ),
                                ),
                                DataCell(Text(_recordProgressLabel(job))),
                                DataCell(
                                  Text(
                                    job.completedAt == null
                                        ? '-'
                                        : _dateTime(job.completedAt!),
                                  ),
                                ),
                                DataCell(Text(_retentionLabel(job, now: now))),
                                DataCell(
                                  Text(
                                    _sanitizedJobNote(job),
                                    style: TextStyle(
                                      color: _hasJobErrorNote(job)
                                          ? AdminColors.redFg
                                          : AdminColors.muted,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  job.isTerminal
                                      ? const SizedBox.shrink()
                                      : OutlinedButton.icon(
                                          onPressed: refreshingJobId == job.id
                                              ? null
                                              : () => onRefresh(job.id),
                                          icon: refreshingJobId == job.id
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.refresh_outlined,
                                                  size: 16,
                                                ),
                                          label: Text(
                                            refreshingJobId == job.id
                                                ? 'Refreshing…'
                                                : 'Refresh status',
                                          ),
                                        ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BackupHistoryCard extends StatelessWidget {
  const _BackupHistoryCard({
    required this.job,
    required this.now,
    required this.refreshing,
    required this.onRefresh,
  });

  final BackupJob job;
  final DateTime now;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final note = _sanitizedJobNote(job);
    final hasError = _hasJobErrorNote(job);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dateTime(job.requestedAt),
                      style: const TextStyle(
                        color: AdminColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_triggerLabel(job.trigger)} backup',
                      style: const TextStyle(
                        color: AdminColors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AdminSpacing.xs),
              Flexible(
                child: AdminStatusBadge(
                  compact: true,
                  presentation: resolveBackupJobStatus(job, now: now),
                ),
              ),
            ],
          ),
          const SizedBox(height: AdminSpacing.sm),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _CardMetaItem(label: 'Records', value: _recordProgressLabel(job)),
              _CardMetaItem(
                label: 'Completed',
                value: job.completedAt == null
                    ? '-'
                    : _dateTime(job.completedAt!),
              ),
              _CardMetaItem(
                label: 'Retention',
                value: _retentionLabel(job, now: now),
              ),
            ],
          ),
          if (hasError) ...[
            const SizedBox(height: AdminSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AdminColors.redBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AdminColors.redBorder.withValues(alpha: 0.65),
                ),
              ),
              child: Text(
                note,
                style: const TextStyle(
                  color: AdminColors.redFg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (!job.isTerminal) ...[
            const SizedBox(height: AdminSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined, size: 16),
                label: Text(refreshing ? 'Refreshing…' : 'Refresh status'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardMetaItem extends StatelessWidget {
  const _CardMetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: AdminColors.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          color: AdminColors.ink,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

BackupJob? _lastVerifiedJob(List<BackupJob> jobs) {
  BackupJob? best;
  for (final job in jobs) {
    final completedAt = job.completedAt;
    if (job.status == BackupJobStatus.completed &&
        job.verification == BackupVerificationStatus.verified &&
        completedAt != null &&
        (best == null || completedAt.isAfter(best.completedAt!))) {
      best = job;
    }
  }
  return best;
}

String _triggerLabel(String raw) {
  final clean = raw.trim().toLowerCase();
  return switch (clean) {
    'manual' => 'Manual',
    'scheduled' => 'Scheduled',
    '' => 'Manual',
    _ => '${clean[0].toUpperCase()}${clean.substring(1)}',
  };
}

String _recordProgressLabel(BackupJob job) {
  if (job.documentsCompleted == null) return '-';
  final completed = _formatInt(job.documentsCompleted!);
  if (job.documentsEstimated == null || job.documentsEstimated == 0) {
    return completed;
  }
  return '$completed / ${_formatInt(job.documentsEstimated!)}';
}

String _retentionLabel(BackupJob job, {required DateTime now}) {
  if (job.status == BackupJobStatus.failed ||
      job.verification == BackupVerificationStatus.missing) {
    return 'Not retained';
  }
  final days = job.retentionDays;
  final daysText = days > 0 ? '$days ${days == 1 ? 'day' : 'days'}' : null;
  if (job.status == BackupJobStatus.running) {
    return daysText == null ? 'Pending' : '$daysText · Pending';
  }
  final expiresAt = job.expiresAt;

  if (expiresAt != null) {
    final expired = !expiresAt.isAfter(now);
    final dateText = _dateOnly(expiresAt);
    final expiryText = expired ? 'Ended $dateText' : 'Until $dateText';
    return daysText == null ? expiryText : '$daysText · $expiryText';
  }
  if (daysText != null) return daysText;
  return 'Server-managed';
}

bool _hasJobErrorNote(BackupJob job) =>
    job.status == BackupJobStatus.failed ||
    job.verification == BackupVerificationStatus.missing;

String _sanitizedJobNote(BackupJob job) {
  if (!_hasJobErrorNote(job)) return '-';
  final safeMessage = _safePlainText(job.errorMessage);
  if (safeMessage != null) return safeMessage;
  if (job.verification == BackupVerificationStatus.missing) {
    return 'Backup finished without a verified output file.';
  }
  return switch (job.errorCode?.trim().toLowerCase()) {
    'unavailable' ||
    'deadline-exceeded' => 'Backup service temporarily unavailable.',
    'permission-denied' ||
    'unauthenticated' => 'Insufficient server permissions.',
    'failed-precondition' => 'Backup prerequisites were not met.',
    'output-missing' || 'missing' => 'Output file could not be verified.',
    _ => 'Backup failed on the server.',
  };
}

String _mapRequestException(FirebaseFunctionsException error) {
  final code = error.code.trim().toLowerCase();
  final msg = error.message?.trim() ?? '';
  if (code == 'failed-precondition') {
    final lower = msg.toLowerCase();
    if (lower.contains('not configured')) {
      return 'Backup storage is not configured yet. Ask your system '
          'administrator to complete server backup setup before requesting a '
          'backup.';
    }
    if (_technicalJargonPattern.hasMatch(msg)) {
      return 'Backup settings on the server are not configured properly. Ask '
          'your system administrator to check the server backup setup.';
    }
    if (lower.contains('running')) {
      return 'A backup is already running. Wait for it to finish or refresh '
          'its status before starting another.';
    }
    if (lower.contains('limit') || lower.contains('daily')) {
      return 'Daily manual backup limit reached. Please wait before '
          'requesting another manual backup.';
    }
    return _safePlainText(msg) ??
        'The backup could not be started right now. Please check whether a '
            'backup is already running or try again later.';
  }
  if (code == 'permission-denied' || code == 'unauthenticated') {
    return 'Super-administrator access is required to request a backup.';
  }
  if (code == 'unavailable' || code == 'deadline-exceeded') {
    return 'The backup service is temporarily unavailable. Please try again '
        'in a moment.';
  }
  return 'Unable to start the backup right now. Please try again or contact '
      'your system administrator.';
}

String _mapRefreshException(FirebaseFunctionsException error) {
  final code = error.code.trim().toLowerCase();
  if (code == 'failed-precondition') {
    return 'Backup status cannot be refreshed because server backup setup is '
        'incomplete.';
  }
  if (code == 'permission-denied' || code == 'unauthenticated') {
    return 'Super-administrator access is required to refresh backup status.';
  }
  if (code == 'not-found') {
    return 'This backup record could not be found.';
  }
  if (code == 'unavailable' || code == 'deadline-exceeded') {
    return 'Unable to refresh backup status because the service is '
        'temporarily unavailable.';
  }
  return 'Unable to refresh backup status right now. Please try again.';
}

String _mapDownloadException(FirebaseFunctionsException error) {
  final code = error.code.trim().toLowerCase();
  if (code == 'failed-precondition') {
    return 'Backup download is unavailable right now because server '
        'prerequisites were not met. No backup file was created.';
  }
  if (code == 'permission-denied' || code == 'unauthenticated') {
    return 'Backup download was denied. Super-administrator access is '
        'required. No backup file was created.';
  }
  if (code == 'unavailable' || code == 'deadline-exceeded') {
    return 'Backup download timed out or the service is unavailable. '
        'No backup file was created.';
  }
  return 'Backup download could not be completed. No backup file was created.';
}

final _technicalJargonPattern = RegExp(
  r'(gs://|firestore|\bfirebase\b|google\s+cloud|cloud\s+storage|'
  r'cloud\s+functions?|httpscallable|service\s+account|'
  r'backup_service_account|backup_retention_days|backup_manual_daily_limit|'
  r'backup_bucket|bucket|iam\.gserviceaccount\.com|\biam\b|'
  r'projects/[^/\s]+/databases|\(default\)|overall_export_metadata|'
  r'exportdocuments|academic\s+year\s+backup|phase\s*1|\bcollections?\b|'
  r'\bdocuments?\b|backup_jobs|admin_audit_logs|counseling_population|'
  r'student_roster)',
  caseSensitive: false,
);

String? _safePlainText(String? raw) {
  final clean = raw?.trim() ?? '';
  if (clean.isEmpty) return null;
  if (_technicalJargonPattern.hasMatch(clean)) return null;
  return clean;
}

String _formatInt(int value) {
  final digits = value.toString();
  if (digits.length <= 3) return digits;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _dateOnly(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
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
