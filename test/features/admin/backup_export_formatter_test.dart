import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel_plus/excel_plus.dart' as excel;
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/backup_export.dart';
import 'package:mind_mates/features/admin/services/backup_export_formatter.dart';

BackupExportDataset _sampleDataset() => BackupExportDataset(
  exportId: 'exp-123',
  exportedAt: DateTime.utc(2026, 11, 20, 4, 5, 6),
  collections: [
    const BackupCollectionDataset(
      collectionKey: 'appointments',
      collectionPaths: ['appointments'],
      documents: [
        BackupDocumentRecord(
          documentId: 'appt-1',
          documentPath: 'appointments/appt-1',
          collectionPath: 'appointments',
          collectionKey: 'appointments',
          createTime: '2026-11-19T10:00:00.000Z',
          updateTime: '2026-11-19T10:05:00.000Z',
          fields: {
            'studentRef': 'ref:users/student-1',
            'notes': 'Line 1,\nLine "2"',
            'scheduledAt': '2026-11-21T09:00:00.000Z',
          },
        ),
      ],
    ),
    const BackupCollectionDataset(
      collectionKey: 'appointments__history',
      collectionPaths: ['appointments/appt-1/history'],
      documents: [
        BackupDocumentRecord(
          documentId: 'hist-1',
          documentPath: 'appointments/appt-1/history/hist-1',
          collectionPath: 'appointments/appt-1/history',
          collectionKey: 'appointments__history',
          parentCollection: 'appointments',
          parentDocumentId: 'appt-1',
          createTime: '2026-11-19T10:00:00.000Z',
          fields: {
            'action': 'confirmed',
            'documentId': 'user-field-collision',
          },
        ),
      ],
    ),
    const BackupCollectionDataset(
      collectionKey: 'empty_collection',
      collectionPaths: ['empty_collection'],
      documents: [],
    ),
  ],
);

void main() {
  test(
    'CSV ZIP exports one CSV per collection, preserves metadata/relationships, and handles empty collections',
    () {
      final bytes = buildBackupCsvZipBytes(_sampleDataset());
      final archive = ZipDecoder().decodeBytes(bytes);

      expect(archive.files.map((f) => f.name).toList(), [
        'appointments.csv',
        'appointments__history.csv',
        'empty_collection.csv',
      ]);

      final apptCsv = utf8.decode(
        archive.findFile('appointments.csv')!.content as List<int>,
      );
      expect(
        apptCsv,
        contains(
          'documentId,documentPath,collectionPath,parentCollection,parentDocumentId,createTime,updateTime,notes,scheduledAt,studentRef',
        ),
      );
      expect(apptCsv, contains('appt-1,appointments/appt-1,appointments'));
      expect(apptCsv, contains('"Line 1,\nLine ""2"""'));
      expect(apptCsv, contains('ref:users/student-1'));
      expect(apptCsv, contains('2026-11-21T09:00:00.000Z'));

      final histCsv = utf8.decode(
        archive.findFile('appointments__history.csv')!.content as List<int>,
      );
      expect(histCsv, contains('field_documentId'));
      expect(
        histCsv,
        contains(
          'hist-1,appointments/appt-1/history/hist-1,appointments/appt-1/history,appointments,appt-1,2026-11-19T10:00:00.000Z,,confirmed,user-field-collision',
        ),
      );

      final emptyCsv = utf8.decode(
        archive.findFile('empty_collection.csv')!.content as List<int>,
      );
      expect(
        emptyCsv.trim(),
        'documentId,documentPath,collectionPath,parentCollection,parentDocumentId,createTime,updateTime',
      );
    },
  );

  test(
    'CSV ZIP includes backup_summary.csv when the database has zero collections',
    () {
      final bytes = buildBackupCsvZipBytes(
        BackupExportDataset(
          exportId: 'empty-db',
          exportedAt: DateTime.utc(2026, 11, 20),
          collections: const [],
        ),
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.map((f) => f.name), ['backup_summary.csv']);
    },
  );

  test(
    'Excel workbook organizes collections into worksheets, sanitizes >31-char names, and handles empty collections',
    () {
      final dataset = BackupExportDataset(
        exportId: 'exp-xlsx',
        exportedAt: DateTime.utc(2026, 11, 20, 4, 5, 6),
        collections: [
          ..._sampleDataset().collections,
          const BackupCollectionDataset(
            collectionKey: 'pending_registration_cancellations',
            collectionPaths: ['pending_registration_cancellations'],
            documents: [
              BackupDocumentRecord(
                documentId: 'reg-1',
                documentPath: 'pending_registration_cancellations/reg-1',
                collectionPath: 'pending_registration_cancellations',
                collectionKey: 'pending_registration_cancellations',
                fields: {'active': true, 'attempts': 2, 'badCtrl': 'ok\x00!'},
              ),
            ],
          ),
          const BackupCollectionDataset(
            collectionKey: 'pending_registration_cancellations_extra',
            collectionPaths: ['pending_registration_cancellations_extra'],
            documents: [],
          ),
        ],
      );

      final bytes = buildBackupExcelBytes(dataset);
      final book = excel.Excel.decodeBytes(bytes);

      expect(book.tables.containsKey('Backup_Summary'), isTrue);
      expect(book.tables.containsKey('appointments'), isTrue);
      expect(book.tables.containsKey('appointments__history'), isTrue);
      expect(book.tables.containsKey('empty_collection'), isTrue);
      expect(book.tables.containsKey('Sheet1'), isFalse);

      // All worksheet names obey Excel's 31-character limit and remain unique.
      for (final name in book.tables.keys) {
        expect(name.length, lessThanOrEqualTo(31));
      }
      expect(book.tables.length, 6);

      // Verify empty collection has header row only.
      final emptyRows = book.tables['empty_collection']!.rows;
      expect(emptyRows.length, 1);

      // Verify control character was stripped and values preserved.
      final longSheetName = book.tables.keys.firstWhere(
        (k) => k.startsWith('pending_registration_cancell'),
      );
      final regRows = book.tables[longSheetName]!.rows;
      expect(regRows.length, 2);
      final headerTexts =
          regRows[0].map((c) => c?.value.toString() ?? '').toList();
      final badCtrlIdx = headerTexts.indexOf('badCtrl');
      expect(regRows[1][badCtrlIdx]?.value.toString(), 'ok!');
    },
  );

  test(
    'Excel workbook splits large datasets across numbered worksheets without losing rows',
    () {
      final docs = [
        for (var i = 1; i <= 5; i++)
          BackupDocumentRecord(
            documentId: 'doc-$i',
            documentPath: 'large_collection/doc-$i',
            collectionPath: 'large_collection',
            collectionKey: 'large_collection',
            fields: {'seq': i},
          ),
      ];
      final dataset = BackupExportDataset(
        exportId: 'exp-split',
        exportedAt: DateTime.utc(2026, 11, 20),
        collections: [
          BackupCollectionDataset(
            collectionKey: 'large_collection',
            collectionPaths: const ['large_collection'],
            documents: docs,
          ),
        ],
      );

      final bytes = buildBackupExcelBytes(dataset, maxRowsPerSheet: 2);
      final book = excel.Excel.decodeBytes(bytes);

      expect(book.tables.keys, containsAll([
        'Backup_Summary',
        'large_collection_1',
        'large_collection_2',
        'large_collection_3',
      ]));

      final exportedIds = <String>[
        for (final sheet in [
          'large_collection_1',
          'large_collection_2',
          'large_collection_3',
        ])
          for (final row in book.tables[sheet]!.rows.skip(1))
            row.first!.value.toString(),
      ];
      expect(exportedIds, ['doc-1', 'doc-2', 'doc-3', 'doc-4', 'doc-5']);
    },
  );

  test('Excel throws rather than silently truncating cells above 32,767 chars', () {
    final dataset = BackupExportDataset(
      exportId: 'exp-huge',
      exportedAt: DateTime.utc(2026, 11, 20),
      collections: [
        BackupCollectionDataset(
          collectionKey: 'huge',
          collectionPaths: const ['huge'],
          documents: [
            BackupDocumentRecord(
              documentId: 'h1',
              documentPath: 'huge/h1',
              collectionPath: 'huge',
              collectionKey: 'huge',
              fields: {'blob': 'a' * (excelMaxCellChars + 1)},
            ),
          ],
        ),
      ],
    );

    expect(() => buildBackupExcelBytes(dataset), throwsStateError);
  });

  test(
    'CSV and Excel neutralize spreadsheet formula injection while preserving negative numbers',
    () {
      final dataset = BackupExportDataset(
        exportId: 'exp-formula',
        exportedAt: DateTime.utc(2026, 11, 20),
        collections: const [
          BackupCollectionDataset(
            collectionKey: 'inquiries',
            collectionPaths: ['inquiries'],
            documents: [
              BackupDocumentRecord(
                documentId: 'inq-1',
                documentPath: 'inquiries/inq-1',
                collectionPath: 'inquiries',
                collectionKey: 'inquiries',
                fields: {
                  'eqFormula': "=CMD|'/C calc'!A0",
                  'plusFormula': '+1+1',
                  'minusFormula': '-2+3',
                  'atFormula': '@SUM(1+1)',
                  'tabFormula': '\t=1+1',
                  'spacedFormula': '  =HYPERLINK("https://example.invalid")',
                  'negativeInt': -42,
                  'negativeDouble': -3.5,
                },
              ),
            ],
          ),
        ],
      );

      final zipBytes = buildBackupCsvZipBytes(dataset);
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final csv = utf8.decode(
        archive.findFile('inquiries.csv')!.content as List<int>,
      );

      expect(csv, contains("'@SUM(1+1)"));
      expect(csv, contains("'=CMD|'/C calc'!A0"));
      expect(csv, contains("'-2+3"));
      expect(csv, contains("'+1+1"));
      expect(csv, contains("'\t=1+1"));
      expect(csv, contains("'  =HYPERLINK(\"\"https://example.invalid\"\")"));
      // Genuine numeric values are preserved without a quote prefix.
      expect(csv, contains(',-3.5,-42,'));

      final xlsxBytes = buildBackupExcelBytes(dataset);
      final book = excel.Excel.decodeBytes(xlsxBytes);
      final rows = book.tables['inquiries']!.rows;
      final headers = rows[0].map((c) => c!.value.toString()).toList();
      final dataRow = rows[1];

      String cellStr(String col) =>
          dataRow[headers.indexOf(col)]!.value.toString();

      expect(cellStr('eqFormula'), "'=CMD|'/C calc'!A0");
      expect(cellStr('plusFormula'), "'+1+1");
      expect(cellStr('minusFormula'), "'-2+3");
      expect(cellStr('atFormula'), "'@SUM(1+1)");
      expect(cellStr('tabFormula'), "'\t=1+1");
      expect(
        cellStr('spacedFormula'),
        '\'  =HYPERLINK("https://example.invalid")',
      );
      expect(dataRow[headers.indexOf('negativeInt')]!.value, isA<excel.IntCellValue>());
      expect(dataRow[headers.indexOf('negativeDouble')]!.value, isA<excel.DoubleCellValue>());
    },
  );

  test(
    'realistic staging fixture exports all collections, subcollections, and split large sheets completely',
    () {
      final stagingCollections = <BackupCollectionDataset>[
        const BackupCollectionDataset(
          collectionKey: 'users',
          collectionPaths: ['users'],
          documents: [
            BackupDocumentRecord(
              documentId: 'stu-001',
              documentPath: 'users/stu-001',
              collectionPath: 'users',
              collectionKey: 'users',
              createTime: '2026-10-01T08:00:00.000Z',
              updateTime: '2026-11-10T09:30:00.000Z',
              fields: {
                'accessRole': 'appUser',
                'collegeId': 'cas',
                'dayStreak': 7,
              },
            ),
          ],
        ),
        const BackupCollectionDataset(
          collectionKey: 'inquiries',
          collectionPaths: ['inquiries'],
          documents: [
            BackupDocumentRecord(
              documentId: 'inq-001',
              documentPath: 'inquiries/inq-001',
              collectionPath: 'inquiries',
              collectionKey: 'inquiries',
              fields: {'subject': 'Schedule help', 'status': 'resolved'},
            ),
          ],
        ),
        const BackupCollectionDataset(
          collectionKey: 'inquiries__replies',
          collectionPaths: ['inquiries/inq-001/replies'],
          documents: [
            BackupDocumentRecord(
              documentId: 'rep-001',
              documentPath: 'inquiries/inq-001/replies/rep-001',
              collectionPath: 'inquiries/inq-001/replies',
              collectionKey: 'inquiries__replies',
              parentCollection: 'inquiries',
              parentDocumentId: 'inq-001',
              fields: {'body': 'We are available Tuesday.', 'authorRef': 'ref:users/staff-1'},
            ),
          ],
        ),
        BackupCollectionDataset(
          collectionKey: 'moodEntries',
          collectionPaths: const ['moodEntries'],
          documents: [
            for (var i = 1; i <= 60; i++)
              BackupDocumentRecord(
                documentId: 'me-${i.toString().padLeft(3, '0')}',
                documentPath: 'moodEntries/me-${i.toString().padLeft(3, '0')}',
                collectionPath: 'moodEntries',
                collectionKey: 'moodEntries',
                fields: {
                  'userId': 'stu-001',
                  'level': (i % 5) + 1,
                  'occurredAt': '2026-11-15T08:00:00.000Z',
                },
              ),
          ],
        ),
        const BackupCollectionDataset(
          collectionKey: 'recommendations',
          collectionPaths: ['recommendations'],
          documents: [],
        ),
      ];

      final dataset = BackupExportDataset(
        exportId: 'exp-staging-fixture',
        exportedAt: DateTime.utc(2026, 11, 20, 8, 0, 0),
        collections: stagingCollections,
      );

      final zipBytes = buildBackupCsvZipBytes(dataset);
      final archive = ZipDecoder().decodeBytes(zipBytes);
      expect(archive.files.map((f) => f.name).toList(), [
        'users.csv',
        'inquiries.csv',
        'inquiries__replies.csv',
        'moodEntries.csv',
        'recommendations.csv',
      ]);
      final moodCsv = utf8.decode(
        archive.findFile('moodEntries.csv')!.content as List<int>,
      );
      expect(moodCsv.trim().split('\n').length, 61); // 1 header + 60 docs

      final xlsxBytes = buildBackupExcelBytes(dataset, maxRowsPerSheet: 25);
      final book = excel.Excel.decodeBytes(xlsxBytes);
      expect(book.tables.keys, containsAll([
        'Backup_Summary',
        'users',
        'inquiries',
        'inquiries__replies',
        'moodEntries_1',
        'moodEntries_2',
        'moodEntries_3',
        'recommendations',
      ]));
      final totalMoodRows = [
        'moodEntries_1',
        'moodEntries_2',
        'moodEntries_3',
      ].fold<int>(0, (sum, s) => sum + book.tables[s]!.rows.length - 1);
      expect(totalMoodRows, 60);
    },
  );
}
