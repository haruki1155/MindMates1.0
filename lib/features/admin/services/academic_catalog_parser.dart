import 'dart:convert';

import 'package:excel_plus/excel_plus.dart' as excel;

/// The columns an academic catalogue file may carry.
enum CatalogRole {
  college,
  collegeCode,
  department,
  departmentCode,
  course,
  courseCode,
}

/// One sheet of a catalogue file: its header row and the non-blank rows below
/// it. Every row has exactly `headers.length` cells; values are trimmed text.
class CatalogSheet {
  const CatalogSheet({
    required this.name,
    required this.headers,
    required this.rows,
  });

  final String name;
  final List<String> headers;
  final List<List<String>> rows;
}

class CatalogParseResult {
  const CatalogParseResult({required this.sheets, required this.fileErrors});

  final List<CatalogSheet> sheets;
  final List<String> fileErrors;
}

/// Header row of the downloadable catalogue template.
const catalogTemplateHeaders = <String>[
  'College',
  'College Code',
  'Department',
  'Department Code',
  'Course',
  'Course Code',
];

/// How many leading rows are searched for the header row.
const _headerSearchDepth = 20;

CatalogParseResult _failure(String message) =>
    CatalogParseResult(sheets: const [], fileErrors: [message]);

/// Reads every sheet of an .xlsx workbook, or a .csv as a single sheet.
/// Nothing is dropped silently: a sheet without a recognisable header row is
/// reported in `fileErrors` by name.
CatalogParseResult parseCatalogFile(String fileName, List<int> bytes) {
  final lower = fileName.toLowerCase();
  final isCsv = lower.endsWith('.csv');
  if (!isCsv && !lower.endsWith('.xlsx')) {
    return _failure('Upload a .xlsx or .csv file.');
  }
  if (bytes.isEmpty) return _failure('The file is empty.');

  final grids = <String, List<List<String>>>{};
  try {
    if (isCsv) {
      grids[fileName] = _parseCsv(utf8.decode(bytes, allowMalformed: true));
    } else {
      final book = excel.Excel.decodeBytes(bytes);
      for (final entry in book.tables.entries) {
        grids[entry.key] = [
          for (final row in entry.value.rows)
            [for (final cell in row) _cellText(cell?.value)],
        ];
      }
    }
  } catch (_) {
    return _failure(
      'The file could not be read. Check that it is a valid '
      '${isCsv ? 'CSV' : 'Excel'} file.',
    );
  }
  if (grids.isEmpty) return _failure('The file has no sheets.');

  final sheets = <CatalogSheet>[];
  final errors = <String>[];
  final expected = catalogTemplateHeaders.join(', ');
  for (final entry in grids.entries) {
    final sheet = _buildSheet(entry.key, entry.value);
    if (sheet != null) {
      sheets.add(sheet);
    } else {
      errors.add(
        isCsv
            ? 'No header row found. Expect columns such as $expected.'
            : 'Sheet "${entry.key}": no header row found. Expect columns '
                  'such as $expected.',
      );
    }
  }
  return CatalogParseResult(sheets: sheets, fileErrors: errors);
}

CatalogSheet? _buildSheet(String name, List<List<String>> grid) {
  // The header is the row, among the first few, with the most EXACT synonym
  // matches (a title or data row such as "Course Offerings" must not win on a
  // prefix match); the earliest wins a tie. Prefix matching only applies when
  // mapping columns of the chosen row.
  var headerAt = -1;
  var best = 0;
  for (var r = 0; r < grid.length && r < _headerSearchDepth; r++) {
    final found = _detect(grid[r], allowPrefix: false).length;
    if (found > best) {
      best = found;
      headerAt = r;
    }
  }
  if (headerAt < 0) return null;

  final body = [
    for (var r = headerAt + 1; r < grid.length; r++)
      if (grid[r].any((c) => c.isNotEmpty)) grid[r],
  ];
  var width = grid[headerAt].length;
  for (final row in body) {
    if (row.length > width) width = row.length;
  }
  List<String> pad(List<String> row) => [
    ...row,
    for (var i = row.length; i < width; i++) '',
  ];
  return CatalogSheet(
    name: name,
    headers: pad(grid[headerAt]),
    rows: [for (final row in body) pad(row)],
  );
}

String _normalize(String header) =>
    header.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

const _synonyms = <CatalogRole, List<String>>{
  CatalogRole.college: ['college', 'college name'],
  CatalogRole.collegeCode: ['college code'],
  CatalogRole.department: ['department', 'department name', 'dept'],
  CatalogRole.departmentCode: ['department code', 'dept code'],
  CatalogRole.course: ['course', 'course name', 'program', 'program name'],
  CatalogRole.courseCode: ['course code', 'program code'],
};

/// Guesses which column holds which role from header text alone; cell values
/// are never consulted. Each column and each role is used at most once, and an
/// exact match is preferred to a prefix match (`Course Code (optional)`).
/// Headers that cannot be placed are simply absent from the result.
Map<CatalogRole, int> detectColumns(List<String> headers) =>
    _detect(headers, allowPrefix: true);

Map<CatalogRole, int> _detect(
  List<String> headers, {
  required bool allowPrefix,
}) {
  final normalized = [for (final h in headers) _normalize(h)];
  final result = <CatalogRole, int>{};
  final usedColumns = <int>{};

  for (final role in CatalogRole.values) {
    for (var c = 0; c < normalized.length; c++) {
      if (usedColumns.contains(c)) continue;
      if (_synonyms[role]!.contains(normalized[c])) {
        result[role] = c;
        usedColumns.add(c);
        break;
      }
    }
  }

  // Prefix pass: a column takes the free role whose longest synonym begins its
  // header at a word boundary.
  if (!allowPrefix) return result;
  final wordChar = RegExp(r'[a-z0-9]');
  for (var c = 0; c < normalized.length; c++) {
    if (usedColumns.contains(c)) continue;
    final h = normalized[c];
    CatalogRole? pick;
    var pickLength = 0;
    for (final role in CatalogRole.values) {
      if (result.containsKey(role)) continue;
      for (final synonym in _synonyms[role]!) {
        final boundary =
            h.length > synonym.length &&
            h.startsWith(synonym) &&
            !wordChar.hasMatch(h[synonym.length]);
        if (boundary && synonym.length > pickLength) {
          pick = role;
          pickLength = synonym.length;
        }
      }
    }
    if (pick != null) {
      result[pick] = c;
      usedColumns.add(c);
    }
  }
  return result;
}

String _cellText(excel.CellValue? value) => switch (value) {
  null => '',
  excel.TextCellValue() => value.value.toString().trim(),
  excel.IntCellValue() => value.value.toString(),
  excel.DoubleCellValue() =>
    value.value == value.value.truncateToDouble()
        ? value.value.toInt().toString()
        : value.value.toString(),
  _ => value.toString().trim(),
};

/// Minimal RFC-4180 parser: quoted fields, doubled quotes, CRLF/LF/CR, BOM.
/// Cells are trimmed.
List<List<String>> _parseCsv(String input) {
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var touched = false;

  void endField() {
    row.add(field.toString().trim());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
    touched = false;
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
      continue;
    }
    switch (ch) {
      case '"':
        inQuotes = true;
        touched = true;
      case ',':
        endField();
        touched = true;
      case '\r':
        if (i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
      case '\n':
        endRow();
      default:
        field.write(ch);
        touched = true;
    }
  }
  if (touched || field.isNotEmpty) endRow();
  return rows;
}
