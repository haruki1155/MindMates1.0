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
  List<RosterImportRecord>? importsOverride;
  Object? importsError;
  Future<void>? importsDelay;
  var _commitCalls = 0;
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
    return RosterImportResult(
      status: RosterImportStatus.complete,
      importId: 'imp-$index',
      counts: {'new': rows.length, 'updated': 0, 'linked': 0},
      codes: const [],
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

  List<StudentAccountClaim> claims = [];

  @override
  Future<List<StudentAccountClaim>> listAccountClaims() async {
    calls.add('claims');
    return List.of(claims);
  }

  @override
  Future<void> approveAccountClaim(String uid) async {
    calls.add('approve:$uid');
    claims.removeWhere((c) => c.uid == uid);
  }

  @override
  Future<void> rejectAccountClaim(String uid) async {
    calls.add('reject:$uid');
    claims.removeWhere((c) => c.uid == uid);
  }

  @override
  Future<void> revokeActivation(String studentNo, String reason) async {
    calls.add('revoke:$studentNo');
    lastRevokeReason = reason;
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
  Future<List<RosterImportRecord>> listImports() async {
    if (importsDelay != null) await importsDelay;
    if (importsError != null) throw importsError!;
    return importsOverride ??
        [
          RosterImportRecord(
            id: 'i1',
            fileName: 'registrar_2026.xlsx',
            counts: const {'new': 5, 'updated': 2, 'linked': 1},
            importedByName: 'Admin A',
            importedAt: DateTime.utc(2026, 11, 1, 8),
          ),
        ];
  }

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
    'import sends one call per chunk and summarises, with no activation codes',
    (tester) async {
      final repo = _Repo();
      await _pump(
        tester,
        repo,
        file: _csvFile([for (var i = 0; i < 2500; i++) _csvRow('S-$i')]),
      );
      await _chooseAndPreview(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(repo.commitSizes, [1000, 1000, 500]);
      expect(find.text('2500 new · 0 updated · 0 linked'), findsOneWidget);
      expect(find.textContaining('activation slips'), findsNothing);
      expect(find.textContaining('Activation code'), findsNothing);
    },
  );

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

  testWidgets('a partial result stops and warns', (tester) async {
    final repo = _Repo()
      ..commitOverride = (i) => i == 1
          ? RosterImportResult(
              status: RosterImportStatus.partial,
              importId: 'imp-1',
              counts: const {'new': 400, 'updated': 0, 'linked': 0},
              codes: const [],
              failedRows: const [
                RosterFailedRow(index: 400, studentNo: 'S-1400'),
                RosterFailedRow(index: 401, studentNo: 'S-1401'),
              ],
              message: 'A batch failed. 400 rows were committed.',
            )
          : null;
    await _pump(
      tester,
      repo,
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
    expect(find.textContaining('slips'), findsNothing);
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
    expect(find.text('Reset setup lock'), findsOneWidget);
    expect(find.textContaining('activation code'), findsNothing);
    expect(find.text('Revoke activation'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions for 2021-002'));
    await tester.pumpAndSettle();
    expect(find.text('Revoke activation'), findsOneWidget);
    expect(find.textContaining('activation code'), findsNothing);
  });

  testWidgets('edit, reset lock and deactivate call the repository', (
    tester,
  ) async {
    final repo = _Repo();
    await _pump(tester, repo);

    await openMenu(tester, '2021-001', 'Reset setup lock');
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

  testWidgets('revoke needs a reason and issues no code', (tester) async {
    final repo = _Repo();
    await _pump(tester, repo);
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
    expect(find.textContaining('can set up the account again'), findsOneWidget);
    expect(find.textContaining('activation slips'), findsNothing);
  });

  testWidgets('account requests: an administrator approves or rejects each one', (
    tester,
  ) async {
    StudentAccountClaim claim(String uid, String no) => StudentAccountClaim(
      uid: uid,
      studentNo: no,
      name: 'Ana Cruz',
      college: 'CITE',
      course: 'BSIT',
      yearLevel: '1st Year',
      email: '$uid@example.com',
      submittedAt: DateTime.utc(2026, 11, 20),
      rosterAlreadyClaimed: false,
    );
    final repo = _Repo()
      ..claims = [claim('u1', '2021-001'), claim('u2', '2021-002')];
    await _pump(tester, repo);
    await tester.tap(find.text('Account requests'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Personal email: u1@example.com'),
      findsOneWidget,
    );
    expect(find.textContaining('does not prove it'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
    await tester.pumpAndSettle();
    expect(
      repo.calls.where((c) => c.startsWith('approve')),
      isEmpty,
      reason: 'asks first',
    );
    // Approve stays disabled until the administrator attests they verified the student.
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve').last,
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('claim-identity-verified')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();
    expect(repo.calls, contains('approve:u1'));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reject').last);
    await tester.pumpAndSettle();
    expect(repo.calls, contains('reject:u2'));
    expect(find.text('No account requests are waiting.'), findsOneWidget);
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

  testWidgets(
    'import history renders complete, partial, pending, finalization-failed, legacy, empty, loading, and error states safely',
    (tester) async {
      final gate = Completer<void>();
      final loadingRepo = _Repo()..importsDelay = gate.future;
      await _pump(tester, loadingRepo);
      await tester.tap(find.text('Import history'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();

      final emptyRepo = _Repo()..importsOverride = const [];
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, emptyRepo);
      await _openTab(tester, 'Import history');
      expect(find.text('No imports yet.'), findsOneWidget);

      final errRepo = _Repo()
        ..importsError = FirebaseFunctionsException(
          message: 'History unavailable right now.',
          code: 'unavailable',
        );
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, errRepo);
      await _openTab(tester, 'Import history');
      expect(find.text('History unavailable right now.'), findsOneWidget);

      final repo = _Repo()
        ..importsOverride = [
          RosterImportRecord(
            id: 'c1',
            fileName: 'done.xlsx',
            status: RosterImportHistoryStatus.complete,
            rowCount: 15,
            failedRowCount: 0,
            counts: const {'new': 10, 'updated': 3, 'linked': 2},
            importedByName: 'Admin A',
            importedAt: DateTime.utc(2026, 11, 2, 8),
          ),
          RosterImportRecord(
            id: 'p1',
            fileName: 'part.xlsx',
            status: RosterImportHistoryStatus.partial,
            rowCount: 12,
            failedRowCount: 4,
            failureCode: 'time-budget-exceeded',
            counts: const {'new': 6, 'updated': 2, 'linked': 0},
            importedByName: 'Admin B',
            importedAt: DateTime.utc(2026, 11, 2, 9),
          ),
          RosterImportRecord(
            id: 'u1',
            fileName: 'crashed.xlsx',
            status: RosterImportHistoryStatus.pending,
            rowCount: 30,
            counts: const {'new': 0, 'updated': 0, 'linked': 0},
            importedByName: 'Admin C',
            importedAt: DateTime.utc(2026, 11, 2, 10),
          ),
          RosterImportRecord(
            id: 'f1',
            fileName: 'finfail.xlsx',
            status: RosterImportHistoryStatus.partial,
            rowCount: 20,
            failedRowCount: 0,
            failureCode: 'finalization-failed',
            counts: const {'new': 20, 'updated': 0, 'linked': 0},
            importedByName: 'Admin D',
            importedAt: DateTime.utc(2026, 11, 2, 11),
          ),
          RosterImportRecord(
            id: 'l1',
            fileName: 'legacy.xlsx',
            counts: const {'new': 4, 'updated': 0, 'linked': 0},
            importedByName: 'Admin E',
            importedAt: DateTime.utc(2026, 10, 1, 8),
          ),
        ];
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, repo);
      await _openTab(tester, 'Import history');

      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Partially imported'), findsOneWidget);
      expect(find.text('Not finalized'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Status unavailable'), findsOneWidget);
      expect(
        find.textContaining('10 new · 3 updated · 2 linked'),
        findsOneWidget,
      );
      expect(find.textContaining('4 row(s) not imported'), findsOneWidget);
      expect(
        find.textContaining('Import outcome requires verification.'),
        findsWidgets,
      );
      expect(find.textContaining('do not blindly re-upload'), findsWidgets);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('crashed.xlsx'),
            matching: find.byType(Card),
          ),
          matching: find.textContaining('0 new'),
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').contains('CODE0'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'aborted finalization directs admin safely to Import history without auto-retry',
    (tester) async {
      final repo = _Repo()
        ..beforeCommit = (i) async {
          throw FirebaseFunctionsException(
            message:
                'Roster records were updated, but finalizing the import log failed. Check Import History before retrying.',
            code: 'aborted',
          );
        };
      await _pump(
        tester,
        repo,
        file: _csvFile([for (var i = 0; i < 1500; i++) _csvRow('S-$i')]),
      );
      await _chooseAndPreview(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(
        repo.commitSizes,
        [1000],
        reason: 'must stop without retrying or sending remaining chunks',
      );
      expect(find.textContaining('Check Import history'), findsOneWidget);
      expect(
        find.textContaining('may already have been saved'),
        findsOneWidget,
      );
      expect(find.textContaining('FirebaseFunctionsException'), findsNothing);
    },
  );
}
