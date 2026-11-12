import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../models/student_personal_info.dart';
import '../../../models/student_roster_models.dart';
import '../../../repositories/student_roster_repository.dart';
import '../services/admin_file_download.dart';
import '../services/admin_import_file_picker.dart';
import '../services/student_roster_file_parser.dart';
import '../theme/admin_theme.dart';

const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

const codesShownOnceWarning =
    'Codes are shown only once. Download them before leaving this page.';

typedef RosterFilePicker = Future<AdminImportFile?> Function();

/// Tracks whether freshly issued activation codes have been downloaded so the
/// portal shell can ask before navigating away.
class StudentRosterLeaveGuard {
  bool hasUndownloadedCodes = false;

  Future<bool> confirmLeave(BuildContext context) async {
    if (!hasUndownloadedCodes) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave without downloading?'),
        content: const Text(
          'Activation codes from this import have not been downloaded and '
          'cannot be shown again. $codesShownOnceWarning',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay on page'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave anyway'),
          ),
        ],
      ),
    );
    return leave == true;
  }
}

String _errorText(Object error) {
  if (error is FirebaseFunctionsException) {
    final message = error.message;
    return message == null || message.isEmpty
        ? 'The request failed (${error.code}).'
        : message;
  }
  return 'Something went wrong. Please try again.';
}

String _shortDate(DateTime d) {
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

final _dateKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');
String _spellIfDate(String value) =>
    _dateKey.hasMatch(value) ? spelledDate(value) : value;

String _countsLine(Map<String, int> c) =>
    '${c['new'] ?? 0} new · ${c['updated'] ?? 0} updated · ${c['linked'] ?? 0} linked';

const _yearLevels = [
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
  '5th Year',
];

/// Admin-only: import the registrar roster, issue activation slips and manage
/// roster rows.
class StudentRosterPage extends StatefulWidget {
  const StudentRosterPage({
    super.key,
    this.repository,
    this.pickFile = pickAdminImportFile,
    this.download = downloadAdminFile,
    this.leaveGuard,
  });

  final StudentRosterRepository? repository;
  final RosterFilePicker pickFile;
  final AdminFileDownloader download;
  final StudentRosterLeaveGuard? leaveGuard;

  @override
  State<StudentRosterPage> createState() => _StudentRosterPageState();
}

enum _Tab { roster, import, corrections, history, legacy }

class _StudentRosterPageState extends State<StudentRosterPage> {
  late final StudentRosterRepository _repo =
      widget.repository ?? StudentRosterRepository();
  late final StudentRosterLeaveGuard _guard =
      widget.leaveGuard ?? StudentRosterLeaveGuard();

  _Tab _tab = _Tab.roster;

  // ----------------------------------------------------------- roster tab
  final _search = TextEditingController();
  String _statusFilter = '';
  String _yearFilter = '';
  List<RosterRowView> _rosterRows = const [];
  String? _nextPageToken;
  bool _rosterLoading = false;
  String? _rosterError;
  final Set<String> _selected = {};
  final Set<String> _busyRows = {};

  // ----------------------------------------------------------- import tab
  AdminImportFile? _file;
  RosterParseResult? _parsed;
  List<RosterPreviewRow>? _previewRows;
  Map<String, int> _previewCounts = const {};
  bool _previewing = false;
  bool _importing = false;
  String _progress = '';
  String? _importError;
  Map<String, int>? _importCounts;
  RosterImportResult? _partial;
  int _partialFailedCount = 0;
  final List<IssuedActivationCode> _codes = [];
  bool _codesDownloaded = true;

  // ------------------------------------------------------- other tabs
  List<StudentCorrection>? _corrections;
  String? _correctionsError;
  final Map<String, ({String message, bool offerEdit})> _correctionIssues = {};
  final Set<String> _busyCorrections = {};
  List<RosterImportRecord>? _imports;
  String? _importsError;
  List<LegacyStudent>? _legacy;
  String? _legacyError;

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  @override
  void dispose() {
    _guard.hasUndownloadedCodes = false;
    _search.dispose();
    super.dispose();
  }

  void _syncGuard() {
    _guard.hasUndownloadedCodes = _codes.isNotEmpty && !_codesDownloaded;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ===================================================================
  // Build
  // ===================================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_guard.hasUndownloadedCodes,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _guard.confirmLeave(context)) {
          _guard.hasUndownloadedCodes = false;
          navigator.pop();
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Student Roster',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Import the registrar roster, issue one-time activation codes '
              'and manage student records.',
            ),
            const SizedBox(height: 20),
            _tabBar(),
            const SizedBox(height: 20),
            switch (_tab) {
              _Tab.roster => _rosterTab(),
              _Tab.import => _importTab(),
              _Tab.corrections => _correctionsTab(),
              _Tab.history => _historyTab(),
              _Tab.legacy => _legacyTab(),
            },
          ],
        ),
      ),
    );
  }

  Widget _tabBar() {
    const labels = {
      _Tab.roster: 'Roster',
      _Tab.import: 'Import',
      _Tab.corrections: 'Corrections',
      _Tab.history: 'Import history',
      _Tab.legacy: 'Legacy – not in roster',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in labels.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: _tab == e.key,
            onSelected: (_) => _openTab(e.key),
          ),
      ],
    );
  }

  void _openTab(_Tab tab) {
    setState(() => _tab = tab);
    switch (tab) {
      case _Tab.corrections:
        if (_corrections == null) _loadCorrections();
      case _Tab.history:
        if (_imports == null) _loadImports();
      case _Tab.legacy:
        if (_legacy == null) _loadLegacy();
      case _Tab.roster || _Tab.import:
        break;
    }
  }

  Widget _error(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(message, style: const TextStyle(color: AdminColors.danger)),
  );

  Widget _loading() => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator()),
  );

  // ===================================================================
  // Roster tab
  // ===================================================================

  Future<void> _loadRoster({bool more = false}) async {
    if (_rosterLoading) return;
    setState(() {
      _rosterLoading = true;
      _rosterError = null;
    });
    try {
      final page = await _repo.listRoster(
        search: _search.text.trim(),
        status: _statusFilter,
        yearLevel: _yearFilter,
        pageToken: more ? _nextPageToken : null,
      );
      if (!mounted) return;
      setState(() {
        _rosterRows = more ? [..._rosterRows, ...page.rows] : page.rows;
        _nextPageToken = page.nextPageToken;
        if (!more) _selected.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _rosterError = _errorText(e));
    } finally {
      if (mounted) setState(() => _rosterLoading = false);
    }
  }

  Widget _rosterTab() {
    final selectable = _rosterRows.where((r) => !r.activated).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _search,
                onSubmitted: (_) => _loadRoster(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name or Student No.',
                ),
              ),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                key: ValueKey('status-$_statusFilter'),
                isExpanded: true,
                initialValue: _statusFilter,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('All statuses')),
                  DropdownMenuItem(
                    value: 'notActivated',
                    child: Text('Not activated'),
                  ),
                  DropdownMenuItem(
                    value: 'activated',
                    child: Text('Activated'),
                  ),
                  DropdownMenuItem(
                    value: 'infoIncomplete',
                    child: Text('Info incomplete'),
                  ),
                  DropdownMenuItem(
                    value: 'deactivated',
                    child: Text('Deactivated'),
                  ),
                ],
                onChanged: (v) {
                  _statusFilter = v ?? '';
                  _loadRoster();
                },
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                key: ValueKey('year-$_yearFilter'),
                isExpanded: true,
                initialValue: _yearFilter,
                decoration: const InputDecoration(labelText: 'Year level'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All years')),
                  for (final y in _yearLevels)
                    DropdownMenuItem(value: y, child: Text(y)),
                ],
                onChanged: (v) {
                  _yearFilter = v ?? '';
                  _loadRoster();
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: _rosterLoading ? null : () => _loadRoster(),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            if (_selected.isNotEmpty)
              FilledButton.icon(
                onPressed: _issueSelected,
                icon: const Icon(Icons.vpn_key_outlined),
                label: Text('Issue activation codes (${_selected.length})'),
              ),
          ],
        ),
        if (selectable.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                if (_selected.length == selectable.length) {
                  _selected.clear();
                } else {
                  _selected
                    ..clear()
                    ..addAll(selectable.map((r) => r.studentNo));
                }
              }),
              child: Text(
                _selected.length == selectable.length
                    ? 'Clear selection'
                    : 'Select all not activated',
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (_rosterError != null) _error(_rosterError!),
        if (_rosterRows.isEmpty && !_rosterLoading && _rosterError == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No roster records match these filters.'),
          ),
        for (final row in _rosterRows) _rosterRowTile(row),
        if (_rosterLoading) _loading(),
        if (_nextPageToken != null && !_rosterLoading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: () => _loadRoster(more: true),
              child: const Text('Load more'),
            ),
          ),
      ],
    );
  }

  String _statusLabel(RosterRowView r) {
    if (r.status == 'deactivated') return 'Deactivated';
    if (!r.activated) return 'Not activated';
    return r.personalInfoComplete ? 'Activated' : 'Activated · info incomplete';
  }

  Widget _rosterRowTile(RosterRowView row) {
    final busy = _busyRows.contains(row.studentNo);
    final deactivated = row.status == 'deactivated';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: row.activated
            ? const SizedBox(width: 40)
            : Checkbox(
                value: _selected.contains(row.studentNo),
                onChanged: (v) => setState(() {
                  v == true
                      ? _selected.add(row.studentNo)
                      : _selected.remove(row.studentNo);
                }),
              ),
        title: Text(
          '${row.name} · ${row.studentNo}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${row.college} · ${row.course} · ${row.yearLevel}\n'
          '${_statusLabel(row)}',
        ),
        isThreeLine: true,
        trailing: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : PopupMenuButton<String>(
                tooltip: 'Actions for ${row.studentNo}',
                onSelected: (v) => _rowAction(row, v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (!row.activated) ...[
                    const PopupMenuItem(
                      value: 'lock',
                      child: Text('Reset activation lock'),
                    ),
                    const PopupMenuItem(
                      value: 'issue',
                      child: Text('Issue new activation code'),
                    ),
                  ],
                  if (row.activated)
                    const PopupMenuItem(
                      value: 'revoke',
                      child: Text('Revoke activation'),
                    ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(deactivated ? 'Reactivate' : 'Deactivate'),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _rowAction(RosterRowView row, String action) async {
    switch (action) {
      case 'edit':
        await _editRecord(
          studentNo: row.studentNo,
          name: row.name,
          college: row.college,
          course: row.course,
          yearLevel: row.yearLevel,
        );
      case 'lock':
        await _guarded(row.studentNo, () async {
          await _repo.resetActivationLock(row.studentNo);
          _toast('Activation lock reset for ${row.studentNo}.');
        });
      case 'issue':
        await _issueCodes([row.studentNo]);
      case 'revoke':
        await _revoke(row);
      case 'toggle':
        final deactivating = row.status != 'deactivated';
        final ok = await _confirm(
          title: deactivating ? 'Deactivate student?' : 'Reactivate student?',
          body: deactivating
              ? '${row.name} (${row.studentNo}) will no longer be able to '
                    'activate or use this roster record.'
              : '${row.name} (${row.studentNo}) will be able to use this '
                    'roster record again.',
          confirmLabel: deactivating ? 'Deactivate' : 'Reactivate',
        );
        if (!ok) return;
        await _guarded(row.studentNo, () async {
          await _repo.setRosterStatus(row.studentNo, active: !deactivating);
          _toast(
            deactivating ? 'Student deactivated.' : 'Student reactivated.',
          );
        }, reload: true);
    }
  }

  Future<void> _guarded(
    String studentNo,
    Future<void> Function() body, {
    bool reload = false,
  }) async {
    setState(() => _busyRows.add(studentNo));
    try {
      await body();
      if (reload && mounted) {
        setState(() => _busyRows.remove(studentNo));
        await _loadRoster();
      }
    } catch (e) {
      _toast(_errorText(e));
    } finally {
      if (mounted) setState(() => _busyRows.remove(studentNo));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<String?> _askReason({
    required String title,
    required String body,
    required String confirmLabel,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        _ReasonDialog(title: title, body: body, confirmLabel: confirmLabel),
  );

  // -------------------------------------------------- codes (issue/revoke)

  Future<void> _issueSelected() => _issueCodes(_selected.toList());

  Future<void> _issueCodes(List<String> studentNos) async {
    final multiple = studentNos.length > 1;
    final ok = await _confirm(
      title: 'Issue new activation code${multiple ? 's' : ''}?',
      body: multiple
          ? 'New one-time codes will be issued for ${studentNos.length} '
                'students. Any earlier code for them stops working.'
          : 'A new one-time code will be issued for ${studentNos.single}. '
                'Any earlier code stops working.',
      confirmLabel: 'Issue',
    );
    if (!ok) return;
    setState(() => _busyRows.addAll(studentNos));
    try {
      final result = await _repo.issueActivationCodes(studentNos);
      if (!mounted) return;
      setState(() {
        _selected.removeAll(studentNos);
        _busyRows.removeAll(studentNos);
      });
      await _showCodesDialog(
        title: 'Activation codes issued',
        codes: result.codes,
        showCodes: false,
        skipped: result.skipped,
      );
    } catch (e) {
      _toast(_errorText(e));
    } finally {
      if (mounted) setState(() => _busyRows.removeAll(studentNos));
    }
  }

  Future<void> _revoke(RosterRowView row) async {
    final reason = await _askReason(
      title: 'Revoke activation?',
      body:
          '${row.name} (${row.studentNo}) will lose access to the claimed '
          'account. The data is kept and a new activation code is issued. '
          'Enter the reason for the audit log.',
      confirmLabel: 'Revoke activation',
    );
    if (reason == null || !mounted) return;
    setState(() => _busyRows.add(row.studentNo));
    try {
      final code = await _repo.revokeActivation(row.studentNo, reason);
      if (!mounted) return;
      setState(() => _busyRows.remove(row.studentNo));
      await _showCodesDialog(
        title: 'Activation revoked',
        codes: [code],
        showCodes: true,
      );
      if (mounted) await _loadRoster();
    } catch (e) {
      _toast(_errorText(e));
    } finally {
      if (mounted) setState(() => _busyRows.remove(row.studentNo));
    }
  }

  Future<void> _showCodesDialog({
    required String title,
    required List<IssuedActivationCode> codes,
    required bool showCodes,
    List<({String studentNo, String reason})> skipped = const [],
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CodesDialog(
        title: title,
        codes: codes,
        showCodes: showCodes,
        skipped: skipped,
        onDownload: () => _downloadSlips(codes),
      ),
    );
  }

  /// Returns true when the browser download was started.
  bool _downloadSlips(List<IssuedActivationCode> codes) {
    try {
      widget.download(
        'activation_slips_${DateTime.now().toIso8601String().substring(0, 10)}.xlsx',
        buildActivationSlipsXlsx(codes),
        _xlsxMime,
      );
      return true;
    } catch (_) {
      _toast('The download could not be started.');
      return false;
    }
  }

  // -------------------------------------------------------------- edit

  Future<void> _editRecord({
    required String studentNo,
    required String name,
    String college = '',
    String course = '',
    String yearLevel = '',
  }) async {
    final fields = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _EditRecordDialog(
        studentNo: studentNo,
        name: name,
        college: college,
        course: course,
        yearLevel: yearLevel,
      ),
    );
    if (fields == null || fields.isEmpty || !mounted) return;
    await _guarded(studentNo, () async {
      await _repo.updateRosterRecord(studentNo, fields);
      _toast('Roster record updated.');
    }, reload: true);
  }

  // ===================================================================
  // Import tab
  // ===================================================================

  bool get _hasBlockingFileProblems {
    final p = _parsed;
    return p == null || p.hasBlockingProblems;
  }

  Future<void> _chooseFile() async {
    try {
      final file = await widget.pickFile();
      if (file == null || !mounted) return;
      final parsed = parseRosterFile(file.name, file.bytes);
      setState(() {
        _file = file;
        _parsed = parsed;
        _previewRows = null;
        _previewCounts = const {};
        _importError = null;
        _importCounts = null;
        _partial = null;
      });
    } catch (e) {
      if (mounted) setState(() => _importError = _errorText(e));
    }
  }

  void _downloadTemplate() {
    try {
      widget.download(
        'student_roster_template.xlsx',
        buildRosterTemplateXlsx(),
        _xlsxMime,
      );
    } catch (_) {
      _toast('The template could not be downloaded.');
    }
  }

  Future<void> _preview() async {
    final file = _file;
    final parsed = _parsed;
    if (file == null || parsed == null || _hasBlockingFileProblems) return;
    setState(() {
      _previewing = true;
      _importError = null;
    });
    try {
      final rows = <RosterPreviewRow>[];
      final counts = <String, int>{};
      var offset = 0;
      for (final chunk in chunkRows(parsed.rows)) {
        final result = await _repo.previewImport(file.name, chunk);
        for (final r in result.rows) {
          rows.add(
            RosterPreviewRow(
              index: r.index + offset,
              studentNo: r.studentNo,
              kind: r.kind,
              changes: r.changes,
              errors: r.errors,
            ),
          );
        }
        for (final e in result.counts.entries) {
          counts[e.key] = (counts[e.key] ?? 0) + e.value;
        }
        offset += chunk.length;
      }
      if (!mounted) return;
      setState(() {
        _previewRows = rows;
        _previewCounts = counts;
      });
    } catch (e) {
      if (mounted) setState(() => _importError = _errorText(e));
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  bool get _previewHasErrors {
    final rows = _previewRows;
    if (rows == null) return true;
    return (_previewCounts['error'] ?? 0) > 0 ||
        rows.any((r) => r.kind == RosterPreviewKind.error);
  }

  Future<void> _commit() async {
    final file = _file;
    final parsed = _parsed;
    if (file == null ||
        parsed == null ||
        _previewRows == null ||
        _previewHasErrors ||
        _importing) {
      return;
    }
    final chunks = chunkRows(parsed.rows);
    setState(() {
      _importing = true;
      _importError = null;
      _importCounts = null;
      _partial = null;
      _codes.clear();
      _codesDownloaded = true;
    });
    final totals = <String, int>{};
    try {
      for (var i = 0; i < chunks.length; i++) {
        if (mounted) {
          setState(
            () => _progress = 'Importing part ${i + 1} of ${chunks.length}…',
          );
        }
        final result = await _repo.commitImport(file.name, chunks[i]);
        for (final e in result.counts.entries) {
          totals[e.key] = (totals[e.key] ?? 0) + e.value;
        }
        _codes.addAll(result.codes);
        if (result.isPartial) {
          if (mounted) {
            setState(() {
              _partial = result;
              _partialFailedCount = result.failedRows.length;
            });
          }
          break;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _importError =
              '${_errorText(e)} The import stopped; rows already imported '
              'stay in the roster.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _progress = '';
          _importCounts = totals.isEmpty && _importError != null
              ? null
              : totals;
          _codesDownloaded = _codes.isEmpty;
          _parsed = null;
          _previewRows = null;
          _file = null;
          _syncGuard();
        });
        _imports = null;
        _loadRoster();
      }
    }
  }

  void _downloadImportSlips() {
    if (_downloadSlips(List.of(_codes))) {
      setState(() {
        _codesDownloaded = true;
        _syncGuard();
      });
    }
  }

  Widget _importTab() {
    final parsed = _parsed;
    final file = _file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _importing || _previewing ? null : _chooseFile,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Choose roster file'),
            ),
            OutlinedButton.icon(
              onPressed: _downloadTemplate,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download template'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Accepts .xlsx or .csv using the template columns.'),
        if (_importError != null) _error(_importError!),
        if (_partial != null) _partialBanner(_partial!),
        if (_importCounts != null) _summaryCard(),
        if (parsed != null && file != null) ...[
          const SizedBox(height: 16),
          _fileCard(file, parsed),
        ],
        if (_previewRows != null) ...[
          const SizedBox(height: 16),
          _previewCard(),
        ],
      ],
    );
  }

  Widget _partialBanner(RosterImportResult result) => Card(
    color: const Color(0xFFFFF1D6),
    margin: const EdgeInsets.only(top: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AdminColors.accentStrong,
              ),
              SizedBox(width: 8),
              Text(
                'Import only partly completed',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (result.message != null) Text(result.message!),
          Text('Committed: ${_countsLine(_importCounts ?? result.counts)}'),
          Text('$_partialFailedCount row(s) were not imported.'),
          const Text(
            'No further parts were sent. Download the slips for the rows that '
            'were imported, then fix the file and import it again.',
          ),
        ],
      ),
    ),
  );

  Widget _summaryCard() => Card(
    margin: const EdgeInsets.only(top: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _countsLine(_importCounts!),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (_codes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              codesShownOnceWarning,
              style: const TextStyle(color: AdminColors.danger),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _downloadImportSlips,
              icon: const Icon(Icons.download),
              label: Text('Download activation slips (${_codes.length})'),
            ),
            if (_codesDownloaded)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Activation slips downloaded.'),
              ),
          ],
        ],
      ),
    ),
  );

  Widget _fileCard(AdminImportFile file, RosterParseResult parsed) {
    final dupes = parsed.duplicateStudentNos;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              file.name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text('${parsed.rows.length} student row(s) found'),
            for (final e in parsed.fileErrors) _error(e),
            if (dupes.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Duplicate Student No. in this file:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final e in dupes.entries)
                _error('${e.key} appears on rows ${e.value.join(', ')}'),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _hasBlockingFileProblems || _previewing || _importing
                  ? null
                  : _preview,
              icon: _previewing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewCard() {
    final rows = _previewRows!;
    final parsed = _parsed;
    String dobOf(int index) {
      final raw = parsed != null && index < parsed.rows.length
          ? parsed.rows[index]['dateOfBirth'] ?? ''
          : '';
      return _spellIfDate(raw);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('New ${_previewCounts['new'] ?? 0}')),
                Chip(label: Text('Update ${_previewCounts['update'] ?? 0}')),
                Chip(
                  label: Text('Links account ${_previewCounts['link'] ?? 0}'),
                ),
                Chip(label: Text('Error ${_previewCounts['error'] ?? 0}')),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: rows.length > 6 ? 360 : null,
              child: ListView.separated(
                shrinkWrap: rows.length <= 6,
                physics: rows.length > 6
                    ? null
                    : const NeverScrollableScrollPhysics(),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final label = switch (r.kind) {
                    RosterPreviewKind.newRow => 'New',
                    RosterPreviewKind.update => 'Update',
                    RosterPreviewKind.link => 'Links account',
                    RosterPreviewKind.error => 'Error',
                  };
                  return ListTile(
                    dense: true,
                    title: Text('${r.studentNo} · $label'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Row ${r.index + 2} · Born ${dobOf(r.index)}'),
                        for (final c in r.changes.entries)
                          Text(
                            '${c.key}: ${_spellIfDate(c.value.from)} → '
                            '${_spellIfDate(c.value.to)}',
                          ),
                        for (final e in r.errors)
                          Text(
                            e,
                            style: const TextStyle(color: AdminColors.danger),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (_previewHasErrors)
              const Text(
                'Fix the error rows in your file and choose it again. '
                'Nothing is imported while any row has an error.',
              ),
            if (_progress.isNotEmpty) Text(_progress),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _previewHasErrors || _importing ? null : _commit,
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check),
              label: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  // ===================================================================
  // Corrections tab
  // ===================================================================

  Future<void> _loadCorrections() async {
    setState(() => _correctionsError = null);
    try {
      final list = await _repo.listCorrections(pendingOnly: true);
      if (mounted) setState(() => _corrections = list);
    } catch (e) {
      if (mounted) {
        setState(() {
          _corrections = const [];
          _correctionsError = _errorText(e);
        });
      }
    }
  }

  Widget _correctionsTab() {
    final list = _corrections;
    if (list == null) return _loading();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_correctionsError != null) _error(_correctionsError!),
        if (list.isEmpty && _correctionsError == null)
          const Text('No pending correction requests.'),
        for (final c in list) _correctionCard(c),
      ],
    );
  }

  Widget _correctionCard(StudentCorrection c) {
    final issue = _correctionIssues[c.id];
    final busy = _busyCorrections.contains(c.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.studentName.isEmpty ? 'Student' : c.studentName} · ${c.studentNo}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              '${c.field}: ${_spellIfDate(c.currentValue)} → '
              '${_spellIfDate(c.requestedValue)}',
            ),
            Text('Reason: ${c.reason}'),
            if (issue != null) ...[
              const SizedBox(height: 8),
              _error(issue.message),
              if (issue.offerEdit)
                OutlinedButton.icon(
                  onPressed: () => _editRecord(
                    studentNo: c.studentNo,
                    name: c.studentName,
                    college: c.field == 'college' ? c.requestedValue : '',
                    course: c.field == 'course' ? c.requestedValue : '',
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit record'),
                ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : () => _approve(c),
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => _reject(c),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(StudentCorrection c) async {
    setState(() => _busyCorrections.add(c.id));
    try {
      await _repo.reviewCorrection(c.id, approve: true);
      _afterReview(c, 'Correction approved.');
    } on FirebaseFunctionsException catch (e) {
      final academic = c.field == 'college' || c.field == 'course';
      if (mounted) {
        setState(
          () => _correctionIssues[c.id] = (
            message: _errorText(e),
            offerEdit: e.code == 'failed-precondition' && academic,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _correctionIssues[c.id] = (
            message: _errorText(e),
            offerEdit: false,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyCorrections.remove(c.id));
    }
  }

  Future<void> _reject(StudentCorrection c) async {
    final reason = await _askReason(
      title: 'Reject correction?',
      body:
          'Tell ${c.studentName.isEmpty ? 'the student' : c.studentName} '
          'why this change was not accepted.',
      confirmLabel: 'Reject',
    );
    if (reason == null || !mounted) return;
    setState(() => _busyCorrections.add(c.id));
    try {
      await _repo.reviewCorrection(c.id, approve: false, reason: reason);
      _afterReview(c, 'Correction rejected.');
    } catch (e) {
      _toast(_errorText(e));
    } finally {
      if (mounted) setState(() => _busyCorrections.remove(c.id));
    }
  }

  void _afterReview(StudentCorrection c, String message) {
    if (!mounted) return;
    setState(() {
      _corrections = [
        for (final x in _corrections ?? const <StudentCorrection>[])
          if (x.id != c.id) x,
      ];
      _correctionIssues.remove(c.id);
    });
    _toast(message);
  }

  // ===================================================================
  // History + legacy tabs
  // ===================================================================

  Future<void> _loadImports() async {
    setState(() => _importsError = null);
    try {
      final list = await _repo.listImports();
      if (mounted) setState(() => _imports = list);
    } catch (e) {
      if (mounted) {
        setState(() {
          _imports = const [];
          _importsError = _errorText(e);
        });
      }
    }
  }

  Widget _historyTab() {
    final list = _imports;
    if (list == null) return _loading();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_importsError != null) _error(_importsError!),
        if (list.isEmpty && _importsError == null)
          const Text('No imports yet.'),
        for (final i in list)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(
                i.fileName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_countsLine(i.counts)}\n'
                '${i.importedByName} · ${_shortDate(i.importedAt)}',
              ),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }

  Future<void> _loadLegacy() async {
    setState(() => _legacyError = null);
    try {
      final list = await _repo.listLegacyNotInRoster();
      if (mounted) setState(() => _legacy = list);
    } catch (e) {
      if (mounted) {
        setState(() {
          _legacy = const [];
          _legacyError = _errorText(e);
        });
      }
    }
  }

  Widget _legacyTab() {
    final list = _legacy;
    if (list == null) return _loading();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Existing student accounts whose School ID is not in the roster.',
        ),
        const SizedBox(height: 8),
        if (_legacyError != null) _error(_legacyError!),
        if (list.isEmpty && _legacyError == null)
          const Text('Every existing student account is in the roster.'),
        for (final s in list)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(
                s.name.isEmpty ? s.userId : s.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(s.schoolId),
            ),
          ),
      ],
    );
  }
}

// =====================================================================
// Dialogs
// =====================================================================

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
  });
  final String title;
  final String body;
  final String confirmLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.body),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLength: 500,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

class _CodesDialog extends StatefulWidget {
  const _CodesDialog({
    required this.title,
    required this.codes,
    required this.showCodes,
    required this.skipped,
    required this.onDownload,
  });
  final String title;
  final List<IssuedActivationCode> codes;
  final bool showCodes;
  final List<({String studentNo, String reason})> skipped;
  final bool Function() onDownload;

  @override
  State<_CodesDialog> createState() => _CodesDialogState();
}

class _CodesDialogState extends State<_CodesDialog> {
  bool _downloaded = false;

  Future<void> _close() async {
    if (!_downloaded && widget.codes.isNotEmpty) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Close without downloading?'),
          content: const Text(codesShownOnceWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Close anyway'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.codes.isEmpty)
            const Text('No codes were issued.')
          else ...[
            Text('${widget.codes.length} code(s) issued.'),
            const SizedBox(height: 8),
            const Text(
              codesShownOnceWarning,
              style: TextStyle(color: AdminColors.danger),
            ),
          ],
          if (widget.showCodes)
            for (final c in widget.codes)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText(
                  '${c.studentNo}: ${c.code}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
          for (final s in widget.skipped)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Skipped ${s.studentNo}: ${s.reason}'),
            ),
        ],
      ),
    ),
    actions: [
      if (widget.codes.isNotEmpty)
        FilledButton.icon(
          onPressed: () {
            if (widget.onDownload()) setState(() => _downloaded = true);
          },
          icon: const Icon(Icons.download),
          label: Text('Download activation slips (${widget.codes.length})'),
        ),
      TextButton(onPressed: _close, child: const Text('Close')),
    ],
  );
}

class _EditRecordDialog extends StatefulWidget {
  const _EditRecordDialog({
    required this.studentNo,
    required this.name,
    required this.college,
    required this.course,
    required this.yearLevel,
  });
  final String studentNo;
  final String name;
  final String college;
  final String course;
  final String yearLevel;

  @override
  State<_EditRecordDialog> createState() => _EditRecordDialogState();
}

class _EditRecordDialogState extends State<_EditRecordDialog> {
  final _surname = TextEditingController();
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _dob = TextEditingController();
  late final _college = TextEditingController(text: widget.college);
  late final _course = TextEditingController(text: widget.course);
  late String _year = _yearLevels.contains(widget.yearLevel)
      ? widget.yearLevel
      : '';
  String? _error;

  @override
  void dispose() {
    for (final c in [_surname, _first, _middle, _dob, _college, _course]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final fields = <String, String>{};
    void put(String key, String value) {
      if (value.trim().isNotEmpty) fields[key] = value.trim();
    }

    put('surname', _surname.text);
    put('firstName', _first.text);
    put('middleName', _middle.text);
    if (_dob.text.trim().isNotEmpty) {
      final key = parseRosterDate(_dob.text);
      if (key == null) {
        setState(() => _error = 'Enter the date as MM/DD/YYYY.');
        return;
      }
      fields['dateOfBirth'] = key;
    }
    put('college', _college.text);
    put('course', _course.text);
    if (_year.isNotEmpty && _year != widget.yearLevel) {
      fields['yearLevel'] = _year;
    }
    Navigator.pop(context, fields);
  }

  Widget _field(TextEditingController c, String label, {String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Edit ${widget.studentNo}'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.name}\nLeave a field blank to keep its current value.',
            ),
            const SizedBox(height: 12),
            _field(_surname, 'Surname'),
            _field(_first, 'First name'),
            _field(_middle, 'Middle name'),
            _field(_dob, 'Date of birth', hint: 'MM/DD/YYYY'),
            _field(_college, 'College'),
            _field(_course, 'Course'),
            DropdownButtonFormField<String>(
              initialValue: _year,
              decoration: const InputDecoration(labelText: 'Year level'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Keep current')),
                for (final y in _yearLevels)
                  DropdownMenuItem(value: y, child: Text(y)),
              ],
              onChanged: (v) => setState(() => _year = v ?? ''),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AdminColors.danger),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
