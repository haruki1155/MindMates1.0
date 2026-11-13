import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/academic_catalog_import_dialog.dart';
import 'package:mind_mates/features/admin/screens/academic_structure_page.dart';
import 'package:mind_mates/features/admin/services/academic_catalog_parser.dart';
import 'package:mind_mates/features/admin/services/admin_import_file_picker.dart';
import 'package:mind_mates/models/academic_import_models.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _Repo extends AdminPortalRepository {
  final previews = <List<Map<String, String>>>[];
  final imports = <List<Map<String, String>>>[];
  CatalogPreview Function(List<Map<String, String>> rows)? previewBuilder;
  CatalogImportResult importResult = const CatalogImportResult(
    importId: 'imp-1',
    counts: {'colleges': 1, 'departments': 2, 'courses': 3},
    status: 'complete',
  );

  @override
  Stream<List<College>> watchColleges() => Stream.value(const []);
  @override
  Stream<List<Department>> watchDepartments() => Stream.value(const []);
  @override
  Stream<List<Course>> watchCourses() => Stream.value(const []);

  @override
  Future<CatalogPreview> previewCatalogImport({
    required String fileName,
    required String sheetName,
    required List<Map<String, String>> rows,
  }) async {
    previews.add(rows);
    return previewBuilder?.call(rows) ??
        CatalogPreview(
          rows: [
            for (var i = 0; i < rows.length; i++)
              CatalogRowResult(index: i, kind: CatalogRowKind.create),
          ],
          counts: {
            'create': rows.length,
            'exists': 0,
            'error': 0,
            'colleges': 1,
            'departments': 2,
            'courses': 3,
          },
        );
  }

  @override
  Future<CatalogImportResult> importCatalog({
    required String fileName,
    required String sheetName,
    required List<Map<String, String>> rows,
  }) async {
    imports.add(rows);
    return importResult;
  }
}

CatalogSheet _sheet(
  String name, {
  List<String> headers = const ['College', 'Course', 'Notes'],
  List<List<String>>? rows,
}) => CatalogSheet(
  name: name,
  headers: headers,
  rows:
      rows ??
      const [
        ['CITE', 'BSIT', 'x'],
        ['CITE', '', 'y'],
      ],
);

Future<void> _open(
  WidgetTester tester,
  _Repo repo,
  CatalogParseResult parsed,
) async {
  tester.view.physicalSize = const Size(1440, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AcademicStructurePage(
          repository: repo,
          pickFile: () async =>
              AdminImportFile(name: 'cat.xlsx', bytes: Uint8List(1)),
          parseFile: (_, _) => parsed,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Import catalogue'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose file'));
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester, [String label = 'Continue']) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String label) => tester
    .widget<FilledButton>(find.widgetWithText(FilledButton, label))
    .enabled;

void main() {
  testWidgets('three sheets: chooser states the count and defaults to first', (
    tester,
  ) async {
    await _open(
      tester,
      _Repo(),
      CatalogParseResult(
        sheets: [_sheet('A'), _sheet('B'), _sheet('C')],
        fileErrors: const ['1 sheet could not be read: Notes'],
      ),
    );
    expect(find.text('3 sheets were found.'), findsOneWidget);
    expect(find.text('1 sheet could not be read: Notes'), findsOneWidget);
    expect(
      tester.widget<RadioGroup<int>>(find.byType(RadioGroup<int>)).groupValue,
      0,
    );
  });

  testWidgets(
    'mapping lists six roles, detects, allows clear; gates Continue',
    (tester) async {
      await _open(
        tester,
        _Repo(),
        CatalogParseResult(sheets: [_sheet('A')], fileErrors: const []),
      );
      await _next(tester);
      for (final label in [
        'College *',
        'College code',
        'Department',
        'Department code',
        'Course *',
        'Course code',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('e.g. CITE'), findsOneWidget);
      expect(_enabled(tester, 'Continue'), isTrue);

      // Clear Course -> Continue disabled.
      await tester.tap(find.byKey(const ValueKey('map-course')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not in file').last);
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'Continue'), isFalse);
    },
  );

  testWidgets('rows: unmapped role absent, blank mapped cell is empty string', (
    tester,
  ) async {
    final repo = _Repo();
    await _open(
      tester,
      repo,
      CatalogParseResult(sheets: [_sheet('A')], fileErrors: const []),
    );
    await _next(tester);
    await _next(tester);
    expect(repo.previews.single, [
      {'college': 'CITE', 'course': 'BSIT'},
      {'college': 'CITE', 'course': ''},
    ]);
    expect(repo.previews.single.first.containsKey('department'), isFalse);
  });

  testWidgets('preview shows errors, invented department; Import disabled', (
    tester,
  ) async {
    final repo = _Repo()
      ..previewBuilder = (rows) => const CatalogPreview(
        rows: [
          CatalogRowResult(
            index: 0,
            kind: CatalogRowKind.create,
            inventedDepartment: 'CITE',
          ),
          CatalogRowResult(
            index: 1,
            kind: CatalogRowKind.error,
            errors: ['Course is required.'],
          ),
        ],
        counts: {
          'create': 1,
          'exists': 0,
          'error': 1,
          'colleges': 1,
          'departments': 1,
          'courses': 1,
        },
      );
    await _open(
      tester,
      repo,
      CatalogParseResult(sheets: [_sheet('A')], fileErrors: const []),
    );
    await _next(tester);
    await _next(tester);
    expect(find.text('Course is required.'), findsOneWidget);
    expect(find.textContaining('"CITE" will be created'), findsOneWidget);
    expect(find.textContaining('Will create'), findsNothing);
    expect(_enabled(tester, 'Import'), isFalse);
  });

  testWidgets('successful import shows counts and closes', (tester) async {
    final repo = _Repo();
    await _open(
      tester,
      repo,
      CatalogParseResult(sheets: [_sheet('A')], fileErrors: const []),
    );
    await _next(tester);
    await _next(tester);
    expect(find.textContaining('Will create 1 college'), findsOneWidget);
    await _next(tester, 'Import');
    expect(repo.imports.single, repo.previews.single);
    expect(find.text('Import complete'), findsOneWidget);
    expect(
      find.text('Created 1 college(s), 2 department(s) and 3 course(s).'),
      findsOneWidget,
    );
    await _next(tester, 'Done');
    expect(find.byType(AcademicCatalogImportDialog), findsNothing);
  });

  testWidgets('partial result shows message and committed counts', (
    tester,
  ) async {
    final repo = _Repo()
      ..importResult = const CatalogImportResult(
        importId: 'i',
        counts: {'colleges': 1, 'departments': 0, 'courses': 0},
        status: 'partial',
        message: 'Stopped after the first college.',
      );
    await _open(
      tester,
      repo,
      CatalogParseResult(sheets: [_sheet('A')], fileErrors: const []),
    );
    await _next(tester);
    await _next(tester);
    await _next(tester, 'Import');
    expect(find.text('Stopped after the first college.'), findsOneWidget);
    expect(
      find.textContaining('1 college(s), 0 department(s)'),
      findsOneWidget,
    );
    expect(find.text('Import complete'), findsNothing);
  });

  testWidgets('over 1,000 rows is refused before any call', (tester) async {
    final repo = _Repo();
    await _open(
      tester,
      repo,
      CatalogParseResult(
        sheets: [
          _sheet(
            'Big',
            rows: [
              for (var i = 0; i < 1001; i++) ['C$i', 'X$i', ''],
            ],
          ),
        ],
        fileErrors: const [],
      ),
    );
    expect(find.textContaining('split the file'), findsOneWidget);
    expect(_enabled(tester, 'Continue'), isFalse);
    expect(repo.previews, isEmpty);
  });
}
