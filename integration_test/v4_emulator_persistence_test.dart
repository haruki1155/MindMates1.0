import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mind_mates/features/student_assessment/data/student_assessment_v4_questions.dart';
import 'package:mind_mates/features/student_assessment/data/workplace_assessment_v4_questions.dart';
import 'package:mind_mates/features/student_assessment/models/student_assessment_models.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';

const _host = String.fromEnvironment('V4_EMULATOR_HOST');
const _email = String.fromEnvironment('V4_EMULATOR_EMAIL');
const _password = String.fromEnvironment('V4_EMULATOR_PASSWORD');
const _role = String.fromEnvironment('V4_EMULATOR_ROLE', defaultValue: 'student');
const _projectId = 'demo-mindmate-phase7';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('persists one authoritative V4 result through emulators', (
    tester,
  ) async {
    // Fail closed: no operation is attempted unless every service is local.
    expect(
      _host,
      Platform.isAndroid ? anyOf('10.0.2.2', '127.0.0.1') : '127.0.0.1',
    );
    expect(_email, isNotEmpty);
    expect(_password, isNotEmpty);

    final app = await Firebase.initializeApp();
    expect(app.options.projectId, _projectId);
    await FirebaseAuth.instance.useAuthEmulator(
      _host,
      9099,
      automaticHostMapping: false,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      _host,
      8080,
      automaticHostMapping: false,
    );
    FirebaseFunctions.instanceFor(region: 'us-central1').useFunctionsEmulator(
      _host,
      5001,
      automaticHostMapping: false,
    );

    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: _email,
      password: _password,
    );
    final uid = credential.user!.uid;
    final (instrumentVersion, domainId, questions) = switch (_role) {
      'student' => (
        StudentAssessmentV4Questions.instrumentVersion,
        'academic',
        StudentAssessmentV4Questions.questions,
      ),
      'teaching' => (
        TeachingAssessmentV4Questions.instrumentVersion,
        'teachingWorkloadDemands',
        TeachingAssessmentV4Questions.questions,
      ),
      'nonTeaching' => (
        NonTeachingAssessmentV4Questions.instrumentVersion,
        'nonTeachingWorkloadDemands',
        NonTeachingAssessmentV4Questions.questions,
      ),
      _ => throw ArgumentError.value(_role, 'V4_EMULATOR_ROLE'),
    };
    final answers = [
      for (final question in questions)
        StudentAssessmentAnswer(questionId: question.id, answer: LikertAnswer.often),
    ];
    final submissionId = 'phase7_${_role}_v4_submission';
    final repository = AssessmentRepository();
    final assessments = FirebaseFirestore.instance.collection('assessments');

    expect(
      (await assessments.where('userId', isEqualTo: uid).get()).docs,
      isEmpty,
    );

    final preview = await repository.previewV4AssessmentDomain(
      instrumentVersion: instrumentVersion,
      domainId: domainId,
      answers: answers.take(10).toList(),
    );
    expect(preview['domainId'], domainId);
    expect(
      (await assessments.where('userId', isEqualTo: uid).get()).docs,
      isEmpty,
      reason: 'A preview must never create an official assessment record.',
    );

    final saved = await repository.saveV4FullAssessment(
      userId: uid,
      instrumentVersion: instrumentVersion,
      answers: answers,
      submissionId: submissionId,
    );
    final retried = await repository.saveV4FullAssessment(
      userId: uid,
      instrumentVersion: instrumentVersion,
      answers: answers,
      submissionId: submissionId,
    );
    // A retry may serialize envelope metadata differently, but must resolve to
    // the same saved submission and server-authoritative result.
    expect(retried['submissionId'], submissionId);
    expect(retried['result'], saved['result']);

    final documents = await assessments.where('userId', isEqualTo: uid).get();
    expect(documents.docs, hasLength(1));
    final persisted = documents.docs.single.data();
    expect(persisted['submissionId'], submissionId);
    expect(
      (persisted['instrument'] as Map<Object?, Object?>)['version'],
      instrumentVersion,
    );
    expect(persisted['result'], saved['result']);
    expect((persisted['responses'] as List), hasLength(50));
  });
}
