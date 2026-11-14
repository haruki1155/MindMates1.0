import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/session_evidence.dart';
import 'package:mind_mates/features/admin/widgets/clinical_interview_widgets.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _NoteRepo extends AdminPortalRepository {
  @override
  Future<SessionEvidenceRecord?> getClinicalSessionEvidence(String appointmentId) async =>
      const SessionEvidenceRecord(
        summary: 'Session review saved',
        interviewQuestions: 'What questions were asked?',
        requirementsChecked: 'Informed consent reviewed',
        materialsUsed: 'Counseling worksheet',
        attachments: [],
      );
}

void main() {
  testWidgets('interview editor exposes checklists, questions and document controls', (tester) async {
    final questions = TextEditingController();
    final requirements = TextEditingController();
    final materials = TextEditingController();
    addTearDown(() { questions.dispose(); requirements.dispose(); materials.dispose(); });
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: ClinicalInterviewEditor(
        questions: questions,
        requirements: requirements,
        materials: materials,
        files: const [],
        busy: false,
        onChooseFiles: () {},
        onRemoveFile: (_) {},
      )),
    )));
    expect(find.text('Interview questions asked'), findsOneWidget);
    expect(find.text('Student requirements checked'), findsOneWidget);
    expect(find.text('Materials used'), findsOneWidget);
    expect(find.text('Add images / documents'), findsOneWidget);
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
    expect(find.text('Informed consent reviewed'), findsOneWidget);
    expect(find.text('Counseling worksheet'), findsOneWidget);
  });
}
