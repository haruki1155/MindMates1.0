import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/student_case_history_page.dart';
import 'package:mind_mates/models/student_case_history_model.dart';

StudentCaseHistoryEntry _entry(
  String id, {
  String? at,
  String status = 'completed',
  bool archived = false,
  String counselor = '',
  String concern = '',
}) => StudentCaseHistoryEntry.fromJson({
  'id': id,
  'status': status,
  'scheduledAt': at,
  'scheduledTime': at == null ? '' : '9:00 AM',
  'archived': archived,
  'counselorName': counselor,
  'concern': concern,
  'location': 'PACC',
  'hasSchedule': at != null,
});

StudentCaseHistoryResult _page(
  List<StudentCaseHistoryEntry> items, {
  String? next,
}) => StudentCaseHistoryResult(
  studentId: 's1',
  displayName: 'Ana Cruz',
  collegeId: 'cite',
  items: items,
  nextCursor: next,
  truncated: false,
);

Future<void> _pump(
  WidgetTester tester,
  StudentCaseHistoryLoader loader, {
  Size size = const Size(1200, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StudentCaseHistoryPage(
                    studentId: 's1',
                    studentName: 'Ana Cruz',
                    loader: loader,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows cases newest first, grouped by year, with status, '
      'archived marker and counselor', (tester) async {
    await _pump(
      tester,
      ({cursor}) async => _page([
        _entry(
          'a3',
          at: '2026-04-02T01:00:00.000Z',
          status: 'requested',
          concern: 'Sleep',
        ),
        _entry(
          'a2',
          at: '2026-03-02T01:00:00.000Z',
          status: 'confirmed',
          counselor: 'Coach Cite',
        ),
        _entry(
          'a1',
          at: '2025-09-10T01:00:00.000Z',
          archived: true,
          counselor: 'Coach Old',
        ),
        _entry('legacy'),
      ]),
    );

    expect(find.text('Ana Cruz'), findsWidgets);
    final y2026 = tester.getTopLeft(find.text('2026')).dy;
    final y2025 = tester.getTopLeft(find.text('2025')).dy;
    final undated = tester.getTopLeft(find.text('Date not recorded')).dy;
    expect(y2026 < y2025 && y2025 < undated, isTrue);
    expect(
      tester.getTopLeft(find.text('Requested')).dy <
          tester.getTopLeft(find.text('Confirmed')).dy,
      isTrue,
    );
    expect(find.text('Archived'), findsOneWidget);
    expect(find.textContaining('Coach Cite'), findsOneWidget);
    expect(find.textContaining('Sleep'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('load more appends the next page using the cursor', (
    tester,
  ) async {
    final cursors = <String?>[];
    await _pump(tester, ({cursor}) async {
      cursors.add(cursor);
      return cursor == null
          ? _page([_entry('a2', at: '2026-03-02T01:00:00.000Z')], next: 'c1')
          : _page([
              _entry('a1', at: '2025-09-10T01:00:00.000Z', status: 'no_show'),
            ]);
    });
    expect(find.text('No-show'), findsNothing);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(cursors, [null, 'c1']);
    expect(find.text('No-show'), findsOneWidget);
    // Appended, not replaced: the first page's case is still shown.
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('empty history explains there are no cases', (tester) async {
    await _pump(tester, ({cursor}) async => _page(const []));
    expect(find.text('No cases recorded'), findsOneWidget);
  });

  testWidgets('a load failure offers retry', (tester) async {
    var calls = 0;
    await _pump(tester, ({cursor}) async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return _page([_entry('a1', at: '2026-03-02T01:00:00.000Z')]);
    });
    expect(find.text('We could not load this case history.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('an unauthorized counselor sees a not-authorized message', (
    tester,
  ) async {
    await _pump(
      tester,
      ({cursor}) async => throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'not allowed',
      ),
    );
    expect(
      find.text("You are not authorized to view this student's case history."),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('back navigation returns to the previous screen', (tester) async {
    await _pump(tester, ({cursor}) async => _page(const []));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('renders without overflow on a phone-width screen', (
    tester,
  ) async {
    await _pump(
      tester,
      ({cursor}) async => _page([
        _entry(
          'a1',
          at: '2026-03-02T01:00:00.000Z',
          archived: true,
          status: 'reschedule_proposed',
          counselor: 'A counselor with a rather long display name',
          concern: 'A long concern ' * 20,
        ),
      ], next: 'c1'),
      size: const Size(360, 740),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Reschedule proposed'), findsOneWidget);
  });

  testWidgets('shows a loading indicator while the first page loads', (
    tester,
  ) async {
    final pending = Completer<StudentCaseHistoryResult>();
    await tester.pumpWidget(
      MaterialApp(
        home: StudentCaseHistoryPage(
          studentId: 's1',
          studentName: 'Ana Cruz',
          loader: ({cursor}) => pending.future,
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(_page(const []));
    await tester.pumpAndSettle();
    expect(find.text('No cases recorded'), findsOneWidget);
  });
}
