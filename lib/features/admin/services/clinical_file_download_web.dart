import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> saveClinicalFileBytes(
  Uint8List bytes,
  String fileName,
  String contentType,
) async {
  final sanitizedName = fileName
      .replaceAll(RegExp(r'[\x00-\x1f]'), '')
      .replaceAll(RegExp(r'[/\\]'), '_')
      .trim();
  final safeName =
      sanitizedName.isEmpty || RegExp(r'^[._\s]+$').hasMatch(sanitizedName)
      ? 'attachment'
      : sanitizedName;
  final safeContentType = contentType.trim().isEmpty
      ? 'application/octet-stream'
      : contentType.trim();
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: safeContentType),
  );
  final url = web.URL.createObjectURL(blob);
  try {
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = safeName
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    await Future<void>.delayed(const Duration(seconds: 1));
  } finally {
    web.URL.revokeObjectURL(url);
  }
}
