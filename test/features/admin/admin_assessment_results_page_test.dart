import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_assessment_presentation.dart';
import 'package:mind_mates/features/admin/screens/admin_assessment_results_page.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeRepository extends AdminPortalRepository {
  _FakeRepository([List<AdminAssessmentRecord>? records])
    : _records =
          records ??
          [
            AdminAssessmentRecord(
              id: 'quick-1',
              userId: 'u1',
              type: 'quick',
              createdAt: DateTime(2026, 11, 13),
              status: 'low',
              role: 'student',
            ),
            AdminAssessmentRecord(
              id: 'full-1',
              userId: 'u1',
              type: 'full',
              createdAt: DateTime(2026, 11, 13),
              status: 'someStrain',
              role: 'student',
            ),
          ];

  final List<AdminAssessmentRecord> _records;

  @override
  Stream<List<AdminAssessmentRecord>> watchAssessments() =>
      Stream.value(_records);
}

void main() {
  testWidgets(
    'subnavigation, whole-row selection and no view/archive buttons',
    (tester) async {
      String? selectedId;
      String? selectedName;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminAssessmentResultsPage(
                repository: _FakeRepository(),
                onAssessmentOpen: (record, name) {
                  selectedId = record.id;
                  selectedName = name;
                },
                loadParticipants: (ids) async => {
                  'u1': const AssessmentParticipantInfo(
                    userId: 'u1',
                    name: 'Sample Student',
                    role: 'student',
                    college: 'CITE',
                  ),
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quick Assessment'), findsWidgets);
      expect(find.text('Sample Student'), findsOneWidget);
      expect(find.byTooltip('View assessment results'), findsNothing);
      expect(find.byTooltip('Archive assessment'), findsNothing);
      await tester.ensureVisible(find.text('Sample Student'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sample Student'));
      await tester.pump();
      expect(selectedId, 'quick-1');
      expect(selectedName, 'Sample Student');
      expect(find.text('Actions'), findsNothing);
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Full Assessment'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Full Assessment'));
      await tester.pumpAndSettle();
      expect(find.text('Sample Student'), findsOneWidget);
      expect(find.text('Some areas need attention'), findsOneWidget);
      expect(find.text('Low'), findsNothing);
      await tester.ensureVisible(find.text('Sample Student'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sample Student'));
      await tester.pump();
      expect(selectedId, 'full-1');
    },
  );

  testWidgets(
    'small participant groups (1 and 4) show 1–4 participants without <5, while 5 and 8 show counts and bars',
    (tester) async {
      final records = <AdminAssessmentRecord>[];
      final participants = <String, AssessmentParticipantInfo>{};

      void addGroup({
        required String prefix,
        required int count,
        required String role,
        required String college,
      }) {
        for (var i = 1; i <= count; i++) {
          final uid = '$prefix-$i';
          records.add(
            AdminAssessmentRecord(
              id: 'rec-$uid',
              userId: uid,
              type: 'quick',
              createdAt: DateTime(2026, 11, 13),
              status: 'low',
              role: role,
            ),
          );
          participants[uid] = AssessmentParticipantInfo(
            userId: uid,
            name: 'Participant $uid',
            role: role,
            college: college,
          );
        }
      }

      // Students by college: counts of 1, 4, 5, and 8
      addGroup(prefix: 'cas', count: 1, role: 'student', college: 'CAS');
      addGroup(prefix: 'cite', count: 4, role: 'student', college: 'CITE');
      addGroup(prefix: 'cbaa', count: 5, role: 'student', college: 'CBAA');
      addGroup(prefix: 'chm', count: 8, role: 'student', college: 'CHM');

      // Employees by role: counts of 4 and 5
      addGroup(prefix: 'teach', count: 4, role: 'teaching', college: 'CAS');
      addGroup(
        prefix: 'nonteach',
        count: 5,
        role: 'nonteaching',
        college: 'Unassigned',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminAssessmentResultsPage(
                repository: _FakeRepository(records),
                onAssessmentOpen: (_, _) {},
                loadParticipants: (_) async => participants,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Updated privacy range explanation.
      expect(
        find.text(
          'Each person is counted once. For privacy, groups with fewer than 5 people are shown as a range.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Suppressed'), findsNothing);
      expect(find.text('<5'), findsNothing);

      // 3 small groups (CAS=1, CITE=4, Teaching=4) show "1–4 participants".
      expect(find.text('1–4 participants'), findsNWidgets(3));

      // Exact small counts and tooltips must never be revealed.
      expect(find.byTooltip('1 assessed participants'), findsNothing);
      expect(find.byTooltip('4 assessed participants'), findsNothing);
      expect(find.text('1'), findsNothing);
      expect(find.text('4'), findsNothing);

      // Groups >= 5 (CBAA=5, CHM=8, Non-Teaching=5) display progress bars, tooltips, and exact counts.
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
      expect(find.byTooltip('5 assessed participants'), findsNWidgets(2));
      expect(find.byTooltip('8 assessed participants'), findsOneWidget);
      expect(find.text('5'), findsNWidgets(2));
      expect(find.text('8'), findsOneWidget);
    },
  );
}
