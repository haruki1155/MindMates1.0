import 'dart:math' as math;

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
  const ReportGenerationPage({super.key, required this.repository});

  final AdminPortalRepository repository;

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
  String _schoolYear = _currentSchoolYear();
  _ReportPeriod _period = _ReportPeriod.wholeYear;
  DateTimeRange? _customRange;
  bool _downloading = false;
  bool _previewing = false;
  bool _filterLoading = false;
  int _reportRequestId = 0;

  @override
  void initState() {
    super.initState();
    _report = _fetch();
  }

  Future<AdminReportAnalytics> _fetch() =>
      widget.repository.fetchReportAnalytics(
        userCategory: _userCategory,
        appointmentDepartment: _appointmentDepartment,
        schoolYear: _schoolYear,
        startDate: _period == _ReportPeriod.wholeYear
            ? null
            : _periodRange()?.start,
        endDate: _period == _ReportPeriod.wholeYear
            ? null
            : _periodRange()?.end,
      );

  DateTimeRange? _periodRange() {
    if (_period == _ReportPeriod.custom) return _customRange;
    final startYear =
        int.tryParse(_schoolYear.split('-').first) ?? DateTime.now().year;
    return _period == _ReportPeriod.firstSemester
        ? DateTimeRange(
            start: DateTime(startYear, 6, 1),
            end: DateTime(startYear, 12, 1),
          )
        : DateTimeRange(
            start: DateTime(startYear, 12, 1),
            end: DateTime(startYear + 1, 6, 1),
          );
  }

  void _refresh() => _reloadReport();

  void _reloadReport() {
    final requestId = ++_reportRequestId;
    final future = _fetch();
    setState(() {
      _report = future;
      _filterLoading = true;
    });
    future.then(
      (_) {
        if (mounted && requestId == _reportRequestId) {
          setState(() => _filterLoading = false);
        }
      },
      onError: (_, _) {
        if (mounted && requestId == _reportRequestId) {
          setState(() => _filterLoading = false);
        }
      },
    );
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
      if (value != 'all' &&
          _dimension == AppointmentReportDimension.department) {
        _dimension = AppointmentReportDimension.course;
      }
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
      builder: (context, snapshot) => SingleChildScrollView(
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
                  canDownload: snapshot.hasData,
                  showImport: _reportType == AdminReportType.appointments,
                  onRefresh: _refresh,
                  onDownload: snapshot.hasData
                      ? () => _download(snapshot.requireData)
                      : null,
                  onPreview: snapshot.hasData
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
                  _ErrorPanel(onRetry: _refresh)
                else if (snapshot.hasData)
                  _content(snapshot.requireData),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(AdminReportAnalytics report) => Column(
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
          department: _appointmentDepartment,
          departmentOptions: report.appointmentDepartmentOptions,
          onYearChanged: (value) {
            setState(() => _schoolYear = value);
            _reloadReport();
          },
          onAddYear: widget.repository.currentAccessRole == AccessRole.admin
              ? () => _createAcademicYear(report.population.schoolYear)
              : null,
          onPeriodChanged: (value) {
            setState(() => _period = value);
            _reloadReport();
          },
          onCustomPeriod: () async {
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
          },
          onDepartmentChanged: _selectDepartment,
          onDimensionChanged: (value) => setState(() => _dimension = value),
          onChartChanged: (value) => setState(() => _chartType = value),
        ),
      ] else ...[
        _ControlPanel(
          reportType: _reportType,
          chartType: _chartType,
          dimension: _dimension,
          userCategory: _userCategory,
          userCategories: report.userCategoryOptions,
          appointmentDepartment: _appointmentDepartment,
          departmentOptions: report.appointmentDepartmentOptions,
          onChartChanged: (value) => setState(() => _chartType = value),
          onDimensionChanged: (value) => setState(() => _dimension = value),
          onUserCategoryChanged: _selectUserCategory,
          onDepartmentChanged: _selectDepartment,
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

  Future<void> _download(AdminReportAnalytics report) async {
    setState(() => _downloading = true);
    try {
      await AdminReportPdfService.download(
        report: report,
        reportType: _reportType,
        chartType: _chartType,
        userCategoryKey: _userCategory,
        appointmentDimension: _dimension,
      );
      try {
        await widget.repository.recordAuditEvent(
          action: 'REPORT_EXPORTED_PDF',
          category: 'REPORTS',
          targetType: 'report',
          targetId: report.population.schoolYear,
          metadata: {
            'reportType': _reportType.name,
            'department': _appointmentDepartment,
            'period': report.dateRange.label,
          },
        );
      } catch (_) {}
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
    if (_previewing) return;
    setState(() => _previewing = true);
    try {
      final pdfBytes = await AdminReportPdfService.build(
        report: report,
        reportType: _reportType,
        chartType: _chartType,
        userCategoryKey: _userCategory,
        appointmentDimension: _dimension,
      );
      if (!mounted) return;
      try {
        await widget.repository.recordAuditEvent(
          action: 'REPORT_VIEWED',
          category: 'REPORTS',
          targetType: 'report',
          targetId: report.population.schoolYear,
          metadata: {
            'reportType': _reportType.name,
            'period': report.dateRange.label,
          },
        );
      } catch (_) {}
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 980,
            height: 760,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'PDF preview',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close preview',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    build: (format) async => pdfBytes,
                    allowPrinting: false,
                    allowSharing: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    padding: const EdgeInsets.all(16),
                    pdfPreviewPageDecoration: const BoxDecoration(
                      color: Color(0xFFECEFF1),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
      if (mounted) setState(() => _previewing = false);
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

  Future<void> _createAcademicYear(String copyFrom) async {
    final choice = await showDialog<_NewAcademicYearChoice>(
      context: context,
      builder: (_) => const _NewAcademicYearDialog(),
    );
    if (choice == null) return;
    try {
      await widget.repository.createAcademicYear(
        schoolYear: choice.schoolYear,
        copyFrom: copyFrom,
        copyPopulation: choice.copyPopulation,
      );
      if (!mounted) return;
      setState(() {
        _schoolYear = choice.schoolYear;
        _report = _fetch();
      });
      _showReportSnackBar(
        context,
        'Academic year ${choice.schoolYear} created.',
      );
    } catch (error) {
      if (mounted) {
        _showReportSnackBar(context, _friendlyReportError(error), error: true);
      }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.loading,
    required this.downloading,
    required this.previewing,
    required this.canDownload,
    required this.showImport,
    required this.onRefresh,
    required this.onDownload,
    required this.onPreview,
    required this.onImport,
  });

  final bool loading;
  final bool downloading;
  final bool previewing;
  final bool canDownload;
  final bool showImport;
  final VoidCallback onRefresh;
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
          OutlinedButton.icon(
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
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
  Widget build(BuildContext context) => SegmentedButton<AdminReportType>(
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
    ],
    selected: {value},
    onSelectionChanged: (selection) => onChanged(selection.first),
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
    required this.department,
    required this.departmentOptions,
    required this.onYearChanged,
    required this.onAddYear,
    required this.onPeriodChanged,
    required this.onCustomPeriod,
    required this.onDepartmentChanged,
    required this.onDimensionChanged,
    required this.onChartChanged,
  });

  final String schoolYear;
  final List<AcademicYearRecord> years;
  final _ReportPeriod period;
  final AdminReportAnalytics report;
  final ReportChartType chartType;
  final AppointmentReportDimension dimension;
  final String department;
  final List<ReportFilterOption> departmentOptions;
  final ValueChanged<String> onYearChanged;
  final VoidCallback? onAddYear;
  final ValueChanged<_ReportPeriod> onPeriodChanged;
  final VoidCallback onCustomPeriod;
  final ValueChanged<String> onDepartmentChanged;
  final ValueChanged<AppointmentReportDimension> onDimensionChanged;
  final ValueChanged<ReportChartType> onChartChanged;

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: _panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'REPORT CONTROLS',
                  style: TextStyle(
                    color: AdminColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (onAddYear != null)
                TextButton.icon(
                  onPressed: onAddYear,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('Add academic year'),
                ),
            ],
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
                    child: _LabeledControl(
                      label: 'Academic year',
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            options.any((item) => item.schoolYear == schoolYear)
                            ? schoolYear
                            : options.first.schoolYear,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                        items: options
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.schoolYear,
                                child: Row(
                                  children: [
                                    Text(item.schoolYear),
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
                          if (value != null) onYearChanged(value);
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _LabeledControl(
                      label: 'Reporting period',
                      child: DropdownButtonFormField<_ReportPeriod>(
                        initialValue: period,
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
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 950;
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: _scopeControl()),
                        const SizedBox(width: 14),
                        Expanded(child: _groupControl()),
                        const SizedBox(width: 14),
                        _visualControl(),
                      ],
                    )
                  : Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _scopeControl(),
                        _groupControl(),
                        _visualControl(),
                      ],
                    );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 15,
                color: AdminColors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Percentages are calculated using the population snapshot for ${report.population.schoolYear}.',
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

  Widget _scopeControl() => SizedBox(
    width: 280,
    child: _LabeledControl(
      label: 'Department scope',
      child: DropdownButtonFormField<String>(
        initialValue: department,
        isExpanded: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.account_balance_outlined),
        ),
        items: [
          const DropdownMenuItem(value: 'all', child: Text('All departments')),
          ...departmentOptions.map(
            (item) => DropdownMenuItem(
              value: item.key,
              child: Text(item.label, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) {
          if (value != null) onDepartmentChanged(value);
        },
      ),
    ),
  );

  Widget _groupControl() => _LabeledControl(
    label: 'Group by',
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
    required this.reportType,
    required this.chartType,
    required this.dimension,
    required this.userCategory,
    required this.userCategories,
    required this.appointmentDepartment,
    required this.departmentOptions,
    required this.onChartChanged,
    required this.onDimensionChanged,
    required this.onUserCategoryChanged,
    required this.onDepartmentChanged,
  });

  final AdminReportType reportType;
  final ReportChartType chartType;
  final AppointmentReportDimension dimension;
  final String userCategory;
  final List<ReportFilterOption> userCategories;
  final String appointmentDepartment;
  final List<ReportFilterOption> departmentOptions;
  final ValueChanged<ReportChartType> onChartChanged;
  final ValueChanged<AppointmentReportDimension> onDimensionChanged;
  final ValueChanged<String> onUserCategoryChanged;
  final ValueChanged<String> onDepartmentChanged;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: _panelDecoration,
    child: Wrap(
      spacing: 30,
      runSpacing: 18,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        _LabeledControl(
          label: reportType == AdminReportType.users
              ? 'USER CATEGORY'
              : 'GROUP APPOINTMENTS BY',
          child: reportType == AdminReportType.users
              ? Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Overall'),
                      selected: userCategory == 'all',
                      onSelected: (_) => onUserCategoryChanged('all'),
                    ),
                    for (final category in userCategories)
                      ChoiceChip(
                        label: Text(category.label),
                        selected: userCategory == category.key,
                        onSelected: (_) => onUserCategoryChanged(category.key),
                      ),
                  ],
                )
              : Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<String>(
                        initialValue: appointmentDepartment,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Department scope',
                          prefixIcon: Icon(Icons.account_balance_outlined),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('All departments'),
                          ),
                          ...departmentOptions.map(
                            (department) => DropdownMenuItem(
                              value: department.key,
                              child: Text(
                                department.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) onDepartmentChanged(value);
                        },
                      ),
                    ),
                    SegmentedButton<AppointmentReportDimension>(
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
                      onSelectionChanged: (values) =>
                          onDimensionChanged(values.first),
                    ),
                  ],
                ),
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
            if (widget.config.status != 'closed') ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _saving ? null : _confirmCloseYear,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Close this year'),
                  ),
                ],
              ),
            ],
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

  Future<void> _confirmCloseYear() async {
    final allValid =
        widget.config.configured &&
        _fields.values.every((field) {
          final value = int.tryParse(field.text.trim());
          return value != null && value > 0;
        });
    if (!allValid) {
      setState(
        () => _error =
            'Save a valid population for every department before locking this year.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _CloseAcademicYearDialog(schoolYear: widget.config.schoolYear),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.closeAcademicYear(widget.config.schoolYear);
      if (mounted) widget.onYearChanged(widget.config.schoolYear);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyReportError(error));
    }
  }
}

class _CloseAcademicYearDialog extends StatefulWidget {
  const _CloseAcademicYearDialog({required this.schoolYear});
  final String schoolYear;
  @override
  State<_CloseAcademicYearDialog> createState() =>
      _CloseAcademicYearDialogState();
}

class _CloseAcademicYearDialogState extends State<_CloseAcademicYearDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phrase = 'CLOSE ${widget.schoolYear}';
    return AlertDialog(
      title: const Text('Lock academic year?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This locks the saved population and preserves this year for historical reports. This cannot be edited afterward.',
          ),
          const SizedBox(height: 12),
          Text('Type $phrase to confirm.'),
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Confirmation'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _controller.text.trim() == phrase
              ? () => Navigator.pop(context, true)
              : null,
          child: const Text('Lock year'),
        ),
      ],
    );
  }
}

class _NewAcademicYearDialog extends StatefulWidget {
  const _NewAcademicYearDialog();
  @override
  State<_NewAcademicYearDialog> createState() => _NewAcademicYearDialogState();
}

class _NewAcademicYearDialogState extends State<_NewAcademicYearDialog> {
  final _controller = TextEditingController();
  bool _copyPopulation = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create academic year'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'School year',
            hintText: '2027-2028',
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _copyPopulation,
          onChanged: (value) =>
              setState(() => _copyPopulation = value ?? false),
          title: const Text('Copy previous population as a starting point'),
          subtitle: const Text('Leave unchecked to start empty.'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _NewAcademicYearChoice(_controller.text.trim(), _copyPopulation),
        ),
        child: const Text('Create'),
      ),
    ],
  );
}

class _NewAcademicYearChoice {
  const _NewAcademicYearChoice(this.schoolYear, this.copyPopulation);
  final String schoolYear;
  final bool copyPopulation;
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
  const _ErrorPanel({required this.onRetry});
  final VoidCallback onRetry;
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
        ),
        const SizedBox(height: 5),
        const Text(
          'Check the report function deployment and your access, then try again.',
          style: TextStyle(color: AdminColors.muted),
        ),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
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
