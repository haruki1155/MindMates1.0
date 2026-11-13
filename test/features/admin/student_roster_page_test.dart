import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:excel_plus/excel_plus.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/student_roster_page.dart';
import 'package:mind_mates/features/admin/services/admin_import_file_picker.dart';
import 'package:mind_mates/features/admin/services/student_roster_file_parser.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/student_personal_info.dart';
import 'package:mind_mates/models/student_roster_models.dart';
import 'package:mind_mates/repositories/student_roster_repository.dart';

const _header =
    'Student No.,Surname,First Name,Middle Name,Date of Birth (MM/DD/YYYY),College,Course,Year Level';

String _csvRow(String no, {String dob = '02/03/2005'}) =>
    '$no,Santos,Ana,,$dob,CITE,BSIT,1';

AdminImportFile _csvFile(List<String> rows, {String name = 'roster.csv'}) =>
    AdminImportFile(
      name: name,
      bytes: Uint8List.fromList(utf8.encode('$_header\n${rows.join('\n')}\n')),
    );

IssuedActivationCode _code(String studentNo, String code) =>
    IssuedActivationCode(
      studentNo: studentNo,
      name: 'Student $studentNo',
      college: 'CITE',
      course: 'BSIT',
      yearLevel: '1st Year',
      code: code,
      expiresAt: DateTime.utc(2027, 1, 12),
    );

RosterRowView _rosterRow(
  String no, {
  bool activated = false,
  String status = 'active',
}) => RosterRowView(
  studentNo: no,
  name: 'Student $no',
  college: 'CITE',
  course: 'BSIT',
  yearLevel: '1st Year',
  activated: activated,
  status: status,
  personalInfoComplete: activated,
  userId: activated ? 'uid-$no' : null,
);

class _Repo extends StudentRosterRepository {
  final calls = <String>[];
  final commitSizes = <int>[];
  final rosterStatuses = <String?>[];
  Object? approveError;
  List<RosterRowView> roster = [
    _rosterRow('2021-001'),
    _rosterRow('2021-002', activated: true),
  ];
  List<StudentCorrection> corrections = [];
  RosterImportResult? Function(int callIndex)? commitOverride;
  Future<void> Function(int callIndex)? beforeCommit;
  var _commitCalls = 0;
  var _codeSeq = 0;
  Map<String, String>? lastUpdateFields;
  String? lastReviewReason;
  String? lastRevokeReason;

  @override
  Future<({List<RosterPreviewRow> rows, Map<String, int> counts})>
  previewImport(String fileName, List<Map<String, String>> rows) async {
    calls.add('preview');
    var errors = 0;
    final out = <RosterPreviewRow>[];
    for (var i = 0; i < rows.length; i++) {
      final bad = rows[i]['studentNo']!.startsWith('ERR');
      final link = rows[i]['studentNo']!.startsWith('LNK');
      if (bad) errors++;
      out.add(
        RosterPreviewRow(
          index: i,
          studentNo: rows[i]['studentNo']!,
          kind: bad
              ? RosterPreviewKind.error
              : link
              ? RosterPreviewKind.link
              : rows[i]['studentNo']!.startsWith('UPD')
              ? RosterPreviewKind.update
              : RosterPreviewKind.newRow,
          changes: rows[i]['studentNo']!.startsWith('UPD')
              ? {'dateOfBirth': (from: '2005-02-03', to: '2005-02-04')}
              : const {},
          errors: bad ? const ['Course was not found.'] : const [],
          warnings: link
              ? const ['The existing account has a different name.']
              : const [],
        ),
      );
    }
    return (
      rows: out,
      counts: {
        'new': out.where((r) => r.kind == RosterPreviewKind.newRow).length,
        'update': out.where((r) => r.kind == RosterPreviewKind.update).length,
        'link': out.where((r) => r.kind == RosterPreviewKind.link).length,
        'error': errors,
      },
    );
  }

  @override
  Future<RosterImportResult> commitImport(
    String fileName,
    List<Map<String, String>> rows,
  ) async {
    calls.add('commit');
    commitSizes.add(rows.length);
    final index = _commitCalls++;
    await beforeCommit?.call(index);
    final override = commitOverride?.call(index);
    if (override != null) return override;
    final codes = [
      for (final r in rows)
        _code(
          r['studentNo']!,
          'CODE${(_codeSeq++).toString().padLeft(5, '0')}',
        ),
    ];
    return RosterImportResult(
      status: RosterImportStatus.complete,
      importId: 'imp-$index',
      counts: {'new': rows.length, 'updated': 0, 'linked': 0},
      codes: codes,
    );
  }

  @override
  Future<({List<RosterRowView> rows, String? nextPageToken})> listRoster({
    String? search,
    String? collegeId,
    String? courseId,
    String? yearLevel,
    String? status,
    String? pageToken,
  }) async {
    rosterStatuses.add(status);
    return (rows: roster, nextPageToken: null);
  }

  @override
  Future<void> updateRosterRecord(
    String studentNo,
    Map<String, String> fields,
  ) async {
    calls.add('update:$studentNo');
    lastUpdateFields = fields;
  }

  @override
  Future<void> setRosterStatus(String studentNo, {required bool active}) async {
    calls.add('status:$studentNo:${active ? 'active' : 'deactivated'}');
  }

  @override
  Future<void> resetActivationLock(String studentNo) async {
    calls.add('lock:$studentNo');
  }

  @override
  Future<
    ({
      List<IssuedActivationCode> codes,
      List<({String studentNo, String reason})> skipped,
    })
  >
  issueActivationCodes(List<String> studentNos) async {
    calls.add('issue:${studentNos.join('|')}');
    return (
      codes: [for (final n in studentNos) _code(n, 'ISSUE${n.length}')],
      skipped: const <({String studentNo, String reason})>[],
    );
  }

  @override
  Future<IssuedActivationCode> revokeActivation(
    String studentNo,
    String reason,
  ) async {
    calls.add('revoke:$studentNo');
    lastRevokeReason = reason;
    return _code(studentNo, 'REVOKE-NEWCODE');
  }

  @override
  Future<List<StudentCorrection>> listCorrections({
    bool pendingOnly = false,
  }) async => corrections;

  @override
  Future<String> reviewCorrection(
    String requestId, {
    required bool approve,
    String? reason,
  }) async {
    calls.add('review:$requestId:${approve ? 'approve' : 'reject'}');
    lastReviewReason = reason;
    final error = approveError;
    if (approve && error != null) throw error;
    return approve ? 'approved' : 'rejected';
  }

  @override
  Future<List<RosterImportRecord>> listImports() async => [
    RosterImportRecord(
      id: 'i1',
      fileName: 'registrar_2026.xlsx',
      counts: const {'new': 5, 'updated': 2, 'linked': 1},
      importedByName: 'Admin A',
      importedAt: DateTime.utc(2026, 11, 1, 8),
    ),
  ];

  @override
  Future<List<LegacyStudent>> listLegacyNotInRoster() async => const [
    LegacyStudent(userId: 'u9', schoolId: '2019-777', name: 'Old Timer'),
  ];
}

class _Downloads {
  final files = <({String name, List<int> bytes})>[];
  void call(String name, List<int> bytes, String mime) =>
      files.add((name: name, bytes: bytes));
}

Future<void> _pump(
  WidgetTester tester,
  _Repo repo, {
  AdminImportFile? file,
  _Downloads? downloads,
  StudentRosterLeaveGuard? guard,
}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dl = downloads ?? _Downloads();
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
      home: Scaffold(
        body: StudentRosterPage(
          repository: repo,
          pickFile: () async => file,
          download: dl.call,
          leaveGuard: guard,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _chooseAndPreview(WidgetTester tester) async {
  await _openTab(tester, 'Import');
  await tester.tap(find.text('Choose roster file'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Preview'));
  await tester.pumpAndSettle();
}

FilledButton _button(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is FilledButton),
          )
          .first,
    );

void main() {
  testWidgets('duplicates across the file are shown and block Preview', (
    tester,
  ) async {
    final repo = _Repo();
    await _pump(
      tester,
      repo,
      file: _csvFile([_csvRow('2021-001'), _csvRow('2021001')]),
    );
    await _openTab(tester, 'Import');
    await tester.tap(find.text('Choose roster file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2021001 appears on rows 2, 3'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Preview'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a link row warning is shown and still allows the import', (
    tester,
  ) async {
    final repo = _Repo();
    await _pump(tester, repo, file: _csvFile([_csvRow('LNK-001')]));
    await _chooseAndPreview(tester);

    expect(find.text('LNK-001 · Links account'), findsOneWidget);
    expect(
      find.text('The existing account has a different name.'),
      findsOneWidget,
    );
    // A warning is not an error: Import stays enabled.
    expect(_button(tester, 'Import').onPressed, isNotNull);
  });

  testWidgets('a missing column is shown as a file error', (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      repo,
      file: AdminImportFile(
        name: 'bad.csv',
        bytes: Uint8List.fromList(utf8.encode('Student No.,Surname\n1,2\n')),
      ),
    );
    await _openTab(tester, 'Import');
    await tester.tap(find.text('Choose roster file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Missing columns'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Preview'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('preview shows counts, spelled dates and per-row changes', (
    tester,
  ) async {
    final repo = _Repo();
    await _pump(
      tester,
      repo,
      file: _csvFile([_csvRow('2021-001'), _csvRow('UPD-1')]),
    );
    await _chooseAndPreview(tester);
    expect(find.text('New 1'), findsOneWidget);
    expect(find.text('Update 1'), findsOneWidget);
    expect(find.text('Links account 0'), findsOneWidget);
    expect(find.text('Error 0'), findsOneWidget);
    expect(find.textContaining('Born Feb 3, 2005'), findsWidgets);
    expect(
      find.textContaining('dateOfBirth: Feb 3, 2005 → Feb 4, 2005'),
      findsOneWidget,
    );
    expect(_button(tester, 'Import').onPressed, isNotNull);
  });

  testWidgets('any error row disables Import', (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      repo,
      file: _csvFile([_csvRow('2021-001'), _csvRow('ERR-1')]),
    );
    await _chooseAndPreview(tester);
    expect(find.text('Error 1'), findsOneWidget);
    expect(find.text('Course was not found.'), findsOneWidget);
    expect(_button(tester, 'Import').onPressed, isNull);
  });

  testWidgets(
    'import sends one call per chunk, summarises and offers every code once',
    (tester) async {
      final repo = _Repo();
      final downloads = _Downloads();
      final guard = StudentRosterLeaveGuard();
      await _pump(
        tester,
        repo,
        downloads: downloads,
        guard: guard,
        file: _csvFile([for (var i = 0; i < 2500; i++) _csvRow('S-$i')]),
      );
      await _chooseAndPreview(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(repo.commitSizes, [1000, 1000, 500]);
      expect(find.text('2500 new · 0 updated · 0 linked'), findsOneWidget);
      expect(find.text('Download activation slips (2500)'), findsOneWidget);
      expect(find.text(codesShownOnceWarning), findsOneWidget);
      expect(guard.hasUndownloadedCodes, isTrue);

      // Leaving with undownloaded codes asks first.
      final context = tester.element(find.byType(StudentRosterPage));
      var left = true;
      final pending = guard.confirmLeave(context).then((v) => left = v);
      await tester.pumpAndSettle();
      expect(find.text('Leave without downloading?'), findsOneWidget);
      await tester.tap(find.text('Stay on page'));
      await tester.pumpAndSettle();
      await pending;
      expect(left, isFalse);

      await tester.tap(find.text('Download activation slips (2500)'));
      await tester.pumpAndSettle();
      expect(downloads.files, hasLength(1));
      expect(guard.hasUndownloadedCodes, isFalse);
      expect(await guard.confirmLeave(context), isTrue);

      final book = excel.Excel.decodeBytes(downloads.files.single.bytes);
      final rows = book.tables.values.first.rows
          .skip(1)
          .map((r) => r[5]?.value.toString())
          .toList();
      expect(rows, hasLength(2500));
      expect(rows.toSet(), hasLength(2500));
      expect(rows.first, 'CODE00000');
      expect(rows.last, 'CODE02499');
    },
  );

  testWidgets('codes are never written to debug logs', (tester) async {
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    final repo = _Repo();
    await _pump(tester, repo, file: _csvFile([_csvRow('S-1'), _csvRow('S-2')]));
    await _chooseAndPreview(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download activation slips (2)'));
    await tester.pumpAndSettle();
    debugPrint = original;
    expect(logged.where((l) => l.contains('CODE0')), isEmpty);
  });

  testWidgets('an in-flight import counts as codes at risk for leaving', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = _Repo()..beforeCommit = (i) => gate.future;
    final guard = StudentRosterLeaveGuard();
    await _pump(tester, repo, guard: guard, file: _csvFile([_csvRow('S-1')]));
    await _chooseAndPreview(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pump();
    expect(guard.hasUndownloadedCodes, isTrue);
    final context = tester.element(find.byType(StudentRosterPage));
    final pending = guard.confirmLeave(context);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Leave without downloading?'), findsOneWidget);
    await tester.tap(find.text('Stay on page'));
    await tester.pump();
    expect(await pending, isFalse);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('no further chunks are sent once the page is disposed', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = _Repo()
      ..beforeCommit = (i) => i == 0 ? gate.future : Future.value();
    await _pump(
      tester,
      repo,
      file: _csvFile([for (var i = 0; i < 1500; i++) _csvRow('S-$i')]),
    );
    await _chooseAndPreview(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.commitSizes, [1000]);
  });

  testWidgets('slips stay available after choosing a new file and a new '
      'import asks before discarding undownloaded codes', (tester) async {
    final repo = _Repo();
    final guard = StudentRosterLeaveGuard();
    await _pump(tester, repo, guard: guard, file: _csvFile([_csvRow('S-1')]));
    await _chooseAndPreview(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
    expect(find.text('Download activation slips (1)'), findsOneWidget);

    await tester.tap(find.text('Choose roster file'));
    await tester.pumpAndSettle();
    expect(find.text('Download activation slips (1)'), findsOneWidget);
    expect(guard.hasUndownloadedCodes, isTrue);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
    expect(find.text('Discard undownloaded codes?'), findsOneWidget);
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(repo.commitSizes, [1]);
    expect(find.text('Download activation slips (1)'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and import'));
    await tester.pumpAndSettle();
    expect(repo.commitSizes, [1, 1]);
  });

  testWidgets('a partial result stops, warns and still offers the slips', (
    tester,
  ) async {
    final repo = _Repo()
      ..commitOverride = (i) => i == 1
          ? RosterImportResult(
              status: RosterImportStatus.partial,
              importId: 'imp-1',
              counts: const {'new': 400, 'updated': 0, 'linked': 0},
              codes: [_code('S-1000', 'PARTIAL001')],
              failedRows: const [
                RosterFailedRow(index: 400, studentNo: 'S-1400'),
                RosterFailedRow(index: 401, studentNo: 'S-1401'),
              ],
              message: 'A batch failed. 400 rows were committed.',
            )
          : null;
    final guard = StudentRosterLeaveGuard();
    await _pump(
      tester,
      repo,
      guard: guard,
      file: _csvFile([for (var i = 0; i < 2500; i++) _csvRow('S-$i')]),
    );
    await _chooseAndPreview(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(repo.commitSizes, [1000, 1000], reason: 'no third chunk');
    expect(find.text('Import only partly completed'), findsOneWidget);
    expect(
      find.text('A batch failed. 400 rows were committed.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('1400 new · 0 updated · 0 linked'),
      findsWidgets,
    );
    expect(find.text('2 row(s) were not imported.'), findsOneWidget);
    expect(find.text('Download activation slips (1001)'), findsOneWidget);
    expect(guard.hasUndownloadedCodes, isTrue);
  });

  testWidgets('Download template produces the header row', (tester) async {
    final downloads = _Downloads();
    await _pump(tester, _Repo(), downloads: downloads);
    await _openTab(tester, 'Import');
    await tester.tap(find.text('Download template'));
    await tester.pumpAndSettle();
    final book = excel.Excel.decodeBytes(downloads.files.single.bytes);
    final header = book.tables.values.first.rows.first
        .map((c) => c?.value.toString())
        .toList();
    expect(header, rosterTemplateHeaders);
  });

  testWidgets('status filter calls listRoster with the chosen status', (
    tester,
  ) async {
    final repo = _Repo();
    await _pump(tester, repo);
    expect(repo.rosterStatuses.last, '');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivated').last);
    await tester.pumpAndSettle();
    expect(repo.rosterStatuses.last, 'deactivated');
  });

  Future<void> openMenu(
    WidgetTester tester,
    String studentNo,
    String item,
  ) async {
    await tester.tap(find.byTooltip('Actions for $studentNo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  testWidgets('row menus expose the right actions per state', (tester) async {
    await _pump(tester, _Repo());
    await tester.tap(find.byTooltip('Actions for 2021-001'));
    await tester.pumpAndSettle();
    expect(find.text('Issue new activation code'), findsOneWidget);
    expect(find.text('Reset activation lock'), findsOneWidget);
    expect(find.text('Revoke activation'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions for 2021-002'));
    await tester.pumpAndSettle();
    expect(find.text('Revoke activation'), findsOneWidget);
    expect(find.text('Issue new activation code'), findsNothing);
  });

  testWidgets('edit, reset lock and deactivate call the repository', (
    tester,
  ) async {
    final repo = _Repo();
    await _pump(tester, repo);

    await openMenu(tester, '2021-001', 'Reset activation lock');
    expect(repo.calls, contains('lock:2021-001'));

    await openMenu(tester, '2021-001', 'Edit');
    await tester.enterText(find.widgetWithText(TextField, 'Surname'), 'Reyes');
    await tester.enterText(
      find.widgetWithText(TextField, 'Date of birth'),
      '02/04/2005',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('update:2021-001'));
    expect(repo.lastUpdateFields, {
      'surname': 'Reyes',
      'dateOfBirth': '2005-02-04',
      'college': 'CITE',
      'course': 'BSIT',
    });

    await openMenu(tester, '2021-001', 'Deactivate');
    expect(find.text('Deactivate student?'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('status')), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('status:2021-001:deactivated'));
  });

  testWidgets('Reactivate asks for confirmation too', (tester) async {
    final repo = _Repo()
      ..roster = [_rosterRow('2021-005', status: 'deactivated')];
    await _pump(tester, repo);
    await openMenu(tester, '2021-005', 'Reactivate');
    expect(find.text('Reactivate student?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reactivate'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('status:2021-005:active'));
  });

  testWidgets('issue new code per row and in bulk offers slips', (
    tester,
  ) async {
    final repo = _Repo()
      ..roster = [_rosterRow('2021-001'), _rosterRow('2021-003')];
    final downloads = _Downloads();
    await _pump(tester, repo, downloads: downloads);

    await openMenu(tester, '2021-001', 'Issue new activation code');
    await tester.tap(find.widgetWithText(FilledButton, 'Issue'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('issue:2021-001'));
    expect(find.text(codesShownOnceWarning), findsOneWidget);
    await tester.tap(find.text('Download activation slips (1)'));
    await tester.pumpAndSettle();
    expect(downloads.files, hasLength(1));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).at(0));
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Issue activation codes (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Issue'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('issue:2021-001|2021-003'));
    expect(find.text('Download activation slips (2)'), findsOneWidget);
  });

  testWidgets('revoke needs a reason, then shows the new code to download', (
    tester,
  ) async {
    final repo = _Repo();
    final downloads = _Downloads();
    await _pump(tester, repo, downloads: downloads);
    await openMenu(tester, '2021-002', 'Revoke activation');

    final confirm = find.widgetWithText(FilledButton, 'Revoke activation');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason'),
      'Wrong person',
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(repo.calls, contains('revoke:2021-002'));
    expect(repo.lastRevokeReason, 'Wrong person');
    expect(find.textContaining('REVOKE-NEWCODE'), findsOneWidget);
    await tester.tap(find.text('Download activation slips (1)'));
    await tester.pumpAndSettle();
    expect(downloads.files, hasLength(1));
  });

  testWidgets('corrections: reject needs a reason, approve works', (
    tester,
  ) async {
    final repo = _Repo()
      ..corrections = [
        StudentCorrection(
          id: 'c1',
          field: 'surname',
          currentValue: 'Santos',
          requestedValue: 'Santoz',
          reason: 'Typo',
          status: 'pending',
          reviewReason: '',
          createdAt: DateTime.utc(2026, 11, 2),
          studentNo: '2021-001',
          studentName: 'Ana Santos',
        ),
      ];
    await _pump(tester, repo);
    await _openTab(tester, 'Corrections');
    expect(find.text('Ana Santos · 2021-001'), findsOneWidget);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    final reject = find.widgetWithText(FilledButton, 'Reject');
    expect(tester.widget<FilledButton>(reject).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason'),
      'Not valid',
    );
    await tester.pumpAndSettle();
    await tester.tap(reject);
    await tester.pumpAndSettle();
    expect(repo.calls, contains('review:c1:reject'));
    expect(repo.lastReviewReason, 'Not valid');
    expect(find.text('No pending correction requests.'), findsOneWidget);
  });

  testWidgets(
    'a college/course precondition failure offers the Edit record shortcut',
    (tester) async {
      final repo = _Repo()
        ..approveError = FirebaseFunctionsException(
          message: 'The course is not under the selected college.',
          code: 'failed-precondition',
        )
        ..corrections = [
          StudentCorrection(
            id: 'c2',
            field: 'college',
            currentValue: 'CITE',
            requestedValue: 'CBA',
            reason: 'Shifted',
            status: 'pending',
            reviewReason: '',
            createdAt: DateTime.utc(2026, 11, 2),
            studentNo: '2021-001',
            studentName: 'Ana Santos',
          ),
        ];
      await _pump(tester, repo);
      await _openTab(tester, 'Corrections');
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(
        find.text('The course is not under the selected college.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Edit record'));
      await tester.pumpAndSettle();
      expect(find.text('Edit 2021-001'), findsOneWidget);
      // College is prefilled with the requested value; admin can fix course too.
      expect(find.widgetWithText(TextField, 'CBA'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Course'), 'BSBA');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.lastUpdateFields, {'college': 'CBA', 'course': 'BSBA'});
    },
  );

  testWidgets('import history and legacy tabs list their data', (tester) async {
    await _pump(tester, _Repo());
    await _openTab(tester, 'Import history');
    expect(find.text('registrar_2026.xlsx'), findsOneWidget);
    expect(find.textContaining('5 new · 2 updated · 1 linked'), findsOneWidget);
    await _openTab(tester, 'Legacy – not in roster');
    expect(find.text('Old Timer'), findsOneWidget);
    expect(find.text('2019-777'), findsOneWidget);
  });
}
