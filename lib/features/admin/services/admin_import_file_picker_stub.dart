import 'dart:typed_data';

class AdminImportFile {
  const AdminImportFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
}

Future<AdminImportFile?> pickAdminImportFile() async => null;

void downloadImportTemplate() {}
