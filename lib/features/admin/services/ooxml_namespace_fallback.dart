import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel_plus/excel_plus.dart' as excel;

/// Decodes an .xlsx, tolerating writers that namespace-prefix every OOXML
/// element (`<x:workbook xmlns:x="...">`). `excel_plus` matches element names
/// literally, so such a file registers zero sheets and reads as corrupt.
///
/// The bytes are decoded as-is first; only if that throws or yields no sheets
/// is one retry made on a copy with the literal `x:` prefix stripped. If the
/// retry also fails, the original error is rethrown.
excel.Excel decodeXlsxWithNamespaceFallback(List<int> bytes) {
  Object? firstError;
  StackTrace? firstStack;
  try {
    final book = excel.Excel.decodeBytes(bytes);
    // `tables` is lazy and throws for a workbook with no registered sheets.
    if (book.tables.isNotEmpty) return book;
  } catch (e, s) {
    firstError = e;
    firstStack = s;
  }
  try {
    final book = excel.Excel.decodeBytes(_stripXPrefix(bytes));
    if (book.tables.isNotEmpty) return book;
  } catch (_) {
    // Fall through to the original failure.
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError, firstStack!);
  }
  return excel.Excel.decodeBytes(bytes);
}

List<int> _stripXPrefix(List<int> bytes) {
  final source = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final file in source.files) {
    if (!file.isFile) continue;
    var content = file.content as List<int>;
    if (file.name.endsWith('.xml') || file.name.endsWith('.rels')) {
      final text = utf8
          .decode(content, allowMalformed: true)
          .replaceAll('<x:', '<')
          .replaceAll('</x:', '</')
          .replaceAll('xmlns:x=', 'xmlns=');
      content = utf8.encode(text);
    }
    out.addFile(ArchiveFile(file.name, content.length, content));
  }
  return ZipEncoder().encode(out);
}
