import 'dart:math' as math;
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart' as excel;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../models/profile_roles.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../../authentication/data/registration_organization_catalog.dart';
import '../../../services/admin_report_pdf_service.dart';
import '../domain/report_generation_models.dart';
import '../theme/admin_theme.dart';
import '../services/admin_import_file_picker.dart';

enum _ReportPeriod { wholeYear, firstSemester, secondSemester, custom }

class ReportGenerationPage extends StatefulWidget {
  const ReportGenerationPage({
    super.key,
    required this.repository,
    this.pdfPreviewBuilder,
    this.onPrintPdf,
    this.onSharePdf,
  });

  final AdminPortalRepository repository;
  final Widget Function(BuildContext context, Uint8List bytes)?
  pdfPreviewBuilder;
  final Future<void> Function(Uint8List bytes)? onPrintPdf;
  final Future<void> Function(Uint8List bytes, String filename)? onSharePdf;

  @override
  State<ReportGenerationPage> createState() => _ReportGenerationPageState();
}

class _ReportGenerationPageState extends State<ReportGenerationPage> {
  late Future<AdminReportAnalytics> _report;
  AdminReportType _reportType = AdminReportType.users;
  ReportChartType _chartType = ReportChartType.pie;
  AppointmentReportDimension _dimension = AppointmentReportDimension.department;
  String _userCategory = 'all';
  String _appointmentDepartment = 'all';
  String _program = 'all';
  String _schoolYear = _currentSchoolYear();
  _ReportPeriod _period = _ReportPeriod.wholeYear;
  EmotionalActivitySource _emotionalSource = EmotionalActivitySource.all;
  DateTimeRange? _customRange;
  AdminReportAnalytics? _latestReport;
  bool _downloading = false;
  bool _previewing = false;
  bool _filterLoading = false;
  int _reportRequestId = 0;

  @override
  void initState() {
    super.initState();
    _report = _runFetch(_reportRequestId);
  }

  String get _periodLabel => switch (_period) {
    _ReportPeriod.wholeYear => 'Whole academic year',
    _ReportPeriod.firstSemester => '1st semester',
    _ReportPeriod.secondSemester => '2nd semester',
    _ReportPeriod.custom => 'Custom date range',
  };

  Future<AdminReportAnalytics> _fetch() {
    final range = _period == _ReportPeriod.wholeYear ? null : _periodRange();
    return widget.repository.fetchFilteredReportAnalytics(
      userCategory: _userCategory,
      appointmentDepartment: _appointmentDepartment,
      program: _program,
      schoolYear: _schoolYear,
      periodLabel: _period == _ReportPeriod.wholeYear ? null : _periodLabel,
      startDate: range?.start,
      endDate: range?.end,
      emotionalSource: _emotionalSource.wireKey,
    );
  }

  Future<AdminReportAnalytics> _runFetch(int requestId) {
    final future = _fetch();
    future.then(
      (value) {
        if (!mounted || requestId != _reportRequestId) return;
        setState(() {
          _latestReport = value;
          _filterLoading = false;
        });
      },
      onError: (_, _) {
        if (!mounted || requestId != _reportRequestId) return;
        setState(() => _filterLoading = false);
      },
    );
    return future;
  }

  /// Converts a Philippines (UTC+8) calendar date midnight to its UTC instant.
  static DateTime _manilaDayStart(int year, int month, int day) =>
      DateTime.utc(year, month, day).subtract(const Duration(hours: 8));

  static DateTime? _parseCalendarDate(String raw) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;
    return DateTime.utc(year, month, day);
  }

  DateTimeRange? _periodRange() {
    if (_period == _ReportPeriod.custom) {
      final range = _customRange;
      if (range == null) return null;
      return DateTimeRange(
        start: _manilaDayStart(
          range.start.year,
          range.start.month,
          range.start.day,
        ),
        end: _manilaDayStart(
          range.end.year,
          range.end.month,
          range.end.day + 1,
        ),
      );
    }
    final activeYear = _latestReport?.population.years
        .where((item) => item.schoolYear == _schoolYear)
        .firstOrNull;
    final configuredStart = activeYear == null
        ? null
        : _parseCalendarDate(activeYear.startDate);
    final configuredEnd = activeYear == null
        ? null
        : _parseCalendarDate(activeYear.endDate);
    if (configuredStart != null && configuredEnd != null) {
      final yearStart = _manilaDayStart(
        configuredStart.year,
        configuredStart.month,
        configuredStart.day,
      );
      final yearEndExclusive = _manilaDayStart(
        configuredEnd.year,
        configuredEnd.month,
        configuredEnd.day + 1,
      );
      final mid = _manilaDayStart(
        configuredStart.year,
        configuredStart.month + 6,
        configuredStart.day,
      );
      if (mid.isAfter(yearStart) && mid.isBefore(yearEndExclusive)) {
        return _period == _ReportPeriod.firstSemester
            ? DateTimeRange(start: yearStart, end: mid)
            : DateTimeRange(start: mid, end: yearEndExclusive);
      }
    }
    final startYear =
        int.tryParse(_schoolYear.split('-').first) ?? DateTime.now().year;
    return _period == _ReportPeriod.firstSemester
        ? DateTimeRange(
            start: _manilaDayStart(startYear, 6, 1),
            end: _manilaDayStart(startYear, 12, 1),
          )
        : DateTimeRange(
            start: _manilaDayStart(startYear, 12, 1),
            end: _manilaDayStart(startYear + 1, 6, 1),
          );
  }

  void _refresh() => _reloadReport();

  void _reloadReport() {
    final requestId = ++_reportRequestId;
    setState(() {
      _filterLoading = true;
      _report = _runFetch(requestId);
    });
  }

  void _selectUserCategory(String value) {
    setState(() {
      _userCategory = value;
    });
    _reloadReport();
  }

  void _selectDepartment(String value) {
    setState(() {
      _appointmentDepartment = value;
      _program = 'all';
      if (value != 'all' &&
          _dimension == AppointmentReportDimension.department) {
        _dimension = AppointmentReportDimension.course;
      }
    });
    _reloadReport();
  }

  void _selectProgram(String value) {
    setState(() {
      _program = value;
    });
    _reloadReport();
  }

  void _resetFilters() {
    final currentYear =
        _latestReport?.population.years
            .where((item) => item.status == 'current')
            .firstOrNull
            ?.schoolYear ??
        _currentSchoolYear();
    setState(() {
      _userCategory = 'all';
      _appointmentDepartment = 'all';
      _program = 'all';
      _schoolYear = currentYear;
      _period = _ReportPeriod.wholeYear;
      _customRange = null;
      _emotionalSource = EmotionalActivitySource.all;
      _dimension = AppointmentReportDimension.department;
    });
    _reloadReport();
  }

  Future<void> _pickCustomPeriod() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _customRange,
    );
    if (range == null || !mounted) return;
    setState(() {
      _customRange = range;
      _period = _ReportPeriod.custom;
    });
    _reloadReport();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.currentAccessRole.canAccessClinicalData) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Counselor or administrator access is required.'),
        ),
      );
    }
    return FutureBuilder<AdminReportAnalytics>(
      future: _report,
      builder: (context, snapshot) {
        final readySnapshot =
            snapshot.hasData && !snapshot.hasError && !_filterLoading;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
            28,
            MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
            40,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    loading:
                        snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData,
                    downloading: _downloading,
                    previewing: _previewing,
                    canDownload: readySnapshot,
                    showImport: _reportType == AdminReportType.appointments,
                    onDownload: readySnapshot
                        ? () => _download(snapshot.requireData)
                        : null,
                    onPreview: readySnapshot
                        ? () => _preview(snapshot.requireData)
                        : null,
                    onImport: _reportType == AdminReportType.appointments
                        ? _showBulkImport
                        : null,
                  ),
                  const SizedBox(height: 22),
                  _ReportToggle(
                    value: _reportType,
                    onChanged: (value) => setState(() => _reportType = value),
                  ),
                  const SizedBox(height: 18),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData)
                    const _LoadingPanel()
                  else if (snapshot.hasError)
                    _ErrorPanel(
                      onRetry: _refresh,
                      onResetFilters: _resetFilters,
                    )
                  else if (snapshot.hasData)
                    _content(snapshot.requireData),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content(AdminReportAnalytics report) {
    final collegeOptions = report.filters.collegeOptions.isNotEmpty
        ? report.filters.collegeOptions
        : (_reportType == AdminReportType.emotionalActivity &&
                  report.emotionalActivity.departmentOptions.isNotEmpty
              ? report.emotionalActivity.departmentOptions
              : report.appointmentDepartmentOptions);
    final programOptions = report.filters.programsForCollege(
      _appointmentDepartment,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_reportType == AdminReportType.appointments) ...[
          _AdminReportControls(
            schoolYear: _schoolYear,
            years: report.population.years,
            period: _period,
            report: report,
            chartType: _chartType,
            dimension: _dimension,
            userCategory: _userCategory,
            userCategories: report.userCategoryOptions,
            department: _appointmentDepartment,
            departmentOptions: collegeOptions,
            program: _program,
            programOptions: programOptions,
            onYearChanged: (value) {
              setState(() => _schoolYear = value);
              _reloadReport();
            },
            onPeriodChanged: (value) {
              setState(() => _period = value);
              _reloadReport();
            },
            onCustomPeriod: _pickCustomPeriod,
            onUserCategoryChanged: _selectUserCategory,
            onDepartmentChanged: _selectDepartment,
            onProgramChanged: _selectProgram,
            onDimensionChanged: (value) => setState(() => _dimension = value),
            onChartChanged: (value) => setState(() => _chartType = value),
          ),
        ] else if (_reportType == AdminReportType.emotionalActivity) ...[
          _EmotionalReportControls(
            schoolYear: _schoolYear,
            years: report.population.years,
            period: _period,
            report: report,
            chartType: _chartType,
            source: _emotionalSource,
            userCategory: _userCategory,
            userCategories: report.userCategoryOptions,
            department: _appointmentDepartment,
            departmentOptions: collegeOptions,
            program: _program,
            programOptions: programOptions,
            onYearChanged: (value) {
              setState(() => _schoolYear = value);
              _reloadReport();
            },
            onPeriodChanged: (value) {
              setState(() => _period = value);
              _reloadReport();
            },
            onCustomPeriod: _pickCustomPeriod,
            onSourceChanged: (value) {
              setState(() => _emotionalSource = value);
              _reloadReport();
            },
            onUserCategoryChanged: _selectUserCategory,
            onDepartmentChanged: _selectDepartment,
            onProgramChanged: _selectProgram,
            onChartChanged: (value) => setState(() => _chartType = value),
          ),
        ] else ...[
          _ControlPanel(
            schoolYear: _schoolYear,
            years: report.population.years,
            period: _period,
            reportType: _reportType,
            chartType: _chartType,
            dimension: _dimension,
            userCategory: _userCategory,
            userCategories: report.userCategoryOptions,
            appointmentDepartment: _appointmentDepartment,
            departmentOptions: collegeOptions,
            program: _program,
            programOptions: programOptions,
            onYearChanged: (value) {
              setState(() => _schoolYear = value);
              _reloadReport();
            },
            onPeriodChanged: (value) {
              setState(() => _period = value);
              _reloadReport();
            },
            onCustomPeriod: _pickCustomPeriod,
            onChartChanged: (value) => setState(() => _chartType = value),
            onDimensionChanged: (value) => setState(() => _dimension = value),
            onUserCategoryChanged: _selectUserCategory,
            onDepartmentChanged: _selectDepartment,
            onProgramChanged: _selectProgram,
          ),
        ],
        const SizedBox(height: 22),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _filterLoading
              ? const _ReportSkeleton(key: ValueKey('report-skeleton'))
              : _reportType == AdminReportType.users
              ? _UserReport(
                  key: const ValueKey('users'),
                  report: report,
                  chartType: _chartType,
                  categoryKey: _userCategory,
                )
              : _reportType == AdminReportType.emotionalActivity
              ? _EmotionalActivityReportView(
                  key: const ValueKey('emotional'),
                  report: report,
                  chartType: _chartType,
                )
              : _AppointmentReport(
                  key: const ValueKey('appointments'),
                  report: report,
                  chartType: _chartType,
                  dimension: _dimension,
                ),
        ),
        if (_reportType == AdminReportType.appointments &&
            widget.repository.currentAccessRole == AccessRole.admin) ...[
          const SizedBox(height: 26),
          Text('Report setup', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          _PopulationSetup(
            repository: widget.repository,
            config: report.population,
            onSaved: (config) {
              setState(() {
                _schoolYear = config.schoolYear;
              });
              _reloadReport();
              _showReportSnackBar(
                context,
                'Population saved for ${config.schoolYear}. Reports are now updating.',
              );
            },
            onYearChanged: (schoolYear) {
              setState(() {
                _schoolYear = schoolYear;
              });
              _reloadReport();
            },
          ),
          const SizedBox(height: 18),
          _ImportedFilesPanel(repository: widget.repository),
        ],
        const SizedBox(height: 14),
        _PrivacyNotice(generatedAt: report.generatedAt),
      ],
    );
  }

  Future<Uint8List> _buildPdf(AdminReportAnalytics report) =>
      AdminReportPdfService.build(
        report: report,
        reportType: _reportType,
        chartType: _chartType,
        userCategoryKey: _userCategory,
        appointmentDimension: _dimension,
      );

  Future<void> _recordReportAudit(
    String action,
    AdminReportAnalytics report,
  ) async {
    try {
      await widget.repository.recordAuditEvent(
        action: action,
        category: 'REPORTS',
        targetType: 'report',
        targetId: report.population.schoolYear,
        metadata: {
          'reportType': _reportType.name,
          'department': _appointmentDepartment,
          'program': _program,
          'period': report.filters.periodLabel,
        },
      );
    } catch (_) {}
  }

  Future<void> _shareOrDownloadPdf(
    AdminReportAnalytics report,
    Uint8List pdfBytes,
  ) async {
    if (widget.onSharePdf != null) {
      await widget.onSharePdf!(
        pdfBytes,
        AdminReportPdfService.filenameFor(report, _reportType),
      );
    } else {
      await AdminReportPdfService.download(
        report: report,
        reportType: _reportType,
        chartType: _chartType,
        userCategoryKey: _userCategory,
        appointmentDimension: _dimension,
        prebuiltBytes: pdfBytes,
      );
    }
    await _recordReportAudit('REPORT_EXPORTED_PDF', report);
  }

  Future<void> _printPdf(
    AdminReportAnalytics report,
    Uint8List pdfBytes,
  ) async {
    if (widget.onPrintPdf != null) {
      await widget.onPrintPdf!(pdfBytes);
    } else {
      await Printing.layoutPdf(
        name: AdminReportPdfService.filenameFor(report, _reportType),
        onLayout: (_) async => pdfBytes,
      );
    }
    await _recordReportAudit('REPORT_PRINTED', report);
  }

  Future<void> _download(AdminReportAnalytics report) async {
    if (_downloading || _filterLoading) return;
    setState(() => _downloading = true);
    try {
      final pdfBytes = await _buildPdf(report);
      await _shareOrDownloadPdf(report, pdfBytes);
    } catch (_) {
      if (mounted) {
        _showReportSnackBar(
          context,
          'Unable to generate the PDF report.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _preview(AdminReportAnalytics report) async {
    if (_previewing || _filterLoading) return;
    setState(() => _previewing = true);
    try {
      final pdfBytes = await _buildPdf(report);
      if (!mounted) return;
      await _recordReportAudit('REPORT_VIEWED', report);
      if (!mounted) return;
      setState(() => _previewing = false);
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (dialogContext) => _ReportPreviewDialog(
          report: report,
          reportType: _reportType,
          pdfBytes: pdfBytes,
          pdfPreviewBuilder: widget.pdfPreviewBuilder,
          onPrint: () => _printPdf(report, pdfBytes),
          onDownload: () => _shareOrDownloadPdf(report, pdfBytes),
        ),
      );
    } catch (_) {
      if (mounted) {
        _showReportSnackBar(
          context,
          'Unable to prepare the PDF preview.',
          error: true,
        );
      }
    } finally {
      if (mounted && _previewing) setState(() => _previewing = false);
    }
  }

  Future<void> _showBulkImport() async {
    final imported = await showDialog<int>(
      context: context,
      builder: (_) => _BulkImportDialog(repository: widget.repository),
    );
    if (!mounted || imported == null) return;
    _refresh();
    _showReportSnackBar(context, '$imported walk-in appointments imported.');
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.loading,
    required this.downloading,
    required this.previewing,
    required this.canDownload,
    required this.showImport,
    required this.onDownload,
    required this.onPreview,
    required this.onImport,
  });

  final bool loading;
  final bool downloading;
  final bool previewing;
  final bool canDownload;
  final bool showImport;
  final VoidCallback? onDownload;
  final VoidCallback? onPreview;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final actions = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (showImport)
            OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Bulk import'),
            ),
          OutlinedButton.icon(
            onPressed: previewing ? null : onPreview,
            icon: previewing
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.preview_outlined, size: 18),
            label: Text(previewing ? 'Preparing preview' : 'Preview PDF'),
          ),
          FilledButton.icon(
            onPressed: canDownload && !downloading ? onDownload : null,
            icon: downloading
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: Text(downloading ? 'Preparing PDF' : 'Download PDF'),
          ),
        ],
      );
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Report Generation',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Privacy-preserving insights for app users and counseling appointments.',
            style: TextStyle(color: AdminColors.muted),
          ),
        ],
      );
      if (constraints.maxWidth < 1000) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 16), actions],
        );
      }
      return Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: 20),
          actions,
        ],
      );
    },
  );
}

class _ImportedFilesPanel extends StatefulWidget {
  const _ImportedFilesPanel({required this.repository});

  final AdminPortalRepository repository;

  @override
  State<_ImportedFilesPanel> createState() => _ImportedFilesPanelState();
}

class _ImportedFilesPanelState extends State<_ImportedFilesPanel> {
  late Future<List<ImportedWalkInFile>> _files;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _files = widget.repository.listWalkInImports();
  }

  void _reload() {
    setState(() => _files = widget.repository.listWalkInImports());
  }

  Future<void> _delete(ImportedWalkInFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete imported file?'),
        content: Text(
          'This will permanently remove “${file.fileName}” and its ${file.rowCount} imported appointment${file.rowCount == 1 ? '' : 's'}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AdminColors.danger),
            child: const Text('Delete file'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingId = file.id);
    try {
      await widget.repository.deleteWalkInImport(file.id);
      if (mounted) {
        _showReportSnackBar(context, 'Imported file deleted.');
        _reload();
      }
    } catch (error) {
      if (mounted) {
        _showReportSnackBar(context, _friendlyReportError(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _toggleArchive(ImportedWalkInFile file) async {
    setState(() => _deletingId = file.id);
    try {
      await widget.repository.archiveWalkInImport(
        file.id,
        archived: !file.archived,
      );
      if (mounted) {
        _showReportSnackBar(
          context,
          file.archived ? 'Imported file restored.' : 'Imported file archived.',
        );
        _reload();
      }
    } catch (error) {
      if (mounted) {
        _showReportSnackBar(context, _friendlyReportError(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: _panelDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Imported files',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Review and remove office walk-in imports from your reports.',
                    style: TextStyle(color: AdminColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh imported files',
              onPressed: _deletingId == null ? _reload : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<ImportedWalkInFile>>(
          future: _files,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _ImportedFilesSkeleton();
            }
            if (snapshot.hasError) {
              return Row(
                children: [
                  const Expanded(
                    child: Text(
                      'We could not load imported files.',
                      style: TextStyle(color: AdminColors.danger),
                    ),
                  ),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('Try again'),
                  ),
                ],
              );
            }
            final files = snapshot.data ?? const <ImportedWalkInFile>[];
            if (files.isEmpty) {
              return const Text(
                'No imported files yet. Files imported through Bulk import will appear here.',
                style: TextStyle(color: AdminColors.muted),
              );
            }
            return Column(
              children: files
                  .map(
                    (file) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: file.archived
                            ? AdminColors.surfaceMuted
                            : AdminColors.accentFaint,
                        child: Icon(
                          file.archived
                              ? Icons.archive_outlined
                              : Icons.description_outlined,
                          size: 19,
                        ),
                      ),
                      title: Text(
                        file.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${file.rowCount} appointment${file.rowCount == 1 ? '' : 's'} • ${_importDate(file.importedAt)}${file.archived ? ' • Archived' : ''}',
                      ),
                      trailing: Wrap(
                        spacing: 2,
                        children: [
                          IconButton(
                            tooltip: file.archived
                                ? 'Restore imported file'
                                : 'Archive imported file',
                            onPressed: _deletingId == null
                                ? () => _toggleArchive(file)
                                : null,
                            icon: _deletingId == file.id
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    file.archived
                                        ? Icons.unarchive_outlined
                                        : Icons.archive_outlined,
                                  ),
                          ),
                          IconButton(
                            tooltip: 'Delete imported file',
                            onPressed: _deletingId == null
                                ? () => _delete(file)
                                : null,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    ),
  );
}

class _ImportedFilesSkeleton extends StatelessWidget {
  const _ImportedFilesSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      2,
      (index) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: Color(0xFFE9E9E6)),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBar(width: 220),
                  SizedBox(height: 7),
                  _SkeletonBar(width: 140, height: 10),
                ],
              ),
            ),
            SizedBox(width: 24),
            _SkeletonBar(width: 22, height: 22),
          ],
        ),
      ),
    ),
  );
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, this.height = 14});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFE9E9E6),
      borderRadius: BorderRadius.circular(5),
    ),
  );
}

String _importDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class _BulkImportDialog extends StatefulWidget {
  const _BulkImportDialog({required this.repository});
  final AdminPortalRepository repository;
  @override
  State<_BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends State<_BulkImportDialog> {
  final _name = TextEditingController();
  final _studentId = TextEditingController();
  final _year = TextEditingController();
  final _date = TextEditingController();
  final _rows = <WalkInAppointmentImportRow>[];
  _ImportCourseOption? _selectedCourse;
  String _fileName = 'Manual walk-in entries';
  bool _reading = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _studentId, _year, _date]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import counseling walk-ins'),
    content: SizedBox(
      width: 700,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add office walk-ins manually or import an Excel file. Required columns are Full name, Student ID, Department/Course, and Year Level. Date of log-in is optional.',
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminColors.accentFaint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Excel tips: use the first row as column headers. Accepted header variations include Student ID, Department/Course, Year Level, and Date of login. Save as .xlsx, .xls, or .csv.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _input(_name, 'Full name *', 250),
                _input(_studentId, 'Student ID *', 180),
                _courseDropdown(),
                _yearDropdown(),
                _input(_date, 'Date of log-in (YYYY-MM-DD)', 220),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _reading || _saving ? null : _addManual,
                  icon: const Icon(Icons.add),
                  label: const Text('Add row'),
                ),
                OutlinedButton.icon(
                  onPressed: _reading || _saving ? null : _pickFile,
                  icon: _reading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(
                    _reading ? 'Reading file...' : 'Choose Excel / CSV',
                  ),
                ),
              ],
            ),
            OutlinedButton.icon(
              onPressed: _reading || _saving ? null : downloadImportTemplate,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download template'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AdminColors.danger)),
            ],
            const SizedBox(height: 20),
            Text(
              'Ready to import: ${_rows.length}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_rows.isEmpty)
              const Text(
                'Your imported rows will appear here for review.',
                style: TextStyle(color: AdminColors.muted),
              )
            else
              ..._rows.asMap().entries.map(
                (entry) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 13,
                    child: Text('${entry.key + 1}'),
                  ),
                  title: Text(entry.value.fullName),
                  subtitle: Text(
                    '${entry.value.studentId} / ${entry.value.course} / ${entry.value.department} / ${entry.value.yearLevel}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove row',
                    onPressed: _saving
                        ? null
                        : () => setState(() => _rows.removeAt(entry.key)),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _rows.isEmpty || _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check),
        label: Text(_saving ? 'Importing...' : 'Import ${_rows.length} rows'),
      ),
    ],
  );

  Widget _input(TextEditingController controller, String label, double width) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Widget _courseDropdown() => SizedBox(
    width: 250,
    child: DropdownButtonFormField<_ImportCourseOption>(
      initialValue: _selectedCourse,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Course *'),
      hint: const Text('Select course'),
      items: _importCourseOptions
          .map(
            (option) => DropdownMenuItem(
              value: option,
              child: Text(option.course, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _selectedCourse = value),
    ),
  );

  Widget _yearDropdown() => SizedBox(
    width: 150,
    child: DropdownButtonFormField<String>(
      initialValue: _year.text.isEmpty ? null : _year.text,
      decoration: const InputDecoration(labelText: 'Year level *'),
      hint: const Text('Select year'),
      items: const ['Year 1', 'Year 2', 'Year 3', 'Year 4', 'Year 5']
          .map((year) => DropdownMenuItem(value: year, child: Text(year)))
          .toList(),
      onChanged: (value) => setState(() => _year.text = value ?? ''),
    ),
  );

  void _addManual() {
    final row = _rowFromValues(
      _name.text,
      _studentId.text,
      _selectedCourse?.department ?? '',
      _selectedCourse?.course ?? '',
      _year.text,
      _date.text,
    );
    if (row == null) return;
    setState(() {
      _rows.add(row);
      _error = null;
    });
    for (final controller in [_name, _studentId, _year, _date]) {
      controller.clear();
    }
    setState(() => _selectedCourse = null);
  }

  Future<void> _pickFile() async {
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final file = await pickAdminImportFile();
      if (file == null) return;
      _fileName = file.name;
      final extension = file.extension;
      final parsed = extension == 'csv'
          ? _parseCsv(String.fromCharCodes(file.bytes))
          : _parseExcel(file.bytes);
      if (parsed.isEmpty) {
        throw const FormatException(
          'No valid rows were found. Check the header row and required columns.',
        );
      }
      setState(() => _rows.addAll(parsed));
    } catch (error) {
      setState(
        () => _error = error.toString().replaceFirst('FormatException: ', ''),
      );
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  List<WalkInAppointmentImportRow> _parseExcel(List<int> bytes) {
    final workbook = excel.Excel.decodeBytes(bytes);
    final sheet = workbook.tables.values.firstOrNull;
    if (sheet == null || sheet.rows.isEmpty) return [];
    final headers = sheet.rows.first
        .map((cell) => _header(cell?.value?.toString() ?? ''))
        .toList();
    return sheet.rows
        .skip(1)
        .map(
          (row) => _fromCells(
            headers,
            row.map((cell) => cell?.value?.toString() ?? '').toList(),
          ),
        )
        .whereType<WalkInAppointmentImportRow>()
        .toList();
  }

  List<WalkInAppointmentImportRow> _parseCsv(String input) {
    final lines = input
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];
    final headers = _splitCsv(lines.first).map(_header).toList();
    return lines
        .skip(1)
        .map((line) => _fromCells(headers, _splitCsv(line)))
        .whereType<WalkInAppointmentImportRow>()
        .toList();
  }

  WalkInAppointmentImportRow? _fromCells(
    List<String> headers,
    List<String> cells,
  ) {
    String value(String key) {
      final index = headers.indexOf(key);
      return index >= 0 && index < cells.length ? cells[index].trim() : '';
    }

    final course = _courseFor(value('course'), value('department'));
    if (course == null) return null;
    return _rowFromValues(
      value('name'),
      value('studentid'),
      course.department,
      course.course,
      value('year'),
      value('date'),
    );
  }

  WalkInAppointmentImportRow? _rowFromValues(
    String name,
    String id,
    String department,
    String course,
    String year,
    String date,
  ) {
    if ([
      name,
      id,
      department,
      course,
      year,
    ].any((value) => value.trim().isEmpty)) {
      setState(
        () => _error =
            'Full name, Student ID, Course, and Year Level are required.',
      );
      return null;
    }
    final normalizedYear = _normalizeYear(year);
    if (normalizedYear == null) {
      setState(
        () => _error = 'Choose Year 1, Year 2, Year 3, Year 4, or Year 5.',
      );
      return null;
    }
    final loggedAt = date.trim().isEmpty
        ? null
        : DateTime.tryParse(date.trim());
    if (date.trim().isNotEmpty && loggedAt == null) {
      setState(
        () => _error = 'Use YYYY-MM-DD for the optional date of log-in.',
      );
      return null;
    }
    return WalkInAppointmentImportRow(
      fullName: name.trim(),
      studentId: id.trim(),
      department: department.trim(),
      course: course.trim(),
      yearLevel: normalizedYear,
      loggedAt: loggedAt,
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final imported = await widget.repository.importWalkInAppointments(
        _rows,
        fileName: _fileName,
      );
      if (mounted) Navigator.pop(context, imported);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyReportError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  _ImportCourseOption? _courseFor(String course, String department) {
    final courseKey = _normalizeText(course);
    final departmentKey = _normalizeText(department);
    final match = _importCourseOptions.where((option) {
      final sameCourse = _normalizeText(option.course) == courseKey;
      final sameDepartment =
          departmentKey.isEmpty ||
          _normalizeText(option.department) == departmentKey;
      return sameCourse && sameDepartment;
    }).firstOrNull;
    if (match == null) {
      setState(
        () => _error =
            'Course "$course" is not in the organization course list. Use the downloaded template or update the Organization Directory.',
      );
    }
    return match;
  }
}

class _ImportCourseOption {
  const _ImportCourseOption(this.department, this.course);
  final String department;
  final String course;
}

final _importCourseOptions = [
  for (final group in registrationCollegeCourseOptions)
    for (final course in group.courses)
      _ImportCourseOption(group.department, course),
];

String _normalizeText(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String? _normalizeYear(String value) => switch (_normalizeText(value)) {
  '1' || '1st' || 'year1' || '1styear' => 'Year 1',
  '2' || '2nd' || 'year2' || '2ndyear' => 'Year 2',
  '3' || '3rd' || 'year3' || '3rdyear' => 'Year 3',
  '4' || '4th' || 'year4' || '4thyear' => 'Year 4',
  '5' || '5th' || 'year5' || '5thyear' => 'Year 5',
  _ => null,
};

String _header(String value) {
  final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return switch (normalized) {
    'fullname' || 'name' => 'name',
    'studentid' || 'id' => 'studentid',
    'departmentcourse' => 'course',
    'department' => 'department',
    'course' => 'course',
    'yearlevel' || 'year' => 'year',
    'dateofloginin' ||
    'dateoflogginin' ||
    'dateoflogin' ||
    'dateofloggingin' ||
    'date' ||
    'login' => 'date',
    _ => normalized,
  };
}

List<String> _splitCsv(String line) {
  final values = <String>[];
  var buffer = StringBuffer();
  var quoted = false;
  for (final char in line.split('')) {
    if (char == '"') {
      quoted = !quoted;
      continue;
    }
    if (char == ',' && !quoted) {
      values.add(buffer.toString());
      buffer = StringBuffer();
    } else {
      buffer.write(char);
    }
  }
  values.add(buffer.toString());
  return values;
}

class _ReportToggle extends StatelessWidget {
  const _ReportToggle({required this.value, required this.onChanged});
  final AdminReportType value;
  final ValueChanged<AdminReportType> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 560) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.groups_outlined, size: 17),
              label: const Text('App users'),
              selected: value == AdminReportType.users,
              onSelected: (_) => onChanged(AdminReportType.users),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.calendar_month_outlined, size: 17),
              label: const Text('Counseling appointments'),
              selected: value == AdminReportType.appointments,
              onSelected: (_) => onChanged(AdminReportType.appointments),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.favorite_outline, size: 17),
              label: const Text('Emotional activity'),
              selected: value == AdminReportType.emotionalActivity,
              onSelected: (_) => onChanged(AdminReportType.emotionalActivity),
            ),
          ],
        );
      }
      return SegmentedButton<AdminReportType>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: AdminReportType.users,
            icon: Icon(Icons.groups_outlined),
            label: Text('App users'),
          ),
          ButtonSegment(
            value: AdminReportType.appointments,
            icon: Icon(Icons.calendar_month_outlined),
            label: Text('Counseling appointments'),
          ),
          ButtonSegment(
            value: AdminReportType.emotionalActivity,
            icon: Icon(Icons.favorite_outline),
            label: Text('Emotional activity'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      );
    },
  );
}

class _AcademicYearField extends StatelessWidget {
  const _AcademicYearField({
    this.dropdownKey,
    required this.schoolYear,
    required this.years,
    required this.onChanged,
  });

  final Key? dropdownKey;
  final String schoolYear;
  final List<AcademicYearRecord> years;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = years.isEmpty
        ? [
            AcademicYearRecord(
              schoolYear: schoolYear,
              startDate: '',
              endDate: '',
              status: 'current',
            ),
          ]
        : years;
    final activeYear = options.any((item) => item.schoolYear == schoolYear)
        ? schoolYear
        : options.first.schoolYear;
    return _LabeledControl(
      label: 'Academic year',
      child: DropdownButtonFormField<String>(
        key: dropdownKey ?? ValueKey('yr-$activeYear'),
        initialValue: activeYear,
        isExpanded: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.school_outlined),
        ),
        items: options
            .map(
              (item) => DropdownMenuItem(
                value: item.schoolYear,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        item.schoolYear,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.status == 'current') ...[
                      const SizedBox(width: 8),
                      const _CurrentBadge(),
                    ],
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _ReportingPeriodField extends StatelessWidget {
  const _ReportingPeriodField({
    this.dropdownKey,
    required this.period,
    required this.onPeriodChanged,
    required this.onCustomPeriod,
  });

  final Key? dropdownKey;
  final _ReportPeriod period;
  final ValueChanged<_ReportPeriod> onPeriodChanged;
  final VoidCallback onCustomPeriod;

  @override
  Widget build(BuildContext context) => _LabeledControl(
    label: 'Reporting period',
    child: DropdownButtonFormField<_ReportPeriod>(
      key: dropdownKey ?? ValueKey('period-${period.name}'),
      initialValue: period,
      isExpanded: true,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.date_range_outlined),
      ),
      items: const [
        DropdownMenuItem(
          value: _ReportPeriod.wholeYear,
          child: Text('Whole year'),
        ),
        DropdownMenuItem(
          value: _ReportPeriod.firstSemester,
          child: Text('1st semester'),
        ),
        DropdownMenuItem(
          value: _ReportPeriod.secondSemester,
          child: Text('2nd semester'),
        ),
        DropdownMenuItem(
          value: _ReportPeriod.custom,
          child: Text('Custom dates'),
        ),
      ],
      onChanged: (value) {
        if (value == _ReportPeriod.custom) {
          onCustomPeriod();
        } else if (value != null) {
          onPeriodChanged(value);
        }
      },
    ),
  );
}

class _CollegeDropdownField extends StatelessWidget {
  const _CollegeDropdownField({
    required this.dropdownKey,
    required this.label,
    required this.allLabel,
    required this.department,
    required this.departmentOptions,
    required this.onChanged,
  });

  final Key dropdownKey;
  final String label;
  final String allLabel;
  final String department;
  final List<ReportFilterOption> departmentOptions;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final activeDept = departmentOptions.any((item) => item.key == department)
        ? department
        : 'all';
    return _LabeledControl(
      label: label,
      child: DropdownButtonFormField<String>(
        key: dropdownKey,
        initialValue: activeDept,
        isExpanded: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.account_balance_outlined),
        ),
        items: [
          DropdownMenuItem(
            value: 'all',
            child: Text(allLabel, overflow: TextOverflow.ellipsis),
          ),
          ...departmentOptions.map(
            (item) => DropdownMenuItem(
              value: item.key,
              child: Text(item.label, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _ProgramDropdownField extends StatelessWidget {
  const _ProgramDropdownField({
    required this.dropdownKey,
    required this.program,
    required this.programOptions,
    required this.onChanged,
  });

  final Key dropdownKey;
  final String program;
  final List<ReportFilterOption> programOptions;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final activeProgram = programOptions.any((item) => item.key == program)
        ? program
        : 'all';
    final optionsSignature = programOptions.map((item) => item.key).join('|');
    return _LabeledControl(
      label: 'Program',
      child: KeyedSubtree(
        key: dropdownKey,
        child: DropdownButtonFormField<String>(
          key: ValueKey('program-field-$activeProgram-$optionsSignature'),
          initialValue: activeProgram,
          isExpanded: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.menu_book_outlined),
          ),
          items: [
            const DropdownMenuItem(
              value: 'all',
              child: Text('All programs', overflow: TextOverflow.ellipsis),
            ),
            ...programOptions.map(
              (item) => DropdownMenuItem(
                value: item.key,
                child: Text(item.label, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _CategoryChipsField extends StatelessWidget {
  const _CategoryChipsField({
    required this.label,
    required this.allLabel,
    required this.userCategory,
    required this.userCategories,
    required this.onChanged,
  });

  final String label;
  final String allLabel;
  final String userCategory;
  final List<ReportFilterOption> userCategories;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => _LabeledControl(
    label: label,
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: Text(allLabel),
          selected: userCategory == 'all',
          onSelected: (_) => onChanged('all'),
        ),
        for (final category in userCategories)
          ChoiceChip(
            label: Text(category.label),
            selected: userCategory == category.key,
            onSelected: (_) => onChanged(category.key),
          ),
      ],
    ),
  );
}

class _AdminReportControls extends StatelessWidget {
  const _AdminReportControls({
    required this.schoolYear,
    required this.years,
    required this.period,
    required this.report,
    required this.chartType,
    required this.dimension,
    required this.userCategory,
    required this.userCategories,
    required this.department,
    required this.departmentOptions,
    required this.program,
    required this.programOptions,
    required this.onYearChanged,
    required this.onPeriodChanged,
    required this.onCustomPeriod,
    required this.onUserCategoryChanged,
    required this.onDepartmentChanged,
    required this.onProgramChanged,
    required this.onDimensionChanged,
    required this.onChartChanged,
  });

  final String schoolYear;
  final List<AcademicYearRecord> years;
  final _ReportPeriod period;
  final AdminReportAnalytics report;
  final ReportChartType chartType;
  final AppointmentReportDimension dimension;
  final String userCategory;
  final List<ReportFilterOption> userCategories;
  final String department;
  final List<ReportFilterOption> departmentOptions;
  final String program;
  final List<ReportFilterOption> programOptions;
  final ValueChanged<String> onYearChanged;
  final ValueChanged<_ReportPeriod> onPeriodChanged;
  final VoidCallback onCustomPeriod;
  final ValueChanged<String> onUserCategoryChanged;
  final ValueChanged<String> onDepartmentChanged;
  final ValueChanged<String> onProgramChanged;
  final ValueChanged<AppointmentReportDimension> onDimensionChanged;
  final ValueChanged<ReportChartType> onChartChanged;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
    decoration: _panelDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'REPORT CONTROLS',
          style: TextStyle(
            color: AdminColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 700;
            final width = twoColumns
                ? (constraints.maxWidth - 14) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: width,
                  child: _AcademicYearField(
                    schoolYear: schoolYear,
                    years: years,
                    onChanged: onYearChanged,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ReportingPeriodField(
                    period: period,
                    onPeriodChanged: onPeriodChanged,
                    onCustomPeriod: onCustomPeriod,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _CollegeDropdownField(
                    dropdownKey: const ValueKey('appt-dept-dropdown'),
                    label: 'Department scope',
                    allLabel: 'All departments',
                    department: department,
                    departmentOptions: departmentOptions,
                    onChanged: onDepartmentChanged,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ProgramDropdownField(
                    dropdownKey: const ValueKey('appt-program-dropdown'),
                    program: program,
                    programOptions: programOptions,
                    onChanged: onProgramChanged,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _CategoryChipsField(
              label: 'Population category',
              allLabel: 'All',
              userCategory: userCategory,
              userCategories: userCategories,
              onChanged: onUserCategoryChanged,
            ),
            _groupControl(),
            _visualControl(),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.info_outline, size: 15, color: AdminColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Percentages are calculated using the population snapshot for ${report.population.schoolYear}.',
                style: const TextStyle(color: AdminColors.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _groupControl() => _LabeledControl(
    label: 'Group by',
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<AppointmentReportDimension>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: AppointmentReportDimension.department,
            label: Text('Department'),
          ),
          ButtonSegment(
            value: AppointmentReportDimension.course,
            label: Text('Course'),
          ),
          ButtonSegment(
            value: AppointmentReportDimension.yearLevel,
            label: Text('Year level'),
          ),
        ],
        selected: {dimension},
        onSelectionChanged: (values) => onDimensionChanged(values.first),
      ),
    ),
  );

  Widget _visualControl() => _LabeledControl(
    label: 'Visualization',
    child: SegmentedButton<ReportChartType>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: ReportChartType.bar,
          icon: Icon(Icons.bar_chart, size: 18),
          label: Text('Bar'),
        ),
        ButtonSegment(
          value: ReportChartType.pie,
          icon: Icon(Icons.pie_chart_outline, size: 18),
          label: Text('Pie'),
        ),
      ],
      selected: {chartType},
      onSelectionChanged: (values) => onChartChanged(values.first),
    ),
  );
}

class _CurrentBadge extends StatelessWidget {
  const _CurrentBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AdminColors.accentSoft,
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Text(
      'Current',
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
    ),
  );
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.schoolYear,
    required this.years,
    required this.period,
    required this.reportType,
    required this.chartType,
    required this.dimension,
    required this.userCategory,
    required this.userCategories,
    required this.appointmentDepartment,
    required this.departmentOptions,
    required this.program,
    required this.programOptions,
    required this.onYearChanged,
    required this.onPeriodChanged,
    required this.onCustomPeriod,
    required this.onChartChanged,
    required this.onDimensionChanged,
    required this.onUserCategoryChanged,
    required this.onDepartmentChanged,
    required this.onProgramChanged,
  });

  final String schoolYear;
  final List<AcademicYearRecord> years;
  final _ReportPeriod period;
  final AdminReportType reportType;
  final ReportChartType chartType;
  final AppointmentReportDimension dimension;
  final String userCategory;
  final List<ReportFilterOption> userCategories;
  final String appointmentDepartment;
  final List<ReportFilterOption> departmentOptions;
  final String program;
  final List<ReportFilterOption> programOptions;
  final ValueChanged<String> onYearChanged;
  final ValueChanged<_ReportPeriod> onPeriodChanged;
  final VoidCallback onCustomPeriod;
  final ValueChanged<ReportChartType> onChartChanged;
  final ValueChanged<AppointmentReportDimension> onDimensionChanged;
  final ValueChanged<String> onUserCategoryChanged;
  final ValueChanged<String> onDepartmentChanged;
  final ValueChanged<String> onProgramChanged;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: _panelDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 700;
            final width = twoColumns
                ? (constraints.maxWidth - 14) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: width,
                  child: _AcademicYearField(
                    dropdownKey: const ValueKey('users-yr-dropdown'),
                    schoolYear: schoolYear,
                    years: years,
                    onChanged: onYearChanged,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ReportingPeriodField(
                    dropdownKey: const ValueKey('users-period-dropdown'),
                    period: period,
                    onPeriodChanged: onPeriodChanged,
                    onCustomPeriod: onCustomPeriod,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _CollegeDropdownField(
                    dropdownKey: const ValueKey('users-dept-dropdown'),
                    label: 'College / department',
                    allLabel: 'All colleges & departments',
                    department: appointmentDepartment,
                    departmentOptions: departmentOptions,
                    onChanged: onDepartmentChanged,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ProgramDropdownField(
                    dropdownKey: const ValueKey('users-program-dropdown'),
                    program: program,
                    programOptions: programOptions,
                    onChanged: onProgramChanged,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 30,
          runSpacing: 18,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _CategoryChipsField(
              label: 'USER CATEGORY',
              allLabel: 'Overall',
              userCategory: userCategory,
              userCategories: userCategories,
              onChanged: onUserCategoryChanged,
            ),
            _LabeledControl(
              label: 'CHART TYPE',
              child: SegmentedButton<ReportChartType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ReportChartType.pie,
                    icon: Icon(Icons.pie_chart_outline, size: 18),
                    label: Text('Pie'),
                  ),
                  ButtonSegment(
                    value: ReportChartType.bar,
                    icon: Icon(Icons.bar_chart, size: 18),
                    label: Text('Bar'),
                  ),
                ],
                selected: {chartType},
                onSelectionChanged: (values) => onChartChanged(values.first),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: AdminColors.muted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: .9,
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );
}

class _UserReport extends StatelessWidget {
  const _UserReport({
    super.key,
    required this.report,
    required this.chartType,
    required this.categoryKey,
  });
  final AdminReportAnalytics report;
  final ReportChartType chartType;
  final String categoryKey;

  @override
  Widget build(BuildContext context) {
    final selected = report.userCategories
        .where((item) => item.key == categoryKey)
        .firstOrNull;
    final active = selected?.activePercentage ?? report.overallActivePercentage;
    final data = [
      ReportPercentageItem(key: 'active', label: 'Active', percentage: active),
      ReportPercentageItem(
        key: 'inactive',
        label: 'No recent activity',
        percentage: 100 - active,
      ),
    ];
    return Column(
      children: [
        _SummaryCards(
          cards: [
            _SummaryValue(
              label: 'Active app users',
              value: _formatPercent(active),
              note: 'Last ${report.activeWindowDays} days',
              icon: Icons.bolt_outlined,
            ),
            _SummaryValue(
              label: 'Selected population',
              value: selected == null
                  ? '100%'
                  : _formatPercent(selected.populationPercentage),
              note: report.userScopeLabel,
              icon: Icons.people_outline,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _ChartPanel(
          title: '${selected?.label ?? 'Overall app users'} activity',
          subtitle: 'Percentages only | portal accounts excluded',
          data: data,
          chartType: chartType,
        ),
        const SizedBox(height: 18),
        _PercentageTable(
          title: categoryKey == 'all'
              ? 'App users per category'
              : 'Selected app-user category only',
          headers: const ['Category', 'Population share', 'Active rate'],
          rows: report.userCategories
              .map(
                (item) => [
                  item.label,
                  _formatPercent(item.populationPercentage),
                  _formatPercent(item.activePercentage),
                ],
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _AppointmentReport extends StatelessWidget {
  const _AppointmentReport({
    super.key,
    required this.report,
    required this.chartType,
    required this.dimension,
  });
  final AdminReportAnalytics report;
  final ReportChartType chartType;
  final AppointmentReportDimension dimension;

  @override
  Widget build(BuildContext context) {
    final items = report.appointmentsFor(dimension);
    final label = _dimensionLabel(dimension);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Appointment results · ${report.population.schoolYear}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          '${report.dateRange.label} · ${report.appointmentDepartmentScopeLabel}',
          style: const TextStyle(color: AdminColors.muted),
        ),
        if (!report.population.configured) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: _panelDecoration,
            child: const Text(
              'Complete and save the student population in Report setup below to calculate population-based percentages. Appointment counts remain available.',
              style: TextStyle(color: AdminColors.muted),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _SummaryCards(
          cards: [
            _SummaryValue(
              label: 'Total appointments',
              value: '${report.totalAppointments}',
              note: 'Academic year ${report.population.schoolYear}',
              icon: Icons.calendar_month_outlined,
            ),
            _SummaryValue(
              label: 'Unique students served',
              value: '${report.uniqueStudentsServed}',
              note: 'Students with at least one appointment',
              icon: Icons.people_outline,
            ),
            _SummaryValue(
              label: 'Counseling reach',
              value: report.population.configured
                  ? _formatPercent(report.counselingReach)
                  : 'Not available',
              note: 'Unique students / population',
              icon: Icons.groups_outlined,
            ),
            _SummaryValue(
              label: 'Completion rate',
              value: _formatPercent(report.completionRate),
              note: 'Completed / scheduled',
              icon: Icons.task_alt_outlined,
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text('Service details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        _SummaryCards(
          cards: [
            _SummaryValue(
              label: 'Appointment rate',
              value: report.population.configured
                  ? _formatPercent(report.appointmentRate)
                  : 'Not available',
              note: 'Appointments / population',
              icon: Icons.percent_outlined,
            ),
            _SummaryValue(
              label: 'Waiting time',
              value: report.waitingTimeDays == null
                  ? 'No data'
                  : '${report.waitingTimeDays!.toStringAsFixed(1)} days',
              note: 'Request to scheduled appointment',
              icon: Icons.hourglass_bottom_outlined,
            ),
            _SummaryValue(
              label: 'Rescheduled',
              value: '${report.rescheduledAppointments}',
              note: 'Schedule adjustments',
              icon: Icons.event_repeat_outlined,
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (!report.population.configured)
          const SizedBox.shrink()
        else if (report.uniqueStudentsServed < 5)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: _panelDecoration,
            child: const Text(
              'Distribution details are hidden because this report contains fewer than 5 unique students. Aggregate totals remain available.',
              style: TextStyle(color: AdminColors.muted),
            ),
          )
        else
          _ChartPanel(
            title: 'Appointments by $label',
            subtitle:
                '${report.appointmentDepartmentScopeLabel} only | share within selected scope',
            data: items,
            chartType: items.length > 6 ? ReportChartType.bar : chartType,
          ),
        const SizedBox(height: 18),
        if (report.population.configured && report.uniqueStudentsServed >= 5)
          _PercentageTable(
            title:
                '$label distribution - ${report.appointmentDepartmentScopeLabel}',
            headers: const ['Category', 'Appointment share'],
            rows: items
                .map((item) => [item.label, _formatPercent(item.percentage)])
                .toList(growable: false),
          ),
        if (report.comparison != null) ...[
          const SizedBox(height: 18),
          _ComparisonPanel(report: report),
        ],
        if (report.trends.length > 1) ...[
          const SizedBox(height: 18),
          _TrendPanel(report: report),
        ],
      ],
    );
  }
}

class _ComparisonPanel extends StatelessWidget {
  const _ComparisonPanel({required this.report});
  final AdminReportAnalytics report;
  String change(num current, num previous, {bool points = false}) {
    if (previous == 0) return current == 0 ? '—' : 'New';
    final value = points
        ? current - previous
        : (current - previous) / previous * 100;
    return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}${points ? ' pp' : '%'}';
  }

  @override
  Widget build(BuildContext context) {
    final previous = report.comparison!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compared with ${previous.schoolYear}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 30,
            runSpacing: 12,
            children: [
              _Change(
                label: 'Appointments',
                value: change(
                  report.totalAppointments,
                  previous.totalAppointments,
                ),
              ),
              _Change(
                label: 'Students served',
                value: change(
                  report.uniqueStudentsServed,
                  previous.uniqueStudentsServed,
                ),
              ),
              _Change(
                label: 'Reach',
                value: change(
                  report.counselingReach,
                  previous.counselingReach,
                  points: true,
                ),
              ),
              _Change(
                label: 'Completion',
                value: change(
                  report.completionRate,
                  previous.completionRate,
                  points: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Change extends StatelessWidget {
  const _Change({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AdminColors.muted)),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
    ],
  );
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.report});
  final AdminReportAnalytics report;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _panelDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Trend across academic years',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        ...report.trends.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 95, child: Text(item.schoolYear)),
                Expanded(
                  child: LinearProgressIndicator(
                    value:
                        report.trends
                                .map((e) => e.totalAppointments)
                                .reduce(math.max) ==
                            0
                        ? 0
                        : item.totalAppointments /
                              report.trends
                                  .map((e) => e.totalAppointments)
                                  .reduce(math.max),
                    minHeight: 10,
                  ),
                ),
                const SizedBox(width: 10),
                Text('${item.totalAppointments}'),
              ],
            ),
          ),
        ),
        const Text(
          'Total appointments by year. Use the comparison cards for reach and completion changes.',
          style: TextStyle(color: AdminColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class _PopulationSetup extends StatefulWidget {
  const _PopulationSetup({
    required this.repository,
    required this.config,
    required this.onSaved,
    required this.onYearChanged,
  });

  final AdminPortalRepository repository;
  final CounselingPopulationConfig config;
  final ValueChanged<CounselingPopulationConfig> onSaved;
  final ValueChanged<String> onYearChanged;

  @override
  State<_PopulationSetup> createState() => _PopulationSetupState();
}

class _PopulationSetupState extends State<_PopulationSetup> {
  late final TextEditingController _schoolYear;
  late Map<String, TextEditingController> _fields;
  final Map<String, Map<String, String>> _draftsByYear = {};
  bool _saving = false;
  // Keep the report page compact by default; admins can expand the panel when
  // they need to edit or review department populations.
  bool _expanded = false;
  bool _editingPopulation = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _schoolYear = TextEditingController(
      text: widget.config.schoolYear.isEmpty
          ? _currentSchoolYear()
          : widget.config.schoolYear,
    );
    final departments = widget.config.departments.isEmpty
        ? [
            for (final group in registrationCollegeCourseOptions)
              group.department,
          ]
        : widget.config.departments;
    _fields = {
      for (final department in departments)
        department: TextEditingController(
          text: '${widget.config.populations[department] ?? ''}',
        ),
    };
  }

  @override
  void didUpdateWidget(covariant _PopulationSetup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.schoolYear == widget.config.schoolYear) return;
    final hasUnsavedChanges = _fields.entries.any(
      (entry) =>
          entry.value.text !=
          '${oldWidget.config.populations[entry.key] ?? ''}',
    );
    if (hasUnsavedChanges) {
      _draftsByYear[oldWidget.config.schoolYear] = {
        for (final entry in _fields.entries) entry.key: entry.value.text,
      };
    } else {
      _draftsByYear.remove(oldWidget.config.schoolYear);
    }
    _schoolYear.text = widget.config.schoolYear;
    for (final field in _fields.values) {
      field.dispose();
    }
    final departments = widget.config.departments.isEmpty
        ? [
            for (final group in registrationCollegeCourseOptions)
              group.department,
          ]
        : widget.config.departments;
    final draft = _draftsByYear[widget.config.schoolYear];
    _fields = {
      for (final department in departments)
        department: TextEditingController(
          text:
              draft?[department] ??
              '${widget.config.populations[department] ?? ''}',
        ),
    };
    _editingPopulation = draft != null && widget.config.configured;
    _error = null;
  }

  @override
  void dispose() {
    _schoolYear.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: _panelDecoration,
    child: Material(
      type: MaterialType.transparency,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (expanded) =>
              setState(() => _expanded = expanded),
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          title: Text(
            'Student population setup',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          subtitle: Text(
            widget.config.status == 'closed'
                ? 'Locked for ${widget.config.schoolYear}. Historical reports are protected.'
                : 'Set department populations for ${widget.config.schoolYear}.',
            style: const TextStyle(color: AdminColors.muted),
          ),
          children: [
            const Divider(height: 18),
            const Text(
              'Enter the current student population for every department. Appointment percentages use these values as their denominators. Save a new school year when enrollment changes.',
              style: TextStyle(color: AdminColors.muted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _schoolYear,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'School year',
                  hintText: 'YYYY-YYYY',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in _fields.entries)
                  SizedBox(
                    width: 300,
                    child: TextField(
                      controller: entry.value,
                      readOnly:
                          widget.config.status == 'closed' ||
                          (widget.config.configured && !_editingPopulation),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: entry.key,
                        suffixText: 'students',
                      ),
                    ),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AdminColors.danger)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving || widget.config.status == 'closed'
                  ? null
                  : widget.config.configured && !_editingPopulation
                  ? _confirmEditPopulation
                  : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                widget.config.status == 'closed'
                    ? 'Population locked'
                    : widget.config.configured && !_editingPopulation
                    ? 'Edit population'
                    : _saving
                    ? 'Saving...'
                    : 'Save population',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _save() async {
    final schoolYear = _schoolYear.text.trim();
    final populations = <String, int>{};
    for (final entry in _fields.entries) {
      final value = int.tryParse(entry.value.text.trim());
      if (value == null || value < 1) {
        setState(
          () =>
              _error = 'Enter a whole-number population for every department.',
        );
        return;
      }
      populations[entry.key] = value;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.saveCounselingPopulation(
        schoolYear: schoolYear,
        populations: populations,
      );
      if (mounted) {
        setState(() {
          _editingPopulation = false;
          _draftsByYear.remove(schoolYear);
        });
        widget.onSaved(saved);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyReportError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmEditPopulation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit student population?'),
        content: const Text(
          'Changing these values changes the population denominator and may update appointment percentages for this academic year. Review the figures carefully before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue editing'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _editingPopulation = true;
        _error = null;
      });
    }
  }
}

String _currentSchoolYear() {
  final now = DateTime.now();
  final start = now.month >= 6 ? now.year : now.year - 1;
  return '$start-${start + 1}';
}

String _friendlyReportError(Object error) {
  final raw = error.toString().toLowerCase();
  if (raw.contains('already-exists')) {
    return 'That academic year already exists. Choose it from the list or enter a different year.';
  }
  if (raw.contains('failed-precondition')) {
    return 'This action is not available yet. Check that all required population values are saved.';
  }
  if (raw.contains('permission-denied')) {
    return 'You do not have permission to change academic-year settings.';
  }
  final message = FirebaseErrorMessage.describe(
    error,
    fallback: 'We could not complete that action. Please try again.',
  ).trim();
  // Do not allow provider exception formatting to reach the interface.
  if (message.isEmpty ||
      message.contains('firebase_functions/') ||
      message.contains('firebase_auth/') ||
      message.startsWith('[')) {
    return 'We could not complete that action. Please try again.';
  }
  return message;
}

void _showReportSnackBar(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: error ? AdminColors.danger : const Color(0xFF263238),
        duration: const Duration(seconds: 4),
      ),
    );
}

class _SummaryValue {
  const _SummaryValue({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
  });
  final String label;
  final String value;
  final String note;
  final IconData icon;
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.cards});
  final List<_SummaryValue> cards;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 660
          ? (constraints.maxWidth - 14) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final card in cards)
            Container(
              width: width,
              padding: const EdgeInsets.all(20),
              decoration: _panelDecoration,
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AdminColors.accentFaint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(card.icon, color: AdminColors.accentStrong),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.label,
                          style: const TextStyle(
                            color: AdminColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          card.value,
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          card.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AdminColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class _ChartPanel extends StatelessWidget {
  const _ChartPanel({
    required this.title,
    required this.subtitle,
    required this.data,
    required this.chartType,
  });
  final String title;
  final String subtitle;
  final List<ReportPercentageItem> data;
  final ReportChartType chartType;

  @override
  Widget build(BuildContext context) {
    final chartData = _compact(data);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: AdminColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 22),
          if (chartData.isEmpty)
            const SizedBox(
              height: 220,
              child: Center(
                child: Text('No reportable appointment data is available.'),
              ),
            )
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: chartType == ReportChartType.pie
                  ? _PieChart(key: const ValueKey('pie'), data: chartData)
                  : _BarChart(key: const ValueKey('bar'), data: chartData),
            ),
        ],
      ),
    );
  }
}

const _chartColors = <Color>[
  AdminColors.accentStrong,
  AdminColors.success,
  Color(0xFF6D5E9C),
  Color(0xFF4F7799),
  Color(0xFFB7654D),
  Color(0xFF7D7D75),
  Color(0xFF527D7A),
  Color(0xFF967345),
];

class _PieChart extends StatelessWidget {
  const _PieChart({super.key, required this.data});
  final List<ReportPercentageItem> data;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final pie = SizedBox(
        width: 230,
        height: 230,
        child: CustomPaint(painter: _PieChartPainter(data)),
      );
      final legend = _ChartLegend(data: data);
      if (constraints.maxWidth < 620) {
        return Column(children: [pie, const SizedBox(height: 18), legend]);
      }
      return Row(
        children: [
          Expanded(child: Center(child: pie)),
          const SizedBox(width: 24),
          Expanded(child: legend),
        ],
      );
    },
  );
}

class _PieChartPainter extends CustomPainter {
  const _PieChartPainter(this.data);
  final List<ReportPercentageItem> data;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 46;
    for (var index = 0; index < data.length; index++) {
      final sweep = math.pi * 2 * (data[index].percentage / 100);
      paint.color = _chartColors[index % _chartColors.length];
      canvas.drawArc(rect.deflate(30), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.data != data;
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.data});
  final List<ReportPercentageItem> data;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var index = 0; index < data.length; index++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _chartColors[index % _chartColors.length],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(data[index].label, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 10),
              Text(
                _formatPercent(data[index].percentage),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
    ],
  );
}

class _BarChart extends StatelessWidget {
  const _BarChart({super.key, required this.data});
  final List<ReportPercentageItem> data;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < data.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data[index].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    _formatPercent(data[index].percentage),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: data[index].percentage / 100,
                  minHeight: 13,
                  color: _chartColors[index % _chartColors.length],
                  backgroundColor: AdminColors.surfaceMuted,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _PercentageTable extends StatelessWidget {
  const _PercentageTable({
    required this.title,
    required this.headers,
    required this.rows,
  });
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: _panelDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const Text(
            'No reportable data is available.',
            style: TextStyle(color: AdminColors.muted),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: headers
                  .map((header) => DataColumn(label: Text(header)))
                  .toList(growable: false),
              rows: rows
                  .map(
                    (row) => DataRow(
                      cells: row
                          .map((value) => DataCell(Text(value)))
                          .toList(growable: false),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
      ],
    ),
  );
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice({required this.generatedAt});
  final DateTime generatedAt;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AdminColors.accentFaint,
      border: Border.all(color: AdminColors.accentSoft),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.shield_outlined,
          size: 19,
          color: AdminColors.accentStrong,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Confidential aggregate view • Percentages only • No personal identifiers or portal accounts • Generated ${_formatDateTime(generatedAt.toLocal())}',
            style: const TextStyle(color: AdminColors.muted, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _EmotionalReportControls extends StatelessWidget {
  const _EmotionalReportControls({
    required this.schoolYear,
    required this.years,
    required this.period,
    required this.report,
    required this.chartType,
    required this.source,
    required this.userCategory,
    required this.userCategories,
    required this.department,
    required this.departmentOptions,
    required this.program,
    required this.programOptions,
    required this.onYearChanged,
    required this.onPeriodChanged,
    required this.onCustomPeriod,
    required this.onSourceChanged,
    required this.onUserCategoryChanged,
    required this.onDepartmentChanged,
    required this.onProgramChanged,
    required this.onChartChanged,
  });

  final String schoolYear;
  final List<AcademicYearRecord> years;
  final _ReportPeriod period;
  final AdminReportAnalytics report;
  final ReportChartType chartType;
  final EmotionalActivitySource source;
  final String userCategory;
  final List<ReportFilterOption> userCategories;
  final String department;
  final List<ReportFilterOption> departmentOptions;
  final String program;
  final List<ReportFilterOption> programOptions;
  final ValueChanged<String> onYearChanged;
  final ValueChanged<_ReportPeriod> onPeriodChanged;
  final VoidCallback onCustomPeriod;
  final ValueChanged<EmotionalActivitySource> onSourceChanged;
  final ValueChanged<String> onUserCategoryChanged;
  final ValueChanged<String> onDepartmentChanged;
  final ValueChanged<String> onProgramChanged;
  final ValueChanged<ReportChartType> onChartChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: _panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'EMOTIONAL ACTIVITY FILTERS',
            style: TextStyle(
              color: AdminColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 700;
              final fieldWidth = twoColumns
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: _AcademicYearField(
                      dropdownKey: ValueKey('emo-yr-$schoolYear'),
                      schoolYear: schoolYear,
                      years: years,
                      onChanged: onYearChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _ReportingPeriodField(
                      dropdownKey: ValueKey('emo-period-${period.name}'),
                      period: period,
                      onPeriodChanged: onPeriodChanged,
                      onCustomPeriod: onCustomPeriod,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _CollegeDropdownField(
                      dropdownKey: const ValueKey('emo-dept-dropdown'),
                      label: 'College / department',
                      allLabel: 'All colleges & departments',
                      department: department,
                      departmentOptions: departmentOptions,
                      onChanged: onDepartmentChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _ProgramDropdownField(
                      dropdownKey: const ValueKey('emo-program-dropdown'),
                      program: program,
                      programOptions: programOptions,
                      onChanged: onProgramChanged,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              _LabeledControl(
                label: 'Approved data source',
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<EmotionalActivitySource>(
                    showSelectedIcon: false,
                    segments: [
                      for (final option in EmotionalActivitySource.values)
                        ButtonSegment(value: option, label: Text(option.label)),
                    ],
                    selected: {source},
                    onSelectionChanged: (values) =>
                        onSourceChanged(values.first),
                  ),
                ),
              ),
              _CategoryChipsField(
                label: 'Population category',
                allLabel: 'All',
                userCategory: userCategory,
                userCategories: userCategories,
                onChanged: onUserCategoryChanged,
              ),
              _LabeledControl(
                label: 'Visualization',
                child: SegmentedButton<ReportChartType>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ReportChartType.bar,
                      icon: Icon(Icons.bar_chart, size: 18),
                      label: Text('Bar'),
                    ),
                    ButtonSegment(
                      value: ReportChartType.pie,
                      icon: Icon(Icons.pie_chart_outline, size: 18),
                      label: Text('Pie'),
                    ),
                  ],
                  selected: {chartType},
                  onSelectionChanged: (values) => onChartChanged(values.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.privacy_tip_outlined,
                size: 15,
                color: AdminColors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${report.emotionalActivity.departmentCoverageNote} Small cohorts (n < ${report.emotionalActivity.suppressionThreshold}) are suppressed; journal notes and photos are excluded.',
                  style: const TextStyle(
                    color: AdminColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmotionalActivityReportView extends StatelessWidget {
  const _EmotionalActivityReportView({
    super.key,
    required this.report,
    required this.chartType,
  });

  final AdminReportAnalytics report;
  final ReportChartType chartType;

  String _bucketValue(
    EmotionalActivityBucket bucket,
    int suppressionThreshold,
  ) => bucket.suppressed || bucket.percentage == null
      ? 'Suppressed (n < $suppressionThreshold)'
      : _formatPercent(bucket.percentage!);

  @override
  Widget build(BuildContext context) {
    final emotional = report.emotionalActivity;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Emotional activity results · ${report.population.schoolYear}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          '${emotional.dateRangeLabel} · ${emotional.sourceScopeLabel} · ${report.userScopeLabel} · ${report.appointmentDepartmentScopeLabel}',
          style: const TextStyle(color: AdminColors.muted),
        ),
      ],
    );

    if (emotional.suppressed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: _panelDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: AdminColors.accentStrong,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Privacy protection active',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  emotional.suppressionReason ??
                      'Suppressed to protect privacy: fewer than ${emotional.suppressionThreshold} unique participants matched the active filters.',
                  style: const TextStyle(color: AdminColors.muted),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (emotional.isEmpty || !emotional.isReady) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: _panelDecoration,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No emotional activity data available for the selected filters.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 6),
                Text(
                  'Try broadening the academic year, reporting period, college, or approved data source.',
                  style: TextStyle(color: AdminColors.muted),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final chartItems = emotional.valenceBreakdown
        .where((item) => !item.suppressed && item.percentage != null)
        .map(
          (item) => ReportPercentageItem(
            key: item.key,
            label: item.label,
            percentage: item.percentage!,
          ),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 14),
        _SummaryCards(
          cards: [
            _SummaryValue(
              label: 'Population participation',
              value: emotional.participationRate != null
                  ? _formatPercent(emotional.participationRate!)
                  : emotional.appUserCohortShare != null
                  ? _formatPercent(emotional.appUserCohortShare!)
                  : 'Not available',
              note: emotional.participationRate != null
                  ? 'Unique participants / ${report.population.schoolYear} population'
                  : 'Unique participants / active cohort',
              icon: Icons.groups_outlined,
            ),
            _SummaryValue(
              label: 'Primary emotional pattern',
              value:
                  emotional.dominantValenceLabel ??
                  'Suppressed (n < ${emotional.suppressionThreshold})',
              note: emotional.hasMixedCategories
                  ? 'Includes mixed user categories'
                  : report.userScopeLabel,
              icon: Icons.favorite_outline,
            ),
            _SummaryValue(
              label: 'Mood vs assessments mix',
              value:
                  emotional.moodCheckInShare != null &&
                      emotional.assessmentShare != null
                  ? '${_formatPercent(emotional.moodCheckInShare!)} / ${_formatPercent(emotional.assessmentShare!)}'
                  : emotional.sourceScopeLabel,
              note:
                  emotional.moodCheckInShare != null &&
                      emotional.assessmentShare != null
                  ? 'Mood check-ins / verified assessments'
                  : 'Source breakdown gated at n >= ${emotional.suppressionThreshold}',
              icon: Icons.pie_chart_outline,
            ),
            _SummaryValue(
              label: 'Privacy guard',
              value: 'n >= ${emotional.suppressionThreshold}',
              note: 'Small groups & raw text/images omitted',
              icon: Icons.shield_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (chartItems.isNotEmpty)
          _ChartPanel(
            title: 'Emotional pattern distribution',
            subtitle:
                'Unsuppressed aggregate percentages only · small sub-cells marked as suppressed',
            data: chartItems,
            chartType: chartType,
          ),
        if (chartItems.isNotEmpty) const SizedBox(height: 18),
        _PercentageTable(
          title: 'Emotional valence summary',
          headers: const ['Emotional pattern', 'Share'],
          rows: emotional.valenceBreakdown
              .map(
                (item) => [
                  item.label,
                  _bucketValue(item, emotional.suppressionThreshold),
                ],
              )
              .toList(growable: false),
        ),
        if (emotional.moodBreakdown.isNotEmpty) ...[
          const SizedBox(height: 18),
          _PercentageTable(
            title: 'Mood check-in breakdown',
            headers: const ['Mood state', 'Share'],
            rows: emotional.moodBreakdown
                .map(
                  (item) => [
                    item.label,
                    _bucketValue(item, emotional.suppressionThreshold),
                  ],
                )
                .toList(growable: false),
          ),
        ],
        if (emotional.assessmentBreakdown.isNotEmpty) ...[
          const SizedBox(height: 18),
          _PercentageTable(
            title: 'Well-being assessment breakdown',
            headers: const ['Assessment pattern', 'Share'],
            rows: emotional.assessmentBreakdown
                .map(
                  (item) => [
                    item.label,
                    _bucketValue(item, emotional.suppressionThreshold),
                  ],
                )
                .toList(growable: false),
          ),
        ],
        if (emotional.periodTrends.isNotEmpty) ...[
          const SizedBox(height: 18),
          _PercentageTable(
            title: 'Monthly emotional activity trend',
            headers: const ['Period', 'Share of activity'],
            rows: emotional.periodTrends
                .map(
                  (item) => [
                    item.label,
                    _bucketValue(item, emotional.suppressionThreshold),
                  ],
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();
  @override
  Widget build(BuildContext context) => Container(
    height: 320,
    width: double.infinity,
    decoration: _panelDecoration,
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _ReportSkeleton extends StatelessWidget {
  const _ReportSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: _panelDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SkeletonBlock(width: 180, height: 24),
            const Spacer(),
            _SkeletonBlock(width: 96, height: 24),
          ],
        ),
        const SizedBox(height: 18),
        _SkeletonBlock(width: double.infinity, height: 220),
        const SizedBox(height: 18),
        _SkeletonBlock(width: 220, height: 20),
        const SizedBox(height: 12),
        for (var index = 0; index < 4; index++) ...[
          _SkeletonBlock(width: double.infinity, height: 16),
          const SizedBox(height: 10),
        ],
      ],
    ),
  );
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFE7E5DF),
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.onRetry, this.onResetFilters});
  final VoidCallback onRetry;
  final VoidCallback? onResetFilters;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: _panelDecoration,
    child: Column(
      children: [
        const Icon(
          Icons.cloud_off_outlined,
          size: 38,
          color: AdminColors.muted,
        ),
        const SizedBox(height: 12),
        const Text(
          'The report could not be loaded.',
          style: TextStyle(fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 5),
        const Text(
          'Check your filters, access scope, or report function deployment, then try again.',
          style: TextStyle(color: AdminColors.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            if (onResetFilters != null)
              FilledButton.tonal(
                onPressed: onResetFilters,
                child: const Text('Reset filters'),
              ),
          ],
        ),
      ],
    ),
  );
}

class _ReportPreviewDialog extends StatefulWidget {
  const _ReportPreviewDialog({
    required this.report,
    required this.reportType,
    required this.pdfBytes,
    required this.onPrint,
    required this.onDownload,
    this.pdfPreviewBuilder,
  });

  final AdminReportAnalytics report;
  final AdminReportType reportType;
  final Uint8List pdfBytes;
  final Future<void> Function() onPrint;
  final Future<void> Function() onDownload;
  final Widget Function(BuildContext context, Uint8List bytes)?
  pdfPreviewBuilder;

  @override
  State<_ReportPreviewDialog> createState() => _ReportPreviewDialogState();
}

class _ReportPreviewDialogState extends State<_ReportPreviewDialog> {
  bool _printing = false;
  bool _downloading = false;

  Future<void> _handlePrint() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await widget.onPrint();
    } catch (_) {
      if (mounted) {
        _showReportSnackBar(
          context,
          'Unable to launch the print dialog.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _handleDownload() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await widget.onDownload();
    } catch (_) {
      if (mounted) {
        _showReportSnackBar(
          context,
          'Unable to download the PDF report.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final filters = widget.report.filters;
    final schoolYear = filters.schoolYear.isNotEmpty
        ? filters.schoolYear
        : widget.report.population.schoolYear;
    final chips = <String>[
      'AY $schoolYear',
      filters.periodLabel,
      filters.userCategoryLabel,
      filters.collegeLabel,
      filters.programLabel,
      if (widget.reportType == AdminReportType.emotionalActivity)
        filters.emotionalSourceLabel,
    ];
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 12 : 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 980,
          maxHeight: compact ? 680 : 780,
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 20,
                14,
                compact ? 8 : 12,
                12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.picture_as_pdf_outlined),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'Report Preview',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AdminColors.accentSoft,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'CONFIDENTIAL · AGGREGATE DATA',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AdminColors.accentStrong,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Generated ${_formatDateTime(widget.report.generatedAt.toLocal())} · ${chips.join(' · ')}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AdminColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child:
                  widget.pdfPreviewBuilder?.call(context, widget.pdfBytes) ??
                  PdfPreview(
                    build: (format) async => widget.pdfBytes,
                    allowPrinting: false,
                    allowSharing: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    padding: EdgeInsets.all(compact ? 8 : 16),
                    pdfPreviewPageDecoration: const BoxDecoration(
                      color: Color(0xFFECEFF1),
                    ),
                  ),
            ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 20,
                vertical: 12,
              ),
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _printing ? null : _handlePrint,
                      icon: _printing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.print_outlined, size: 18),
                      label: Text(_printing ? 'Printing...' : 'Print'),
                    ),
                    FilledButton.icon(
                      onPressed: _downloading ? null : _handleDownload,
                      icon: _downloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined, size: 18),
                      label: Text(
                        _downloading ? 'Preparing...' : 'Download PDF',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<ReportPercentageItem> _compact(List<ReportPercentageItem> items) {
  if (items.length <= 8) return items;
  final visible = items.take(7).toList(growable: true);
  visible.add(
    ReportPercentageItem(
      key: 'remaining',
      label: 'Remaining categories',
      percentage: items
          .skip(7)
          .fold<double>(0, (sum, item) => sum + item.percentage)
          .clamp(0, 100),
    ),
  );
  return visible;
}

String _dimensionLabel(AppointmentReportDimension dimension) =>
    switch (dimension) {
      AppointmentReportDimension.department => 'department',
      AppointmentReportDimension.course => 'course',
      AppointmentReportDimension.yearLevel => 'year level',
    };

String _formatPercent(double value) {
  final text = value.roundToDouble() == value
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text%';
}

String _formatDateTime(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

const _panelDecoration = BoxDecoration(
  color: AdminColors.surface,
  border: Border.fromBorderSide(BorderSide(color: AdminColors.border)),
  borderRadius: BorderRadius.all(Radius.circular(10)),
);
