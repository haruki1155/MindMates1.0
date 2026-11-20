import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_plus/excel_plus.dart' as excel;

import '../domain/backup_export.dart';

/// Conservative per-worksheet data-row cap (well below Excel's 1,048,576 row
/// hard limit) so large collections split cleanly across numbered worksheets.
const int defaultExcelMaxRowsPerSheet = 50000;

/// Maximum Excel cell text length allowed by the OOXML specification.
const int excelMaxCellChars = 32767;

/// Leading metadata columns included on every exported collection table.
const List<String> backupMetadataColumns = [
  'documentId',
  'documentPath',
  'collectionPath',
  'parentCollection',
  'parentDocumentId',
  'createTime',
  'updateTime',
];

final Set<String> _metadataColumnSet = backupMetadataColumns.toSet();
final RegExp _invalidXmlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');
final RegExp _invalidSheetChars = RegExp(r'[\[\]:*?/\\]');
final RegExp _unsafeFileChars = RegExp(r'[^A-Za-z0-9._-]');
final RegExp _spreadsheetFormulaTrigger = RegExp(r'^(?:[\t\r]|[\s]*[=+\-@])');

/// Neutralizes spreadsheet formula injection (OWASP CSV/XLSX injection) by
/// prepending a leading single quote to strings beginning with `=`, `+`, `-`,
/// `@`, `\t`, `\r`, or whitespace followed by a formula operator.
String neutralizeSpreadsheetFormula(String text) {
  if (text.isEmpty) return text;
  if (_spreadsheetFormulaTrigger.hasMatch(text)) {
    return "'$text";
  }
  return text;
}

/// Computes the deterministic headers and rows for a single collection.
///
/// Any document field whose name collides with a leading metadata column is
/// exported as `field_<name>` so Firestore document IDs and paths are never
/// overwritten.
({List<String> headers, List<List<Object?>> rows}) buildCollectionTable(
  BackupCollectionDataset collection,
) {
  final fieldKeys = <String>{};
  for (final doc in collection.documents) {
    fieldKeys.addAll(doc.fields.keys);
  }
  final sortedFields = fieldKeys.toList()..sort();

  final fieldHeaders = <({String key, String header})>[];
  final usedHeaders = Set<String>.from(_metadataColumnSet);
  for (final key in sortedFields) {
    var header = _metadataColumnSet.contains(key) ? 'field_$key' : key;
    while (usedHeaders.contains(header)) {
      header = 'field_$header';
    }
    usedHeaders.add(header);
    fieldHeaders.add((key: key, header: header));
  }

  final headers = <String>[
    ...backupMetadataColumns,
    for (final f in fieldHeaders) f.header,
  ];

  final rows = <List<Object?>>[];
  for (final doc in collection.documents) {
    rows.add([
      doc.documentId,
      doc.documentPath,
      doc.collectionPath,
      doc.parentCollection ?? '',
      doc.parentDocumentId ?? '',
      doc.createTime ?? '',
      doc.updateTime ?? '',
      for (final f in fieldHeaders)
        doc.fields.containsKey(f.key) ? doc.fields[f.key] : null,
    ]);
  }

  return (headers: headers, rows: rows);
}

/// Formats any Firestore-serialized value into a plain CSV/text representation.
String formatBackupCellText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is bool || value is num) return value.toString();
  if (value is List || value is Map) return jsonEncode(value);
  return value.toString();
}

/// Encodes one RFC 4180 CSV line with formula-injection neutralization.
String encodeCsvRow(List<Object?> cells) {
  return cells
      .map((cell) {
        final String text;
        if (cell == null) {
          text = '';
        } else if (cell is bool) {
          text = cell.toString();
        } else if (cell is num) {
          text = cell.isFinite
              ? cell.toString()
              : neutralizeSpreadsheetFormula(cell.toString());
        } else {
          text = neutralizeSpreadsheetFormula(formatBackupCellText(cell));
        }
        final needsQuotes =
            text.contains(',') ||
            text.contains('"') ||
            text.contains('\n') ||
            text.contains('\r');
        if (!needsQuotes) return text;
        return '"${text.replaceAll('"', '""')}"';
      })
      .join(',');
}

/// Builds a timestamped download filename for the backup export.
String buildBackupFileName(
  BackupExportFormat format,
  DateTime exportedAt,
) {
  final utc = exportedAt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${utc.year}${two(utc.month)}${two(utc.day)}-${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
  return switch (format) {
    BackupExportFormat.csv => 'mindmate-firestore-backup-$stamp.zip',
    BackupExportFormat.xlsx => 'mindmate-firestore-backup-$stamp.xlsx',
  };
}

/// Builds a ZIP archive containing one `.csv` file per exported collection.
Uint8List buildBackupCsvZipBytes(BackupExportDataset dataset) {
  final archive = Archive();
  final usedFileNames = <String>{};

  if (dataset.collections.isEmpty) {
    final csv = [
      encodeCsvRow(['exportId', 'exportedAt', 'collections', 'documents']),
      encodeCsvRow([
        dataset.exportId,
        dataset.exportedAt.toUtc().toIso8601String(),
        0,
        0,
      ]),
    ].join('\r\n');
    final bytes = utf8.encode('$csv\r\n');
    archive.addFile(ArchiveFile('backup_summary.csv', bytes.length, bytes));
  } else {
    for (final collection in dataset.collections) {
      final fileName = _uniqueCsvFileName(
        collection.collectionKey,
        usedFileNames,
      );
      final table = buildCollectionTable(collection);
      final lines = <String>[
        encodeCsvRow(table.headers),
        for (final row in table.rows) encodeCsvRow(row),
      ];
      final bytes = utf8.encode('${lines.join('\r\n')}\r\n');
      archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
    }
  }

  final encoded = ZipEncoder().encode(archive);
  if (encoded.isEmpty) {
    throw StateError('Generated CSV ZIP archive is empty.');
  }
  return Uint8List.fromList(encoded);
}

String _uniqueCsvFileName(String collectionKey, Set<String> usedLowerNames) {
  var base = collectionKey.replaceAll(_unsafeFileChars, '_').trim();
  if (base.isEmpty) base = 'collection';
  var candidate = '$base.csv';
  var suffix = 2;
  while (usedLowerNames.contains(candidate.toLowerCase())) {
    candidate = '${base}_$suffix.csv';
    suffix++;
  }
  usedLowerNames.add(candidate.toLowerCase());
  return candidate;
}

/// Builds a multi-worksheet Excel (`.xlsx`) workbook for the complete backup.
///
/// Includes a `Backup_Summary` index sheet mapping every collection and
/// worksheet, creates separate worksheets per collection, and splits large
/// collections at [maxRowsPerSheet] data rows per worksheet.
Uint8List buildBackupExcelBytes(
  BackupExportDataset dataset, {
  int maxRowsPerSheet = defaultExcelMaxRowsPerSheet,
}) {
  if (maxRowsPerSheet < 1) {
    throw ArgumentError.value(
      maxRowsPerSheet,
      'maxRowsPerSheet',
      'Must be at least 1.',
    );
  }

  final book = excel.Excel.createExcel();
  final defaultSheet = book.getDefaultSheet() ?? 'Sheet1';
  const summarySheetName = 'Backup_Summary';
  if (defaultSheet != summarySheetName) {
    book.rename(defaultSheet, summarySheetName);
  }
  final usedSheetNames = <String>{summarySheetName.toLowerCase()};

  final summarySheet = book[summarySheetName];
  summarySheet.appendRow([
    excel.TextCellValue('Export ID'),
    excel.TextCellValue('Exported At (UTC)'),
    excel.TextCellValue('Collection Key'),
    excel.TextCellValue('Collection Paths'),
    excel.TextCellValue('Document Count'),
    excel.TextCellValue('Worksheets'),
  ]);

  if (dataset.collections.isEmpty) {
    summarySheet.appendRow([
      excel.TextCellValue(dataset.exportId),
      excel.TextCellValue(dataset.exportedAt.toUtc().toIso8601String()),
      excel.TextCellValue('(none)'),
      excel.TextCellValue(''),
      excel.IntCellValue(0),
      excel.TextCellValue(summarySheetName),
    ]);
  }

  for (final collection in dataset.collections) {
    final table = buildCollectionTable(collection);
    final totalRows = table.rows.length;
    final chunkCount = totalRows == 0
        ? 1
        : ((totalRows + maxRowsPerSheet - 1) ~/ maxRowsPerSheet);
    final worksheetNames = <String>[];

    for (var part = 0; part < chunkCount; part++) {
      final sheetName = _allocateExcelSheetName(
        collection.collectionKey,
        usedSheetNames,
        partIndex: chunkCount > 1 ? part + 1 : null,
      );
      worksheetNames.add(sheetName);
      final sheet = book[sheetName];
      sheet.appendRow([
        for (final header in table.headers)
          excel.TextCellValue(
            _sanitizeExcelText(neutralizeSpreadsheetFormula(header)),
          ),
      ]);

      if (totalRows > 0) {
        final start = part * maxRowsPerSheet;
        final end = (start + maxRowsPerSheet) > totalRows
            ? totalRows
            : (start + maxRowsPerSheet);
        for (var r = start; r < end; r++) {
          sheet.appendRow([
            for (final cell in table.rows[r]) _toExcelCellValue(cell),
          ]);
        }
      }
    }

    summarySheet.appendRow([
      excel.TextCellValue(dataset.exportId),
      excel.TextCellValue(dataset.exportedAt.toUtc().toIso8601String()),
      excel.TextCellValue(_sanitizeExcelText(collection.collectionKey)),
      excel.TextCellValue(
        _sanitizeExcelText(collection.collectionPaths.join('; ')),
      ),
      excel.IntCellValue(totalRows),
      excel.TextCellValue(worksheetNames.join(', ')),
    ]);
  }

  final encoded = book.encode();
  if (encoded == null || encoded.isEmpty) {
    throw StateError('Generated Excel workbook is empty.');
  }
  return Uint8List.fromList(encoded);
}

String _allocateExcelSheetName(
  String collectionKey,
  Set<String> usedLowerNames, {
  int? partIndex,
}) {
  var base = collectionKey.replaceAll(_invalidSheetChars, '_').trim();
  while (base.startsWith("'")) {
    base = base.substring(1);
  }
  while (base.endsWith("'")) {
    base = base.substring(0, base.length - 1);
  }
  if (base.isEmpty) base = 'Collection';

  final partSuffix = partIndex == null ? '' : '_$partIndex';
  final maxBaseLen = 31 - partSuffix.length;
  var clipped = base.length > maxBaseLen ? base.substring(0, maxBaseLen) : base;
  var candidate = '$clipped$partSuffix';

  var collision = 2;
  while (usedLowerNames.contains(candidate.toLowerCase())) {
    final colSuffix = '_$collision$partSuffix';
    final avail = 31 - colSuffix.length;
    clipped = base.length > avail
        ? base.substring(0, avail < 1 ? 1 : avail)
        : base;
    candidate = '$clipped$colSuffix';
    if (candidate.length > 31) {
      candidate = candidate.substring(0, 31);
    }
    collision++;
  }

  usedLowerNames.add(candidate.toLowerCase());
  return candidate;
}

excel.CellValue _toExcelCellValue(Object? value) {
  if (value == null) return excel.TextCellValue('');
  if (value is bool) return excel.BoolCellValue(value);
  if (value is int) return excel.IntCellValue(value);
  if (value is double) {
    return value.isFinite
        ? excel.DoubleCellValue(value)
        : excel.TextCellValue(
            _sanitizeExcelText(neutralizeSpreadsheetFormula(value.toString())),
          );
  }
  return excel.TextCellValue(
    _sanitizeExcelText(
      neutralizeSpreadsheetFormula(formatBackupCellText(value)),
    ),
  );
}

String _sanitizeExcelText(String raw) {
  final cleaned = raw.replaceAll(_invalidXmlChars, '');
  if (cleaned.length > excelMaxCellChars) {
    throw StateError(
      'Backup export contains a cell exceeding Excel\'s $excelMaxCellChars-character limit. Use CSV (.zip) export instead.',
    );
  }
  return cleaned;
}
