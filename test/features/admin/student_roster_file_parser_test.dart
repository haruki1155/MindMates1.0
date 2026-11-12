import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel_plus/excel_plus.dart' as excel;
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/services/student_roster_file_parser.dart';
import 'package:mind_mates/models/student_roster_models.dart';

List<int> _workbookWith(String workbookXml) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('xl/workbook.xml', workbookXml))
    ..addFile(ArchiveFile.string('[Content_Types].xml', '<Types/>'));
  return ZipEncoder().encode(archive);
}

List<int> _csv(String text) => utf8.encode(text);

const _header =
    'Student No.,Surname,First Name,Middle Name,Date of Birth (MM/DD/YYYY),College,Course,Year Level';

void main() {
  group('workbookUses1904', () {
    test('true when workbookPr has date1904="1"', () {
      final bytes = _workbookWith(
        '<workbook><workbookPr date1904="1"/><sheets/></workbook>',
      );
      expect(workbookUses1904(bytes), isTrue);
    });

    test('true for date1904="true"', () {
      final bytes = _workbookWith(
        '<workbook><workbookPr date1904="true" defaultThemeVersion="1"/></workbook>',
      );
      expect(workbookUses1904(bytes), isTrue);
    });

    test('false without the attribute, with 0, or on unreadable input', () {
      expect(
        workbookUses1904(_workbookWith('<workbook><workbookPr/></workbook>')),
        isFalse,
      );
      expect(
        workbookUses1904(
          _workbookWith('<workbook><workbookPr date1904="0"/></workbook>'),
        ),
        isFalse,
      );
      expect(workbookUses1904([1, 2, 3]), isFalse);
    });
  });

  group('parseRosterDate', () {
    test('every supported shape yields the same key', () {
      expect(parseRosterDate(DateTime(2005, 2, 15)), '2005-02-15');
      expect(
        parseRosterDate(excel.DateCellValue(year: 2005, month: 2, day: 15)),
        '2005-02-15',
      );
      expect(parseRosterDate(38398), '2005-02-15');
      expect(parseRosterDate(38398.0), '2005-02-15');
      expect(parseRosterDate('02/15/2005'), '2005-02-15');
      expect(parseRosterDate('2005-02-15'), '2005-02-15');
    });

    test('rejects other formats and impossible dates', () {
      expect(parseRosterDate('13/01/2005'), isNull);
      expect(parseRosterDate('02/30/2005'), isNull);
      expect(parseRosterDate('Feb 15, 2005'), isNull);
      expect(parseRosterDate(''), isNull);
      expect(parseRosterDate(null), isNull);
    });

    test('1904 serials and DateTimes are shifted by 1,462 days', () {
      // Feb 3, 2005 is 38386 in the 1900 system, 36924 in the 1904 system.
      expect(parseRosterDate(38386), '2005-02-03');
      expect(parseRosterDate(36924, date1904: true), '2005-02-03');
      expect(parseRosterDate(36924, date1904: true), parseRosterDate(38386));
      // excel_plus decodes with the 1900 epoch, so a 1904 workbook yields a
      // DateTime that is 1,462 days early.
      expect(
        parseRosterDate(DateTime.utc(2001, 2, 1), date1904: true),
        '2005-02-02',
      );
    });
  });

  test('spelledDate spells the month out', () {
    expect(spelledDate('2005-02-03'), 'Feb 3, 2005');
    expect(spelledDate('1999-12-31'), 'Dec 31, 1999');
    expect(spelledDate('nonsense'), 'nonsense');
  });

  group('parseRosterFile csv', () {
    test('matches headers case-insensitively and in any order', () {
      final result = parseRosterFile(
        'roster.csv',
        _csv(
          'YEAR LEVEL,course,college,date of birth (mm/dd/yyyy),middle name,first name,surname,student no.\n'
          '2,BSIT,CITE,02/15/2005,M,Ana,Santos,2021-001\n',
        ),
      );
      expect(result.fileErrors, isEmpty);
      expect(result.rows, hasLength(1));
      expect(result.rows.single, {
        'studentNo': '2021-001',
        'surname': 'Santos',
        'firstName': 'Ana',
        'middleName': 'M',
        'dateOfBirth': '2005-02-15',
        'college': 'CITE',
        'course': 'BSIT',
        'yearLevel': '2',
      });
    });

    test('reports missing headers by name', () {
      final result = parseRosterFile(
        'roster.csv',
        _csv('Student No.,Surname\n2021-001,Santos\n'),
      );
      expect(result.fileErrors.join(' '), contains('First Name'));
      expect(result.fileErrors.join(' '), contains('Course'));
    });

    test('skips fully blank rows and handles quoted fields', () {
      final result = parseRosterFile(
        'roster.csv',
        _csv(
          '$_header\r\n'
          '2021-001,"Dela Cruz, Jr.",Ana,,02/15/2005,CITE,BSIT,1\r\n'
          ',,,,,,,\r\n'
          '\r\n'
          '2021-002,"O""Neil",Ben,,02/16/2005,CITE,BSIT,1\r\n',
        ),
      );
      expect(result.rows, hasLength(2));
      expect(result.rows.first['surname'], 'Dela Cruz, Jr.');
      expect(result.rows.last['surname'], 'O"Neil');
    });

    test('a date that cannot be read is passed through for server error', () {
      final result = parseRosterFile(
        'roster.csv',
        _csv('$_header\n2021-001,A,B,,13/01/2005,CITE,BSIT,1\n'),
      );
      expect(result.rows.single['dateOfBirth'], '13/01/2005');
    });

    test('duplicate canonical student numbers report both row numbers', () {
      final result = parseRosterFile(
        'roster.csv',
        _csv(
          '$_header\n'
          '2021-001,A,B,,02/15/2005,CITE,BSIT,1\n'
          '2022-005,A,B,,02/15/2005,CITE,BSIT,1\n'
          '2021001,C,D,,02/16/2005,CITE,BSIT,1\n',
        ),
      );
      expect(result.duplicateStudentNos, {
        '2021001': [2, 4],
      });
    });

    test('unsupported extension is a file error', () {
      final result = parseRosterFile('roster.pdf', [1, 2]);
      expect(result.fileErrors, isNotEmpty);
      expect(result.rows, isEmpty);
    });
  });

  group('parseRosterFile xlsx', () {
    test('reads text, serial and date cells', () {
      final book = excel.Excel.createExcel();
      final sheet = book['Sheet1'];
      sheet.appendRow([
        for (final h in rosterTemplateHeaders) excel.TextCellValue(h),
      ]);
      sheet.appendRow([
        excel.TextCellValue('2021-001'),
        excel.TextCellValue('Santos'),
        excel.TextCellValue('Ana'),
        null,
        excel.DateCellValue(year: 2005, month: 2, day: 15),
        excel.TextCellValue('CITE'),
        excel.TextCellValue('BSIT'),
        excel.IntCellValue(1),
      ]);
      sheet.appendRow([
        excel.TextCellValue('2021-002'),
        excel.TextCellValue('Cruz'),
        excel.TextCellValue('Ben'),
        null,
        excel.IntCellValue(38398),
        excel.TextCellValue('CITE'),
        excel.TextCellValue('BSIT'),
        excel.TextCellValue('2nd Year'),
      ]);
      sheet.appendRow([
        excel.TextCellValue('2021-003'),
        excel.TextCellValue('Reyes'),
        excel.TextCellValue('Cy'),
        null,
        excel.TextCellValue('02/15/2005'),
        excel.TextCellValue('CITE'),
        excel.TextCellValue('BSIT'),
        excel.IntCellValue(3),
      ]);
      final bytes = book.encode()!;
      final result = parseRosterFile('roster.xlsx', bytes);
      expect(result.fileErrors, isEmpty);
      expect(result.rows.map((r) => r['dateOfBirth']), [
        '2005-02-15',
        '2005-02-15',
        '2005-02-15',
      ]);
      expect(result.rows.map((r) => r['yearLevel']), ['1', '2nd Year', '3']);
      expect(result.rows.first['studentNo'], '2021-001');
    });
  });

  group('helpers', () {
    test('2,500 rows make 3 chunks of at most 1,000', () {
      final rows = [
        for (var i = 0; i < 2500; i++) {'studentNo': 'S$i'},
      ];
      final chunks = chunkRows(rows);
      expect(chunks.map((c) => c.length), [1000, 1000, 500]);
    });

    test('template headers are exact', () {
      expect(rosterTemplateHeaders, [
        'Student No.',
        'Surname',
        'First Name',
        'Middle Name',
        'Date of Birth (MM/DD/YYYY)',
        'College',
        'Course',
        'Year Level',
      ]);
    });

    test('activation slips contain every code once', () {
      final codes = [
        for (var i = 0; i < 3; i++)
          IssuedActivationCode(
            studentNo: '2021-00$i',
            name: 'Student $i',
            college: 'CITE',
            course: 'BSIT',
            yearLevel: '1st Year',
            code: 'ABCDE-FGH2$i',
            expiresAt: DateTime.utc(2027, 1, 12),
          ),
      ];
      final bytes = buildActivationSlipsXlsx(codes);
      final book = excel.Excel.decodeBytes(bytes);
      final rows = book.tables.values.first.rows
          .map((r) => r.map((c) => c?.value?.toString() ?? '').toList())
          .toList();
      expect(rows.first, [
        'Student No.',
        'Name',
        'College',
        'Course',
        'Year Level',
        'Activation Code',
        'Expires',
      ]);
      expect(rows.skip(1).map((r) => r[5]).toList(), [
        'ABCDE-FGH20',
        'ABCDE-FGH21',
        'ABCDE-FGH22',
      ]);
      expect(rows[1][6], 'Jan 12, 2027');
    });
  });
}
