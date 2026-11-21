import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/session_evidence.dart';
import 'package:mind_mates/features/admin/widgets/clinical_interview_widgets.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _NoteRepo extends AdminPortalRepository {
  _NoteRepo({this.onDownload, this.record});

  final Future<Uint8List> Function(String path, String? appointmentId)?
  onDownload;
  final SessionEvidenceRecord? record;
  String? lastPath;
  String? lastAppointmentId;

  @override
  Future<SessionEvidenceRecord?> getClinicalSessionEvidence(
    String appointmentId,
  ) async =>
      record ??
      const SessionEvidenceRecord(
        summary: 'Session review saved',
        attachments: [
          SessionEvidenceAttachment(
            path:
                'counseling_session_files/appointment-1/counselor/0123456789abcdef0123456789abcdef.pdf',
            name: 'Interview worksheet.pdf',
            contentType: 'application/pdf',
            size: 1024,
          ),
        ],
      );

  @override
  Future<Uint8List> getClinicalEvidenceBytes(
    String path, {
    String? appointmentId,
  }) async {
    lastPath = path;
    lastAppointmentId = appointmentId;
    final handler = onDownload;
    if (handler != null) return handler(path, appointmentId);
    return Uint8List.fromList([1, 2, 3, 4]);
  }
}

void main() {
  testWidgets('interview completion displays only the file upload controls', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: ClinicalInterviewEditor(
        files: const [],
        busy: false,
        onChooseFiles: () => tapped = true,
        onRemoveFile: (_) {},
      )),
    )));
    expect(find.text('Session attachments'), findsOneWidget);
    expect(find.text('Add images / documents'), findsOneWidget);
    expect(find.text('Interview questions asked'), findsNothing);
    expect(find.text('Student requirements checked'), findsNothing);
    expect(find.text('Materials used'), findsNothing);
    await tester.tap(find.text('Add images / documents'));
    expect(tapped, isTrue);
  });

  testWidgets('selected file is listed and removable before saving', (tester) async {
    int? removedIndex;
    final file = PendingSessionEvidenceFile(
      name: 'Interview worksheet.pdf',
      contentType: 'application/pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ClinicalInterviewEditor(
        files: [file],
        busy: false,
        onChooseFiles: () {},
        onRemoveFile: (index) => removedIndex = index,
      )),
    ));
    expect(find.text('Interview worksheet.pdf'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Interview worksheet.pdf'));
    expect(removedIndex, 0);
  });

  testWidgets('read-only documentation loads private saved summary on demand', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ClinicalInterviewRecordViewer(
      repository: _NoteRepo(),
      appointmentId: 'appointment-1',
    ))));
    expect(find.text('Session review saved'), findsNothing);
    await tester.tap(find.text('View session documentation'));
    await tester.pumpAndSettle();
    expect(find.text('Session review saved'), findsOneWidget);
    expect(find.text('Interview worksheet.pdf'), findsOneWidget);
    expect(find.byTooltip('Download Interview worksheet.pdf'), findsOneWidget);
    expect(find.text('Interview questions asked'), findsNothing);
    expect(find.text('Student requirements checked'), findsNothing);
    expect(find.text('Materials used'), findsNothing);
  });

  testWidgets('download passes appointmentId, disables button in-flight, and saves exact bytes/filename/MIME', (tester) async {
    final completer = Completer<Uint8List>();
    final payload = Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 52]);
    final repo = _NoteRepo(onDownload: (_, _) => completer.future);
    Uint8List? savedBytes;
    String? savedName;
    String? savedMime;

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ClinicalInterviewRecordViewer(
      repository: repo,
      appointmentId: 'appointment-1',
      saveFile: (bytes, fileName, contentType) async {
        savedBytes = bytes;
        savedName = fileName;
        savedMime = contentType;
      },
    ))));
    await tester.tap(find.text('View session documentation'));
    await tester.pumpAndSettle();

    final buttonFinder = find.widgetWithIcon(IconButton, Icons.download_outlined);
    await tester.tap(buttonFinder);
    await tester.pump();

    expect(repo.lastAppointmentId, 'appointment-1');
    expect(
      repo.lastPath,
      'counseling_session_files/appointment-1/counselor/0123456789abcdef0123456789abcdef.pdf',
    );
    expect(tester.widget<IconButton>(buttonFinder).onPressed, isNull);

    completer.complete(payload);
    await tester.pumpAndSettle();

    expect(savedBytes, payload);
    expect(savedName, 'Interview worksheet.pdf');
    expect(savedMime, 'application/pdf');
    expect(tester.widget<IconButton>(buttonFinder).onPressed, isNotNull);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('maps permission-denied, missing-file, oversized/invalid, network/timeout, and unsupported-platform errors safely without leaking paths or tokens', (tester) async {
    final errorCases = <({Object error, List<String> expectedAny})>[
      (
        error: FirebaseFunctionsException(code: 'permission-denied', message: 'Denied'),
        expectedAny: ['permission', 'authorized'],
      ),
      (
        error: FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'),
        expectedAny: ['permission', 'authorized'],
      ),
      (
        error: FirebaseFunctionsException(code: 'not-found', message: 'Missing'),
        expectedAny: ['no longer available', 'not found', 'unavailable'],
      ),
      (
        error: FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'),
        expectedAny: ['no longer available', 'not found', 'unavailable'],
      ),
      (
        error: FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Oversized counseling_session_files/appointment-1/counselor/abc.pdf',
        ),
        expectedAny: ['5 mb', 'invalid', 'cannot be downloaded', 'unable to download'],
      ),
      (
        error: const FormatException('gs://bucket/counseling_session_files/secret?token=abc'),
        expectedAny: ['invalid', 'cannot be downloaded', 'unable to download'],
      ),
      (
        error: FirebaseFunctionsException(
          code: 'internal',
          message: 'INTERNAL https://storage.googleapis.com/bucket?token=secret123',
        ),
        expectedAny: ['unable to download', 'error', 'try again'],
      ),
      (
        error: TimeoutException('timed out'),
        expectedAny: ['did not respond in time', 'timed out'],
      ),
      (
        error: FirebaseFunctionsException(code: 'unavailable', message: 'Offline'),
        expectedAny: ['unavailable', 'connection'],
      ),
    ];

    for (var i = 0; i < errorCases.length; i++) {
      final testCase = errorCases[i];
      final repo = _NoteRepo(onDownload: (_, _) async => throw testCase.error);
      await tester.pumpWidget(MaterialApp(
        key: ValueKey('error-case-$i'),
        home: Scaffold(body: ClinicalInterviewRecordViewer(
          repository: repo,
          appointmentId: 'appointment-1',
          saveFile: (_, _, _) async {},
        )),
      ));
      await tester.tap(find.text('View session documentation'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Download Interview worksheet.pdf'));
      await tester.pumpAndSettle();

      final snackBarFinder = find.byType(SnackBar);
      expect(snackBarFinder, findsOneWidget);
      final snackText = tester.widget<Text>(
        find.descendant(of: snackBarFinder, matching: find.byType(Text)),
      ).data!;
      expect(snackText, isNot('Unable to download this private file.'));
      expect(snackText, isNot(contains('counseling_session_files/')));
      expect(snackText, isNot(contains('gs://')));
      expect(snackText, isNot(contains('https://')));
      expect(snackText, isNot(contains('token=')));
      expect(snackText, isNot(contains('INTERNAL')));
      expect(snackText, isNot(contains('App Check')));
      expect(
        testCase.expectedAny.any((needle) => snackText.toLowerCase().contains(needle)),
        isTrue,
        reason: 'Unexpected SnackBar text "$snackText" for ${testCase.error}',
      );
    }

    // Unsupported platform (omitted saveFile invokes VM stub throwing UnsupportedError).
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ClinicalInterviewRecordViewer(
      repository: _NoteRepo(),
      appointmentId: 'appointment-1',
    ))));
    await tester.tap(find.text('View session documentation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Download Interview worksheet.pdf'));
    await tester.pumpAndSettle();

    final stubSnack = tester.widget<Text>(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
    ).data!;
    expect(stubSnack, 'Clinical file downloading is available in the Web portal.');
  });

  testWidgets('redacts URL-encoded, backslash, and storage domain leaks on pass-through FirebaseFunctionsException codes', (tester) async {
    const safeFallback =
        'Unable to download this private file right now. Please try again.';
    final leakyMessages = <String>[
      'Missing counseling_session_files%2Fapt-1%2Fu1%2Fabc.pdf',
      'Redirect https%3A%2F%2Fexample.test%2Fo',
      'Expired token%3Dsecret123',
      'Object gs%3A%2F%2Fbucket%2Ffile',
      r'Windows path counseling_session_files\apt-1\u1\abc.pdf',
      'Denied at firebasestorage.googleapis.com/v0/b/bucket/o',
    ];

    for (var i = 0; i < leakyMessages.length; i++) {
      final rawMessage = leakyMessages[i];
      final repo = _NoteRepo(
        onDownload: (_, _) async => throw FirebaseFunctionsException(
          code: 'already-exists',
          message: rawMessage,
        ),
      );
      await tester.pumpWidget(MaterialApp(
        key: ValueKey('encoded-leak-$i'),
        home: Scaffold(body: ClinicalInterviewRecordViewer(
          repository: repo,
          appointmentId: 'appointment-1',
          saveFile: (_, _, _) async {},
        )),
      ));
      await tester.tap(find.text('View session documentation'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Download Interview worksheet.pdf'));
      await tester.pumpAndSettle();

      final snackText = tester.widget<Text>(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
      ).data!;
      expect(
        snackText,
        safeFallback,
        reason: 'Leaked upstream message "$rawMessage" as "$snackText"',
      );

      final unsupportedRepo = _NoteRepo(
        onDownload: (_, _) async => throw UnsupportedError(rawMessage),
      );
      await tester.pumpWidget(MaterialApp(
        key: ValueKey('unsupported-encoded-leak-$i'),
        home: Scaffold(body: ClinicalInterviewRecordViewer(
          repository: unsupportedRepo,
          appointmentId: 'appointment-1',
          saveFile: (_, _, _) async {},
        )),
      ));
      await tester.tap(find.text('View session documentation'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Download Interview worksheet.pdf'));
      await tester.pumpAndSettle();

      final unsupportedSnackText = tester.widget<Text>(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
      ).data!;
      expect(
        unsupportedSnackText,
        'Clinical file downloading is available in the Web portal.',
        reason:
            'UnsupportedError leaked upstream message "$rawMessage" as "$unsupportedSnackText"',
      );
    }
  });

  testWidgets('sanitizes control-character, whitespace-only, and slash-only filenames to attachment fallback', (tester) async {
    final filenameCases = <({String rawName, String expectedName})>[
      (rawName: '   \n\t  ', expectedName: 'attachment'),
      (rawName: '///\n\t', expectedName: 'attachment'),
      (rawName: '..\\\\//\r\n\t', expectedName: 'attachment'),
      (rawName: '  session\n\t/report\\v1.pdf  ', expectedName: 'session_report_v1.pdf'),
    ];

    for (var i = 0; i < filenameCases.length; i++) {
      final testCase = filenameCases[i];
      String? savedName;
      final repo = _NoteRepo(
        record: SessionEvidenceRecord(
          summary: 'Session review saved',
          attachments: [
            SessionEvidenceAttachment(
              path:
                  'counseling_session_files/appointment-1/counselor/0123456789abcdef0123456789abcdef.pdf',
              name: testCase.rawName,
              contentType: 'application/pdf',
              size: 1024,
            ),
          ],
        ),
      );
      await tester.pumpWidget(MaterialApp(
        key: ValueKey('filename-case-$i'),
        home: Scaffold(body: ClinicalInterviewRecordViewer(
          repository: repo,
          appointmentId: 'appointment-1',
          saveFile: (_, fileName, _) async {
            savedName = fileName;
          },
        )),
      ));
      await tester.tap(find.text('View session documentation'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.download_outlined));
      await tester.pumpAndSettle();

      expect(
        savedName,
        testCase.expectedName,
        reason: 'Unexpected sanitized filename "$savedName" for rawName=${testCase.rawName.codeUnits}',
      );
    }
  });
}
