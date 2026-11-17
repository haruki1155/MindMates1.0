import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/widgets/case_remarks_editor.dart';
import 'package:mind_mates/models/case_remarks_model.dart';

CaseRemarks _remarks(
  String text,
  int revision, {
  String author = 'Coach Cite',
  List<CaseRemarksVersion> versions = const [],
}) => CaseRemarks(
  appointmentId: 'a1',
  text: text,
  revision: revision,
  updatedAt: revision == 0 ? null : DateTime.utc(2026, 11, 16, 1),
  authorName: revision == 0 ? '' : author,
  versions: versions,
);

Widget _host(Widget child, {double width = 1000}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(child: child),
      ),
    ),
  ),
);

Finder get _field => find.byKey(const Key('case-remarks-field'));
Finder get _saveButton => find.widgetWithText(FilledButton, 'Save remarks');

void main() {
  testWidgets('the field is labeled optional and a case with no remarks '
      'can be left blank', (tester) async {
    await tester.pumpWidget(
      _host(
        CaseRemarksEditor(
          load: () async => _remarks('', 0),
          save: (_, _) async => fail('nothing to save'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transcript / Remarks (optional)'), findsOneWidget);
    expect(find.text('No remarks saved yet.'), findsOneWidget);
    // Blank and unchanged: nothing to save, and no error.
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);
  });

  testWidgets('saving sends the text and the loaded revision, then shows '
      'who saved it', (tester) async {
    final saves = <(String, int)>[];
    await tester.pumpWidget(
      _host(
        CaseRemarksEditor(
          load: () async => _remarks('Old', 1),
          save: (text, revision) async {
            saves.add((text, revision));
            return _remarks(text, revision + 1, author: 'Coach Two');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('revision 1'), findsOneWidget);

    await tester.enterText(_field, 'Line one\nLine two');
    await tester.pump();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(saves, [('Line one\nLine two', 1)]);
    expect(find.textContaining('Last saved by Coach Two'), findsOneWidget);
    expect(find.textContaining('revision 2'), findsOneWidget);
  });

  testWidgets('clearing saved remarks requires confirmation and is allowed', (
    tester,
  ) async {
    final saves = <(String, int)>[];
    await tester.pumpWidget(
      _host(
        CaseRemarksEditor(
          load: () async => _remarks('Something', 3),
          save: (text, revision) async {
            saves.add((text, revision));
            return _remarks(text, 4);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field, '');
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(find.text('Clear saved remarks?'), findsOneWidget);
    await tester.tap(find.text('Clear remarks'));
    await tester.pumpAndSettle();
    expect(saves, [('', 3)]);
  });

  testWidgets('a reload shows the stored text, not a stale draft', (
    tester,
  ) async {
    var stored = _remarks('Saved on the server', 2);
    Widget editor(Key key) => _host(
      CaseRemarksEditor(
        key: key,
        load: () async => stored,
        save: (_, _) async => stored,
      ),
    );
    await tester.pumpWidget(editor(const ValueKey(1)));
    await tester.pumpAndSettle();
    await tester.enterText(_field, 'Typed but never saved');

    stored = _remarks('Saved on the server', 2);
    await tester.pumpWidget(editor(const ValueKey(2)));
    await tester.pumpAndSettle();

    expect(find.text('Saved on the server'), findsOneWidget);
    expect(find.text('Typed but never saved'), findsNothing);
  });

  testWidgets('a failed save keeps the typed text and says it was not saved', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CaseRemarksEditor(
          load: () async => _remarks('', 0),
          save: (_, _) async => throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'offline',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field, 'Do not lose me');
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Do not lose me'), findsOneWidget);
    expect(find.textContaining('Remarks were not saved'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('a conflict keeps the draft and offers the latest version', (
    tester,
  ) async {
    var server = _remarks('Original', 1);
    await tester.pumpWidget(
      _host(
        CaseRemarksEditor(
          load: () async => server,
          save: (_, _) async => throw FirebaseFunctionsException(
            code: 'aborted',
            message: 'changed',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field, 'My edit');
    await tester.pump();
    server = _remarks('Someone else edit', 2, author: 'Coach Two');
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('changed by someone else'), findsOneWidget);
    expect(find.text('My edit'), findsOneWidget);

    await tester.tap(find.text('Reload latest'));
    await tester.pumpAndSettle();

    expect(find.text('Someone else edit'), findsOneWidget);
    expect(find.text('Your unsaved text'), findsOneWidget);
    expect(find.text('My edit'), findsOneWidget);
  });

  testWidgets(
    'a refused counselor sees a not-authorized message and no field',
    (tester) async {
      await tester.pumpWidget(
        _host(
          CaseRemarksEditor(
            load: () async => throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'no',
            ),
            save: (_, _) async => fail('must not save'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('not authorized'), findsOneWidget);
      expect(_field, findsNothing);
    },
  );

  testWidgets("switching accounts never shows the previous account's text", (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CaseRemarksEditor(
          key: const ValueKey('counselor-a'),
          load: () async => _remarks('Counselor A private text', 1),
          save: (_, _) async => fail('no save'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Counselor A private text'), findsOneWidget);

    await tester.pumpWidget(
      _host(
        CaseRemarksEditor(
          key: const ValueKey('counselor-b'),
          load: () async => throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'no',
          ),
          save: (_, _) async => fail('no save'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Counselor A private text'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Counselor A private text'), findsNothing);
  });

  testWidgets('previous versions are listed, a load error offers Retry', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      _host(
        CaseRemarksEditor(
          load: () async {
            if (attempts++ == 0) throw StateError('network');
            return _remarks(
              'Current',
              2,
              versions: [
                CaseRemarksVersion(
                  revision: 2,
                  text: 'Current',
                  authorName: 'Coach Cite',
                  savedAt: DateTime.utc(2026, 11, 16, 1),
                ),
                const CaseRemarksVersion(
                  revision: 1,
                  text: '',
                  authorName: 'Coach Two',
                  savedAt: null,
                ),
              ],
            );
          },
          save: (_, _) async => fail('no save'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Previous versions (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Revision 1 · Coach Two'), findsOneWidget);
    expect(find.text('(cleared)'), findsOneWidget);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('lays out without overflow at ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          CaseRemarksEditor(
            load: () async => _remarks('Some remarks', 4),
            save: (_, _) async => fail('no save'),
          ),
          width: width,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_field, 'Changed');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_saveButton, findsOneWidget);
    });
  }
}
