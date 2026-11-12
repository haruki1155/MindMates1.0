import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel_plus/excel_plus.dart' as excel;

import '../../../models/student_roster_models.dart';

/// Header row of the downloadable roster template (also the expected import
/// columns).
const rosterTemplateHeaders = [
  'Student No.',
  'Surname',
  'First Name',
  'Middle Name',
  'Date of Birth (MM/DD/YYYY)',
  'College',
  'Course',
  'Year Level',
];

/// Wire keys for [rosterTemplateHeaders], in the same order.
const _fieldKeys = [
  'studentNo',
  'surname',
  'firstName',
  'middleName',
  'dateOfBirth',
  'college',
  'course',
  'yearLevel',
];

const rosterChunkSize = 1000;

class RosterParseResult {
  const RosterParseResult({
    required this.rows,
    required this.fileErrors,
    required this.duplicateStudentNos,
  });

  /// Rows keyed by wire field name; blank rows are skipped.
  final List<Map<String, String>> rows;
  final List<String> fileErrors;

  /// Canonical Student No. -> 1-based spreadsheet row numbers (header is row
  /// 1) for every Student No. that appears more than once in the whole file.
  final Map<String, List<int>> duplicateStudentNos;

  bool get hasBlockingProblems =>
      fileErrors.isNotEmpty || duplicateStudentNos.isNotEmpty || rows.isEmpty;
}

RosterParseResult _failure(String message) => RosterParseResult(
  rows: const [],
  fileErrors: [message],
  duplicateStudentNos: const {},
);

String _normalizeHeader(String header) =>
    header.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Maps a normalized header to a wire key. The date header is also accepted
/// without its format hint.
final Map<String, String> _headerLookup = {
  for (var i = 0; i < rosterTemplateHeaders.length; i++)
    _normalizeHeader(rosterTemplateHeaders[i]): _fieldKeys[i],
  'date of birth': 'dateOfBirth',
  'student no': 'studentNo',
  'student number': 'studentNo',
};

/// Mirrors the server's canonical Student No. (uppercase, alphanumerics only)
/// so duplicates are caught across the whole file before chunking.
String _canonicalStudentNo(String value) =>
    value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

RosterParseResult parseRosterFile(String fileName, List<int> bytes) {
  final lower = fileName.toLowerCase();
  List<List<Object?>> grid;
  var date1904 = false;
  try {
    if (lower.endsWith('.csv')) {
      grid = _parseCsv(utf8.decode(bytes, allowMalformed: true));
    } else if (lower.endsWith('.xlsx')) {
      date1904 = workbookUses1904(bytes);
      final book = excel.Excel.decodeBytes(bytes);
      final sheet = book.tables.values.firstOrNull;
      grid = sheet == null
          ? const []
          : [
              for (final row in sheet.rows)
                [for (final cell in row) _cellObject(cell?.value)],
            ];
    } else {
      return _failure('Upload a .xlsx or .csv file.');
    }
  } catch (_) {
    return _failure(
      'The file could not be read. Check that it is a valid '
      '${lower.endsWith('.csv') ? 'CSV' : 'Excel'} file.',
    );
  }
  if (grid.isEmpty) return _failure('The file is empty.');

  final headerIndex = <String, int>{};
  final headerRow = grid.first;
  for (var c = 0; c < headerRow.length; c++) {
    final key = _headerLookup[_normalizeHeader(_text(headerRow[c]))];
    if (key != null) headerIndex.putIfAbsent(key, () => c);
  }
  final missing = [
    for (var i = 0; i < _fieldKeys.length; i++)
      if (!headerIndex.containsKey(_fieldKeys[i])) rosterTemplateHeaders[i],
  ];
  if (missing.isNotEmpty) {
    return _failure(
      'Missing column${missing.length == 1 ? '' : 's'}: '
      '${missing.join(', ')}.',
    );
  }

  final rows = <Map<String, String>>[];
  final seen = <String, List<int>>{};
  for (var r = 1; r < grid.length; r++) {
    final cells = grid[r];
    Object? cell(String key) {
      final c = headerIndex[key]!;
      return c < cells.length ? cells[c] : null;
    }

    if (_fieldKeys.every((k) => _text(cell(k)).trim().isEmpty)) continue;
    final row = <String, String>{};
    for (final key in _fieldKeys) {
      final raw = cell(key);
      if (key == 'dateOfBirth') {
        row[key] =
            parseRosterDate(raw, date1904: date1904) ?? _text(raw).trim();
      } else {
        row[key] = _text(raw).trim();
      }
    }
    rows.add(row);
    final canonical = _canonicalStudentNo(row['studentNo']!);
    if (canonical.isNotEmpty) {
      seen.putIfAbsent(canonical, () => []).add(r + 1);
    }
  }
  return RosterParseResult(
    rows: rows,
    fileErrors: [if (rows.isEmpty) 'The file has no student rows.'],
    duplicateStudentNos: {
      for (final e in seen.entries)
        if (e.value.length > 1) e.key: e.value,
    },
  );
}

Object? _cellObject(excel.CellValue? value) => switch (value) {
  null => null,
  excel.TextCellValue() => value.value.toString(),
  excel.IntCellValue() => value.value,
  excel.DoubleCellValue() => value.value,
  excel.DateCellValue() => value,
  excel.DateTimeCellValue() => value,
  _ => value.toString(),
};

String _text(Object? value) => switch (value) {
  null => '',
  String() => value,
  int() => value.toString(),
  double() =>
    value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toString(),
  excel.TextCellValue() => value.value.toString(),
  _ => value.toString(),
};

/// Minimal RFC-4180 parser: quoted fields, doubled quotes, CRLF/LF/CR, BOM.
List<List<Object?>> _parseCsv(String input) {
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final rows = <List<Object?>>[];
  var row = <Object?>[];
  final field = StringBuffer();
  var inQuotes = false;
  var touched = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <Object?>[];
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

/// Converts a spreadsheet date cell to `YYYY-MM-DD`, or null when it cannot be
/// read. Accepts DateTime, excel_plus date cells, Excel serial numbers,
/// `MM/DD/YYYY` and `YYYY-MM-DD` text. When [date1904] is set, serials are
/// read in the 1904 system and DateTimes decoded with the 1900 epoch are
/// shifted forward by 1,462 days.
String? parseRosterDate(Object? cell, {bool date1904 = false}) {
  const shift = Duration(days: 1462);
  switch (cell) {
    case null:
      return null;
    case excel.DateCellValue():
      return _fromDate(
        DateTime.utc(cell.year, cell.month, cell.day),
        date1904 ? shift : Duration.zero,
      );
    case excel.DateTimeCellValue():
      return _fromDate(
        DateTime.utc(cell.year, cell.month, cell.day),
        date1904 ? shift : Duration.zero,
      );
    case DateTime():
      return _fromDate(
        DateTime.utc(cell.year, cell.month, cell.day),
        date1904 ? shift : Duration.zero,
      );
    case excel.IntCellValue():
      return parseRosterDate(cell.value, date1904: date1904);
    case excel.DoubleCellValue():
      return parseRosterDate(cell.value, date1904: date1904);
    case excel.TextCellValue():
      return parseRosterDate(cell.value.toString(), date1904: date1904);
    case num():
      if (!cell.isFinite || cell < 1 || cell > 2958465) return null;
      final epoch = date1904
          ? DateTime.utc(1904, 1, 1)
          : DateTime.utc(1899, 12, 30);
      return _fromDate(epoch.add(Duration(days: cell.floor())), Duration.zero);
    case String():
      final text = cell.trim();
      final us = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
      if (us != null) {
        return _validated(
          int.parse(us.group(3)!),
          int.parse(us.group(1)!),
          int.parse(us.group(2)!),
        );
      }
      final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
      if (iso != null) {
        return _validated(
          int.parse(iso.group(1)!),
          int.parse(iso.group(2)!),
          int.parse(iso.group(3)!),
        );
      }
      return null;
    default:
      return null;
  }
}

String? _validated(int year, int month, int day) {
  if (year < 1000) return null;
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return _key(date);
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String? _fromDate(DateTime utc, Duration shift) => _key(utc.add(shift));

/// True when the workbook declares `<workbookPr date1904="1"/>`.
bool workbookUses1904(List<int> xlsxBytes) {
  try {
    final archive = ZipDecoder().decodeBytes(xlsxBytes);
    final file = archive.findFile('xl/workbook.xml');
    if (file == null) return false;
    final xml = utf8.decode(file.content, allowMalformed: true);
    final tag = RegExp(
      r'<(?:\w+:)?workbookPr\b[^>]*>',
    ).firstMatch(xml)?.group(0);
    if (tag == null) return false;
    final attr = RegExp(
      r'''\bdate1904\s*=\s*["']([^"']*)["']''',
    ).firstMatch(tag)?.group(1);
    return attr == '1' || attr?.toLowerCase() == 'true';
  } catch (_) {
    return false;
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `2005-02-03` -> `Feb 3, 2005`; anything unparseable is returned as is.
String spelledDate(String dateKey) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateKey);
  if (m == null) return dateKey;
  final month = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return dateKey;
  return '${_months[month - 1]} ${int.parse(m.group(3)!)}, ${m.group(1)}';
}

const slipHeaders = [
  'Student No.',
  'Name',
  'College',
  'Course',
  'Year Level',
  'Activation Code',
  'Expires',
];

List<int> buildActivationSlipsXlsx(List<IssuedActivationCode> codes) {
  final book = excel.Excel.createExcel();
  final sheet = book[book.getDefaultSheet() ?? 'Sheet1'];
  sheet.appendRow([for (final h in slipHeaders) excel.TextCellValue(h)]);
  for (final c in codes) {
    final expires = c.expiresAt.toUtc();
    sheet.appendRow([
      excel.TextCellValue(c.studentNo),
      excel.TextCellValue(c.name),
      excel.TextCellValue(c.college),
      excel.TextCellValue(c.course),
      excel.TextCellValue(c.yearLevel),
      excel.TextCellValue(c.code),
      excel.TextCellValue(spelledDate(_key(expires))),
    ]);
  }
  return book.encode() ?? const [];
}

/// Builds the blank template workbook (header row only).
List<int> buildRosterTemplateXlsx() {
  final book = excel.Excel.createExcel();
  final sheet = book[book.getDefaultSheet() ?? 'Sheet1'];
  sheet.appendRow([
    for (final h in rosterTemplateHeaders) excel.TextCellValue(h),
  ]);
  return book.encode() ?? const [];
}

List<List<Map<String, String>>> chunkRows(
  List<Map<String, String>> rows, {
  int size = rosterChunkSize,
}) => [
  for (var i = 0; i < rows.length; i += size)
    rows.sublist(i, i + size > rows.length ? rows.length : i + size),
];
