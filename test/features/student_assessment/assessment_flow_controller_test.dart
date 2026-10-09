import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/features/student_assessment/models/student_assessment_models.dart';
import 'package:mind_mates/features/student_assessment/screens/assessment_domain_review_screen.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';

void main() {
  test('V4 pauses at each role-specific domain boundary with its ten answers', () async {
    for (final role in [
      AssessmentRole.student,
      AssessmentRole.faculty,
      AssessmentRole.staff,
    ]) {
      final repository = _PreviewRepository();
      final provider = AssessmentProvider(repository)..selectRole(role);
      provider.startStudentAssessment();
      for (var index = 0; index < 10; index += 1) {
        await provider.answerCurrentStudentQuestion(LikertAnswer.often);
      }

      expect(provider.flowStage, AssessmentFlowStage.domainReview);
      expect(repository.previewRequests, hasLength(1));
      expect(repository.previewRequests.single.answers, hasLength(10));
      expect(
        repository.previewRequests.single.domainId,
        provider.studentQuestions.first.v4DomainId,
      );
      expect(provider.studentQuestionIndex, 9);
    }
  });

  test('retry and continue-without-preview preserve answers and session identity', () async {
    final repository = _PreviewRepository(failFirstPreview: true);
    final provider = AssessmentProvider(repository)..startStudentAssessment();
    final submissionId = provider.v4SubmissionId;
    for (var index = 0; index < 10; index += 1) {
      await provider.answerCurrentStudentQuestion(LikertAnswer.often);
    }

    expect(provider.flowStage, AssessmentFlowStage.recoverableError);
    await provider.retryDomainPreview();
    expect(provider.flowStage, AssessmentFlowStage.domainReview);
    provider.continueAfterDomainReview();
    expect(provider.studentQuestionIndex, 10);
    expect(provider.studentAnswers, hasLength(10));
    expect(provider.v4SubmissionId, submissionId);
  });

  test('editing a reviewed domain requests a replacement preview', () async {
    final repository = _PreviewRepository();
    final provider = AssessmentProvider(repository)
      ..startStudentAssessment();
    for (var index = 0; index < 10; index += 1) {
      await provider.answerCurrentStudentQuestion(LikertAnswer.often);
    }
    provider.continueAfterDomainReview();
    provider.goBackStudentQuestion();
    await provider.answerCurrentStudentQuestion(LikertAnswer.never);

    expect(repository.previewRequests, hasLength(2));
    expect(provider.flowStage, AssessmentFlowStage.domainReview);
  });

  testWidgets('domain review renders only the authoritative preview response', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssessmentDomainReviewScreen(
          preview: const {
            'domainLabel': 'Academic',
            'status': 'supportMayHelp',
            'summary': 'Server-calculated category summary.',
            'focusInsight': 'Server focus.',
            'suggestedAction': 'Server action.',
            'reflectionPrompt': 'Server prompt.',
            'interventionEligible': true,
          },
          onContinue: () {},
          onRetry: () async {},
          onBack: () {},
        ),
      ),
    );

    expect(find.text('Academic'), findsOneWidget);
    expect(find.text('Server-calculated category summary.'), findsOneWidget);
    expect(find.text('Continue Assessment'), findsOneWidget);
    expect(find.textContaining('diagnos'), findsNothing);
  });
}

class _PreviewRequest {
  const _PreviewRequest(this.instrumentVersion, this.domainId, this.answers);
  final String instrumentVersion;
  final String domainId;
  final List<StudentAssessmentAnswer> answers;
}

class _PreviewRepository extends AssessmentRepository {
  _PreviewRepository({this.failFirstPreview = false});
  final bool failFirstPreview;
  final List<_PreviewRequest> previewRequests = [];

  @override
  Future<Map<String, Object>> previewV4AssessmentDomain({
    required String instrumentVersion,
    required String domainId,
    required List<StudentAssessmentAnswer> answers,
  }) async {
    previewRequests.add(_PreviewRequest(instrumentVersion, domainId, answers));
    if (failFirstPreview && previewRequests.length == 1) {
      throw StateError('offline');
    }
    return {
      'domainId': domainId,
      'domainLabel': 'Verified domain',
      'status': 'mostlySupported',
      'isScorable': true,
      'answeredCount': 10,
      'presentedCount': 10,
      'summary': 'Server result.',
      'suggestedAction': 'Continue.',
      'reflectionPrompt': 'Reflect.',
      'interventionEligible': false,
      'policyVersion': 'assessment_intervention_v1',
    };
  }
}
