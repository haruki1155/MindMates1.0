import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../models/academic_import_models.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../services/academic_catalog_parser.dart';
import '../services/admin_import_file_picker.dart';
import '../theme/admin_theme.dart';

/// Most rows one catalogue import may carry (one preview call, one import call).
const catalogImportRowLimit = 1000;

typedef CatalogFilePicker = Future<AdminImportFile?> Function();
typedef CatalogFileParser =
    CatalogParseResult Function(String fileName, List<int> bytes);

/// Builds the wire rows for [sheet] from the administrator's confirmed
/// [mapping]. An unmapped role is ABSENT from every row map; a mapped column
/// whose cell is empty is present as `''`. Values are trimmed.
List<Map<String, String>> buildCatalogRows(
  CatalogSheet sheet,
  Map<CatalogRole, int> mapping,
) => [
  for (final row in sheet.rows)
    {
      for (final entry in mapping.entries)
        entry.key.name: entry.value >= 0 && entry.value < row.length
            ? row[entry.value].trim()
            : '',
    },
];

enum _Step { pick, sheet, mapping, preview, result }

const _roleLabels = <CatalogRole, String>{
  CatalogRole.college: 'College',
  CatalogRole.collegeCode: 'College code',
  CatalogRole.department: 'Department',
  CatalogRole.departmentCode: 'Department code',
  CatalogRole.course: 'Course',
  CatalogRole.courseCode: 'Course code',
};

class AcademicCatalogImportDialog extends StatefulWidget {
  const AcademicCatalogImportDialog({
    super.key,
    required this.repository,
    this.pickFile = pickAdminImportFile,
    this.parseFile = parseCatalogFile,
  });

  final AdminPortalRepository repository;
  final CatalogFilePicker pickFile;
  final CatalogFileParser parseFile;

  @override
  State<AcademicCatalogImportDialog> createState() =>
      _AcademicCatalogImportDialogState();
}

class _AcademicCatalogImportDialogState
    extends State<AcademicCatalogImportDialog> {
  _Step _step = _Step.pick;
  bool _busy = false;
  String? _error;
  String _fileName = '';
  CatalogParseResult? _parsed;
  int _sheetIndex = 0;
  Map<CatalogRole, int> _mapping = {};
  int? _mappedSheetIndex;
  List<Map<String, String>> _rows = const [];
  CatalogPreview? _preview;
  CatalogImportResult? _result;

  CatalogSheet get _sheet => _parsed!.sheets[_sheetIndex];

  bool get _mappingValid =>
      _mapping.containsKey(CatalogRole.college) &&
      _mapping.containsKey(CatalogRole.course);

  bool get _sheetTooLarge => _sheet.rows.length > catalogImportRowLimit;

  /// The backend refuses a row-less file, so there is nothing to continue to.
  bool get _sheetEmpty => _sheet.rows.isEmpty;

  bool get _previewBlocked {
    final p = _preview!;
    return (p.counts['error'] ?? 0) > 0 ||
        p.rows.any((r) => r.kind == CatalogRowKind.error);
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await widget.pickFile();
      if (!mounted) return;
      if (file == null) {
        setState(() => _busy = false);
        return;
      }
      final parsed = widget.parseFile(file.name, file.bytes);
      setState(() {
        _busy = false;
        _fileName = file.name;
        _parsed = parsed;
        _sheetIndex = 0;
        if (parsed.sheets.isEmpty) {
          _error = parsed.fileErrors.isEmpty
              ? 'No readable sheet was found in this file.'
              : parsed.fileErrors.join('\n');
        } else {
          _step = _Step.sheet;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'The file could not be opened.';
      });
    }
  }

  void _toMapping() {
    setState(() {
      // Only re-detect when the sheet changed; keep hand-corrected columns.
      if (_mappedSheetIndex != _sheetIndex) {
        _mapping = Map.of(detectColumns(_sheet.headers));
        _mappedSheetIndex = _sheetIndex;
      }
      _error = null;
      _step = _Step.mapping;
    });
  }

  Future<void> _runPreview() async {
    final rows = buildCatalogRows(_sheet, _mapping);
    setState(() {
      _busy = true;
      _error = null;
      _rows = rows;
    });
    try {
      final preview = await widget.repository.previewCatalogImport(
        fileName: _fileName,
        sheetName: _sheet.name,
        rows: rows,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _preview = preview;
        _step = _Step.preview;
      });
    } on FirebaseFunctionsException catch (e) {
      // A refusal the server explained is shown as it stands: telling the
      // administrator to retry a file the backend will never accept is worse
      // than saying what is wrong with it.
      if (!mounted) return;
      final explained = (e.message ?? '').trim();
      setState(() {
        _busy = false;
        _error = explained.isEmpty ? _previewFailed : explained;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _previewFailed;
      });
    }
  }

  static const _previewFailed =
      'The preview could not be generated. Please try again.';

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.importCatalog(
        fileName: _fileName,
        sheetName: _sheet.name,
        rows: _rows,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
        _step = _Step.result;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final rejected =
          e.code == 'invalid-argument' && (e.message ?? '').isNotEmpty;
      setState(() {
        _busy = false;
        _error = rejected ? e.message : _partialWriteWarning;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _partialWriteWarning;
      });
    }
  }

  static const _partialWriteWarning =
      'The import did not finish. Some records may already have been '
      'created; preview the file again to see what is still missing.';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AdminColors.surface,
      title: const Text('Import catalogue'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._body(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AdminColors.danger),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
      actions: _actions(),
    );
  }

  List<Widget> _body() => switch (_step) {
    _Step.pick => [
      const Text(
        'Upload a .xlsx or .csv file with College and Course columns. '
        'Department and the code columns are optional.',
      ),
    ],
    _Step.sheet => _sheetBody(),
    _Step.mapping => _mappingBody(),
    _Step.preview => _previewBody(),
    _Step.result => _resultBody(),
  };

  List<Widget> _sheetBody() {
    final parsed = _parsed!;
    final n = parsed.sheets.length;
    return [
      Text(
        n == 1 ? '1 sheet was found.' : '$n sheets were found.',
        style: const TextStyle(color: AdminColors.ink),
      ),
      if (parsed.fileErrors.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final e in parsed.fileErrors)
          Text(e, style: const TextStyle(color: AdminColors.danger)),
      ],
      const SizedBox(height: 8),
      RadioGroup<int>(
        groupValue: _sheetIndex,
        onChanged: (v) => setState(() => _sheetIndex = v ?? 0),
        child: Column(
          children: [
            for (var i = 0; i < n; i++)
              RadioListTile<int>(
                value: i,
                title: Text(parsed.sheets[i].name),
                subtitle: Text('${parsed.sheets[i].rows.length} rows'),
              ),
          ],
        ),
      ),
      if (_sheetTooLarge)
        Text(
          'This sheet has ${_sheet.rows.length} rows. A single import is '
          'limited to $catalogImportRowLimit rows; split the file and import '
          'it in parts.',
          style: const TextStyle(color: AdminColors.danger),
        ),
      if (_sheetEmpty)
        const Text(
          'This sheet has no data rows.',
          style: TextStyle(color: AdminColors.danger),
        ),
    ];
  }

  String _sample(int column) {
    for (final row in _sheet.rows) {
      if (column < row.length && row[column].trim().isNotEmpty) {
        return row[column].trim();
      }
    }
    return '';
  }

  List<Widget> _mappingBody() => [
    const Text(
      'Confirm which column is which. College and Course are required.',
    ),
    const SizedBox(height: 8),
    for (final role in CatalogRole.values)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(
                role == CatalogRole.college || role == CatalogRole.course
                    ? '${_roleLabels[role]!} *'
                    : _roleLabels[role]!,
              ),
            ),
            Expanded(
              child: DropdownButton<int>(
                key: ValueKey('map-${role.name}'),
                isExpanded: true,
                value: _mapping[role] ?? -1,
                items: [
                  const DropdownMenuItem(value: -1, child: Text('Not in file')),
                  for (var i = 0; i < _sheet.headers.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        _sheet.headers[i].isEmpty
                            ? 'Column ${i + 1}'
                            : _sheet.headers[i],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  if (v == null || v < 0) {
                    _mapping.remove(role);
                    return;
                  }
                  // One column can only mean one thing: two roles sharing a
                  // column would name a department after every course, or make
                  // a code the course name, and the preview would call it
                  // Create with nothing to flag.
                  _mapping.removeWhere((other, column) => column == v);
                  _mapping[role] = v;
                }),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              child: Text(
                _mapping.containsKey(role)
                    ? 'e.g. ${_sample(_mapping[role]!)}'
                    : '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AdminColors.muted),
              ),
            ),
          ],
        ),
      ),
    if (!_mapping.containsKey(CatalogRole.department))
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Without a Department column, one department per college is '
          'created, named after the college.',
          style: TextStyle(color: AdminColors.muted),
        ),
      ),
  ];

  List<Widget> _previewBody() {
    final preview = _preview!;
    final errorRows = preview.rows
        .where((r) => r.kind == CatalogRowKind.error)
        .length;
    final errors = (preview.counts['error'] ?? 0) > errorRows
        ? preview.counts['error']!
        : errorRows;
    return [
      if (_previewBlocked)
        Text(
          '$errors row(s) have errors. Fix the file and upload it again; '
          'nothing is imported while any row has an error.',
          style: const TextStyle(color: AdminColors.danger),
        )
      else
        Text(
          'Will create ${preview.counts['colleges'] ?? 0} college(s), '
          '${preview.counts['departments'] ?? 0} department(s) and '
          '${preview.counts['courses'] ?? 0} course(s). '
          '${preview.counts['exists'] ?? 0} row(s) already exist and will '
          'be skipped.',
        ),
      const SizedBox(height: 8),
      for (final row in preview.rows) _previewRow(row),
    ];
  }

  /// The true 1-based row of the source file; falls back to the position
  /// below a header on row 1 when the parser supplied none.
  int _fileRow(int index) {
    final source = _sheet.sourceRows;
    return index >= 0 && index < source.length ? source[index] : index + 2;
  }

  Widget _previewRow(CatalogRowResult row) {
    final (label, color) = switch (row.kind) {
      CatalogRowKind.create => ('Create', AdminColors.success),
      CatalogRowKind.exists => ('Exists', AdminColors.muted),
      CatalogRowKind.error => ('Error', AdminColors.danger),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AdminColors.surfaceMuted,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Row ${_fileRow(row.index)} of the file - $label',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          for (final e in row.errors)
            Text(e, style: const TextStyle(color: AdminColors.danger)),
          for (final w in row.warnings)
            Text(w, style: const TextStyle(color: AdminColors.accentStrong)),
          if (row.inventedDepartment != null)
            Text(
              'No department in the file: "${row.inventedDepartment}" will be '
              'created for this college.',
              style: const TextStyle(color: AdminColors.muted),
            ),
        ],
      ),
    );
  }

  List<Widget> _resultBody() {
    final r = _result!;
    final counts =
        '${r.counts['colleges'] ?? 0} college(s), '
        '${r.counts['departments'] ?? 0} department(s) and '
        '${r.counts['courses'] ?? 0} course(s)';
    if (r.isPartial) {
      return [
        const Text(
          'Import incomplete',
          style: TextStyle(
            color: AdminColors.danger,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (r.message != null) Text(r.message!),
        const SizedBox(height: 8),
        Text('Created before it stopped: $counts.'),
      ];
    }
    return [
      const Text(
        'Import complete',
        style: TextStyle(
          color: AdminColors.success,
          fontWeight: FontWeight.w600,
        ),
      ),
      Text('Created $counts.'),
    ];
  }

  List<Widget> _actions() {
    void close() => Navigator.of(context).pop();
    switch (_step) {
      case _Step.pick:
        return [
          TextButton(
            onPressed: _busy ? null : close,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _pick,
            child: const Text('Choose file'),
          ),
        ];
      case _Step.sheet:
        return [
          TextButton(onPressed: close, child: const Text('Cancel')),
          FilledButton(
            onPressed: _sheetTooLarge || _sheetEmpty ? null : _toMapping,
            child: const Text('Continue'),
          ),
        ];
      case _Step.mapping:
        return [
          TextButton(
            onPressed: _busy ? null : () => setState(() => _step = _Step.sheet),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: _mappingValid && !_busy ? _runPreview : null,
            child: const Text('Continue'),
          ),
        ];
      case _Step.preview:
        return [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _step = _Step.mapping),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: _previewBlocked || _busy ? null : _import,
            child: const Text('Import'),
          ),
        ];
      case _Step.result:
        return [FilledButton(onPressed: close, child: const Text('Done'))];
    }
  }
}
