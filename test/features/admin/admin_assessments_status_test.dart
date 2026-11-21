import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_assessment_presentation.dart';
import 'package:mind_mates/features/admin/screens/admin_assessment_results_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _AssessmentStatusRepo extends AdminPortalRepository {
  _AssessmentStatusRepo(this.records);
  final List<AdminAssessmentRecord> records;

  @override
  Stream<List<AdminAssessmentRecord>> watchAssessments() =>
      Stream.value(records);
}

void main() {
  testWidgets(
    'Full and Quick assessments render semantic AdminStatusBadge with neutral fallback for unknown/missing',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _AssessmentStatusRepo([
        AdminAssessmentRecord(
          id: 'q1',
          userId: 'u1',
          type: 'quick',
          createdAt: DateTime(2026, 11, 20),
          status: 'generally_supported',
          role: 'Student',
        ),
        AdminAssessmentRecord(
          id: 'f1',
          userId: 'u1',
          type: 'full',
          createdAt: DateTime(2026, 11, 20),
          status: 'moderate',
          role: 'Student',
        ),
        AdminAssessmentRecord(
          id: 'f2',
          userId: 'u2',
          type: 'full',
          createdAt: DateTime(2026, 11, 19),
          status: 'severe',
          role: 'Student',
        ),
        AdminAssessmentRecord(
          id: 'f3',
          userId: 'u3',
          type: 'full',
          createdAt: DateTime(2026, 11, 18),
          status: '',
          role: 'Student',
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminAssessmentResultsPage(
                repository: repo,
                loadParticipants: (_) async => const {
                  'u1': AssessmentParticipantInfo(
                    userId: 'u1',
                    name: 'Alice',
                    role: 'Student',
                    college: 'College of Engineering',
                  ),
                  'u2': AssessmentParticipantInfo(
                    userId: 'u2',
                    name: 'Bob',
                    role: 'Student',
                    college: 'College of Engineering',
                  ),
                  'u3': AssessmentParticipantInfo(
                    userId: 'u3',
                    name: 'Cara',
                    role: 'Student',
                    college: 'College of Engineering',
                  ),
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Quick tab shows AdminStatusBadge.
      expect(find.byType(AdminStatusBadge), findsOneWidget);
      expect(find.text('Supported'), findsOneWidget);

      // Switch to Full Assessment tab.
      await tester.tap(find.text('Full Assessment'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminStatusBadge), findsNWidgets(3));
      expect(find.text('Moderate'), findsOneWidget);
      expect(find.text('Severe'), findsOneWidget);
      expect(find.text('Result unavailable'), findsOneWidget);
    },
  );
}
