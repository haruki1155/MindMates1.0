import 'dart:convert';

import 'package:excel_plus/excel_plus.dart' as excel;
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/services/academic_catalog_parser.dart';

List<int> _xlsx(Map<String, List<List<Object?>>> sheets) {
  final book = excel.Excel.createExcel();
  var first = true;
  for (final entry in sheets.entries) {
    if (first) {
      book.rename(book.getDefaultSheet() ?? 'Sheet1', entry.key);
      first = false;
    }
    final sheet = book[entry.key];
    for (final row in entry.value) {
      sheet.appendRow([
        for (final v in row)
          v == null
              ? null
              : v is int
              ? excel.IntCellValue(v)
              : excel.TextCellValue(v.toString()),
      ]);
    }
  }
  return book.encode()!;
}

List<int> _csv(String text) => utf8.encode(text);

void main() {
  group('parseCatalogFile', () {
    test('returns every sheet of a workbook, named, in order', () {
      final result = parseCatalogFile(
        'cat.xlsx',
        _xlsx({
          'Alpha': [
            ['College', 'Course'],
            ['Engineering', 'BSCE'],
          ],
          'Beta': [
            ['College', 'Course'],
            ['Nursing', 'BSN'],
          ],
          'Gamma': [
            ['College', 'Course'],
            ['Arts', 'AB'],
          ],
        }),
      );
      expect(result.fileErrors, isEmpty);
      expect(result.sheets.map((s) => s.name), ['Alpha', 'Beta', 'Gamma']);
      expect(result.sheets[1].rows, [
        ['Nursing', 'BSN'],
      ]);
      expect(result.sheets[2].headers, ['College', 'Course']);
    });

    test('a csv is exactly one sheet, with quotes and BOM handled', () {
      final result = parseCatalogFile(
        'cat.csv',
        _csv('\uFEFFCollege,Course\r\n"Arts, Letters","Say ""hi""\nthere"\r\n'),
      );
      expect(result.fileErrors, isEmpty);
      expect(result.sheets, hasLength(1));
      expect(result.sheets.single.headers, ['College', 'Course']);
      expect(result.sheets.single.rows, [
        ['Arts, Letters', 'Say "hi"\nthere'],
      ]);
    });

    test('finds the header row below blank rows', () {
      final result = parseCatalogFile(
        'cat.csv',
        _csv(',\n\nCollege,Department,Course\nEng,Civil,BSCE\n'),
      );
      expect(result.fileErrors, isEmpty);
      expect(result.sheets.single.headers, ['College', 'Department', 'Course']);
      expect(result.sheets.single.rows, [
        ['Eng', 'Civil', 'BSCE'],
      ]);
    });

    test('no recognisable header row is a file error', () {
      final result = parseCatalogFile('cat.csv', _csv('foo,bar\n1,2\n'));
      expect(result.sheets, isEmpty);
      expect(result.fileErrors, hasLength(1));
      expect(result.fileErrors.single.toLowerCase(), contains('header'));
    });

    test('an unusable sheet is reported by name, not silently dropped', () {
      final result = parseCatalogFile(
        'cat.xlsx',
        _xlsx({
          'Good': [
            ['College'],
            ['Eng'],
          ],
          'Notes': [
            ['hello'],
          ],
        }),
      );
      expect(result.sheets.map((s) => s.name), ['Good']);
      expect(result.fileErrors.single, contains('Notes'));
    });

    test('headers without data rows give a sheet with empty rows', () {
      final result = parseCatalogFile('cat.csv', _csv('College,Course\n'));
      expect(result.fileErrors, isEmpty);
      expect(result.sheets.single.rows, isEmpty);
    });

    test('a title row above a lone Course header is not the header', () {
      final result = parseCatalogFile(
        'cat.csv',
        _csv('Course Offerings 2026\nCourse\nBSCE\nBSN\n'),
      );
      expect(result.fileErrors, isEmpty);
      expect(result.sheets.single.headers, ['Course']);
      expect(result.sheets.single.rows, [
        ['BSCE'],
        ['BSN'],
      ]);
    });

    test('an xlsx title row above the header is discarded', () {
      final result = parseCatalogFile(
        'cat.xlsx',
        _xlsx({
          'S': [
            ['College of Engineering'],
            ['College', 'Course'],
            ['Eng', 'BSCE'],
          ],
        }),
      );
      expect(result.fileErrors, isEmpty);
      expect(result.sheets.single.headers, ['College', 'Course']);
      expect(result.sheets.single.rows, [
        ['Eng', 'BSCE'],
      ]);
    });

    test('an xlsx header at a non-first row is found', () {
      final result = parseCatalogFile(
        'cat.xlsx',
        _xlsx({
          'S': [
            [null],
            [null],
            ['Course'],
            ['BSCE'],
          ],
        }),
      );
      expect(result.fileErrors, isEmpty);
      expect(result.sheets.single.headers, ['Course']);
      expect(result.sheets.single.rows, [
        ['BSCE'],
      ]);
    });

    test('a data row containing College of Arts never beats the header', () {
      final result = parseCatalogFile(
        'cat.csv',
        _csv('Course\nCollege of Arts\nBSN\n'),
      );
      expect(result.sheets.single.headers, ['Course']);
      expect(result.sheets.single.rows, [
        ['College of Arts'],
        ['BSN'],
      ]);
    });

    test('a CR-only line ending is read', () {
      final result = parseCatalogFile(
        'cat.csv',
        _csv('College,Course\rEng,BSCE\r'),
      );
      expect(result.sheets.single.rows, [
        ['Eng', 'BSCE'],
      ]);
    });

    test('an empty sheet in a workbook is reported by name', () {
      final result = parseCatalogFile(
        'cat.xlsx',
        _xlsx({
          'Good': [
            ['College'],
            ['Eng'],
          ],
          'Empty': <List<Object?>>[],
        }),
      );
      expect(result.sheets.map((s) => s.name), ['Good']);
      expect(result.fileErrors.single, contains('Empty'));
    });

    test('a header-only xlsx gives a sheet with empty rows', () {
      final result = parseCatalogFile(
        'cat.xlsx',
        _xlsx({
          'S': [
            ['College', 'Course'],
          ],
        }),
      );
      expect(result.fileErrors, isEmpty);
      expect(result.sheets.single.rows, isEmpty);
    });

    test('a zero-byte file is a file error', () {
      expect(parseCatalogFile('cat.csv', []).fileErrors, isNotEmpty);
      expect(parseCatalogFile('cat.xlsx', []).fileErrors, isNotEmpty);
    });

    test('unsupported extension and corrupt xlsx are file errors', () {
      expect(parseCatalogFile('cat.pdf', [1]).fileErrors, isNotEmpty);
      expect(parseCatalogFile('cat.xlsx', [1, 2, 3]).fileErrors, isNotEmpty);
    });

    test('blank and trailing blank rows are dropped, cells trimmed', () {
      final result = parseCatalogFile(
        'cat.csv',
        _csv('College,Course\nEng , BSCE\n,\n  ,  \nArts,AB\n,\n\n'),
      );
      expect(result.sheets.single.rows, [
        ['Eng', 'BSCE'],
        ['Arts', 'AB'],
      ]);
    });

    test('short rows are padded to the header width; numbers become text', () {
      final result = parseCatalogFile(
        'cat.xlsx',
        _xlsx({
          'S': [
            ['College', 'College Code', 'Course'],
            ['Eng', 12],
          ],
        }),
      );
      expect(result.sheets.single.rows, [
        ['Eng', '12', ''],
      ]);
    });
  });

  group('detectColumns', () {
    test('maps the template headers regardless of case, spaces and order', () {
      final map = detectColumns([
        ' COURSE CODE ',
        'department',
        'College  Code',
        'Course',
        'Department Code',
        'COLLEGE',
      ]);
      expect(map, {
        CatalogRole.courseCode: 0,
        CatalogRole.department: 1,
        CatalogRole.collegeCode: 2,
        CatalogRole.course: 3,
        CatalogRole.departmentCode: 4,
        CatalogRole.college: 5,
      });
    });

    test('template headers constant maps to every role in order', () {
      final map = detectColumns(catalogTemplateHeaders);
      expect(map.length, 6);
      for (final role in CatalogRole.values) {
        expect(map[role], role.index);
      }
    });

    test('maps Program and Course Name to course, Program Code to code', () {
      expect(detectColumns(['Program', 'Program Code']), {
        CatalogRole.course: 0,
        CatalogRole.courseCode: 1,
      });
      expect(detectColumns(['Course Name'])[CatalogRole.course], 0);
    });

    test('an unplaceable header is absent, without throwing', () {
      final map = detectColumns(['Remarks', 'College', '']);
      expect(map, {CatalogRole.college: 1});
    });

    test('a column is used once and the first match wins', () {
      final map = detectColumns(['Course', 'Program']);
      expect(map, {CatalogRole.course: 0});
    });

    test('exact match beats a prefix match', () {
      final map = detectColumns(['Course Code (optional)', 'Course']);
      expect(map[CatalogRole.course], 1);
      expect(map[CatalogRole.courseCode], 0);
    });
  });
}
