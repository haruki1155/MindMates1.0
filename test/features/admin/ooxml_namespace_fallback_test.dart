import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:excel_plus/excel_plus.dart' as excel;
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/services/academic_catalog_parser.dart';
import 'package:mind_mates/features/admin/services/student_roster_file_parser.dart';

/// Inverse of the fix: rewrites every `.xml`/`.rels` entry so each element
/// carries the `x:` prefix, as some non-Excel writers emit.
List<int> _prefixed(List<int> xlsx) {
  final src = ZipDecoder().decodeBytes(xlsx);
  final out = Archive();
  for (final f in src.files) {
    if (!f.isFile) continue;
    var content = f.content as List<int>;
    if (f.name.endsWith('.xml') || f.name.endsWith('.rels')) {
      final text = utf8
          .decode(content)
          .replaceAllMapped(
            RegExp(r'<(/?)(?![\w.-]*:)([A-Za-z_][\w.-]*)'),
            (m) => '<${m[1]}x:${m[2]}',
          )
          .replaceAll(' xmlns="', ' xmlns:x="');
      content = utf8.encode(text);
    }
    out.addFile(ArchiveFile(f.name, content.length, content));
  }
  return ZipEncoder().encode(out);
}

List<int> _book(List<List<String>> rows) {
  final book = excel.Excel.createExcel();
  final sheet = book[book.getDefaultSheet() ?? 'Sheet1'];
  for (final r in rows) {
    sheet.appendRow([for (final v in r) excel.TextCellValue(v)]);
  }
  return book.encode()!;
}

final _rosterRows = [
  rosterTemplateHeaders,
  ['2021-001', 'Santos', 'Ana', '', '02/15/2005', 'CITE', 'BSIT', '1'],
  ['2021-002', 'Cruz', 'Ben', '', '03/01/2004', 'CITE', 'BSIT', '2'],
];

final _catalogRows = [
  ['College', 'Course'],
  ['Engineering', 'BSCE'],
  ['Nursing', 'BSN'],
];

void main() {
  test('fixture really is prefixed and breaks plain excel_plus', () {
    final bytes = _prefixed(_book(_catalogRows));
    final wb = utf8.decode(
      ZipDecoder().decodeBytes(bytes).findFile('xl/workbook.xml')!.content,
    );
    expect(wb, contains('<x:sheet '));
    expect(
      () => excel.Excel.decodeBytes(bytes).tables,
      throwsA(isA<Exception>()),
    );
  });

  group('parseRosterFile', () {
    test('reads a namespace-prefixed workbook with values intact', () {
      final result = parseRosterFile('r.xlsx', _prefixed(_book(_rosterRows)));
      expect(result.fileErrors, isEmpty);
      expect(result.rows, hasLength(2));
      expect(result.rows.first['studentNo'], '2021-001');
      expect(result.rows.first['surname'], 'Santos');
      expect(result.rows.first['dateOfBirth'], '2005-02-15');
      expect(result.rows.last['firstName'], 'Ben');
      expect(result.rows.last['yearLevel'], '2');
    });

    test('plain workbook parses as before', () {
      final result = parseRosterFile('r.xlsx', _book(_rosterRows));
      expect(result.fileErrors, isEmpty);
      expect(result.rows.map((r) => r['surname']), ['Santos', 'Cruz']);
    });

    test('csv is unaffected', () {
      final csv = _rosterRows.map((r) => r.join(',')).join('\n');
      final result = parseRosterFile('r.csv', utf8.encode(csv));
      expect(result.fileErrors, isEmpty);
      expect(result.rows, hasLength(2));
    });

    test('non-zip bytes still report the unreadable-file error', () {
      final rnd = Random(7);
      final result = parseRosterFile(
        'r.xlsx',
        List<int>.generate(300, (_) => rnd.nextInt(256)),
      );
      expect(result.fileErrors, [
        'The file could not be read. Check that it is a valid Excel file.',
      ]);
    });
  });

  group('parseCatalogFile', () {
    test('reads a namespace-prefixed workbook with values intact', () {
      final result = parseCatalogFile(
        'c.xlsx',
        _prefixed(_book(_catalogRows)),
      );
      expect(result.fileErrors, isEmpty);
      expect(result.sheets.single.headers, ['College', 'Course']);
      expect(result.sheets.single.rows, [
        ['Engineering', 'BSCE'],
        ['Nursing', 'BSN'],
      ]);
    });

    test('plain workbook parses as before', () {
      final result = parseCatalogFile('c.xlsx', _book(_catalogRows));
      expect(result.fileErrors, isEmpty);
      expect(result.sheets.single.rows.first, ['Engineering', 'BSCE']);
    });

    test('csv is unaffected', () {
      final result = parseCatalogFile(
        'c.csv',
        utf8.encode('College,Course\nEngineering,BSCE\n'),
      );
      expect(result.fileErrors, isEmpty);
      expect(result.sheets.single.rows, [
        ['Engineering', 'BSCE'],
      ]);
    });

    test('non-zip bytes still report the unreadable-file error', () {
      final rnd = Random(7);
      final result = parseCatalogFile(
        'c.xlsx',
        List<int>.generate(300, (_) => rnd.nextInt(256)),
      );
      expect(result.fileErrors, [
        'The file could not be read. Check that it is a valid Excel file.',
      ]);
    });
  });
}
