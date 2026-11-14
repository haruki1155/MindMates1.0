import 'student_personal_info.dart';
import 'student_roster_models.dart' show intMap;

enum CatalogRowKind {
  create,
  exists,
  error;

  static CatalogRowKind parse(Object? value) => switch (value) {
    'create' => CatalogRowKind.create,
    'exists' => CatalogRowKind.exists,
    _ => CatalogRowKind.error,
  };
}

/// One file row as judged by `previewAcademicCatalogImport`.
class CatalogRowResult {
  const CatalogRowResult({
    required this.index,
    required this.kind,
    this.errors = const [],
    this.warnings = const [],
    this.inventedDepartment,
  });

  final int index;
  final CatalogRowKind kind;
  final List<String> errors;
  final List<String> warnings;
  final String? inventedDepartment;

  factory CatalogRowResult.fromJson(Object? json) {
    final map = asStringMap(json);
    final invented = asText(map['inventedDepartment']);
    return CatalogRowResult(
      index: (map['index'] as num?)?.toInt() ?? 0,
      kind: CatalogRowKind.parse(map['kind']),
      errors: [for (final e in asList(map['errors'])) asText(e)],
      warnings: [for (final w in asList(map['warnings'])) asText(w)],
      inventedDepartment: invented.isEmpty ? null : invented,
    );
  }
}

class CatalogPreview {
  const CatalogPreview({required this.rows, required this.counts});

  final List<CatalogRowResult> rows;

  /// `create`, `exists`, `error` count rows; `colleges`, `departments`,
  /// `courses` count the records the import would create.
  final Map<String, int> counts;

  factory CatalogPreview.fromJson(Object? json) {
    final map = asStringMap(json);
    return CatalogPreview(
      rows: [for (final r in asList(map['rows'])) CatalogRowResult.fromJson(r)],
      counts: intMap(map['counts']),
    );
  }
}

class CatalogImportResult {
  const CatalogImportResult({
    required this.importId,
    required this.counts,
    required this.status,
    this.message,
  });

  final String importId;

  /// Records actually committed: `colleges`, `departments`, `courses`.
  final Map<String, int> counts;

  /// `complete` or `partial`.
  final String status;
  final String? message;

  bool get isPartial => status == 'partial';

  factory CatalogImportResult.fromJson(Object? json) {
    final map = asStringMap(json);
    final message = asText(map['message']);
    return CatalogImportResult(
      importId: asText(map['importId']),
      counts: intMap(map['counts']),
      // Only an explicit `complete` reads as success: anything unexpected is
      // reported as partial, so an unrecognised status never claims the whole
      // file was imported.
      status: map['status'] == 'complete' ? 'complete' : 'partial',
      message: message.isEmpty ? null : message,
    );
  }
}
