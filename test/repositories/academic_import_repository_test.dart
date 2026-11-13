import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/academic_import_models.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

Map<Object?, Object?> _m(Map<Object?, Object?> v) => v;

void main() {
  late List<(String, Map<String, Object?>)> calls;
  late Object? Function(String name) respond;

  AdminPortalRepository build() {
    calls = [];
    return AdminPortalRepository(
      callableInvoker: (name, data) async {
        calls.add((name, data));
        return respond(name);
      },
    );
  }

  test(
    'previewCatalogImport maps kinds, warnings and invented department',
    () async {
      final repo = build();
      respond = (_) => _m({
        'rows': <Object?>[
          _m({
            'index': 0,
            'kind': 'create',
            'errors': <Object?>[],
            'warnings': <Object?>[],
            'inventedDepartment': 'College of Pharmacy',
          }),
          _m({
            'index': 1,
            'kind': 'exists',
            'errors': <Object?>[],
            'warnings': <Object?>['differs from the stored code'],
          }),
          _m({
            'index': 2,
            'kind': 'error',
            'errors': <Object?>['archived'],
            'warnings': <Object?>[],
          }),
        ],
        'counts': _m({
          'create': 1,
          'exists': 1,
          'error': 1,
          'colleges': 1,
          'departments': 1,
          'courses': 0,
        }),
      });
      final rows = [
        {'college': 'A', 'department': ''},
      ];
      final preview = await repo.previewCatalogImport(
        fileName: 'f.xlsx',
        sheetName: 'S1',
        rows: rows,
      );
      expect(calls.single.$1, 'previewAcademicCatalogImport');
      expect(calls.single.$2, {
        'fileName': 'f.xlsx',
        'sheetName': 'S1',
        'rows': rows,
      });
      expect(preview.rows.map((r) => r.kind), [
        CatalogRowKind.create,
        CatalogRowKind.exists,
        CatalogRowKind.error,
      ]);
      expect(preview.rows[0].inventedDepartment, 'College of Pharmacy');
      expect(preview.rows[1].inventedDepartment, isNull);
      expect(preview.rows[1].warnings, ['differs from the stored code']);
      expect(preview.rows[2].errors, ['archived']);
      expect(preview.rows[2].index, 2);
      expect(preview.counts['departments'], 1);
      expect(preview.counts['error'], 1);
    },
  );

  test('importCatalog maps status, counts and message', () async {
    final repo = build();
    respond = (_) => _m({
      'importId': 'imp1',
      'status': 'partial',
      'message': 'stopped early',
      'counts': _m({'colleges': 1, 'departments': 2, 'courses': 0}),
    });
    final result = await repo.importCatalog(
      fileName: 'f.xlsx',
      sheetName: 'S1',
      rows: const [],
    );
    expect(calls.single.$1, 'importAcademicCatalog');
    expect(result.importId, 'imp1');
    expect(result.status, 'partial');
    expect(result.message, 'stopped early');
    expect(result.counts, {'colleges': 1, 'departments': 2, 'courses': 0});
  });

  test('importCatalog complete has no message', () async {
    final repo = build();
    respond = (_) => _m({
      'importId': 'imp2',
      'status': 'complete',
      'counts': _m({'colleges': 0, 'departments': 0, 'courses': 3}),
    });
    final result = await repo.importCatalog(
      fileName: 'f',
      sheetName: 's',
      rows: const [],
    );
    expect(result.status, 'complete');
    expect(result.message, isNull);
  });

  test('importCatalog treats an unrecognised status as partial', () async {
    final repo = build();
    respond = (_) => _m({
      'importId': 'imp3',
      'status': 'queued-somehow',
      'counts': _m({'colleges': 0, 'departments': 0, 'courses': 0}),
    });
    final result = await repo.importCatalog(
      fileName: 'f',
      sheetName: 's',
      rows: const [],
    );
    expect(result.status, 'partial');
    expect(result.isPartial, isTrue);
  });
}
