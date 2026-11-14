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
        attachments: [],
      );
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

  testWidgets('read-only documentation loads private saved summary on demand', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ClinicalInterviewRecordViewer(
      repository: _NoteRepo(),
      appointmentId: 'appointment-1',
    ))));
    expect(find.text('Session review saved'), findsNothing);
    await tester.tap(find.text('View session documentation'));
    await tester.pumpAndSettle();
    expect(find.text('Session review saved'), findsOneWidget);
    expect(find.text('Interview questions asked'), findsNothing);
    expect(find.text('Student requirements checked'), findsNothing);
    expect(find.text('Materials used'), findsNothing);
  });
}
