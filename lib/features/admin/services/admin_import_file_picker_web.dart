import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class AdminImportFile {
  const AdminImportFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
}

Future<AdminImportFile?> pickAdminImportFile() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.xlsx,.xls,.csv'
    ..multiple = false;
  input.click();
  await input.onChange.first;
  final file = input.files?.item(0);
  if (file == null) return null;
  final reader = web.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoadEnd.first;
  final bytes = (reader.result as JSArrayBuffer?)?.toDart.asUint8List();
  if (bytes == null || bytes.isEmpty) {
    throw const FormatException('The selected file could not be read.');
  }
  return AdminImportFile(name: file.name, bytes: bytes);
}

void downloadImportTemplate() {
  final csv =
      'Full name,Student ID,Department/Course,Year Level,Date of log-in\nExample Student,2026-0001,BS Psychology,Year 1,2026-09-11\n';
  final blob = web.Blob(
    [csv.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  try {
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = 'mindmate_counseling_walkin_template.csv';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    web.URL.revokeObjectURL(url);
  }
}
