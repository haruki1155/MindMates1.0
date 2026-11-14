import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_assessment_presentation.dart';
import 'package:mind_mates/features/admin/screens/admin_assessment_results_page.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeRepository extends AdminPortalRepository {
  @override
  Stream<List<AdminAssessmentRecord>> watchAssessments() => Stream.value([
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
  ]);
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
}
